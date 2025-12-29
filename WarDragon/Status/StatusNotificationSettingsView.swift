//
//  StatusNotificationSettingsView.swift
//  WarDragon
//
//  Created by Luke on 6/23/25.
//


import SwiftUI

struct StatusNotificationSettingsView: View {
    @ObservedObject private var settings = Settings.shared
    
    var body: some View {
        Form {
            Section(header: Text("Status Notifications")) {
                Toggle("Enable Status Notifications", isOn: .init(
                    get: { settings.statusNotificationsEnabled },
                    set: { enabled in
                        settings.updateStatusNotificationSettings(
                            enabled: enabled,
                            interval: settings.statusNotificationInterval,
                            thresholds: settings.statusNotificationThresholds
                        )
                    }
                ))
                
                if settings.statusNotificationsEnabled {
                    Text("Receive system status updates on this device and via webhooks (if enabled)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if Settings.shared.webhooksEnabled {
                Section(header: Text("Webhook Status Notifications")) {
                    Toggle("Send Status to Webhooks", isOn: .init(
                        get: { settings.enabledWebhookEvents.contains(.systemAlert) },
                        set: { enabled in
                            var events = settings.enabledWebhookEvents
                            if enabled {
                                events.insert(.systemAlert)
                                events.insert(.temperatureAlert)
                                events.insert(.memoryAlert)
                                events.insert(.cpuAlert)
                            } else {
                                events.remove(.systemAlert)
                                events.remove(.temperatureAlert)
                                events.remove(.memoryAlert)
                                events.remove(.cpuAlert)
                            }
                            settings.enabledWebhookEvents = events
                        }
                    ))
                    
                    if settings.enabledWebhookEvents.contains(.systemAlert) {
                        Text("Status notifications will also be sent to configured webhook services")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if settings.statusNotificationsEnabled {
                Section(header: Text("Notification Frequency")) {
                    ForEach(StatusNotificationInterval.allCases, id: \.self) { interval in
                        NotificationIntervalRow(
                            interval: interval,
                            isSelected: settings.statusNotificationInterval == interval
                        ) {
                            settings.updateStatusNotificationSettings(
                                enabled: settings.statusNotificationsEnabled,
                                interval: interval,
                                thresholds: settings.statusNotificationThresholds
                            )
                        }
                    }
                }
                
                // Show threshold alerts section for all intervals except never
                if settings.statusNotificationInterval != .never {
                    Section(header: Text("Threshold Alerts")) {
                        Toggle("Also Send Threshold Alerts", isOn: .init(
                            get: { settings.statusNotificationThresholds },
                            set: { enabled in
                                settings.updateStatusNotificationSettings(
                                    enabled: settings.statusNotificationsEnabled,
                                    interval: settings.statusNotificationInterval,
                                    thresholds: enabled
                                )
                            }
                        ))
                        
                        if settings.statusNotificationThresholds {
                            if settings.statusNotificationInterval == .always {
                                Text("Send immediate alerts when CPU, memory, or temperature thresholds are exceeded (in addition to all status updates)")
                            } else {
                                Text("Send immediate alerts when CPU, memory, or temperature thresholds are exceeded, in addition to regular status updates")
                            }
                        }
                    }
                }
                
                
                Section(header: Text("Current Status")) {
                    StatusSummaryView()
                }
                
                Section(header: Text("Preview")) {
                    Button("Send Test Status Notification") {
                        sendTestStatusNotification()
                    }
                    .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle("Status Notifications")
        .navigationBarTitleDisplayMode(.large)
    }
    
    private func sendTestStatusNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Test Status Notification"
        content.body = "CPU: 45%, Memory: 60%, Temp: 65°C - All systems normal"
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        UNUserNotificationCenter.current().add(request)
        
        // Also send webhook if enabled
        if Settings.shared.webhooksEnabled {
            let data: [String: Any] = [
                "title": "Test Status Notification",
                "message": "This is a test status notification from WarDragon",
                "cpu_usage": 45.0,
                "memory_usage": 60.0,
                "temperature": 65.0,
                "test": true
            ]
            
            WebhookManager.shared.sendWebhook(event: .systemAlert, data: data)
        }
    }
}

struct NotificationIntervalRow: View {
    let interval: StatusNotificationInterval
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: interval.icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(interval.displayName)
                    .font(.headline)
                Text(interval.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private var iconColor: Color {
        switch interval {
        case .never:
            return .gray
        case .always:
            return .red  // Red for high frequency
        case .thresholdOnly:
            return .orange
        case .every5Minutes, .every15Minutes, .every30Minutes:
            return .blue
        case .hourly, .every2Hours, .every6Hours:
            return .green
        case .daily:
            return .purple
        }
    }
}

struct StatusSummaryView: View {
    @StateObject private var settings = Settings.shared
    
    private var timeUntilNextNotification: String {
        switch settings.statusNotificationInterval {
        case .never:
            return "N/A"
        case .always:
            return "Immediate"
        case .thresholdOnly:
            return "Threshold-based"
        default:
            guard let interval = settings.statusNotificationInterval.intervalSeconds else {
                return "N/A"
            }
            
            let timeSinceLastNotification = Date().timeIntervalSince(settings.lastStatusNotificationTime)
            let timeRemaining = interval - timeSinceLastNotification
            
            if timeRemaining <= 0 {
                return "Ready to send"
            }
            
            let hours = Int(timeRemaining) / 3600
            let minutes = Int(timeRemaining.truncatingRemainder(dividingBy: 3600)) / 60
            
            if hours > 0 {
                return "\(hours)h \(minutes)m"
            } else {
                return "\(minutes)m"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current Setting:")
                Spacer()
                Text(settings.statusNotificationInterval.displayName)
                    .foregroundColor(.secondary)
            }
            
            if settings.statusNotificationInterval != .never && settings.statusNotificationInterval != .thresholdOnly {
                HStack {
                    Text("Last Notification:")
                    Spacer()
                    Text(settings.lastStatusNotificationTime, style: .relative)
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Next Notification:")
                    Spacer()
                    Text(timeUntilNextNotification)
                        .foregroundColor(settings.statusNotificationInterval == .always ? .green : .secondary)
                }
            }
            
            HStack {
                Text("Threshold Alerts:")
                Spacer()
                Text(settings.statusNotificationThresholds ? "Enabled" : "Disabled")
                    .foregroundColor(settings.statusNotificationThresholds ? .green : .secondary)
            }
        }
    }
}

#Preview {
    NavigationView {
        StatusNotificationSettingsView()
    }
}
