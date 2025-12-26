//
//  MQTTClient.swift
//  WarDragon
//
//  MQTT client for publishing drone detections and system status
//
//  Uses CocoaMQTT library - install via SPM:
//  https://github.com/emqx/CocoaMQTT
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
    
    // CocoaMQTT instance
    private var mqtt: CocoaMQTT?
    private var mqttDelegate: MQTTClientDelegateHandler?
    
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
        disconnect()
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
        
        // Disconnect CocoaMQTT
        mqtt?.disconnect()
        mqtt = nil
        mqttDelegate = nil
        
        state = .disconnected
        logger.info("Disconnected from MQTT broker")
    }
                    )
                }
            }
        }
        
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
                    await Task.sleep(nanoseconds: UInt64.max)
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
        
        let mqtt = CocoaMQTT(
            clientID: clientID,
            host: configuration.host,
            port: UInt16(configuration.port)
        )
        
        // Basic configuration
        mqtt.username = configuration.username
        mqtt.password = configuration.password
        mqtt.keepAlive = UInt16(configuration.keepalive)
        mqtt.cleanSession = configuration.cleanSession
        mqtt.enableSSL = configuration.useTLS
        
        // Create and set delegate
        let delegate = MQTTClientDelegateHandler(client: self)
        mqtt.delegate = delegate
        
        // Store references
        await MainActor.run {
            self.mqtt = mqtt
            self.mqttDelegate = delegate
        }
        
        // Connect
        let connected = mqtt.connect()
        if !connected {
            throw MQTTError.connectionFailed
        }
        
        // Wait for connection with timeout
        var attempts = 0
        while attempts < 50 { // 5 seconds total
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
            
            let currentState = await MainActor.run { self.state }
            switch currentState {
            case .connected:
                logger.info("Connected to MQTT broker \(self.configuration.host):\(self.configuration.port)")
                return
            case .failed(let error):
                throw error
            default:
                attempts += 1
            }
        }
        
        throw MQTTError.connectionFailed
    }
    
    /// Publish message internally using CocoaMQTT
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
        
        // Create message
        let message = CocoaMQTTMessage(topic: topic, payload: [UInt8](payload))
        message.qos = cocoaQoS
        message.retained = retain
        
        // Publish
        mqtt.publish(message)
        
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

// MARK: - CocoaMQTT Delegate Handler

class MQTTClientDelegateHandler: CocoaMQTTDelegate {
    weak var client: MQTTClient?
    private let logger = Logger(subsystem: "com.wardragon", category: "MQTTDelegate")
    
    init(client: MQTTClient) {
        self.client = client
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        Task { @MainActor in
            guard let client = client else { return }
            
            if ack == .accept {
                logger.info("MQTT connection accepted")
                client.state = .connected
            } else {
                logger.error("MQTT connection rejected: \(ack)")
                client.state = .failed(MQTTError.connectionFailed)
            }
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        Task { @MainActor in
            guard let client = client else { return }
            
            switch state {
            case .initial:
                client.state = .disconnected
            case .connecting:
                client.state = .connecting
            case .connected:
                client.state = .connected
            case .disconnected:
                client.state = .disconnected
            @unknown default:
                break
            }
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        logger.debug("Published message \(id) to \(message.topic)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        logger.debug("Publish ACK \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        // Handle incoming messages if needed (for future subscriptions)
        logger.debug("Received message on \(message.topic)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        logger.info("Subscribed to topics successfully")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        logger.info("Unsubscribed from topics")
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        // Keepalive ping
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        // Keepalive pong
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        Task { @MainActor in
            guard let client = client else { return }
            
            if let error = err {
                logger.warning("MQTT disconnected with error: \(error.localizedDescription)")
                client.state = .failed(error)
            } else {
                logger.info("MQTT disconnected gracefully")
                client.state = .disconnected
            }
        }
    }
}


