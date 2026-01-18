//
//  MQTTClient.swift
//  WarDragon
//
//  MQTT client for publishing drone detections and system status
//
//  Uses CocoaMQTT 1.3.2 (stable version)
//

import Foundation
import Combine
import os.log
import CocoaMQTT
import UIKit

/// MQTT client connection state
enum MQTTConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(Error)
    
    static func == (lhs: MQTTConnectionState, rhs: MQTTConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// MQTT client for WarDragon
@MainActor
class MQTTClient: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var state: MQTTConnectionState = .disconnected
    @Published private(set) var messagesSent: Int = 0
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private var configuration: MQTTConfiguration
    private let logger = Logger(subsystem: "com.wardragon", category: "MQTTClient")
    
    // CocoaMQTT 1.3.2 instance
    private var mqtt: CocoaMQTT?
    private let connectionQueue = DispatchQueue(label: "com.wardragon.mqtt")
    
    // CocoaMQTT instance (weak reference to avoid retain cycles)
    // NOTE: You'll need to add CocoaMQTT to your project via SPM
    // For now, this is a placeholder implementation using URLSession for basic HTTP MQTT bridge
    // In production, replace with actual CocoaMQTT implementation
    
    private var reconnectTask: Task<Void, Never>?
    private var isConnecting = false
    private var messageQueue: [(topic: String, payload: Data)] = []
    private let maxQueueSize = 500
    
    // MARK: - Initialization
    
    init(configuration: MQTTConfiguration) {
        self.configuration = configuration
    }
    
    deinit {
        // Cancel reconnection task
        reconnectTask?.cancel()
        reconnectTask = nil
        
        // Disconnect MQTT (direct call to avoid actor isolation)
        mqtt?.disconnect()
        mqtt = nil
    }
    
    // MARK: - Public Methods
    
    /// Connect to MQTT broker
    func connect() {
        guard configuration.isValid else {
            logger.error("Invalid MQTT configuration")
            state = .failed(MQTTError.invalidConfiguration)
            return
        }
        
        guard state == .disconnected || state == .failed(MQTTError.connectionFailed) else {
            logger.debug("Already connecting or connected")
            return
        }
        
        state = .connecting
        isConnecting = true
        
        // Start background reconnection loop
        reconnectTask?.cancel()
        reconnectTask = Task {
            await runConnectLoop()
        }
    }
    
    /// Disconnect from MQTT broker
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        
        // Send offline status before disconnecting
        if state == .connected {
            let offlineMessage = MQTTStatusMessage(
                status: "offline",
                timestamp: ISO8601DateFormatter().string(from: Date()),
                device: UIDevice.current.name
            )
            
            if let payload = offlineMessage.json {
                Task {
                    try? await publish(
                        topic: configuration.statusTopicPath,
                        payload: payload,
                        qos: .atLeastOnce,
                        retain: true
                    )
                }
            }
        }
        
        // Disconnect MQTT
        mqtt?.disconnect()
        mqtt = nil
        
        state = .disconnected
        logger.info("Disconnected from MQTT broker")
    }
    
    /// Publish message to MQTT topic
    func publish(topic: String, payload: Data, qos: MQTTQoS? = nil, retain: Bool? = nil) async throws {
        let effectiveQoS = qos ?? configuration.qos
        let effectiveRetain = retain ?? configuration.retain
        
        // Queue message if not connected
        guard case .connected = state else {
            if messageQueue.count < maxQueueSize {
                messageQueue.append((topic, payload))
                logger.debug("Queued message to \(topic) (queue size: \(self.messageQueue.count))")
            } else {
                logger.warning("Message queue full, dropping message to \(topic)")
            }
            throw MQTTError.notConnected
        }
        
        // This is a simplified implementation
        // In production, replace with actual CocoaMQTT publish call
        try await publishInternal(topic: topic, payload: payload, qos: effectiveQoS, retain: effectiveRetain)
        
        messagesSent += 1
        logger.debug("Published to \(topic) (\(payload.count) bytes, QoS \(effectiveQoS.rawValue))")
    }
    
    /// Publish JSON message
    func publish<T: Encodable>(topic: String, message: T, qos: MQTTQoS? = nil, retain: Bool? = nil) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let payload = try encoder.encode(message)
        try await publish(topic: topic, payload: payload, qos: qos, retain: retain)
    }
    
    /// Publish drone detection
    func publishDrone(_ message: MQTTDroneMessage) async throws {
        let topic = configuration.droneTopic(for: message.mac)
        try await publish(topic: topic, message: message)
        logger.info("Published drone detection: \(message.mac)")
    }
    
    /// Publish system status
    func publishSystemStatus(_ message: MQTTSystemMessage) async throws {
        let topic = configuration.systemTopicPath
        try await publish(topic: topic, message: message, retain: true)
        logger.info("Published system status")
    }
    
    /// Publish system attributes (matches Python wardragon/system/attrs)
    func publishSystemAttributes(
        latitude: Double,
        longitude: Double,
        altitude: Double,
        gpsFix: Bool,
        kitSerial: String,
        timeSource: String = "unknown",
        gpsdTimeUTC: String? = nil
    ) async throws {
        let topic = configuration.baseTopic + "/system/attrs"
        
        let attributes: [String: Any] = [
            "gps_fix": gpsFix,
            "time_source": timeSource,
            "gpsd_time_utc": gpsdTimeUTC ?? ISO8601DateFormatter().string(from: Date()),
            "kit_serial": kitSerial,
            "latitude": latitude,
            "longitude": longitude,
            "altitude": altitude,
            "updated": Int(Date().timeIntervalSince1970)
        ]
        
        let payload = try JSONSerialization.data(withJSONObject: attributes)
        try await publish(topic: topic, payload: payload, qos: .atLeastOnce, retain: false)
        logger.info("Published system attributes to \(topic)")
    }
    
    /// Mark drone as offline (Home Assistant availability)
    func publishDroneOffline(_ macAddress: String) async throws {
        let topic = configuration.droneTopic(for: macAddress) + "/availability"
        let payload = "offline".data(using: .utf8) ?? Data()
        try await publish(topic: topic, payload: payload, qos: .atLeastOnce, retain: true)
        logger.info("Published offline status for drone: \(macAddress)")
    }
    
    /// Publish online status
    func publishOnlineStatus() async throws {
        let message = MQTTStatusMessage(
            status: "online",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            device: UIDevice.current.name
        )
        
        let topic = configuration.statusTopicPath
        try await publish(topic: topic, message: message, qos: .atLeastOnce, retain: true)
        logger.info("Published online status")
    }
    
    /// Publish Home Assistant discovery messages
    func publishHomeAssistantDiscovery(for macAddress: String, deviceName: String) async throws {
        guard configuration.homeAssistantEnabled else { return }
        
        let discoveryTopic = "\(configuration.homeAssistantDiscoveryPrefix)/device_tracker/wardragon_\(macAddress)/config"
        
        let discovery: [String: Any] = [
            "name": "WarDragon - \(deviceName)",
            "unique_id": "wardragon_\(macAddress)",
            "state_topic": configuration.droneTopic(for: macAddress),
            "json_attributes_topic": configuration.droneTopic(for: macAddress),
            "device": [
                "identifiers": ["wardragon_\(macAddress)"],
                "name": deviceName,
                "model": "Remote ID Drone",
                "manufacturer": "WarDragon",
                "sw_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
            ],
            "icon": "mdi:quadcopter",
            "availability_topic": configuration.statusTopicPath,
            "payload_available": "online",
            "payload_not_available": "offline"
        ]
        
        let payload = try JSONSerialization.data(withJSONObject: discovery)
        try await publish(topic: discoveryTopic, payload: payload, retain: true)
        
        logger.info("Published Home Assistant discovery for \(macAddress)")
    }
    
    // MARK: - Private Methods
    
    /// Background reconnection loop (matches Python behavior)
    private func runConnectLoop() async {
        var reconnectAttempts = 0
        
        while !Task.isCancelled {
            do {
                try await establishConnection()
                
                // Send online status
                try? await publishOnlineStatus()
                
                // Flush queued messages
                await flushMessageQueue()
                
                // Wait for connection to fail before retrying
                await withTaskCancellationHandler {
                    try? await Task.sleep(nanoseconds: UInt64.max)
                } onCancel: {
                    // Cancelled by disconnect() or deinit
                }
                
            } catch {
                let delay = calculateReconnectDelay(attempts: reconnectAttempts)
                logger.warning("Connection failed: \(error.localizedDescription). Retrying in \(delay)s...")
                
                await MainActor.run {
                    self.state = .failed(error)
                    self.lastError = error
                }
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    break
                }
                
                reconnectAttempts += 1
            }
        }
    }
    
    /// Establish connection to MQTT broker
    private func establishConnection() async throws {
        await MainActor.run {
            self.state = .connecting
        }
        
        let clientID = "wardragon_\(UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString)"
        
        let mqtt = CocoaMQTT(clientID: clientID, host: configuration.host, port: UInt16(configuration.port))
        mqtt.username = configuration.username
        mqtt.password = configuration.password
        mqtt.keepAlive = UInt16(configuration.keepalive)
        mqtt.cleanSession = configuration.cleanSession
        mqtt.enableSSL = configuration.useTLS
        
        // Set up callbacks (CocoaMQTT 1.3.2 style)
        mqtt.didConnectAck = { [weak self] mqtt, ack in
            Task { @MainActor in
                guard let self = self else { return }
                if ack == .accept {
                    self.logger.info("MQTT connected")
                    self.state = .connected
                } else {
                    self.logger.error("MQTT rejected: \(ack)")
                    self.state = .failed(MQTTError.connectionFailed)
                }
            }
        }
        
        mqtt.didDisconnect = { [weak self] mqtt, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.logger.warning("MQTT disconnected: \(error?.localizedDescription ?? "unknown")")
                self.state = .disconnected
            }
        }
        
        mqtt.didPublishMessage = { [weak self] mqtt, message, id in
            self?.logger.debug("Published message \(id)")
        }
        
        // Store and connect
        await MainActor.run {
            self.mqtt = mqtt
        }
        
        _ = mqtt.connect()
        
        // Wait for connection
        try await waitForConnection()
        
        logger.info("Connected to MQTT broker \(self.configuration.host):\(self.configuration.port)")
    }
    
    /// Wait for connection to establish
    private func waitForConnection() async throws {
        for _ in 0..<50 { // 5 seconds
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            
            let currentState = await MainActor.run { self.state }
            switch currentState {
            case .connected:
                return
            case .failed(let error):
                throw error
            default:
                continue
            }
        }
        throw MQTTError.connectionFailed
    }
    
    /// Publish message internally using CocoaMQTT 1.3.2
    private func publishInternal(topic: String, payload: Data, qos: MQTTQoS, retain: Bool) async throws {
        guard let mqtt = await MainActor.run(body: { self.mqtt }) else {
            throw MQTTError.notConnected
        }
        
        // Convert QoS
        let cocoaQoS: CocoaMQTTQoS
        switch qos {
        case .atMostOnce:
            cocoaQoS = .qos0
        case .atLeastOnce:
            cocoaQoS = .qos1
        case .exactlyOnce:
            cocoaQoS = .qos2
        }
        
        // Publish (CocoaMQTT 1.3.2 API)
        let messageString = String(data: payload, encoding: .utf8) ?? ""
        mqtt.publish(topic, withString: messageString, qos: cocoaQoS, retained: retain)
        
        logger.debug("Would publish \(payload.count) bytes to \(topic) (QoS \(qos.rawValue), retain: \(retain))")
    }
    
    /// Flush queued messages after connection
    private func flushMessageQueue() async {
        let queue = await MainActor.run {
            let current = self.messageQueue
            self.messageQueue.removeAll()
            return current
        }
        
        guard !queue.isEmpty else { return }
        
        logger.info("Flushing \(queue.count) queued messages")
        
        for (topic, payload) in queue {
            do {
                try await publish(topic: topic, payload: payload)
            } catch {
                logger.error("Failed to flush queued message to \(topic): \(error.localizedDescription)")
            }
        }
    }
    
    /// Calculate exponential backoff delay
    private func calculateReconnectDelay(attempts: Int) -> TimeInterval {
        let baseDelay = Double(configuration.reconnectDelay)
        let maxDelay: TimeInterval = 60.0
        
        let delay = min(baseDelay * pow(2.0, Double(attempts)), maxDelay)
        return delay
    }
}

// MARK: - Error Types

enum MQTTError: LocalizedError {
    case invalidConfiguration
    case notConnected
    case connectionFailed
    case publishFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid MQTT configuration"
        case .notConnected:
            return "Not connected to MQTT broker"
        case .connectionFailed:
            return "Connection to MQTT broker failed"
        case .publishFailed:
            return "Failed to publish message"
        }
    }
}



