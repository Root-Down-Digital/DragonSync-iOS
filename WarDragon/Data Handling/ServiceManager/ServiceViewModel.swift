//
//  ServiceViewModel.swift
//  WarDragon
//
//  Created by Luke on 1/10/25.
//

import Foundation
import SwiftUI

class ServiceViewModel: ObservableObject {
    @Published var services: [ServiceControl] = []
    @Published var healthReport: HealthReport?
    @Published var isLoading = false
    @Published var error: String?
    
    private let zmqHandler = ZMQHandler()
    
    struct HealthReport {
        var overallHealth: String
        var issues: [ServiceControl.ServiceIssue]
        var timestamp: Date
        
        var statusColor: Color {
            switch overallHealth.lowercased() {
            case "healthy": return .green
            case "degraded": return .yellow
            default: return .red
            }
        }
    }
    
    func startMonitoring() {
        Task { @MainActor in
            let zmqHost = Settings.shared.zmqHost
            let zmqTelemetryPort = UInt16(Settings.shared.zmqTelemetryPort)
            let zmqStatusPort = UInt16(Settings.shared.zmqStatusPort)
            
            zmqHandler.connect(
                host: zmqHost,
                zmqTelemetryPort: zmqTelemetryPort,
                zmqStatusPort: zmqStatusPort,
                onTelemetry: { _ in }, // Undefined for unused telemetry port
                onStatus: { [weak self] message in
                    self?.handleStatusUpdate(message)
                }
            )
        }
    }
    
    func stopMonitoring() {
        zmqHandler.disconnect()
    }
    
    func toggleService(_ service: ServiceControl) {
        isLoading = true
        
        let command = [
            "command": [
                "type": "service_control",
                "service": service.id,
                "action": service.status.isActive ? "disable" : "enable",
                "timestamp": Date().timeIntervalSince1970
            ]
        ]
        
        zmqHandler.sendServiceCommand(command) { [weak self] (success: Bool, response: Any?) in
            DispatchQueue.main.async {
                self?.isLoading = false
                if !success {
                    self?.error = response as? String
                }
            }
        }
    }
    
    func restartService(_ service: ServiceControl) {
        isLoading = true
        
        let command = [
            "command": [
                "type": "service_control",
                "service": service.id,
                "action": "restart",
                "timestamp": Date().timeIntervalSince1970
            ]
        ]
        
        zmqHandler.sendServiceCommand(command) { [weak self] (success: Bool, response: Any?) in
            DispatchQueue.main.async {
                self?.isLoading = false
                if !success {
                    self?.error = response as? String
                }
            }
        }
    }
    
    private func handleStatusUpdate(_ message: String) {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stats = json["system_stats"] as? [String: Any],
              let services = stats["services"] as? [String: Any] else {
            return
        }

        var updatedServices: [ServiceControl] = []
        
        // Parse the services
        if let categories = services["by_category"] as? [String: [String: Any]] {
            for (category, serviceDict) in categories {
                for (serviceName, details) in serviceDict {
                    guard let details = details as? [String: Any] else { continue }
                    
                    // Get status info
                    let status = details["status"] as? [String: Any] ?? [:]
                    let active = status["active"] as? Bool ?? false
                    let enabled = status["enabled"] as? Bool ?? false
                    
                    // Get resource usage if available
                    let resources = details["resources"] as? [String: Any] ?? [:]
                    let cpuPercent = resources["cpu_percent"] as? Double ?? 0
                    let memPercent = resources["mem_percent"] as? Double ?? 0
                    
                    // Parse any issues
                    let issues = parseIssues(from: details["issues"] as? [[String: Any]] ?? [])
                    
                    // Create service status
                    let serviceStatus = ServiceControl.ServiceStatus(
                        isActive: active,
                        isEnabled: enabled,
                        statusText: active ? "Running" : "Stopped",
                        rawStatus: status["raw_status"] as? String,
                        healthStatus: determineHealthStatus(
                            active: active,
                            issues: issues
                        )
                    )
                    
                    // Create resource usage info if available
                    let resourceUsage = cpuPercent > 0 || memPercent > 0
                        ? ServiceControl.ResourceUsage(
                            cpuPercent: cpuPercent,
                            memoryPercent: memPercent)
                        : nil
                    
                    let service = ServiceControl(
                        id: serviceName,
                        service: serviceName,
                        category: ServiceControl.ServiceCategory(rawValue: category) ?? .comms,
                        description: details["description"] as? String ?? serviceName,
                        dependencies: details["dependencies"] as? [String] ?? [],
                        isCritical: details["critical"] as? Bool ?? false,
                        status: serviceStatus,
                        resources: resourceUsage,
                        issues: issues
                    )
                    
                    updatedServices.append(service)
                }
            }
        }

        // Update health report
        if let healthReport = services["health_report"] as? [String: Any] {
            self.healthReport = HealthReport(
                overallHealth: healthReport["overall_health"] as? String ?? "unknown",
                issues: parseIssues(from: healthReport["issues"] as? [[String: Any]] ?? []),
                timestamp: Date()
            )
        }

        DispatchQueue.main.async {
            self.services = updatedServices
        }
    }
    
    
    private func parseServiceDetails(name: String, category: String, details: [String: Any]) -> ServiceControl {
        let serviceInfo = details["status"] as? [String: Any] ?? [:]
        let resources = details["resources"] as? [String: Any] ?? [:]
        let dependencies = (details["dependencies"] as? [String]) ?? []
        let issues = parseIssues(from: details["issues"] as? [[String: Any]] ?? [])
        
        let status = ServiceControl.ServiceStatus(
            isActive: serviceInfo["active"] as? Bool ?? false,
            isEnabled: serviceInfo["enabled"] as? Bool ?? false,
            statusText: serviceInfo["status"] as? String ?? "unknown",
            rawStatus: details["raw_status"] as? String,
            healthStatus: determineHealthStatus(
                active: serviceInfo["active"] as? Bool ?? false,
                issues: issues
            )
        )
        
        let resourceUsage = ServiceControl.ResourceUsage(
            cpuPercent: resources["cpu_percent"] as? Double ?? 0.0,
            memoryPercent: resources["mem_percent"] as? Double ?? 0.0
        )
        
        return ServiceControl(
            id: name,
            service: details["service"] as? String ?? name,
            category: ServiceControl.ServiceCategory(rawValue: category) ?? .comms,
            description: details["description"] as? String ?? "",
            dependencies: dependencies,
            isCritical: details["critical"] as? Bool ?? false,
            status: status,
            resources: resourceUsage,
            issues: issues
        )
    }
    
    private func parseIssues(from issues: [[String: Any]]) -> [ServiceControl.ServiceIssue] {
        return issues.compactMap { issue in
            guard let message = issue["error"] as? String,
                  let severityStr = issue["severity"] as? String else {
                return nil
            }

            let severity: ServiceControl.ServiceIssue.IssueSeverity
            switch severityStr {
            case "high": severity = .high
            case "medium": severity = .medium
            default: severity = .warning
            }

            return ServiceControl.ServiceIssue(
                message: message,
                severity: severity
            )
        }
    }

    private func determineHealthStatus(
        active: Bool,
        issues: [ServiceControl.ServiceIssue]
    ) -> ServiceControl.ServiceStatus.HealthStatus {
        if !active {
            return .critical
        }
        
        if issues.contains(where: { $0.severity == .high }) {
            return .critical
        }
        
        if issues.contains(where: { $0.severity == .medium }) {
            return .warning
        }
        
        return active ? .healthy : .unknown
    }
    
    private func parseHealthReport(_ report: [String: Any]) -> HealthReport {
        let issues = (report["issues"] as? [[String: Any]] ?? []).compactMap { issueDict -> ServiceControl.ServiceIssue? in
            guard let message = issueDict["error"] as? String,
                  let severityStr = issueDict["severity"] as? String else {
                return nil
            }
            
            let severity: ServiceControl.ServiceIssue.IssueSeverity
            switch severityStr {
            case "high":
                severity = .high
            case "medium":
                severity = .medium
            default:
                severity = .warning
            }
            
            return ServiceControl.ServiceIssue(
                message: message,
                severity: severity
            )
        }
        
        return HealthReport(
            overallHealth: report["overall_health"] as? String ?? "unknown",
            issues: issues,
            timestamp: Date()
        )
    }
    
    func servicesByCategory() -> [ServiceControl.ServiceCategory: [ServiceControl]] {
        Dictionary(grouping: services) { $0.category }
    }
    
    func criticalServices() -> [ServiceControl] {
        services.filter { $0.isCritical }
    }
    
    func servicesWithIssues() -> [ServiceControl] {
        services.filter { !$0.issues.isEmpty }
    }
}
