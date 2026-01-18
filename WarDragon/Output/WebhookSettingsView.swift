//
//  WebhookSettingsView.swift.swift
//  WarDragon
//
//  Created by Luke on 6/23/25.
//

import SwiftUI

struct WebhookSettingsView: View {
    @StateObject private var webhookManager = WebhookManager.shared
    @StateObject private var settings = Settings.shared
    @State private var showingAddWebhook = false
    @State private var selectedConfig: WebhookConfiguration?
    
    var body: some View {

        Form {
            Section(header: Text("Webhook System")) {
                Toggle("Enable Webhooks", isOn: .init(
                    get: { settings.webhooksEnabled },
                    set: { settings.updateWebhookSettings(enabled: $0) }
                ))
                
                if settings.webhooksEnabled {
                    Text("Send notifications to external services when events occur")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if settings.webhooksEnabled {
                Section(header: Text("Event Types")) {
                    Text("Select which events will trigger webhooks")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Quick actions for all status notifications
                    HStack {
                        Image(systemName: "bell.slash.fill")
                            .foregroundColor(.gray)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Disable All Status Notifications")
                                .font(.headline)
                            Text("Turn off all CPU, memory, temperature, and system alerts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: .init(
                            get: {
                                !settings.enabledWebhookEvents.contains(.systemAlert) &&
                                !settings.enabledWebhookEvents.contains(.temperatureAlert) &&
                                !settings.enabledWebhookEvents.contains(.memoryAlert) &&
                                !settings.enabledWebhookEvents.contains(.cpuAlert)
                            },
                            set: { enabled in
                                var events = settings.enabledWebhookEvents
                                if enabled {
                                    events.remove(.systemAlert)
                                    events.remove(.temperatureAlert)
                                    events.remove(.memoryAlert)
                                    events.remove(.cpuAlert)
                                } else {
                                    events.insert(.systemAlert)
                                    events.insert(.temperatureAlert)
                                    events.insert(.memoryAlert)
                                    events.insert(.cpuAlert)
                                }
                                settings.enabledWebhookEvents = events
                            }
                        ))
                    }
                    
                    // Individual event toggles
                    eventToggleRow(for: .droneDetected, title: "Drone Detection", description: "New drone detected", icon: "airplane.circle.fill", color: .blue)

                    eventToggleRow(for: .fpvSignal, title: "FPV Signal", description: "FPV video signal detected", icon: "tv.fill", color: .purple)
                    
                    eventToggleRow(for: .proximityWarning, title: "Proximity Warning", description: "Drone approaching threshold", icon: "exclamationmark.triangle.fill", color: .orange)
                    
                    eventToggleRow(for: .systemAlert, title: "System Alert", description: "General system warnings", icon: "exclamationmark.circle.fill", color: .red)
                    
                    eventToggleRow(for: .temperatureAlert, title: "Temperature Alert", description: "High temperature warnings", icon: "thermometer.high", color: .red)
                    
                    eventToggleRow(for: .memoryAlert, title: "Memory Alert", description: "High memory usage warnings", icon: "memorychip.fill", color: .yellow)
                    
                    eventToggleRow(for: .cpuAlert, title: "CPU Alert", description: "High CPU usage warnings", icon: "cpu.fill", color: .red)
                }
                
                Section(header: Text("Webhook Services")) {
                    if webhookManager.configurations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No webhook services configured")
                                .foregroundColor(.secondary)
                            Text("Add Discord, Matrix, IFTTT, or custom webhook endpoints")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(webhookManager.configurations) { config in
                            WebhookRowView(config: config) {
                                selectedConfig = config
                            }
                        }
                        .onDelete(perform: deleteWebhooks)
                    }
                    
                    Button("Add Webhook Service") {
                        showingAddWebhook = true
                    }
                    .foregroundColor(.blue)
                }
                
                Section(header: Text("Recent Deliveries")) {
                    if webhookManager.recentDeliveries.isEmpty {
                        Text("No recent webhook deliveries")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(webhookManager.recentDeliveries.prefix(5)) { delivery in
                            WebhookDeliveryRowView(delivery: delivery)
                        }
                    }
                }
            }
        }
        .navigationTitle("Webhooks")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showingAddWebhook) {
            WebhookConfigurationView(config: nil) { config in
                webhookManager.addConfiguration(config)
            }
        }
        .sheet(item: $selectedConfig) { config in
            WebhookConfigurationView(config: config) { updatedConfig in
                webhookManager.updateConfiguration(updatedConfig)
            }
        }
    }
    
    private func eventToggleRow(for event: WebhookEvent, title: String, description: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: .init(
                get: { settings.enabledWebhookEvents.contains(event) },
                set: { enabled in
                    var events = settings.enabledWebhookEvents
                    if enabled {
                        events.insert(event)
                    } else {
                        events.remove(event)
                    }
                    settings.enabledWebhookEvents = events
                }
            ))
        }
    }
    
    private func deleteWebhooks(offsets: IndexSet) {
        for index in offsets {
            let config = webhookManager.configurations[index]
            webhookManager.removeConfiguration(config)
        }
    }
}

struct WebhookRowView: View {
    let config: WebhookConfiguration
    let onTap: () -> Void
    @StateObject private var webhookManager = WebhookManager.shared
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: config.type.icon)
                        .foregroundColor(colorForType(config.type))
                    Text(config.name)
                        .font(.headline)
                    Spacer()
                    if !config.isEnabled {
                        Text("Disabled")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                
                Text(config.type.rawValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(config.enabledEvents.count) events enabled")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: .init(
                get: { config.isEnabled },
                set: { _ in webhookManager.toggleWebhook(config) }
            ))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
    
    private func colorForType(_ type: WebhookType) -> Color {
        switch type {
        case .ifttt: return .blue
        case .matrix: return .green
        case .discord: return .indigo
        case .custom: return .gray
        case .mqtt: return .orange
        }
    }
}

struct WebhookDeliveryRowView: View {
    let delivery: WebhookManager.WebhookDelivery
    
    var body: some View {
        HStack {
            Image(systemName: delivery.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(delivery.success ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(delivery.webhookName)
                    .font(.headline)
                Text(delivery.event.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let error = delivery.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(delivery.timestamp, style: .time)
                    .font(.caption)
                if let code = delivery.responseCode {
                    Text("HTTP \(code)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if delivery.retryAttempt > 0 {
                    Text("Retry \(delivery.retryAttempt)")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
}

#Preview {
    WebhookSettingsView()
}
