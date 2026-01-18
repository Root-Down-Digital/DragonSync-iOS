//
//  MQTTClient+CocoaMQTT.swift
//  WarDragon
//
//  Example implementation using CocoaMQTT library
//  
//  TO USE THIS FILE:
//  1. Add CocoaMQTT package: https://github.com/emqx/CocoaMQTT
//  2. Uncomment the code below
//  3. Replace the placeholder methods in MQTTClient.swift with these
//

/*

import CocoaMQTT

// MARK: - CocoaMQTT Integration

extension MQTTClient {
    
    /// Establish connection using CocoaMQTT
    func establishConnectionWithCocoaMQTT() async throws {
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
        
        // Delegate callbacks
        mqtt.didConnectAck = { [weak self] mqtt, ack in
            guard let self = self else { return }
            
            Task { @MainActor in
                if ack == .accept {
                    self.logger.info("Connected to MQTT broker")
                    self.state = .connected
                    self.isConnecting = false
                } else {
                    self.logger.error("Connection rejected: \(ack)")
                    self.state = .failed(MQTTError.connectionFailed)
                }
            }
        }
        
        mqtt.didDisconnect = { [weak self] mqtt, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let error = error {
                    self.logger.warning("Disconnected: \(error.localizedDescription)")
                    self.state = .failed(error)
                } else {
                    self.logger.info("Disconnected gracefully")
                    self.state = .disconnected
                }
            }
        }
        
        mqtt.didPublishMessage = { [weak self] mqtt, message, id in
            guard let self = self else { return }
            self.logger.debug("Published message \(id) to \(message.topic)")
        }
        
        mqtt.didPublishAck = { [weak self] mqtt, id in
            guard let self = self else { return }
            self.logger.debug("Publish acknowledged: \(id)")
        }
        
        mqtt.didReceiveMessage = { [weak self] mqtt, message, id in
            // If you want to support subscriptions in the future
            guard let self = self else { return }
            self.logger.debug("Received message on \(message.topic)")
        }
        
        // Store reference (you'll need to add a property: private var mqtt: CocoaMQTT?)
        // self.mqtt = mqtt
        
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
                return
            case .failed(let error):
                throw error
            default:
                attempts += 1
            }
        }
        
        throw MQTTError.connectionFailed
    }
    
    /// Publish message using CocoaMQTT
    func publishWithCocoaMQTT(topic: String, payload: Data, qos: MQTTQoS, retain: Bool) async throws {
        // Assuming you have: private var mqtt: CocoaMQTT?
        // guard let mqtt = mqtt else {
        //     throw MQTTError.notConnected
        // }
        
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
        // mqtt.publish(message)
        
        logger.debug("Published \(payload.count) bytes to \(topic)")
    }
    
    /// Disconnect using CocoaMQTT
    func disconnectCocoaMQTT() {
        // mqtt?.disconnect()
        // mqtt = nil
        state = .disconnected
        logger.info("Disconnected from MQTT broker")
    }
}

// MARK: - CocoaMQTT Delegate (Alternative Approach)

// You can also implement this as a proper delegate:

class MQTTClientDelegate: CocoaMQTTDelegate {
    weak var client: MQTTClient?
    
    init(client: MQTTClient) {
        self.client = client
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        guard let client = client else { return }
        
        Task { @MainActor in
            if ack == .accept {
                client.state = .connected
            } else {
                client.state = .failed(MQTTError.connectionFailed)
            }
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        guard let client = client else { return }
        
        Task { @MainActor in
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
        guard let client = client else { return }
        client.logger.debug("Published message \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        guard let client = client else { return }
        client.logger.debug("Publish ACK \(id)")
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        // Handle incoming messages if needed
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        // Handle subscriptions if needed
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        // Handle unsubscriptions if needed
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        // Keepalive ping
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        // Keepalive pong
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        guard let client = client else { return }
        
        Task { @MainActor in
            if let error = err {
                client.state = .failed(error)
            } else {
                client.state = .disconnected
            }
        }
    }
}

// MARK: - Updated MQTTClient with CocoaMQTT

/*
To integrate, modify your MQTTClient class:

@MainActor
class MQTTClient: ObservableObject {
    // Add these properties:
    private var mqtt: CocoaMQTT?
    private var mqttDelegate: MQTTClientDelegate?
    
    private func establishConnection() async throws {
        try await establishConnectionWithCocoaMQTT()
    }
    
    private func publishInternal(topic: String, payload: Data, qos: MQTTQoS, retain: Bool) async throws {
        try await publishWithCocoaMQTT(topic: topic, payload: payload, qos: qos, retain: retain)
    }
    
    func disconnect() {
        disconnectCocoaMQTT()
        reconnectTask?.cancel()
        reconnectTask = nil
    }
}
*/

*/

// MARK: - Installation Instructions

/*

## Add CocoaMQTT via Swift Package Manager

1. In Xcode, go to File → Add Package Dependencies
2. Enter the URL: https://github.com/emqx/CocoaMQTT
3. Select version 2.x.x (latest stable)
4. Click "Add Package"
5. Add to your WarDragon target

## Alternative: Add via Package.swift (for SPM projects)

dependencies: [
    .package(url: "https://github.com/emqx/CocoaMQTT.git", from: "2.0.0")
]

## Testing with Mosquitto (Local Broker)

# Install Mosquitto
brew install mosquitto

# Start broker with verbose logging
mosquitto -v

# In another terminal, subscribe to all WarDragon topics:
mosquitto_sub -h localhost -t "wardragon/#" -v

# Test authentication (create password file first):
mosquitto_passwd -c /usr/local/etc/mosquitto/passwd wardragon
# Edit /usr/local/etc/mosquitto/mosquitto.conf:
# allow_anonymous false
# password_file /usr/local/etc/mosquitto/passwd
mosquitto -c /usr/local/etc/mosquitto/mosquitto.conf

## Testing with Public Broker (No Auth)

Use test.mosquitto.org:
- Host: test.mosquitto.org
- Port: 1883 (TCP) or 8883 (TLS)
- No authentication required

## Home Assistant MQTT Addon

1. Install MQTT add-on in Home Assistant
2. Configure username/password
3. Enable MQTT discovery in Configuration → Integrations → MQTT
4. Point WarDragon to HA IP address, port 1883

*/
