//
//  Settings.swift
//  WarDragon
//
//  Created by Luke on 11/23/24.
//

import Foundation
import SwiftUI
import SwiftData

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

@MainActor
class Settings: ObservableObject {
    static let shared = Settings()
    
    private var modelContext: ModelContext?
    private var appSettings: AppSettings?
    
    // Migration flag - true if we're still migrating from UserDefaults
    private var isMigrating = true
    
    private init() {
        // Migrate sensitive data from UserDefaults to Keychain on first launch
        KeychainManager.migrateSensitiveData()
        // Note: keepScreenOn will be set after configure() is called
    }
    
    func configure(with context: ModelContext) {
        self.modelContext = context
        loadOrCreateSettings()
        
        // Apply screen-on setting after loading
        UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        
        // Migration is complete
        isMigrating = false
        
        print("Settings configured with SwiftData")
    }
    
    private func loadOrCreateSettings() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<AppSettings>()
        do {
            let results = try context.fetch(descriptor)
            if let existing = results.first {
                self.appSettings = existing
                print("Loaded existing AppSettings from SwiftData")
            } else {
                // Create new settings and migrate from UserDefaults
                let newSettings = AppSettings()
                migrateFromUserDefaults(to: newSettings)
                context.insert(newSettings)
                try context.save()
                self.appSettings = newSettings
                print("Created new AppSettings and migrated from UserDefaults")
            }
        } catch {
            print("❌ Failed to load AppSettings: \(error)")
        }
    }
    
    private func migrateFromUserDefaults(to settings: AppSettings) {
        // Only migrate if UserDefaults has values (check a few key ones)
        let ud = UserDefaults.standard
        
        // Check if we have existing data to migrate
        guard ud.object(forKey: "connectionMode") != nil else {
            print("ℹ️ No UserDefaults data to migrate - using defaults")
            return
        }
        
        print("🔄 Migrating settings from UserDefaults to SwiftData...")
        
        // Connection Settings
        if let mode = ud.string(forKey: "connectionMode") {
            settings.connectionModeRaw = mode
        }
        settings.zmqHost = ud.string(forKey: "zmqHost") ?? "0.0.0.0"
        settings.multicastHost = ud.string(forKey: "multicastHost") ?? "224.0.0.1"
        settings.multicastPort = ud.integer(forKey: "multicastPort") != 0 ? ud.integer(forKey: "multicastPort") : 6969
        settings.zmqTelemetryPort = ud.integer(forKey: "zmqTelemetryPort") != 0 ? ud.integer(forKey: "zmqTelemetryPort") : 4224
        settings.zmqStatusPort = ud.integer(forKey: "zmqStatusPort") != 0 ? ud.integer(forKey: "zmqStatusPort") : 4225
        settings.zmqSpectrumPort = ud.integer(forKey: "zmqSpectrumPort") != 0 ? ud.integer(forKey: "zmqSpectrumPort") : 4226
        
        // UI Settings
        settings.notificationsEnabled = ud.bool(forKey: "notificationsEnabled")
        settings.keepScreenOn = ud.bool(forKey: "keepScreenOn")
        settings.enableBackgroundDetection = ud.object(forKey: "enableBackgroundDetection") != nil ? ud.bool(forKey: "enableBackgroundDetection") : true
        settings.isListening = ud.bool(forKey: "isListening")
        settings.spoofDetectionEnabled = ud.object(forKey: "spoofDetectionEnabled") != nil ? ud.bool(forKey: "spoofDetectionEnabled") : true
        
        // Status Notifications
        settings.statusNotificationsEnabled = ud.object(forKey: "statusNotificationsEnabled") != nil ? ud.bool(forKey: "statusNotificationsEnabled") : true
        if let interval = ud.string(forKey: "statusNotificationInterval") {
            settings.statusNotificationIntervalRaw = interval
        }
        settings.statusNotificationThresholds = ud.object(forKey: "statusNotificationThresholds") != nil ? ud.bool(forKey: "statusNotificationThresholds") : true
        settings.lastStatusNotificationTimestamp = ud.double(forKey: "lastStatusNotificationTime")
        
        // Warning Thresholds
        settings.cpuWarningThreshold = ud.object(forKey: "cpuWarningThreshold") != nil ? ud.double(forKey: "cpuWarningThreshold") : 80.0
        settings.tempWarningThreshold = ud.object(forKey: "tempWarningThreshold") != nil ? ud.double(forKey: "tempWarningThreshold") : 70.0
        settings.memoryWarningThreshold = ud.object(forKey: "memoryWarningThreshold") != nil ? ud.double(forKey: "memoryWarningThreshold") : 0.85
        settings.plutoTempThreshold = ud.object(forKey: "plutoTempThreshold") != nil ? ud.double(forKey: "plutoTempThreshold") : 85.0
        settings.zynqTempThreshold = ud.object(forKey: "zynqTempThreshold") != nil ? ud.double(forKey: "zynqTempThreshold") : 85.0
        settings.proximityThreshold = ud.object(forKey: "proximityThreshold") != nil ? ud.integer(forKey: "proximityThreshold") : -60
        settings.enableWarnings = ud.object(forKey: "enableWarnings") != nil ? ud.bool(forKey: "enableWarnings") : true
        settings.systemWarningsEnabled = ud.object(forKey: "systemWarningsEnabled") != nil ? ud.bool(forKey: "systemWarningsEnabled") : true
        settings.enableProximityWarnings = ud.bool(forKey: "enableProximityWarnings")
        
        // Processing
        settings.messageProcessingInterval = ud.integer(forKey: "messageProcessingInterval") != 0 ? ud.integer(forKey: "messageProcessingInterval") : 50
        settings.backgroundMessageInterval = ud.integer(forKey: "backgroundMessageInterval") != 0 ? ud.integer(forKey: "backgroundMessageInterval") : 100
        settings.useUserLocationForStatus = ud.bool(forKey: "useUserLocationForStatus")
        settings.hasShownStatusLocationPrompt = ud.bool(forKey: "hasShownStatusLocationPrompt")
        
        // TAK
        settings.takEnabled = ud.bool(forKey: "takEnabled")
        settings.takHost = ud.string(forKey: "takHost") ?? ""
        settings.takPort = ud.integer(forKey: "takPort") != 0 ? ud.integer(forKey: "takPort") : 8089
        if let proto = ud.string(forKey: "takProtocol") {
            settings.takProtocolRaw = proto
        }
        settings.takTLSEnabled = ud.object(forKey: "takTLSEnabled") != nil ? ud.bool(forKey: "takTLSEnabled") : true
        settings.takSkipVerification = ud.bool(forKey: "takSkipVerification")
        
        // MQTT
        settings.mqttEnabled = ud.bool(forKey: "mqttEnabled")
        settings.mqttHost = ud.string(forKey: "mqttHost") ?? ""
        settings.mqttPort = ud.integer(forKey: "mqttPort") != 0 ? ud.integer(forKey: "mqttPort") : 1883
        settings.mqttUseTLS = ud.bool(forKey: "mqttUseTLS")
        settings.mqttUsername = ud.string(forKey: "mqttUsername") ?? ""
        settings.mqttBaseTopic = ud.string(forKey: "mqttBaseTopic") ?? "wardragon"
        settings.mqttQoSRaw = ud.object(forKey: "mqttQoS") != nil ? ud.integer(forKey: "mqttQoS") : 1
        settings.mqttRetain = ud.bool(forKey: "mqttRetain")
        settings.mqttCleanSession = ud.object(forKey: "mqttCleanSession") != nil ? ud.bool(forKey: "mqttCleanSession") : true
        settings.mqttHomeAssistantEnabled = ud.bool(forKey: "mqttHomeAssistantEnabled")
        settings.mqttHomeAssistantDiscoveryPrefix = ud.string(forKey: "mqttHomeAssistantDiscoveryPrefix") ?? "homeassistant"
        settings.mqttKeepalive = ud.integer(forKey: "mqttKeepalive") != 0 ? ud.integer(forKey: "mqttKeepalive") : 60
        settings.mqttReconnectDelay = ud.integer(forKey: "mqttReconnectDelay") != 0 ? ud.integer(forKey: "mqttReconnectDelay") : 5
        
        // ADS-B
        settings.adsbEnabled = ud.bool(forKey: "adsbEnabled")
        settings.adsbReadsbURL = ud.string(forKey: "adsbReadsbURL") ?? "http://localhost:8080"
        settings.adsbDataPath = ud.string(forKey: "adsbDataPath") ?? "/data/aircraft.json"
        settings.adsbPollInterval = ud.object(forKey: "adsbPollInterval") != nil ? ud.double(forKey: "adsbPollInterval") : 2.0
        settings.adsbMaxDistance = ud.double(forKey: "adsbMaxDistance")
        settings.adsbMaxAircraftCount = ud.integer(forKey: "adsbMaxAircraftCount") != 0 ? ud.integer(forKey: "adsbMaxAircraftCount") : 25
        settings.adsbMinAltitude = ud.double(forKey: "adsbMinAltitude")
        settings.adsbMaxAltitude = ud.object(forKey: "adsbMaxAltitude") != nil ? ud.double(forKey: "adsbMaxAltitude") : 50000
        
        // Lattice
        settings.latticeEnabled = ud.bool(forKey: "latticeEnabled")
        settings.latticeServerURL = ud.string(forKey: "latticeServerURL") ?? "https://sandbox.lattice-das.com"
        settings.latticeOrganizationID = ud.string(forKey: "latticeOrganizationID") ?? ""
        settings.latticeSiteID = ud.string(forKey: "latticeSiteID") ?? ""
        
        // Detection Limits
        settings.maxDrones = ud.integer(forKey: "maxDrones") != 0 ? ud.integer(forKey: "maxDrones") : 30
        settings.maxAircraft = ud.integer(forKey: "maxAircraft") != 0 ? ud.integer(forKey: "maxAircraft") : 100
        settings.inactivityTimeout = ud.object(forKey: "inactivityTimeout") != nil ? ud.double(forKey: "inactivityTimeout") : 60.0
        settings.persistDroneDetections = ud.object(forKey: "persistDroneDetections") != nil ? ud.bool(forKey: "persistDroneDetections") : true
        
        // Rate Limiting
        settings.rateLimitEnabled = ud.object(forKey: "rateLimitEnabled") != nil ? ud.bool(forKey: "rateLimitEnabled") : true
        settings.rateLimitDroneInterval = ud.object(forKey: "rateLimitDroneInterval") != nil ? ud.double(forKey: "rateLimitDroneInterval") : 1.0
        settings.rateLimitDroneMaxPerMinute = ud.integer(forKey: "rateLimitDroneMaxPerMinute") != 0 ? ud.integer(forKey: "rateLimitDroneMaxPerMinute") : 30
        settings.rateLimitMQTTMaxPerSecond = ud.integer(forKey: "rateLimitMQTTMaxPerSecond") != 0 ? ud.integer(forKey: "rateLimitMQTTMaxPerSecond") : 10
        settings.rateLimitMQTTBurstCount = ud.integer(forKey: "rateLimitMQTTBurstCount") != 0 ? ud.integer(forKey: "rateLimitMQTTBurstCount") : 20
        settings.rateLimitMQTTBurstPeriod = ud.object(forKey: "rateLimitMQTTBurstPeriod") != nil ? ud.double(forKey: "rateLimitMQTTBurstPeriod") : 5.0
        settings.rateLimitTAKMaxPerSecond = ud.integer(forKey: "rateLimitTAKMaxPerSecond") != 0 ? ud.integer(forKey: "rateLimitTAKMaxPerSecond") : 5
        settings.rateLimitTAKInterval = ud.object(forKey: "rateLimitTAKInterval") != nil ? ud.double(forKey: "rateLimitTAKInterval") : 0.5
        settings.rateLimitWebhookMaxPerMinute = ud.integer(forKey: "rateLimitWebhookMaxPerMinute") != 0 ? ud.integer(forKey: "rateLimitWebhookMaxPerMinute") : 20
        settings.rateLimitWebhookInterval = ud.object(forKey: "rateLimitWebhookInterval") != nil ? ud.double(forKey: "rateLimitWebhookInterval") : 2.0
        
        // Webhooks
        settings.webhooksEnabled = ud.bool(forKey: "webhooksEnabled")
        settings.webhookEventsJson = ud.string(forKey: "webhookEvents") ?? ""
        
        // History
        settings.zmqHostHistoryJson = ud.string(forKey: "zmqHostHistory") ?? "[]"
        settings.multicastHostHistoryJson = ud.string(forKey: "multicastHostHistory") ?? "[]"
        
        print("Migration from UserDefaults complete")
    }
    
    private func saveSettings() {
        guard let context = modelContext else { return }
        do {
            try context.save()
        } catch {
            print("❌ Failed to save settings: \(error)")
        }
    }
    
    // MARK: - Connection Settings (migrated to SwiftData)
    
    var connectionMode: ConnectionMode {
        get { appSettings?.connectionMode ?? .multicast }
        set {
            appSettings?.connectionMode = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var zmqHost: String {
        get { appSettings?.zmqHost ?? "0.0.0.0" }
        set {
            appSettings?.zmqHost = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var multicastHost: String {
        get { appSettings?.multicastHost ?? "224.0.0.1" }
        set {
            appSettings?.multicastHost = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var notificationsEnabled: Bool {
        get { appSettings?.notificationsEnabled ?? true }
        set {
            appSettings?.notificationsEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var keepScreenOn: Bool {
        get { appSettings?.keepScreenOn ?? false }
        set {
            appSettings?.keepScreenOn = newValue
            saveSettings()
            objectWillChange.send()
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
    }
    
    var enableBackgroundDetection: Bool {
        get { appSettings?.enableBackgroundDetection ?? true }
        set {
            appSettings?.enableBackgroundDetection = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var multicastPort: Int {
        get { appSettings?.multicastPort ?? 6969 }
        set {
            appSettings?.multicastPort = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var zmqTelemetryPort: Int {
        get { appSettings?.zmqTelemetryPort ?? 4224 }
        set {
            appSettings?.zmqTelemetryPort = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var zmqStatusPort: Int {
        get { appSettings?.zmqStatusPort ?? 4225 }
        set {
            appSettings?.zmqStatusPort = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var isListening: Bool {
        get { appSettings?.isListening ?? false }
        set {
            appSettings?.isListening = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var spoofDetectionEnabled: Bool {
        get { appSettings?.spoofDetectionEnabled ?? true }
        set {
            appSettings?.spoofDetectionEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var zmqSpectrumPort: Int {
        get { appSettings?.zmqSpectrumPort ?? 4226 }
        set {
            appSettings?.zmqSpectrumPort = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var zmqHostHistoryJson: String {
        get { appSettings?.zmqHostHistoryJson ?? "[]" }
        set {
            appSettings?.zmqHostHistoryJson = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var multicastHostHistoryJson: String {
        get { appSettings?.multicastHostHistoryJson ?? "[]" }
        set {
            appSettings?.multicastHostHistoryJson = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    // MARK: - Status Notification Settings
    
    var statusNotificationsEnabled: Bool {
        get { appSettings?.statusNotificationsEnabled ?? true }
        set {
            appSettings?.statusNotificationsEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var statusNotificationInterval: StatusNotificationInterval {
        get { appSettings?.statusNotificationInterval ?? .never }
        set {
            appSettings?.statusNotificationInterval = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var statusNotificationThresholds: Bool {
        get { appSettings?.statusNotificationThresholds ?? true }
        set {
            appSettings?.statusNotificationThresholds = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var lastStatusNotificationTime: Date {
        get { appSettings?.lastStatusNotificationTime ?? Date(timeIntervalSince1970: 0) }
        set {
            appSettings?.lastStatusNotificationTime = newValue
            saveSettings()
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
        saveSettings()
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
    
    var webhooksEnabled: Bool {
        get { appSettings?.webhooksEnabled ?? false }
        set {
            appSettings?.webhooksEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    private var webhookEventsJson: String {
        get { appSettings?.webhookEventsJson ?? "" }
        set {
            appSettings?.webhookEventsJson = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var enabledWebhookEvents: Set<WebhookEvent> {
        get { appSettings?.enabledWebhookEvents ?? Set(WebhookEvent.allCases) }
        set {
            appSettings?.enabledWebhookEvents = newValue
            saveSettings()
        }
    }
    
    func updateWebhookSettings(enabled: Bool, events: Set<WebhookEvent>? = nil) {
        webhooksEnabled = enabled
        if let events = events {
            enabledWebhookEvents = events
        }
        saveSettings()
    }
    
    // MARK: - Warning Thresholds
    
    var cpuWarningThreshold: Double {
        get { appSettings?.cpuWarningThreshold ?? 80.0 }
        set {
            appSettings?.cpuWarningThreshold = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var tempWarningThreshold: Double {
        get { appSettings?.tempWarningThreshold ?? 70.0 }
        set {
            appSettings?.tempWarningThreshold = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var memoryWarningThreshold: Double {
        get { appSettings?.memoryWarningThreshold ?? 0.85 }
        set {
            appSettings?.memoryWarningThreshold = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var plutoTempThreshold: Double {
        get { appSettings?.plutoTempThreshold ?? 85.0 }
        set {
            appSettings?.plutoTempThreshold = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var zynqTempThreshold: Double {
        get { appSettings?.zynqTempThreshold ?? 85.0 }
        set {
            appSettings?.zynqTempThreshold = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var proximityThreshold: Int {
        get { appSettings?.proximityThreshold ?? -60 }
        set {
            appSettings?.proximityThreshold = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var enableWarnings: Bool {
        get { appSettings?.enableWarnings ?? true }
        set {
            appSettings?.enableWarnings = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var systemWarningsEnabled: Bool {
        get { appSettings?.systemWarningsEnabled ?? true }
        set {
            appSettings?.systemWarningsEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var enableProximityWarnings: Bool {
        get { appSettings?.enableProximityWarnings ?? true }
        set {
            appSettings?.enableProximityWarnings = newValue
            saveSettings()
        }
    }
    
    var messageProcessingInterval: Int {
        get { appSettings?.messageProcessingInterval ?? 50 }
        set {
            appSettings?.messageProcessingInterval = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var backgroundMessageInterval: Int {
        get { appSettings?.backgroundMessageInterval ?? 100 }
        set {
            appSettings?.backgroundMessageInterval = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var useUserLocationForStatus: Bool {
        get { appSettings?.useUserLocationForStatus ?? false }
        set {
            appSettings?.useUserLocationForStatus = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var hasShownStatusLocationPrompt: Bool {
        get { appSettings?.hasShownStatusLocationPrompt ?? false }
        set {
            appSettings?.hasShownStatusLocationPrompt = newValue
            saveSettings()
            objectWillChange.send()
        }
    }

    // MARK: - TAK Server Settings
    
    var takEnabled: Bool {
        get { appSettings?.takEnabled ?? false }
        set {
            appSettings?.takEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var takHost: String {
        get { appSettings?.takHost ?? "" }
        set {
            appSettings?.takHost = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var takPort: Int {
        get { appSettings?.takPort ?? 8089 }
        set {
            appSettings?.takPort = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var takProtocol: TAKProtocol {
        get { appSettings?.takProtocol ?? .tls }
        set {
            appSettings?.takProtocol = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var takTLSEnabled: Bool {
        get { appSettings?.takTLSEnabled ?? true }
        set {
            appSettings?.takTLSEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var takSkipVerification: Bool {
        get { appSettings?.takSkipVerification ?? false }
        set {
            appSettings?.takSkipVerification = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    // P12 password stored securely in Keychain
    var takP12Password: String {
        get {
            (try? KeychainManager.shared.loadString(forKey: "takP12Password")) ?? ""
        }
        set {
            if newValue.isEmpty {
                try? KeychainManager.shared.delete(key: "takP12Password")
            } else {
                try? KeychainManager.shared.save(newValue, forKey: "takP12Password")
            }
            objectWillChange.send()
        }
    }
    
    var takConfiguration: TAKConfiguration {
        get {
            appSettings?.getTAKConfiguration() ?? TAKConfiguration(
                enabled: false,
                host: "",
                port: 8089,
                protocol: .tls,
                tlsEnabled: true,
                p12CertificateData: nil,
                p12Password: nil,
                skipVerification: false
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
            if newValue.p12CertificateData != nil {
                try? newValue.saveP12ToKeychain()
            }
            saveSettings()
        }
    }
    
    func updateTAKConfiguration(_ config: TAKConfiguration) {
        takConfiguration = config
    }
    
    // MARK: - MQTT Settings
    
    var mqttEnabled: Bool {
        get { appSettings?.mqttEnabled ?? false }
        set {
            appSettings?.mqttEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttHost: String {
        get { appSettings?.mqttHost ?? "" }
        set {
            appSettings?.mqttHost = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttPort: Int {
        get { appSettings?.mqttPort ?? 1883 }
        set {
            appSettings?.mqttPort = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttUseTLS: Bool {
        get { appSettings?.mqttUseTLS ?? false }
        set {
            appSettings?.mqttUseTLS = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttUsername: String {
        get { appSettings?.mqttUsername ?? "" }
        set {
            appSettings?.mqttUsername = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    // MQTT password stored securely in Keychain
    var mqttPassword: String {
        get {
            (try? KeychainManager.shared.loadString(forKey: "mqttPassword")) ?? ""
        }
        set {
            if newValue.isEmpty {
                try? KeychainManager.shared.delete(key: "mqttPassword")
            } else {
                try? KeychainManager.shared.save(newValue, forKey: "mqttPassword")
            }
            objectWillChange.send()
        }
    }
    
    var mqttBaseTopic: String {
        get { appSettings?.mqttBaseTopic ?? "wardragon" }
        set {
            appSettings?.mqttBaseTopic = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttQoS: MQTTQoS {
        get { appSettings?.mqttQoS ?? .atLeastOnce }
        set {
            appSettings?.mqttQoS = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttRetain: Bool {
        get { appSettings?.mqttRetain ?? false }
        set {
            appSettings?.mqttRetain = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttCleanSession: Bool {
        get { appSettings?.mqttCleanSession ?? true }
        set {
            appSettings?.mqttCleanSession = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttHomeAssistantEnabled: Bool {
        get { appSettings?.mqttHomeAssistantEnabled ?? false }
        set {
            appSettings?.mqttHomeAssistantEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttHomeAssistantDiscoveryPrefix: String {
        get { appSettings?.mqttHomeAssistantDiscoveryPrefix ?? "homeassistant" }
        set {
            appSettings?.mqttHomeAssistantDiscoveryPrefix = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttKeepalive: Int {
        get { appSettings?.mqttKeepalive ?? 60 }
        set {
            appSettings?.mqttKeepalive = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttReconnectDelay: Int {
        get { appSettings?.mqttReconnectDelay ?? 5 }
        set {
            appSettings?.mqttReconnectDelay = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var mqttConfiguration: MQTTConfiguration {
        get {
            appSettings?.getMQTTConfiguration() ?? MQTTConfiguration(
                enabled: false,
                host: "",
                port: 1883,
                useTLS: false,
                username: nil,
                password: nil,
                baseTopic: "wardragon",
                droneTopicTemplate: "{base}/drones/{mac}",
                systemTopic: "{base}/system",
                statusTopic: "{base}/status",
                qos: .atLeastOnce,
                retain: false,
                cleanSession: true,
                homeAssistantEnabled: false,
                homeAssistantDiscoveryPrefix: "homeassistant",
                keepalive: 60,
                reconnectDelay: 5
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
            saveSettings()
        }
    }
    
    func updateMQTTConfiguration(_ config: MQTTConfiguration) {
        mqttConfiguration = config
    }
    
    // MARK: - ADS-B Settings
    
    var adsbEnabled: Bool {
        get { appSettings?.adsbEnabled ?? false }
        set {
            appSettings?.adsbEnabled = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .adsbSettingsChanged, object: nil)
        }
    }
    
    var adsbReadsbURL: String {
        get { appSettings?.adsbReadsbURL ?? "http://localhost:8080" }
        set {
            appSettings?.adsbReadsbURL = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .adsbSettingsChanged, object: nil)
        }
    }
    
    var adsbDataPath: String {
        get { appSettings?.adsbDataPath ?? "/data/aircraft.json" }
        set {
            appSettings?.adsbDataPath = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .adsbSettingsChanged, object: nil)
        }
    }
    
    var adsbPollInterval: Double {
        get { appSettings?.adsbPollInterval ?? 2.0 }
        set {
            appSettings?.adsbPollInterval = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .adsbSettingsChanged, object: nil)
        }
    }
    
    var adsbMaxDistance: Double {
        get { appSettings?.adsbMaxDistance ?? 0 }
        set {
            appSettings?.adsbMaxDistance = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .adsbSettingsChanged, object: nil)
        }
    }
    
    var adsbMaxAircraftCount: Int {
        get { appSettings?.adsbMaxAircraftCount ?? 25 }
        set {
            appSettings?.adsbMaxAircraftCount = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .adsbSettingsChanged, object: nil)
        }
    }
    
    var adsbMinAltitude: Double {
        get { appSettings?.adsbMinAltitude ?? 0 }
        set {
            appSettings?.adsbMinAltitude = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .adsbSettingsChanged, object: nil)
        }
    }
    
    var adsbMaxAltitude: Double {
        get { appSettings?.adsbMaxAltitude ?? 50000 }
        set {
            appSettings?.adsbMaxAltitude = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .adsbSettingsChanged, object: nil)
        }
    }
    
    var adsbConfiguration: ADSBConfiguration {
        get {
            appSettings?.getADSBConfiguration() ?? ADSBConfiguration(
                enabled: false,
                readsbURL: "http://localhost:8080",
                dataPath: "/data/aircraft.json",
                pollInterval: 2.0,
                maxDistance: nil,
                minAltitude: nil,
                maxAltitude: nil,
                maxAircraftCount: 25
            )
        }
        set {
            adsbEnabled = newValue.enabled
            adsbReadsbURL = newValue.readsbURL
            adsbDataPath = newValue.dataPath
            adsbPollInterval = newValue.pollInterval
            adsbMaxDistance = newValue.maxDistance ?? 0
            adsbMinAltitude = newValue.minAltitude ?? 0
            adsbMaxAltitude = newValue.maxAltitude ?? 50000
            adsbMaxAircraftCount = newValue.maxAircraftCount
        }
    }
    
    func updateADSBConfiguration(_ config: ADSBConfiguration) {
        adsbConfiguration = config
    }
    
    // MARK: - Lattice Settings
    
    var latticeEnabled: Bool {
        get { appSettings?.latticeEnabled ?? false }
        set {
            appSettings?.latticeEnabled = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .latticeSettingsChanged, object: nil)
        }
    }
    
    var latticeServerURL: String {
        get { appSettings?.latticeServerURL ?? "https://sandbox.lattice-das.com" }
        set {
            appSettings?.latticeServerURL = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .latticeSettingsChanged, object: nil)
        }
    }
    
    var latticeAPIToken: String {
        get {
            (try? KeychainManager.shared.loadString(forKey: "latticeAPIToken")) ?? ""
        }
        set {
            if newValue.isEmpty {
                try? KeychainManager.shared.delete(key: "latticeAPIToken")
            } else {
                try? KeychainManager.shared.save(newValue, forKey: "latticeAPIToken")
            }
            objectWillChange.send()
        }
    }
    
    var latticeOrganizationID: String {
        get { appSettings?.latticeOrganizationID ?? "" }
        set {
            appSettings?.latticeOrganizationID = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .latticeSettingsChanged, object: nil)
        }
    }
    
    var latticeSiteID: String {
        get { appSettings?.latticeSiteID ?? "" }
        set {
            appSettings?.latticeSiteID = newValue
            saveSettings()
            objectWillChange.send()
            NotificationCenter.default.post(name: .latticeSettingsChanged, object: nil)
        }
    }
    
    var latticeConfiguration: LatticeClient.LatticeConfiguration {
        get {
            appSettings?.getLatticeConfiguration() ?? LatticeClient.LatticeConfiguration(
                enabled: false,
                serverURL: "https://sandbox.lattice-das.com",
                apiToken: nil,
                organizationID: "",
                siteID: ""
            )
        }
        set {
            latticeEnabled = newValue.enabled
            latticeServerURL = newValue.serverURL
            latticeAPIToken = newValue.apiToken ?? ""
            latticeOrganizationID = newValue.organizationID
            latticeSiteID = newValue.siteID
        }
    }
    
    func updateLatticeConfiguration(_ config: LatticeClient.LatticeConfiguration) {
        latticeConfiguration = config
    }
    
    // MARK: - Detection Limits
    
    var maxDrones: Int {
        get { appSettings?.maxDrones ?? 30 }
        set {
            appSettings?.maxDrones = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var maxAircraft: Int {
        get { appSettings?.maxAircraft ?? 100 }
        set {
            appSettings?.maxAircraft = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var inactivityTimeout: Double {
        get { appSettings?.inactivityTimeout ?? 60.0 }
        set {
            appSettings?.inactivityTimeout = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var persistDroneDetections: Bool {
        get { appSettings?.persistDroneDetections ?? true }
        set {
            appSettings?.persistDroneDetections = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    // MARK: - Rate Limiting Settings
    
    var rateLimitEnabled: Bool {
        get { appSettings?.rateLimitEnabled ?? true }
        set {
            appSettings?.rateLimitEnabled = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitDroneInterval: Double {
        get { appSettings?.rateLimitDroneInterval ?? 1.0 }
        set {
            appSettings?.rateLimitDroneInterval = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitDroneMaxPerMinute: Int {
        get { appSettings?.rateLimitDroneMaxPerMinute ?? 30 }
        set {
            appSettings?.rateLimitDroneMaxPerMinute = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitMQTTMaxPerSecond: Int {
        get { appSettings?.rateLimitMQTTMaxPerSecond ?? 10 }
        set {
            appSettings?.rateLimitMQTTMaxPerSecond = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitMQTTBurstCount: Int {
        get { appSettings?.rateLimitMQTTBurstCount ?? 20 }
        set {
            appSettings?.rateLimitMQTTBurstCount = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitMQTTBurstPeriod: Double {
        get { appSettings?.rateLimitMQTTBurstPeriod ?? 5.0 }
        set {
            appSettings?.rateLimitMQTTBurstPeriod = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitTAKMaxPerSecond: Int {
        get { appSettings?.rateLimitTAKMaxPerSecond ?? 5 }
        set {
            appSettings?.rateLimitTAKMaxPerSecond = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitTAKInterval: Double {
        get { appSettings?.rateLimitTAKInterval ?? 0.5 }
        set {
            appSettings?.rateLimitTAKInterval = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitWebhookMaxPerMinute: Int {
        get { appSettings?.rateLimitWebhookMaxPerMinute ?? 20 }
        set {
            appSettings?.rateLimitWebhookMaxPerMinute = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitWebhookInterval: Double {
        get { appSettings?.rateLimitWebhookInterval ?? 2.0 }
        set {
            appSettings?.rateLimitWebhookInterval = newValue
            saveSettings()
            objectWillChange.send()
        }
    }
    
    var rateLimitConfiguration: RateLimitConfiguration {
        get {
            appSettings?.getRateLimitConfiguration() ?? RateLimitConfiguration(
                enabled: true,
                dronePublishInterval: 1.0,
                droneMaxPerMinute: 30,
                mqttMaxPerSecond: 10,
                mqttBurstCount: 20,
                mqttBurstPeriod: 5.0,
                takMaxPerSecond: 5,
                takPublishInterval: 0.5,
                webhookMaxPerMinute: 20,
                webhookPublishInterval: 2.0
            )
        }
        set {
            rateLimitEnabled = newValue.enabled
            rateLimitDroneInterval = newValue.dronePublishInterval
            rateLimitDroneMaxPerMinute = newValue.droneMaxPerMinute
            rateLimitMQTTMaxPerSecond = newValue.mqttMaxPerSecond
            rateLimitMQTTBurstCount = newValue.mqttBurstCount
            rateLimitMQTTBurstPeriod = newValue.mqttBurstPeriod
            rateLimitTAKMaxPerSecond = newValue.takMaxPerSecond
            rateLimitTAKInterval = newValue.takPublishInterval
            rateLimitWebhookMaxPerMinute = newValue.webhookMaxPerMinute
            rateLimitWebhookInterval = newValue.webhookPublishInterval
        }
    }
    
    func updateRateLimitConfiguration(_ config: RateLimitConfiguration) {
        rateLimitConfiguration = config
    }
    
    //MARK: - Connection
    
    func updateConnection(mode: ConnectionMode, host: String? = nil, isZmqHost: Bool = false) {
        if let host = host {
            if isZmqHost {
                zmqHost = host
            } else {
                multicastHost = host
            }
        }
        connectionMode = mode
        saveSettings()
    }

    func updateStatusLocationSettings(useLocation: Bool) {
        useUserLocationForStatus = useLocation
        hasShownStatusLocationPrompt = true
        saveSettings()
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
        saveSettings()
        objectWillChange.send()
    }
    
    var zmqHostHistory: [String] {
        get {
            appSettings?.zmqHostHistory ?? []
        }
        set {
            appSettings?.zmqHostHistory = newValue
            saveSettings()
        }
    }

    var multicastHostHistory: [String] {
        get {
            appSettings?.multicastHostHistory ?? []
        }
        set {
            appSettings?.multicastHostHistory = newValue
            saveSettings()
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
        saveSettings()
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
        saveSettings()
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
        saveSettings()
        objectWillChange.send()
    }
}
// MARK: - Notification Names
extension Notification.Name {
    static let adsbSettingsChanged = Notification.Name("adsbSettingsChanged")
    static let latticeSettingsChanged = Notification.Name("latticeSettingsChanged")
}

