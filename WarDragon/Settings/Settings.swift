//
//  Settings.swift
//  WarDragon
//
//  Created by Luke on 11/23/24.
//

import Foundation
import SwiftUI

enum ConnectionMode: String, Codable, CaseIterable {
    case multicast = "Multicast"
    case zmq = "Direct ZMQ"
    //    case both = "Both"
    
    var icon: String {
        switch self {
        case .multicast:
            return "antenna.radiowaves.left.and.right"
        case .zmq:
            return "network"
        }
    }
}

//MARK: - Local stored vars (nothing sensitive)

class Settings: ObservableObject {
    static let shared = Settings()
    
    
    
    @AppStorage("connectionMode") var connectionMode: ConnectionMode = .multicast {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("zmqHost") var zmqHost: String = "0.0.0.0" {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("multicastHost") var multicastHost: String = "224.0.0.1" {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("notificationsEnabled") var notificationsEnabled = true {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("keepScreenOn") var keepScreenOn = false {
        didSet {
            objectWillChange.send()
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        }
    }
    @AppStorage("enableBackgroundDetection") var enableBackgroundDetection = true {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("multicastPort") var multicastPort: Int = 6969 {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("zmqTelemetryPort") var zmqTelemetryPort: Int = 4224 {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("zmqStatusPort") var zmqStatusPort: Int = 4225 {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("isListening") var isListening = false {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("spoofDetectionEnabled") var spoofDetectionEnabled = true {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("zmqSpectrumPort") var zmqSpectrumPort: Int = 4226 {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("zmqHostHistory") var zmqHostHistoryJson: String = "[]" {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("multicastHostHistory") var multicastHostHistoryJson: String = "[]" {
        didSet {
            objectWillChange.send()
        }
    }
    // MARK: - Status Notification Settings
    @AppStorage("statusNotificationsEnabled") var statusNotificationsEnabled = true {
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("statusNotificationInterval") var statusNotificationInterval: StatusNotificationInterval = .never {
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("statusNotificationThresholds") var statusNotificationThresholds = true {
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("lastStatusNotificationTime") private var lastStatusNotificationTimestamp: Double = 0
    
    var lastStatusNotificationTime: Date {
        get {
            Date(timeIntervalSince1970: lastStatusNotificationTimestamp)
        }
        set {
            lastStatusNotificationTimestamp = newValue.timeIntervalSince1970
        }
    }
    
    func updateStatusNotificationSettings(
        enabled: Bool,
        interval: StatusNotificationInterval,
        thresholds: Bool
    ) {
        statusNotificationsEnabled = enabled
        statusNotificationInterval = interval
        statusNotificationThresholds = thresholds
    }
    
    func shouldSendStatusNotification() -> Bool {
        guard statusNotificationsEnabled else { return false }
        
        let now = Date()
        let timeSinceLastNotification = now.timeIntervalSince(lastStatusNotificationTime)
        
        switch statusNotificationInterval {
        case .never:
            return false
        case .always:
            return true  // Always send status notifications
        case .thresholdOnly:
            return false  // Don't send regular status updates, only thresholds
        case .every5Minutes:
            return timeSinceLastNotification >= 300
        case .every15Minutes:
            return timeSinceLastNotification >= 900
        case .every30Minutes:
            return timeSinceLastNotification >= 1800
        case .hourly:
            return timeSinceLastNotification >= 3600
        case .every2Hours:
            return timeSinceLastNotification >= 7200
        case .every6Hours:
            return timeSinceLastNotification >= 21600
        case .daily:
            return timeSinceLastNotification >= 86400
        }
    }
    // MARK: - Webhook Settings
    @AppStorage("webhooksEnabled") var webhooksEnabled = false {
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("webhookEvents") private var webhookEventsJson = "" {
        didSet {
            objectWillChange.send()
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
    
    func updateWebhookSettings(enabled: Bool, events: Set<WebhookEvent>? = nil) {
        webhooksEnabled = enabled
        if let events = events {
            enabledWebhookEvents = events
        }
    }
    //MARK: - Warning Thresholds
    @AppStorage("cpuWarningThreshold") var cpuWarningThreshold: Double = 80.0 {  // 80% CPU
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("tempWarningThreshold") var tempWarningThreshold: Double = 70.0 {  // 70°C
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("memoryWarningThreshold") var memoryWarningThreshold: Double = 0.85 {  // 85%
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("plutoTempThreshold") var plutoTempThreshold: Double = 85.0 {  // 85°C
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("zynqTempThreshold") var zynqTempThreshold: Double = 85.0 {  // 85°C
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("proximityThreshold") var proximityThreshold: Int = -60 {  // -60 dBm
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("enableWarnings") var enableWarnings = true {
        didSet {
            objectWillChange.send()
        }
    }
    
    @AppStorage("systemWarningsEnabled") var systemWarningsEnabled = true {
        didSet {
            objectWillChange.send()
        }
    }
    @AppStorage("enableProximityWarnings") var enableProximityWarnings = true
    @AppStorage("messageProcessingInterval") var messageProcessingInterval: Int = 50
    @AppStorage("backgroundMessageInterval") var backgroundMessageInterval: Int = 100
    @AppStorage("useUserLocationForStatus") var useUserLocationForStatus = false {
        didSet { objectWillChange.send() }
    }

    @AppStorage("hasShownStatusLocationPrompt") var hasShownStatusLocationPrompt = false {
        didSet { objectWillChange.send() }
    }

    // MARK: - TAK Server Settings
    @AppStorage("takEnabled") var takEnabled = false {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("takHost") var takHost: String = "" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("takPort") var takPort: Int = 8089 {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("takProtocol") private var takProtocolRaw: String = TAKProtocol.tls.rawValue {
        didSet { objectWillChange.send() }
    }
    
    var takProtocol: TAKProtocol {
        get { TAKProtocol(rawValue: takProtocolRaw) ?? .tls }
        set { takProtocolRaw = newValue.rawValue }
    }
    
    @AppStorage("takTLSEnabled") var takTLSEnabled = true {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("takSkipVerification") var takSkipVerification = false {
        didSet { objectWillChange.send() }
    }
    
    // P12 password stored in UserDefaults (not ideal but matches webhook pattern)
    @AppStorage("takP12Password") private var takP12Password: String = "" {
        didSet { objectWillChange.send() }
    }
    
    var takConfiguration: TAKConfiguration {
        get {
            TAKConfiguration(
                enabled: takEnabled,
                host: takHost,
                port: takPort,
                protocol: takProtocol,
                tlsEnabled: takTLSEnabled,
                p12CertificateData: TAKConfiguration.loadP12FromKeychain(),
                p12Password: takP12Password.isEmpty ? nil : takP12Password,
                skipVerification: takSkipVerification
            )
        }
        set {
            takEnabled = newValue.enabled
            takHost = newValue.host
            takPort = newValue.port
            takProtocol = newValue.protocol
            takTLSEnabled = newValue.tlsEnabled
            takSkipVerification = newValue.skipVerification
            takP12Password = newValue.p12Password ?? ""
            
            // Save certificate to keychain if provided
            if let certData = newValue.p12CertificateData {
                try? newValue.saveP12ToKeychain()
            }
        }
    }
    
    func updateTAKConfiguration(_ config: TAKConfiguration) {
        takConfiguration = config
    }
    
    // MARK: - MQTT Settings
    @AppStorage("mqttEnabled") var mqttEnabled = false {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttHost") var mqttHost: String = "" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttPort") var mqttPort: Int = 1883 {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttUseTLS") var mqttUseTLS = false {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttUsername") var mqttUsername: String = "" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttPassword") private var mqttPassword: String = "" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttBaseTopic") var mqttBaseTopic: String = "wardragon" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttQoS") private var mqttQoSRaw: Int = 1 {
        didSet { objectWillChange.send() }
    }
    
    var mqttQoS: MQTTQoS {
        get { MQTTQoS(rawValue: mqttQoSRaw) ?? .atLeastOnce }
        set { mqttQoSRaw = newValue.rawValue }
    }
    
    @AppStorage("mqttRetain") var mqttRetain = false {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttCleanSession") var mqttCleanSession = true {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttHomeAssistantEnabled") var mqttHomeAssistantEnabled = false {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttHomeAssistantDiscoveryPrefix") var mqttHomeAssistantDiscoveryPrefix: String = "homeassistant" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttKeepalive") var mqttKeepalive: Int = 60 {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("mqttReconnectDelay") var mqttReconnectDelay: Int = 5 {
        didSet { objectWillChange.send() }
    }
    
    var mqttConfiguration: MQTTConfiguration {
        get {
            MQTTConfiguration(
                enabled: mqttEnabled,
                host: mqttHost,
                port: mqttPort,
                useTLS: mqttUseTLS,
                username: mqttUsername.isEmpty ? nil : mqttUsername,
                password: mqttPassword.isEmpty ? nil : mqttPassword,
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
        set {
            mqttEnabled = newValue.enabled
            mqttHost = newValue.host
            mqttPort = newValue.port
            mqttUseTLS = newValue.useTLS
            mqttUsername = newValue.username ?? ""
            mqttPassword = newValue.password ?? ""
            mqttBaseTopic = newValue.baseTopic
            mqttQoS = newValue.qos
            mqttRetain = newValue.retain
            mqttCleanSession = newValue.cleanSession
            mqttHomeAssistantEnabled = newValue.homeAssistantEnabled
            mqttHomeAssistantDiscoveryPrefix = newValue.homeAssistantDiscoveryPrefix
            mqttKeepalive = newValue.keepalive
            mqttReconnectDelay = newValue.reconnectDelay
        }
    }
    
    func updateMQTTConfiguration(_ config: MQTTConfiguration) {
        mqttConfiguration = config
    }
    
    // MARK: - ADS-B Settings
    @AppStorage("adsbEnabled") var adsbEnabled = false {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("adsbReadsbURL") var adsbReadsbURL: String = "http://localhost:8080" {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("adsbPollInterval") var adsbPollInterval: Double = 2.0 {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("adsbMaxDistance") var adsbMaxDistance: Double = 0 {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("adsbMinAltitude") var adsbMinAltitude: Double = 0 {
        didSet { objectWillChange.send() }
    }
    
    @AppStorage("adsbMaxAltitude") var adsbMaxAltitude: Double = 50000 {
        didSet { objectWillChange.send() }
    }
    
    var adsbConfiguration: ADSBConfiguration {
        get {
            ADSBConfiguration(
                enabled: adsbEnabled,
                readsbURL: adsbReadsbURL,
                pollInterval: adsbPollInterval,
                maxDistance: adsbMaxDistance > 0 ? adsbMaxDistance : nil,
                minAltitude: adsbMinAltitude > 0 ? adsbMinAltitude : nil,
                maxAltitude: adsbMaxAltitude < 50000 ? adsbMaxAltitude : nil
            )
        }
        set {
            adsbEnabled = newValue.enabled
            adsbReadsbURL = newValue.readsbURL
            adsbPollInterval = newValue.pollInterval
            adsbMaxDistance = newValue.maxDistance ?? 0
            adsbMinAltitude = newValue.minAltitude ?? 0
            adsbMaxAltitude = newValue.maxAltitude ?? 50000
        }
    }
    
    func updateADSBConfiguration(_ config: ADSBConfiguration) {
        adsbConfiguration = config
    }
    
    //MARK: - Connection
    
    private init() {
        toggleListening(false)
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
    }
    
    func updateConnection(mode: ConnectionMode, host: String? = nil, isZmqHost: Bool = false) {
        if let host = host {
            if isZmqHost {
                zmqHost = host
            } else {
                multicastHost = host
            }
        }
        connectionMode = mode
    }

    func updateStatusLocationSettings(useLocation: Bool) {
        useUserLocationForStatus = useLocation
        hasShownStatusLocationPrompt = true
    }

    func isHostConfigurationValid() -> Bool {
        switch connectionMode {
        case .multicast:
            return !multicastHost.isEmpty
        case .zmq:
            return !zmqHost.isEmpty
        }
    }
    
    func toggleListening(_ active: Bool) {
        if active == isListening {
            return
        }
        
        print("Settings: Toggle listening to \(active)")
        isListening = active
        objectWillChange.send()
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

    
    func updateConnectionHistory(host: String, isZmq: Bool) {
        if isZmq {
            var history = zmqHostHistory
            history.removeAll { $0 == host }
            history.insert(host, at: 0)
            if history.count > 5 {
                history = Array(history.prefix(5))
            }
            zmqHostHistory = history
        } else {
            var history = multicastHostHistory
            history.removeAll { $0 == host }
            history.insert(host, at: 0)
            if history.count > 5 {
                history = Array(history.prefix(5))
            }
            multicastHostHistory = history
        }
    }
    
    var messageProcessingIntervalSeconds: TimeInterval {
        return TimeInterval(messageProcessingInterval) / 1000.0
    }
    
    var backgroundMessageIntervalSeconds: TimeInterval {
        return TimeInterval(backgroundMessageInterval) / 1000.0
    }
    
    func updatePreferences(notifications: Bool, screenOn: Bool) {
        notificationsEnabled = notifications
        keepScreenOn = screenOn
    }
    
    func updateWarningThresholds(
        cpu: Double? = nil,
        temp: Double? = nil,
        memory: Double? = nil,
        plutoTemp: Double? = nil,
        zynqTemp: Double? = nil,
        proximity: Int? = nil
    ) {
        if let cpu = cpu { cpuWarningThreshold = cpu }
        if let temp = temp { tempWarningThreshold = temp }
        if let memory = memory { memoryWarningThreshold = memory }
        if let plutoTemp = plutoTemp { plutoTempThreshold = plutoTemp }
        if let zynqTemp = zynqTemp { zynqTempThreshold = zynqTemp }
        if let proximity = proximity { proximityThreshold = proximity }
        objectWillChange.send()
    }
}
