//
//  SettingsView.swift
//  WarDragon
//
//  Created by Luke on 11/23/24.
//

import SwiftUI
import UIKit
import Network

struct SettingsView: View {
    @ObservedObject var cotHandler : CoTViewModel
    @StateObject private var settings = Settings.shared
    
    var body: some View {
        Form {
            Section("Connection") {
                HStack {
                    Image(systemName: connectionStatusSymbol)
                        .foregroundStyle(connectionStatusColor)
                        .symbolEffect(.bounce, options: .repeat(3), value: cotHandler.isListeningCot)
                    Text(connectionStatusText)
                        .foregroundStyle(connectionStatusColor)
                }
                
                Picker("Mode", selection: .init(
                    get: { settings.connectionMode },
                    set: { settings.updateConnection(mode: $0) }
                )) {
                    ForEach(ConnectionMode.allCases, id: \.self) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }
                        .tag(mode)
                    }
                }
                .disabled(settings.isListening)
                
                if settings.connectionMode == .zmq {
                    HStack {
                        TextField("ZMQ Host", text: .init(
                            get: { settings.zmqHost },
                            set: { settings.updateConnection(mode: settings.connectionMode, host: $0, isZmqHost: true) }
                        ))
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disabled(settings.isListening)
                        .onSubmit {
                            settings.updateConnectionHistory(host: settings.zmqHost, isZmq: true)
                        }
                        
                        if !settings.zmqHostHistory.isEmpty {
                            Menu {
                                ForEach(settings.zmqHostHistory, id: \.self) { host in
                                    Button(host) {
                                        settings.updateConnection(mode: settings.connectionMode, host: host, isZmqHost: true)
                                        settings.updateConnectionHistory(host: host, isZmq: true)
                                    }
                                }
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            .disabled(settings.isListening)
                        }
                    }
                } else {
                    HStack {
                        TextField("Multicast Host", text: .init(
                            get: { settings.multicastHost },
                            set: { settings.updateConnection(mode: settings.connectionMode, host: $0, isZmqHost: false) }
                        ))
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disabled(settings.isListening)
                        .onSubmit {
                            settings.updateConnectionHistory(host: settings.multicastHost, isZmq: false)
                        }
                        
                        
                        if !settings.multicastHostHistory.isEmpty {
                            Menu {
                                ForEach(settings.multicastHostHistory, id: \.self) { host in
                                    Button(host) {
                                        settings.updateConnection(mode: settings.connectionMode, host: host, isZmqHost: false)
                                        settings.updateConnectionHistory(host: host, isZmq: false)
                                    }
                                }
                            } label: {
                                Image(systemName: "clock.arrow.circlepath")
                            }
                            .disabled(settings.isListening)
                        }
                    }
                }
                
                Toggle(isOn: .init(
                    get: { settings.isListening && cotHandler.isListeningCot },
                    set: { newValue in
                        if newValue {
                            settings.toggleListening(true)
                            cotHandler.startListening()
                            
                            // Save host to history when activating
                            if settings.connectionMode == .zmq {
                                settings.updateConnectionHistory(host: settings.zmqHost, isZmq: true)
                            } else {
                                settings.updateConnectionHistory(host: settings.multicastHost, isZmq: false)
                            }
                        } else {
                            settings.toggleListening(false)
                            cotHandler.stopListening()
                        }
                    }
                )) {
                    Text(settings.isListening && cotHandler.isListeningCot ? "Active" : "Inactive")
                }
                .disabled(!settings.isHostConfigurationValid())
            }
            
            Section("Preferences") {
                Toggle("Auto Spoof Detection", isOn: .init(
                    get: { settings.spoofDetectionEnabled },
                    set: { settings.spoofDetectionEnabled = $0 }
                ))
                
                Toggle("Keep Screen On", isOn: .init(
                    get: { settings.keepScreenOn },
                    set: { settings.updatePreferences(notifications: settings.notificationsEnabled, screenOn: $0) }
                ))
                
//                Toggle("Enable Background Detection", isOn: .init(
//                    get: { settings.enableBackgroundDetection },
//                    set: { settings.enableBackgroundDetection = $0 }
//                ))
//                .disabled(settings.isListening) // Can't change while listening is active
            }
            
            Section("Notifications") {
                Toggle("Enable Push Notifications", isOn: .init(
                    get: { settings.notificationsEnabled },
                    set: { settings.updatePreferences(notifications: $0, screenOn: settings.keepScreenOn) }
                ))
                
                if settings.notificationsEnabled {
                    NavigationLink(destination: StatusNotificationSettingsView()) {
                        HStack {
                            Image(systemName: "bell.circle.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text("Notification Settings")
                                Text("Configure frequency and types")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Enable to receive alerts on this device when drones are detected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Webhooks & External Services") {
                Toggle("Enable Webhooks", isOn: .init(
                    get: { settings.webhooksEnabled },
                    set: { settings.updateWebhookSettings(enabled: $0) }
                ))
                
                if settings.webhooksEnabled {
                    NavigationLink(destination: WebhookSettingsView()) {
                        HStack {
                            Image(systemName: "link.circle.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text("Webhook Services")
                                Text("\(WebhookManager.shared.configurations.count) services configured")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("Send notifications to Discord, Matrix, IFTTT, and other external services")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Performance") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Message Processing Interval")
                        Spacer()
                        Stepper(value: $settings.messageProcessingInterval, in: 50...2500, step: 50) {
                            Text("\(settings.messageProcessingInterval) ms")
                                .font(.appCaption)
                                .bold()
                                .foregroundColor(.primary)
                                .frame(width: 100, alignment: .trailing)
                        }
                    }
                }
            }
            
            Section("Warning Thresholds") {
                VStack(alignment: .leading) {
                    Toggle("System Warnings", isOn: $settings.systemWarningsEnabled)
                        .padding(.bottom)
                    
                    if settings.systemWarningsEnabled {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 30) {
                                TacDial(
                                    title: "CPU USAGE",
                                    value: $settings.cpuWarningThreshold,
                                    range: 50...90,
                                    step: 5,
                                    unit: "%",
                                    color: .blue
                                )
                                
                                TacDial(
                                    title: "SYSTEM TEMP",
                                    value: $settings.tempWarningThreshold,
                                    range: 40...85,
                                    step: 5,
                                    unit: "°C",
                                    color: .red
                                )
                                
                                TacDial(
                                    title: "MEMORY",
                                    value: .init(
                                        get: { settings.memoryWarningThreshold * 100 },
                                        set: { settings.memoryWarningThreshold = $0 / 100 }
                                    ),
                                    range: 50...95,
                                    step: 5,
                                    unit: "%",
                                    color: .green
                                )
                                
                                TacDial(
                                    title: "PLUTO TEMP",
                                    value: $settings.plutoTempThreshold,
                                    range: 40...100,
                                    step: 5,
                                    unit: "°C",
                                    color: .purple
                                )
                                
                                TacDial(
                                    title: "ZYNQ TEMP",
                                    value: $settings.zynqTempThreshold,
                                    range: 40...100,
                                    step: 5,
                                    unit: "°C",
                                    color: .orange
                                )
                            }
                            .padding(.horizontal)
                        }
                    }
                }
                
                VStack(alignment: .leading) {
                    Toggle("Proximity Warnings", isOn: $settings.enableProximityWarnings)
                        .padding(.vertical)
                    
                    if settings.enableProximityWarnings {
                        HStack {
                            TacDial(
                                title: "RSSI THRESHOLD",
                                value: .init(
                                    get: { Double(settings.proximityThreshold) },
                                    set: { settings.proximityThreshold = Int($0) }
                                ),
                                range: -90...(-30),
                                step: 5,
                                unit: "dBm",
                                color: .yellow
                            )
                        }
                        .padding(.horizontal)
                    }
                }
            }
            
            Section("Output") {
                NavigationLink {
                    TAKServerSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.blue)
                        Text("TAK Server")
                        Spacer()
                        if settings.takEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
                
                NavigationLink {
                    MQTTSettingsView()
                } label: {
                    HStack {
                        Image(systemName: "network")
                            .foregroundColor(.orange)
                        Text("MQTT Broker")
                        Spacer()
                        if settings.mqttEnabled {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        }
                    }
                }
            }
            
            Section("Ports") {
                switch settings.connectionMode {
                case .multicast:
                    HStack {
                        Text("Multicast")
                        Spacer()
                        Text(verbatim: String(settings.multicastPort))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    
                case .zmq:
                    HStack {
                        Text("ZMQ Telemetry")
                        Spacer()
                        Text(verbatim: String(settings.zmqTelemetryPort))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    HStack {
                        Text("ZMQ Status")
                        Spacer()
                        Text(verbatim: String(settings.zmqStatusPort))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                        .foregroundStyle(.secondary)
                }
                
                Link(destination: URL(string: "https://github.com/Root-Down-Digital/DragonSync-iOS")!) {
                    HStack {
                        Text("Source Code")
                        Spacer()
                        Image(systemName: "arrow.up.right.circle")
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .font(.appHeadline)
    }
    
    private var connectionStatusSymbol: String {
        if cotHandler.isListeningCot {
            switch settings.connectionMode {
            case .multicast:
                return "antenna.radiowaves.left.and.right.circle.fill"
            case .zmq:
                return "network.badge.shield.half.filled"
            }
        } else {
            return "bolt.horizontal.circle"
        }
    }
    
    private var connectionStatusColor: Color {
        if settings.isListening {
            return .green  // Always green when listening
        } else {
            return .red
        }
    }
    
    private var connectionStatusText: String {
        if settings.isListening {
            if cotHandler.isListeningCot {
                return "Connected"
            } else {
                return "Listening..."
            }
        } else {
            return "Disconnected"
        }
    }
}
