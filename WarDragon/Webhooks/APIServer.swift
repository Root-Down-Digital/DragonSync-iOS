//
//  APIServer.swift
//  WarDragon
//
//  Read-only HTTP API server for ATAK companion plugin
//  Matches Python DragonSync api_server.py functionality
//

import Foundation
import Network
import UIKit

/// HTTP API Server for exposing drone detections, system status, and configuration
/// to the WarDragon ATAK companion plugin
@MainActor
class APIServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16
    @Published private(set) var lastError: Error?
    
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.wardragon.apiserver")
    private var connections: [ObjectIdentifier: NWConnection] = [:]  // Use ObjectIdentifier instead of Set
    
    // Dependencies (weak to avoid retain cycles)
    private weak var coTViewModel: CoTViewModel?
    private weak var statusViewModel: StatusViewModel?
    
    init(port: UInt16 = 8088) {
        self.port = port
    }
    
    /// Start the API server
    func start(coTViewModel: CoTViewModel, statusViewModel: StatusViewModel) {
        guard !isRunning else {
            print("API server already running")
            return
        }
        
        self.coTViewModel = coTViewModel
        self.statusViewModel = statusViewModel
        
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.acceptLocalOnly = false // Allow external connections
            
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        print("API server ready on port \(self?.port ?? 0)")
                        self?.isRunning = true
                    case .failed(let error):
                        print("API server failed: \(error)")
                        self?.lastError = error
                        self?.isRunning = false
                    case .cancelled:
                        print("API server cancelled")
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            
            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            
            listener?.start(queue: queue)
            
        } catch {
            print("Failed to start API server: \(error)")
            lastError = error
        }
    }
    
    /// Stop the API server
    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        
        // Close all active connections
        for (_, connection) in connections {
            connection.cancel()
        }
        connections.removeAll()
        
        isRunning = false
        print("API server stopped")
    }
    
    private func handleConnection(_ connection: NWConnection) {
        let connectionId = ObjectIdentifier(connection)
        connections[connectionId] = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            if case .cancelled = state {
                Task { @MainActor in
                    self?.connections.removeValue(forKey: connectionId)
                }
            }
        }
        
        connection.start(queue: queue)
        receiveRequest(from: connection)
    }
    
    private func receiveRequest(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty,
               let requestString = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    await self.processRequest(requestString, connection: connection)
                }
            }
            
            if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func processRequest(_ requestString: String, connection: NWConnection) async {
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, statusCode: 400, body: "Bad Request")
            return
        }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2,
              components[0] == "GET" else {
            sendResponse(connection: connection, statusCode: 405, body: "Method Not Allowed")
            return
        }
        
        let path = components[1]
        
        // Route requests
        switch path {
        case "/status":
            await handleStatus(connection: connection)
        case "/drones":
            await handleDrones(connection: connection)
        case "/signals":
            await handleSignals(connection: connection)
        case "/config":
            await handleConfig(connection: connection)
        case "/update/check":
            await handleUpdateCheck(connection: connection)
        case "/aircraft":
            await handleAircraft(connection: connection)
        case "/health":
            await handleHealth(connection: connection)
        default:
            sendResponse(connection: connection, statusCode: 404, body: "Not Found")
        }
    }
    
    // MARK: - Route Handlers
    
    private func handleStatus(connection: NWConnection) async {
        guard let statusViewModel = statusViewModel,
              let latestStatus = statusViewModel.statusMessages.last else {
            sendJSONResponse(connection: connection, statusCode: 503, data: ["error": "system status unavailable"])
            return
        }
        
        // Get kit ID from device identifier
        let kitId: String
        if let uuid = UIDevice.current.identifierForVendor?.uuidString {
            let prefix = String(uuid.prefix(8))
            kitId = "wardragon-\(prefix)"
        } else {
            kitId = "wardragon-unknown"
        }
        
        let response: [String: Any] = [
            "kit_id": kitId,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "gps": [
                "latitude": latestStatus.gpsData.latitude,
                "longitude": latestStatus.gpsData.longitude,
                "altitude": latestStatus.gpsData.altitude,
                "fix": latestStatus.gpsData.latitude != 0 && latestStatus.gpsData.longitude != 0
            ],
            "system": [
                "cpu_usage": latestStatus.systemStats.cpuUsage,
                "memory_percent": latestStatus.systemStats.memory.percent,
                "temperature": latestStatus.systemStats.temperature,
                "uptime": ProcessInfo.processInfo.systemUptime
            ],
            "ant_sdr": [
                "pluto_temp": latestStatus.antStats.plutoTemp as Any,
                "zynq_temp": latestStatus.antStats.zynqTemp as Any,
                "temp_valid": (latestStatus.antStats.plutoTemp) > 0.0 || (latestStatus.antStats.zynqTemp) > 0.0
            ]
        ]
        
        sendJSONResponse(connection: connection, statusCode: 200, data: response)
    }
    
    private func handleDrones(connection: NWConnection) async {
        guard let coTViewModel = coTViewModel else {
            sendJSONResponse(connection: connection, statusCode: 503, data: ["error": "drone manager unavailable"])
            return
        }
        
        // Export all drones (includes aircraft tracks)
        let drones = coTViewModel.parsedMessages.map { message -> [String: Any] in
            return message.toDictionary()
        }
        
        sendJSONResponse(connection: connection, statusCode: 200, data: ["drones": drones])
    }
    
    private func handleSignals(connection: NWConnection) async {
        // FPV signal detections
        guard let coTViewModel = coTViewModel else {
            sendJSONResponse(connection: connection, statusCode: 503, data: ["error": "signal manager unavailable"])
            return
        }
        
        let signals = coTViewModel.parsedMessages
            .filter { $0.isFPVDetection }
            .map { message -> [String: Any] in
                var dict = message.toDictionary()
                dict["signal_type"] = "fpv"
                return dict
            }
        
        sendJSONResponse(connection: connection, statusCode: 200, data: ["signals": signals])
    }
    
    private func handleConfig(connection: NWConnection) async {
        // Sanitized configuration (no secrets) - matches Python DragonSync format
        let config: [String: Any] = [
            "api": [
                "enabled": true,
                "port": port
            ],
            "mqtt": [
                "enabled": Settings.shared.mqttEnabled,
                "host": Settings.shared.mqttConfiguration.host,
                "port": Settings.shared.mqttConfiguration.port,
                "base_topic": Settings.shared.mqttConfiguration.baseTopic,
                "ha_enabled": Settings.shared.mqttConfiguration.homeAssistantEnabled,
                "ha_prefix": Settings.shared.mqttConfiguration.homeAssistantDiscoveryPrefix
            ],
            "tak": [
                "enabled": Settings.shared.takEnabled,
                "host": Settings.shared.takConfiguration.host,
                "port": Settings.shared.takConfiguration.port,
                "protocol": Settings.shared.takConfiguration.protocol.rawValue,
                "tls": Settings.shared.takConfiguration.tlsEnabled
            ],
            "adsb": [
                "enabled": Settings.shared.adsbEnabled,
                "url": Settings.shared.adsbConfiguration.readsbURL,
                "poll_interval": Settings.shared.adsbConfiguration.pollInterval,
                "min_altitude": Settings.shared.adsbConfiguration.minAltitude as Any,
                "max_altitude": Settings.shared.adsbConfiguration.maxAltitude as Any
            ],
            "kismet": [
                "enabled": Settings.shared.kismetEnabled,
                "url": Settings.shared.kismetConfiguration.serverURL,
                "poll_interval": Settings.shared.kismetConfiguration.pollInterval
            ],
            "lattice": [
                "enabled": Settings.shared.latticeEnabled,
                "url": Settings.shared.latticeConfiguration.serverURL
            ],
            "detections": [
                "max_drones": Settings.shared.maxDrones,
                "max_aircraft": Settings.shared.maxAircraft,
                "inactivity_timeout": Settings.shared.inactivityTimeout
            ],
            "rate_limits": [
                "enabled": Settings.shared.rateLimitConfiguration.enabled,
                "drone_interval": Settings.shared.rateLimitConfiguration.dronePublishInterval,
                "mqtt_max_per_second": Settings.shared.rateLimitConfiguration.mqttMaxPerSecond,
                "tak_max_per_second": Settings.shared.rateLimitConfiguration.takMaxPerSecond
            ],
            "zmq": [
                "telemetry_port": Settings.shared.zmqTelemetryPort,
                "status_port": Settings.shared.zmqStatusPort,
                "spectrum_port": Settings.shared.zmqSpectrumPort
            ]
        ]
        
        sendJSONResponse(connection: connection, statusCode: 200, data: config)
    }
    
    private func handleUpdateCheck(connection: NWConnection) async {
        // Simple version check (read-only)
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        
        let response: [String: Any] = [
            "current_version": appVersion,
            "build_number": buildNumber,
            "update_available": false,  // iOS doesn't have git-based updates
            "platform": "iOS"
        ]
        
        sendJSONResponse(connection: connection, statusCode: 200, data: response)
    }
    
    private func handleAircraft(connection: NWConnection) async {
        // ADS-B aircraft tracks (similar to drones but separate endpoint)
        guard let coTViewModel = coTViewModel else {
            sendJSONResponse(connection: connection, statusCode: 503, data: ["error": "aircraft manager unavailable"])
            return
        }
        
        let aircraft = coTViewModel.parsedMessages
            .filter { $0.uid.hasPrefix("aircraft-") }
            .map { message -> [String: Any] in
                return message.toDictionary()
            }
        
        sendJSONResponse(connection: connection, statusCode: 200, data: ["aircraft": aircraft])
    }
    
    private func handleHealth(connection: NWConnection) async {
        // Simple health check endpoint (Python DragonSync doesn't have this, but it's useful)
        let response: [String: Any] = [
            "status": "healthy",
            "api_version": "1.0",
            "uptime": ProcessInfo.processInfo.systemUptime,
            "active_drones": coTViewModel?.parsedMessages.filter { !$0.uid.hasPrefix("aircraft-") }.count ?? 0,
            "active_aircraft": coTViewModel?.parsedMessages.filter { $0.uid.hasPrefix("aircraft-") }.count ?? 0
        ]
        
        sendJSONResponse(connection: connection, statusCode: 200, data: response)
    }
    
    // MARK: - Response Helpers
    
    private func sendJSONResponse(connection: NWConnection, statusCode: Int, data: [String: Any]) {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted])
            let body = String(data: jsonData, encoding: .utf8) ?? "{}"
            
            let headers = [
                "Content-Type: application/json",
                "Content-Length: \(body.utf8.count)"
            ]
            
            sendResponse(connection: connection, statusCode: statusCode, body: body, headers: headers)
        } catch {
            sendResponse(connection: connection, statusCode: 500, body: "Internal Server Error")
        }
    }
    
    private func sendResponse(connection: NWConnection, statusCode: Int, body: String, headers: [String] = []) {
        let statusText = httpStatusText(for: statusCode)
        var response = "HTTP/1.1 \(statusCode) \(statusText)\r\n"
        
        if headers.isEmpty {
            response += "Content-Type: text/plain\r\n"
            response += "Content-Length: \(body.utf8.count)\r\n"
        } else {
            for header in headers {
                response += "\(header)\r\n"
            }
        }
        
        response += "Connection: close\r\n"
        response += "\r\n"
        response += body
        
        guard let data = response.data(using: .utf8) else { return }
        
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
            connection.cancel()
        })
    }
    
    private func httpStatusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Unknown"
        }
    }
}
