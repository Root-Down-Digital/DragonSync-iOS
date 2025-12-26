//
//  MQTTConfiguration.swift
//  WarDragon
//
//  MQTT broker configuration model
//

import Foundation

/// MQTT Quality of Service levels
enum MQTTQoS: Int, Codable, CaseIterable {
    case atMostOnce = 0      // Fire and forget
    case atLeastOnce = 1     // Acknowledged delivery
    case exactlyOnce = 2     // Assured delivery
    
    var displayName: String {
        switch self {
        case .atMostOnce: return "At most once (0)"
        case .atLeastOnce: return "At least once (1)"
        case .exactlyOnce: return "Exactly once (2)"
        }
    }
    
    var description: String {
        switch self {
        case .atMostOnce: return "Fire and forget - no acknowledgment"
        case .atLeastOnce: return "Acknowledged delivery - may duplicate"
        case .exactlyOnce: return "Assured delivery - no duplicates"
        }
    }
}

/// MQTT broker configuration
struct MQTTConfiguration: Codable, Equatable {
    var enabled: Bool
    var host: String
    var port: Int
    var useTLS: Bool
    
    // Authentication
    var username: String?
    var password: String?
    
    // Topic configuration
    var baseTopic: String
    var droneTopicTemplate: String  // e.g., "{base}/drones/{mac}"
    var systemTopic: String         // e.g., "{base}/system"
    var statusTopic: String         // e.g., "{base}/status"
    
    // Publishing options
    var qos: MQTTQoS
    var retain: Bool                // Retain messages on broker
    var cleanSession: Bool          // Clean session on connect
    
    // Home Assistant integration
    var homeAssistantEnabled: Bool
    var homeAssistantDiscoveryPrefix: String
    
    // Keepalive and reconnection
    var keepalive: Int              // Seconds
    var reconnectDelay: Int         // Seconds
    
    init(
        enabled: Bool = false,
        host: String = "",
        port: Int = 1883,
        useTLS: Bool = false,
        username: String? = nil,
        password: String? = nil,
        baseTopic: String = "wardragon",
        droneTopicTemplate: String = "{base}/drones/{mac}",
        systemTopic: String = "{base}/system",
        statusTopic: String = "{base}/status",
        qos: MQTTQoS = .atLeastOnce,
        retain: Bool = false,
        cleanSession: Bool = true,
        homeAssistantEnabled: Bool = false,
        homeAssistantDiscoveryPrefix: String = "homeassistant",
        keepalive: Int = 60,
        reconnectDelay: Int = 5
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.username = username
        self.password = password
        self.baseTopic = baseTopic
        self.droneTopicTemplate = droneTopicTemplate
        self.systemTopic = systemTopic
        self.statusTopic = statusTopic
        self.qos = qos
        self.retain = retain
        self.cleanSession = cleanSession
        self.homeAssistantEnabled = homeAssistantEnabled
        self.homeAssistantDiscoveryPrefix = homeAssistantDiscoveryPrefix
        self.keepalive = keepalive
        self.reconnectDelay = reconnectDelay
    }
    
    var isValid: Bool {
        !host.isEmpty && port > 0 && port < 65536 && !baseTopic.isEmpty
    }
    
    /// Build topic from template
    func buildTopic(_ template: String, macAddress: String? = nil) -> String {
        var topic = template
            .replacingOccurrences(of: "{base}", with: baseTopic)
        
        if let mac = macAddress {
            topic = topic.replacingOccurrences(of: "{mac}", with: mac)
        }
        
        return topic
    }
    
    /// Get drone-specific topic
    func droneTopic(for macAddress: String) -> String {
        buildTopic(droneTopicTemplate, macAddress: macAddress)
    }
    
    /// Get system topic
    var systemTopicPath: String {
        buildTopic(systemTopic)
    }
    
    /// Get status topic
    var statusTopicPath: String {
        buildTopic(statusTopic)
    }
    
    static func == (lhs: MQTTConfiguration, rhs: MQTTConfiguration) -> Bool {
        lhs.enabled == rhs.enabled &&
        lhs.host == rhs.host &&
        lhs.port == rhs.port &&
        lhs.useTLS == rhs.useTLS &&
        lhs.username == rhs.username &&
        lhs.password == rhs.password &&
        lhs.baseTopic == rhs.baseTopic &&
        lhs.qos == rhs.qos
    }
}

// MARK: - MQTT Message Types

/// MQTT message payload for drone detection
struct MQTTDroneMessage: Codable {
    let mac: String
    let manufacturer: String?
    let rssi: Int?
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let speed: Double?
    let heading: Double?
    let pilotLatitude: Double?
    let pilotLongitude: Double?
    let homeLatitude: Double?
    let homeLongitude: Double?
    let timestamp: String
    let uaType: String?
    let serialNumber: String?
    let caaRegistration: String?
    
    // Additional metadata
    let freq: String?
    let seenBy: String?
    let observedAt: String?
    
    var json: Data? {
        try? JSONEncoder().encode(self)
    }
}

/// MQTT message payload for system status
struct MQTTSystemMessage: Codable {
    let timestamp: String
    let cpuUsage: Double?
    let memoryUsed: Double?
    let temperature: Double?
    let plutoTemp: Double?
    let zynqTemp: Double?
    let gpsFix: Bool?
    let dronesTracked: Int
    let uptime: String?
    
    var json: Data? {
        try? JSONEncoder().encode(self)
    }
}

/// MQTT message for online/offline status
struct MQTTStatusMessage: Codable {
    let status: String  // "online" or "offline"
    let timestamp: String
    let device: String
    
    var json: Data? {
        try? JSONEncoder().encode(self)
    }
}
