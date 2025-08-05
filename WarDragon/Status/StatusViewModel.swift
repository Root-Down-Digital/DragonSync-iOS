//
//  StatusViewModel.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import Foundation
import CoreLocation
import SwiftUI

class StatusViewModel: ObservableObject {
    @Published var statusMessages: [StatusMessage] = []
    @Published var lastStatusMessageReceived: Date?
    @Published var showESP32LocationAlert = false
    private var locationManager = LocationManager.shared
    
    // MARK: - Status Connection Logic
    
    var isSystemOnline: Bool {
        guard let lastReceived = lastStatusMessageReceived else { return false }
        return Date().timeIntervalSince(lastReceived) < 300 // Consider offline if no message in 5min
    }
    
    var statusColor: Color {
        isSystemOnline ? .green : .red
    }
    
    var statusText: String {
        isSystemOnline ? "ONLINE" : "OFFLINE"
    }
    
    var lastReceivedText: String {
        guard let lastReceived = lastStatusMessageReceived else { return "Never" }
        
        let timeInterval = Date().timeIntervalSince(lastReceived)
        
        if timeInterval < 60 {
            return "\(Int(timeInterval))s ago"
        } else if timeInterval < 3600 {
            return "\(Int(timeInterval / 60))m ago"
        } else if timeInterval < 86400 {
            return "\(Int(timeInterval / 3600))h ago"
        } else {
            return "\(Int(timeInterval / 86400))d ago"
        }
    }
    
    struct StatusMessage: Identifiable  {
        var id: String { uid }
        let uid: String
        var serialNumber: String
        var timestamp: Double
        var gpsData: GPSData
        var systemStats: SystemStats
        var antStats: ANTStats
        
        
        struct GPSData {
            var latitude: Double
            var longitude: Double
            var altitude: Double
            var speed: Double
            
            var coordinate: CLLocationCoordinate2D {
                CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        
        struct SystemStats {
            var cpuUsage: Double
            var memory: MemoryStats
            var disk: DiskStats
            var temperature: Double
            var uptime: Double
            
            struct MemoryStats {
                var total: Int64
                var available: Int64
                var percent: Double
                var used: Int64
                var free: Int64
                var active: Int64
                var inactive: Int64
                var buffers: Int64
                var cached: Int64
                var shared: Int64
                var slab: Int64
            }
            
            struct DiskStats {
                var total: Int64
                var used: Int64
                var free: Int64
                var percent: Double
            }
        }
        
        struct ANTStats {
            var plutoTemp: Double
            var zynqTemp: Double
        }
    }
    
    // MARK: - Message Management
    
    func addStatusMessage(_ message: StatusMessage) {
        let processedMessage = processStatusMessage(message)
        statusMessages.append(processedMessage)
        lastStatusMessageReceived = Date()
        
        // Keep only the last 100 messages to prevent memory issues
        if statusMessages.count > 100 {
            statusMessages.removeFirst(statusMessages.count - 100)
        }
        
        // Check thresholds after adding new message
        checkSystemThresholds()
    }
    
    func updateExistingStatusMessage(_ message: StatusMessage) {
        let processedMessage = processStatusMessage(message)
        
        if let index = statusMessages.firstIndex(where: { $0.uid == message.uid }) {
            statusMessages[index] = processedMessage
        } else {
            addStatusMessage(processedMessage)
        }
        lastStatusMessageReceived = Date()
    }
    
    private func processStatusMessage(_ message: StatusMessage) -> StatusMessage {
        var processedMessage = message
        
        if needsLocationSubstitution(message) {
            if !Settings.shared.hasShownStatusLocationPrompt {
                DispatchQueue.main.async { self.showESP32LocationAlert = true }
            }
            
            if Settings.shared.useUserLocationForStatus, let userLocation = locationManager.userLocation {
                processedMessage.gpsData.latitude = userLocation.coordinate.latitude
                processedMessage.gpsData.longitude = userLocation.coordinate.longitude
                processedMessage.gpsData.altitude = userLocation.altitude
                processedMessage.gpsData.speed = max(0, userLocation.speed)
            }
        }
        return processedMessage
    }

    private func needsLocationSubstitution(_ message: StatusMessage) -> Bool {
        let isESP32 = message.serialNumber.contains("ESP32")
        let hasNoGPS = message.gpsData.latitude == 0.0 && message.gpsData.longitude == 0.0
        return isESP32 || hasNoGPS
    }
    
}

extension StatusViewModel {
    func checkSystemThresholds() {
        guard Settings.shared.systemWarningsEnabled,
              let lastMessage = statusMessages.last else {
            return
        }
        
        // Check CPU usage
        if lastMessage.systemStats.cpuUsage > Settings.shared.cpuWarningThreshold {
            if Settings.shared.statusNotificationThresholds {
                sendSystemNotification(
                    title: "High CPU Usage",
                    message: "CPU usage at \(Int(lastMessage.systemStats.cpuUsage))%",
                    isThresholdAlert: true
                )
            }
        }
        
        // Check system
        if lastMessage.systemStats.temperature > Settings.shared.tempWarningThreshold {
            if Settings.shared.statusNotificationThresholds {
                sendSystemNotification(
                    title: "High System Temperature",
                    message: "Temperature at \(Int(lastMessage.systemStats.temperature))°C",
                    isThresholdAlert: true
                )
            }
        }
        
        let usedMemory = lastMessage.systemStats.memory.total - lastMessage.systemStats.memory.available
        let memoryUsage = Double(usedMemory) / Double(lastMessage.systemStats.memory.total)
        if memoryUsage > Settings.shared.memoryWarningThreshold {
            if Settings.shared.statusNotificationThresholds {
                sendSystemNotification(
                    title: "High Memory Usage",
                    message: "Memory usage at \(Int(memoryUsage * 100))%",
                    isThresholdAlert: true
                )
            }
        }
        
        // Check ANTSDR temperatures
        if lastMessage.antStats.plutoTemp > Settings.shared.plutoTempThreshold {
            if Settings.shared.statusNotificationThresholds {
                sendSystemNotification(
                    title: "High Pluto Temperature",
                    message: "Temperature at \(Int(lastMessage.antStats.plutoTemp))°C",
                    isThresholdAlert: true
                )
            }
        }
        
        if lastMessage.antStats.zynqTemp > Settings.shared.zynqTempThreshold {
            if Settings.shared.statusNotificationThresholds {
                sendSystemNotification(
                    title: "High Zynq Temperature",
                    message: "Temperature at \(Int(lastMessage.antStats.zynqTemp))°C",
                    isThresholdAlert: true
                )
            }
        }
        
        // Check for regular status notification
        checkRegularStatusNotification()
    }
    
    private func checkRegularStatusNotification() {
        guard Settings.shared.shouldSendStatusNotification(),
              let lastMessage = statusMessages.last else { return }
        
        let usedMemory = lastMessage.systemStats.memory.total - lastMessage.systemStats.memory.available
        let memoryUsage = Double(usedMemory) / Double(lastMessage.systemStats.memory.total)
        
        sendSystemNotification(
            title: "System Status Update",
            message: "CPU: \(String(format: "%.0f", lastMessage.systemStats.cpuUsage))%, Memory: \(String(format: "%.0f", memoryUsage * 100))%, Temp: \(Int(lastMessage.systemStats.temperature))°C",
            isThresholdAlert: false
        )
        
        // Update last notification time
        Settings.shared.lastStatusNotificationTime = Date()
    }
    
    func deleteStatusMessages(at indexSet: IndexSet) {
        statusMessages.remove(atOffsets: indexSet)
    }
    
    private func sendSystemNotification(title: String, message: String, isThresholdAlert: Bool = false) {
        // Send local notification if enabled
        if Settings.shared.notificationsEnabled {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = message
            
            if isThresholdAlert {
                content.sound = .default
                content.badge = 1
            }
            
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            
            UNUserNotificationCenter.current().add(request)
        }
        
        // Send webhook if webhooks are enabled AND status events are enabled
        if Settings.shared.webhooksEnabled && Settings.shared.enabledWebhookEvents.contains(.systemAlert) {
            let event: WebhookEvent
            if title.contains("Temperature") {
                event = .temperatureAlert
            } else if title.contains("Memory") {
                event = .memoryAlert
            } else if title.contains("CPU") {
                event = .cpuAlert
            } else {
                event = .systemAlert
            }
            
            var data: [String: Any] = [
                "title": title,
                "message": message,
                "timestamp": Date(),
                "is_threshold_alert": isThresholdAlert
            ]
            
            // Add detailed system stats for webhooks
            if let lastMessage = statusMessages.last {
                let usedMemory = lastMessage.systemStats.memory.total - lastMessage.systemStats.memory.available
                let memoryUsagePercent = Double(usedMemory) / Double(lastMessage.systemStats.memory.total) * 100
                
                data["cpu_usage"] = lastMessage.systemStats.cpuUsage
                data["memory_usage"] = memoryUsagePercent
                data["memory_total_gb"] = Double(lastMessage.systemStats.memory.total) / 1_073_741_824
                data["memory_used_gb"] = Double(usedMemory) / 1_073_741_824
                data["memory_available_gb"] = Double(lastMessage.systemStats.memory.available) / 1_073_741_824
                data["system_temperature"] = lastMessage.systemStats.temperature
                data["pluto_temperature"] = lastMessage.antStats.plutoTemp
                data["zynq_temperature"] = lastMessage.antStats.zynqTemp
                data["uptime"] = lastMessage.systemStats.uptime
                data["last_status_received"] = lastStatusMessageReceived?.timeIntervalSince1970
            }
            
            WebhookManager.shared.sendWebhook(event: event, data: data)
        }
    }
}
