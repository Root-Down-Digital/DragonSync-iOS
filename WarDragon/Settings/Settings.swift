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
    @AppStorage("messageProcessingInterval") var messageProcessingInterval: Int = 350
    
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
    
    var messageProcessingIntervalSeconds: Double {
        Double(messageProcessingInterval) / 1000.0
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
