//
//  WebhookManager.swift
//  WarDragon
//

import Foundation
import Combine

// MARK: - WebhookType Enum

enum WebhookType: String, CaseIterable, Codable {
    case ifttt = "IFTTT"
    case matrix = "Matrix"
    case discord = "Discord"
    case mqtt = "MQTT"
    case custom = "Custom"
    
    var icon: String {
        switch self {
        case .ifttt: return "link.circle.fill"
        case .matrix: return "message.circle.fill"
        case .discord: return "bubble.left.and.bubble.right.fill"
        case .mqtt: return "antenna.radiowaves.left.and.right"
        case .custom: return "globe"
        }
    }
    
    var color: String {
        switch self {
        case .ifttt: return "blue"
        case .matrix: return "green"
        case .discord: return "indigo"
        case .mqtt: return "orange"
        case .custom: return "gray"
        }
    }
}

// MARK: - WebhookEvent Enum

enum WebhookEvent: String, CaseIterable, Codable {
    case droneDetected = "drone_detected"
    case fpvSignal = "fpv_signal"
    case systemAlert = "system_alert"
    case proximityWarning = "proximity_warning"
    case temperatureAlert = "temperature_alert"
    case memoryAlert = "memory_alert"
    case cpuAlert = "cpu_alert"
    case connectionLost = "connection_lost"
    case connectionRestored = "connection_restored"
    
    var displayName: String {
        switch self {
        case .droneDetected: return "Drone Detected"
        case .fpvSignal: return "FPV Signal"
        case .systemAlert: return "System Alert"
        case .proximityWarning: return "Proximity Warning"
        case .temperatureAlert: return "Temperature Alert"
        case .memoryAlert: return "Memory Alert"
        case .cpuAlert: return "CPU Alert"
        case .connectionLost: return "Connection Lost"
        case .connectionRestored: return "Connection Restored"
        }
    }
}

// MARK: - WebhookConfiguration Struct

struct WebhookConfiguration: Codable, Identifiable {
    var id: UUID
    var name: String
    var type: WebhookType
    var url: String
    var isEnabled: Bool
    var enabledEvents: Set<WebhookEvent>
    var customHeaders: [String: String]
    var retryCount: Int
    var timeoutSeconds: Double
    
    // Type-specific configurations
    var iftttEventName: String?
    var matrixRoomId: String?
    var matrixAccessToken: String?
    var discordUsername: String?
    var discordAvatarURL: String?
    
    // MQTT-specific configurations
    var mqttTopic: String?
    var mqttUsername: String?
    var mqttPassword: String?
    var mqttQoS: Int?
    
    init(name: String, type: WebhookType, url: String) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.url = url
        self.isEnabled = true
        self.enabledEvents = Set(WebhookEvent.allCases)
        self.customHeaders = [:]
        self.retryCount = 3
        self.timeoutSeconds = 10.0
        self.mqttQoS = 1
    }
}

// MARK: - WebhookPayload Struct

struct WebhookPayload {
    let event: WebhookEvent
    let timestamp: Date
    let data: [String: Any]
    let metadata: [String: String]
    
    // MARK: - Helper method to sanitize data for JSON serialization
    
    private func sanitizeForJSON(_ value: Any) -> Any {
        if let date = value as? Date {
            return ISO8601DateFormatter().string(from: date)
        } else if let dict = value as? [String: Any] {
            return dict.mapValues { sanitizeForJSON($0) }
        } else if let array = value as? [Any] {
            return array.map { sanitizeForJSON($0) }
        } else if let url = value as? URL {
            return url.absoluteString
        } else if let data = value as? Data {
            return data.base64EncodedString()
        } else if JSONSerialization.isValidJSONObject([value]) {
            return value
        } else {
            return String(describing: value)
        }
    }
    
    private func sanitizedData() -> [String: Any] {
        return data.mapValues { sanitizeForJSON($0) }
    }
    
    // MARK: - Payload Formatters
    
    func toIFTTTPayload(eventName: String) -> [String: Any] {
        return [
            "value1": event.displayName,
            "value2": formatTimestamp(),
            "value3": formatDataForDisplay()
        ]
    }
    
    func toMatrixPayload() -> [String: Any] {
        let plainBody = """
        \(event.displayName)
        
        Time: \(formatTimestamp())
        Details: \(formatDataForDisplay())
        \(formatMetadataPlain())
        """
        
        let htmlBody = """
        <strong>\(event.displayName)</strong><br/>
        <br/>
        <strong>Time:</strong> \(formatTimestamp())<br/>
        <strong>Details:</strong> \(formatDataForDisplay())<br/>
        \(formatMetadataHTML())
        """
        
        return [
            "msgtype": "m.text",
            "body": plainBody,
            "format": "org.matrix.custom.html",
            "formatted_body": htmlBody
        ]
    }
    
    func toDiscordPayload(username: String?, avatarURL: String?) -> [String: Any] {
        var payload: [String: Any] = [
            "embeds": [[
                "title": event.displayName,
                "description": formatDataForDisplay(),
                "color": getEventColor(),
                "timestamp": ISO8601DateFormatter().string(from: timestamp),
                "fields": formatFieldsForDiscord(),
                "footer": [
                    "text": "WarDragon Alert System"
                ]
            ]]
        ]
        
        if let username = username {
            payload["username"] = username
        }
        
        if let avatarURL = avatarURL {
            payload["avatar_url"] = avatarURL
        }
        
        return payload
    }
    
    func toMQTTPayload() -> [String: Any] {
        return [
            "event": event.rawValue,
            "event_name": event.displayName,
            "timestamp": ISO8601DateFormatter().string(from: timestamp),
            "data": sanitizedData(),
            "metadata": metadata
        ]
    }
    
    // MARK: - Formatting Helpers
    
    private func formatTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
    
    private func formatDataForDisplay() -> String {
        var parts: [String] = []
        let sanitized = sanitizedData()
        for (key, value) in sanitized {
            parts.append("\(key.capitalized): \(value)")
        }
        return parts.joined(separator: ", ")
    }
    
    private func formatMetadataPlain() -> String {
        guard !metadata.isEmpty else { return "" }
        
        var parts: [String] = []
        for (key, value) in metadata {
            parts.append("\(key.capitalized): \(value)")
        }
        return "\n" + parts.joined(separator: "\n")
    }
    
    private func formatMetadataHTML() -> String {
        guard !metadata.isEmpty else { return "" }
        
        var parts: [String] = []
        for (key, value) in metadata {
            parts.append("<br/><strong>\(key.capitalized):</strong> \(value)")
        }
        return parts.joined(separator: "")
    }
    
    private func formatFieldsForDiscord() -> [[String: Any]] {
        var fields: [[String: Any]] = []
        
        let sanitized = sanitizedData()
        for (key, value) in sanitized {
            fields.append([
                "name": key.capitalized,
                "value": "\(value)",
                "inline": true
            ])
        }
        
        for (key, value) in metadata {
            fields.append([
                "name": key.capitalized,
                "value": value,
                "inline": true
            ])
        }
        
        return fields
    }
    
    private func getEventColor() -> Int {
        switch event {
        case .droneDetected: return 0x3498db
        case .fpvSignal: return 0x9b59b6
        case .systemAlert, .temperatureAlert, .memoryAlert, .cpuAlert: return 0xe74c3c
        case .proximityWarning: return 0xf39c12
        case .connectionLost: return 0xe74c3c
        case .connectionRestored: return 0x27ae60
        }
    }
}

// MARK: - WebhookManager

class WebhookManager: ObservableObject {
    static let shared = WebhookManager()
    
    @Published var configurations: [WebhookConfiguration] = []
    @Published var recentDeliveries: [WebhookDelivery] = []
    
    private var session: URLSession
    private let maxDeliveryHistory = 100
    
    struct WebhookDelivery: Identifiable {
        let id = UUID()
        let webhookName: String
        let event: WebhookEvent
        let timestamp: Date
        let success: Bool
        let responseCode: Int?
        let error: String?
        let retryAttempt: Int
    }
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        
        loadConfigurations()
    }
    
    // MARK: - Configuration Management
    
    func addConfiguration(_ config: WebhookConfiguration) {
        configurations.append(config)
        saveConfigurations()
    }
    
    func updateConfiguration(_ config: WebhookConfiguration) {
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations[index] = config
            saveConfigurations()
        }
    }
    
    func removeConfiguration(_ config: WebhookConfiguration) {
        configurations.removeAll { $0.id == config.id }
        saveConfigurations()
    }
    
    func toggleWebhook(_ config: WebhookConfiguration) {
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations[index].isEnabled.toggle()
            saveConfigurations()
        }
    }
    
    private func saveConfigurations() {
        if let data = try? JSONEncoder().encode(configurations) {
            UserDefaults.standard.set(data, forKey: "webhook_configurations")
        }
    }
    
    private func loadConfigurations() {
        if let data = UserDefaults.standard.data(forKey: "webhook_configurations"),
           let configs = try? JSONDecoder().decode([WebhookConfiguration].self, from: data) {
            configurations = configs
        }
    }
    
    // MARK: - Webhook Delivery
    
    func sendWebhook(event: WebhookEvent, data: [String: Any], metadata: [String: String] = [:]) {
        guard Settings.shared.webhooksEnabled else { return }
        guard Settings.shared.enabledWebhookEvents.contains(event) else { return }
        
        let enabledConfigs = configurations.filter {
            $0.isEnabled && $0.enabledEvents.contains(event)
        }
        
        guard !enabledConfigs.isEmpty else { return }
        
        let payload = WebhookPayload(
            event: event,
            timestamp: Date(),
            data: data,
            metadata: metadata
        )
        
        for config in enabledConfigs {
            Task {
                await deliverWebhook(config: config, payload: payload)
            }
        }
    }
    
    private func deliverWebhook(config: WebhookConfiguration, payload: WebhookPayload, retryAttempt: Int = 0) async {
        if config.type == .mqtt {
            await deliverMQTTWebhook(config: config, payload: payload, retryAttempt: retryAttempt)
            return
        }
        
        do {
            let request = try buildRequest(config: config, payload: payload)
            let (_, response) = try await session.data(for: request)
            
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0
            
            let success = statusCode >= 200 && statusCode < 300
            
            await MainActor.run {
                recordDelivery(
                    webhookName: config.name,
                    event: payload.event,
                    success: success,
                    responseCode: statusCode,
                    error: success ? nil : "HTTP \(statusCode)",
                    retryAttempt: retryAttempt
                )
            }
            
            if !success && retryAttempt < config.retryCount {
                let delay = pow(2.0, Double(retryAttempt)) * 1.0
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await deliverWebhook(config: config, payload: payload, retryAttempt: retryAttempt + 1)
            }
            
        } catch {
            await MainActor.run {
                recordDelivery(
                    webhookName: config.name,
                    event: payload.event,
                    success: false,
                    responseCode: nil,
                    error: error.localizedDescription,
                    retryAttempt: retryAttempt
                )
            }
            
            if retryAttempt < config.retryCount {
                let delay = pow(2.0, Double(retryAttempt)) * 1.0
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await deliverWebhook(config: config, payload: payload, retryAttempt: retryAttempt + 1)
            }
        }
    }
    
    // MARK: - MQTT Delivery
    
    private func deliverMQTTWebhook(config: WebhookConfiguration, payload: WebhookPayload, retryAttempt: Int = 0) async {
        guard let mqttTopic = config.mqttTopic, !mqttTopic.isEmpty else {
            await MainActor.run {
                recordDelivery(
                    webhookName: config.name,
                    event: payload.event,
                    success: false,
                    responseCode: nil,
                    error: "MQTT topic not configured",
                    retryAttempt: retryAttempt
                )
            }
            return
        }
        
        do {
            let jsonPayload = payload.toMQTTPayload()
            guard JSONSerialization.isValidJSONObject(jsonPayload) else {
                throw NSError(domain: "WebhookManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid MQTT JSON payload"])
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: jsonPayload, options: [])
            
            let success = await publishMQTTMessage(
                broker: config.url,
                topic: mqttTopic,
                payload: jsonData,
                qos: config.mqttQoS ?? 1,
                username: config.mqttUsername,
                password: config.mqttPassword
            )
            
            await MainActor.run {
                recordDelivery(
                    webhookName: config.name,
                    event: payload.event,
                    success: success,
                    responseCode: success ? 200 : nil,
                    error: success ? nil : "MQTT publish failed",
                    retryAttempt: retryAttempt
                )
            }
            
            if !success && retryAttempt < config.retryCount {
                let delay = pow(2.0, Double(retryAttempt)) * 1.0
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await deliverMQTTWebhook(config: config, payload: payload, retryAttempt: retryAttempt + 1)
            }
            
        } catch {
            await MainActor.run {
                recordDelivery(
                    webhookName: config.name,
                    event: payload.event,
                    success: false,
                    responseCode: nil,
                    error: error.localizedDescription,
                    retryAttempt: retryAttempt
                )
            }
            
            if retryAttempt < config.retryCount {
                let delay = pow(2.0, Double(retryAttempt)) * 1.0
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await deliverMQTTWebhook(config: config, payload: payload, retryAttempt: retryAttempt + 1)
            }
        }
    }
    
    private func publishMQTTMessage(broker: String, topic: String, payload: Data, qos: Int, username: String?, password: String?) async -> Bool {
        return false
    }
    
    // MARK: - Request Building
    
    private func buildRequest(config: WebhookConfiguration, payload: WebhookPayload) throws -> URLRequest {
        guard let url = URL(string: config.url) else {
            throw NSError(domain: "WebhookManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeoutSeconds
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        for (key, value) in config.customHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let jsonPayload: [String: Any]
        
        switch config.type {
        case .ifttt:
            jsonPayload = payload.toIFTTTPayload(eventName: config.iftttEventName ?? "wardragon_alert")
            
        case .matrix:
            jsonPayload = payload.toMatrixPayload()
            if let accessToken = config.matrixAccessToken {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            
        case .discord:
            jsonPayload = payload.toDiscordPayload(username: config.discordUsername, avatarURL: config.discordAvatarURL)
            
        case .mqtt:
            jsonPayload = payload.toMQTTPayload()
            
        case .custom:
            let sanitizedData = payload.data.mapValues { value -> Any in
                if let date = value as? Date {
                    return ISO8601DateFormatter().string(from: date)
                } else if let url = value as? URL {
                    return url.absoluteString
                } else if let data = value as? Data {
                    return data.base64EncodedString()
                } else if JSONSerialization.isValidJSONObject([value]) {
                    return value
                } else {
                    return String(describing: value)
                }
            }
            
            jsonPayload = [
                "event": payload.event.rawValue,
                "event_name": payload.event.displayName,
                "timestamp": ISO8601DateFormatter().string(from: payload.timestamp),
                "data": sanitizedData,
                "metadata": payload.metadata
            ]
        }
        
        guard JSONSerialization.isValidJSONObject(jsonPayload) else {
            throw NSError(domain: "WebhookManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON payload structure"])
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonPayload, options: [])
        
        return request
    }
    
    private func recordDelivery(webhookName: String, event: WebhookEvent, success: Bool, responseCode: Int?, error: String?, retryAttempt: Int) {
        let delivery = WebhookDelivery(
            webhookName: webhookName,
            event: event,
            timestamp: Date(),
            success: success,
            responseCode: responseCode,
            error: error,
            retryAttempt: retryAttempt
        )
        
        recentDeliveries.insert(delivery, at: 0)
        
        if recentDeliveries.count > maxDeliveryHistory {
            recentDeliveries = Array(recentDeliveries.prefix(maxDeliveryHistory))
        }
    }
    
    // MARK: - Testing
    
    func testWebhook(_ config: WebhookConfiguration) async -> Bool {
        let testPayload = WebhookPayload(
            event: .systemAlert,
            timestamp: Date(),
            data: ["message": "Test webhook from WarDragon"],
            metadata: ["test": "true"]
        )
        
        if config.type == .mqtt {
            return await testMQTTWebhook(config: config, payload: testPayload)
        }
        
        do {
            let request = try buildRequest(config: config, payload: testPayload)
            let (_, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode >= 200 && httpResponse.statusCode < 300
            }
            return false
        } catch {
            return false
        }
    }
    
    private func testMQTTWebhook(config: WebhookConfiguration, payload: WebhookPayload) async -> Bool {
        guard let mqttTopic = config.mqttTopic, !mqttTopic.isEmpty else {
            return false
        }
        
        do {
            let jsonPayload = payload.toMQTTPayload()
            let jsonData = try JSONSerialization.data(withJSONObject: jsonPayload, options: [])
            
            return await publishMQTTMessage(
                broker: config.url,
                topic: mqttTopic,
                payload: jsonData,
                qos: config.mqttQoS ?? 1,
                username: config.mqttUsername,
                password: config.mqttPassword
            )
        } catch {
            return false
        }
    }
}

// MARK: - WebhookManager Extension

extension WebhookManager {
    func recordTestDelivery(config: WebhookConfiguration, success: Bool, responseCode: Int? = nil, error: String?) {
        let delivery = WebhookDelivery(
            webhookName: config.name,
            event: .systemAlert,
            timestamp: Date(),
            success: success,
            responseCode: responseCode,
            error: error,
            retryAttempt: 0
        )
        
        recentDeliveries.insert(delivery, at: 0)
        
        if recentDeliveries.count > maxDeliveryHistory {
            recentDeliveries = Array(recentDeliveries.prefix(maxDeliveryHistory))
        }
    }
}
