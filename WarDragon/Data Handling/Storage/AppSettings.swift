//
//  AppSettings.swift
//  WarDragon
//
//  SwiftData model for app settings (migrated from UserDefaults)
//  Created on January 15, 2026.
//

import Foundation
import SwiftData

@Model
final class AppSettings {
    /// Unique identifier (singleton pattern)
    @Attribute(.unique) var id: String = "default"
    
    // MARK: - Connection Settings
    var connectionModeRaw: String = "Multicast"
    var zmqHost: String = "0.0.0.0"
    var multicastHost: String = "224.0.0.1"
    var multicastPort: Int = 6969
    var zmqTelemetryPort: Int = 4224
    var zmqStatusPort: Int = 4225
    var zmqSpectrumPort: Int = 4226
    
    // MARK: - UI Settings
    var notificationsEnabled: Bool = true
    var keepScreenOn: Bool = false
    var enableBackgroundDetection: Bool = true
    var isListening: Bool = false
    var spoofDetectionEnabled: Bool = true
    
    // MARK: - Status Notification Settings
    var statusNotificationsEnabled: Bool = true
    var statusNotificationIntervalRaw: String = "never"
    var statusNotificationThresholds: Bool = true
    var lastStatusNotificationTimestamp: Double = 0
    
    // MARK: - Warning Thresholds
    var cpuWarningThreshold: Double = 80.0
    var tempWarningThreshold: Double = 70.0
    var memoryWarningThreshold: Double = 0.85
    var plutoTempThreshold: Double = 85.0
    var zynqTempThreshold: Double = 85.0
    var proximityThreshold: Int = -60
    var enableWarnings: Bool = true
    var systemWarningsEnabled: Bool = true
    var enableProximityWarnings: Bool = true
    
    // MARK: - Processing Settings
    var messageProcessingInterval: Int = 50
    var backgroundMessageInterval: Int = 100
    var useUserLocationForStatus: Bool = false
    var hasShownStatusLocationPrompt: Bool = false
    
    // MARK: - TAK Server Settings
    var takEnabled: Bool = false
    var takHost: String = ""
    var takPort: Int = 8089
    var takProtocolRaw: String = "tls"
    var takTLSEnabled: Bool = true
    var takSkipVerification: Bool = false
    
    // MARK: - MQTT Settings
    var mqttEnabled: Bool = false
    var mqttHost: String = ""
    var mqttPort: Int = 1883
    var mqttUseTLS: Bool = false
    var mqttUsername: String = ""
    var mqttBaseTopic: String = "wardragon"
    var mqttQoSRaw: Int = 1
    var mqttRetain: Bool = false
    var mqttCleanSession: Bool = true
    var mqttHomeAssistantEnabled: Bool = false
    var mqttHomeAssistantDiscoveryPrefix: String = "homeassistant"
    var mqttKeepalive: Int = 60
    var mqttReconnectDelay: Int = 5
    
    // MARK: - ADS-B Settings
    var adsbEnabled: Bool = false
    var adsbReadsbURL: String = "http://localhost:8080"
    var adsbDataPath: String = "/data/aircraft.json"
    var adsbPollInterval: Double = 2.0
    var adsbMaxDistance: Double = 0
    var adsbMaxAircraftCount: Int = 25
    var adsbMinAltitude: Double = 0
    var adsbMaxAltitude: Double = 50000
    
    // MARK: - Lattice Settings
    var latticeEnabled: Bool = false
    var latticeServerURL: String = "https://sandbox.lattice-das.com"
    var latticeOrganizationID: String = ""
    var latticeSiteID: String = ""
    
    // MARK: - Detection Limits
    var maxDrones: Int = 30
    var maxAircraft: Int = 100
    var inactivityTimeout: Double = 60.0
    var persistDroneDetections: Bool = true
    
    // MARK: - Rate Limiting Settings
    var rateLimitEnabled: Bool = true
    var rateLimitDroneInterval: Double = 1.0
    var rateLimitDroneMaxPerMinute: Int = 30
    var rateLimitMQTTMaxPerSecond: Int = 10
    var rateLimitMQTTBurstCount: Int = 20
    var rateLimitMQTTBurstPeriod: Double = 5.0
    var rateLimitTAKMaxPerSecond: Int = 5
    var rateLimitTAKInterval: Double = 0.5
    var rateLimitWebhookMaxPerMinute: Int = 20
    var rateLimitWebhookInterval: Double = 2.0
    
    // MARK: - Webhook Settings
    var webhooksEnabled: Bool = false
    var webhookEventsJson: String = ""
    
    // MARK: - History (stored as JSON strings in SwiftData)
    var zmqHostHistoryJson: String = "[]"
    var multicastHostHistoryJson: String = "[]"
    
    init() {}
    
    // MARK: - Computed Properties for Enums
    
    var connectionMode: ConnectionMode {
        get { ConnectionMode(rawValue: connectionModeRaw) ?? .multicast }
        set { connectionModeRaw = newValue.rawValue }
    }
    
    var statusNotificationInterval: StatusNotificationInterval {
        get { StatusNotificationInterval(rawValue: statusNotificationIntervalRaw) ?? .never }
        set { statusNotificationIntervalRaw = newValue.rawValue }
    }
    
    var takProtocol: TAKProtocol {
        get { TAKProtocol(rawValue: takProtocolRaw) ?? .tls }
        set { takProtocolRaw = newValue.rawValue }
    }
    
    var mqttQoS: MQTTQoS {
        get { MQTTQoS(rawValue: mqttQoSRaw) ?? .atLeastOnce }
        set { mqttQoSRaw = newValue.rawValue }
    }
    
    var lastStatusNotificationTime: Date {
        get { Date(timeIntervalSince1970: lastStatusNotificationTimestamp) }
        set { lastStatusNotificationTimestamp = newValue.timeIntervalSince1970 }
    }
    
    // MARK: - Helper Properties
    
    var messageProcessingIntervalSeconds: TimeInterval {
        return TimeInterval(messageProcessingInterval) / 1000.0
    }
    
    var backgroundMessageIntervalSeconds: TimeInterval {
        return TimeInterval(backgroundMessageInterval) / 1000.0
    }
    
    var zmqHostHistory: [String] {
        get {
            guard let data = zmqHostHistoryJson.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                zmqHostHistoryJson = json
            }
        }
    }
    
    var multicastHostHistory: [String] {
        get {
            guard let data = multicastHostHistoryJson.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                multicastHostHistoryJson = json
            }
        }
    }
    
    var enabledWebhookEvents: Set<WebhookEvent> {
        get {
            if let data = webhookEventsJson.data(using: .utf8),
               let events = try? JSONDecoder().decode(Set<WebhookEvent>.self, from: data) {
                return events
            }
            return Set(WebhookEvent.allCases) // Default to all events enabled
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8) {
                webhookEventsJson = json
            }
        }
    }
    
    // MARK: - Configuration Getters
    
    func getMQTTConfiguration() -> MQTTConfiguration {
        // Get password from Keychain
        let password = (try? KeychainManager.shared.loadString(forKey: "mqttPassword")) ?? ""
        
        return MQTTConfiguration(
            enabled: mqttEnabled,
            host: mqttHost,
            port: mqttPort,
            useTLS: mqttUseTLS,
            username: mqttUsername.isEmpty ? nil : mqttUsername,
            password: password.isEmpty ? nil : password,
            baseTopic: mqttBaseTopic,
            droneTopicTemplate: "{base}/drones/{mac}",
            systemTopic: "{base}/system",
            statusTopic: "{base}/status",
            qos: mqttQoS,
            retain: mqttRetain,
            cleanSession: mqttCleanSession,
            homeAssistantEnabled: mqttHomeAssistantEnabled,
            homeAssistantDiscoveryPrefix: mqttHomeAssistantDiscoveryPrefix,
            keepalive: mqttKeepalive,
            reconnectDelay: mqttReconnectDelay
        )
    }
    
    func getTAKConfiguration() -> TAKConfiguration {
        // Get password from Keychain
        let p12Password = (try? KeychainManager.shared.loadString(forKey: "takP12Password")) ?? ""
        
        return TAKConfiguration(
            enabled: takEnabled,
            host: takHost,
            port: takPort,
            protocol: takProtocol,
            tlsEnabled: takTLSEnabled,
            p12CertificateData: TAKConfiguration.loadP12FromKeychain(),
            p12Password: p12Password.isEmpty ? nil : p12Password,
            skipVerification: takSkipVerification
        )
    }
    
    func getADSBConfiguration() -> ADSBConfiguration {
        return ADSBConfiguration(
            enabled: adsbEnabled,
            readsbURL: adsbReadsbURL.trimmingCharacters(in: .whitespacesAndNewlines),
            dataPath: adsbDataPath.trimmingCharacters(in: .whitespacesAndNewlines),
            pollInterval: adsbPollInterval,
            maxDistance: adsbMaxDistance > 0 ? adsbMaxDistance : nil,
            minAltitude: adsbMinAltitude > 0 ? adsbMinAltitude : nil,
            maxAltitude: adsbMaxAltitude < 50000 ? adsbMaxAltitude : nil,
            maxAircraftCount: adsbMaxAircraftCount
        )
    }
    
    func getLatticeConfiguration() -> LatticeClient.LatticeConfiguration {
        // Get token from Keychain
        let apiToken = (try? KeychainManager.shared.loadString(forKey: "latticeAPIToken")) ?? ""
        
        return LatticeClient.LatticeConfiguration(
            enabled: latticeEnabled,
            serverURL: latticeServerURL.trimmingCharacters(in: .whitespacesAndNewlines),
            apiToken: apiToken.isEmpty ? nil : apiToken,
            organizationID: latticeOrganizationID.trimmingCharacters(in: .whitespacesAndNewlines),
            siteID: latticeSiteID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    
    func getRateLimitConfiguration() -> RateLimitConfiguration {
        return RateLimitConfiguration(
            enabled: rateLimitEnabled,
            dronePublishInterval: rateLimitDroneInterval,
            droneMaxPerMinute: rateLimitDroneMaxPerMinute,
            mqttMaxPerSecond: rateLimitMQTTMaxPerSecond,
            mqttBurstCount: rateLimitMQTTBurstCount,
            mqttBurstPeriod: rateLimitMQTTBurstPeriod,
            takMaxPerSecond: rateLimitTAKMaxPerSecond,
            takPublishInterval: rateLimitTAKInterval,
            webhookMaxPerMinute: rateLimitWebhookMaxPerMinute,
            webhookPublishInterval: rateLimitWebhookInterval
        )
    }
}
