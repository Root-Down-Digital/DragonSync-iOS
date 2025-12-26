//
//  MQTTSettingsView.swift
//  WarDragon
//
//  MQTT broker configuration UI
//

import SwiftUI

struct MQTTSettingsView: View {
    @StateObject private var settings = Settings.shared
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showPassword = false
    @State private var expandedSection: String?
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable MQTT", isOn: $settings.mqttEnabled)
            } header: {
                Label("MQTT Publishing", systemImage: "antenna.radiowaves.left.and.right")
            } footer: {
                Text("Publish drone detections and system status to an MQTT broker")
            }
            
            if settings.mqttEnabled {
                Section("Broker Configuration") {
                    TextField("Host", text: $settings.mqttHost)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", value: $settings.mqttPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    Toggle("Use TLS/SSL", isOn: $settings.mqttUseTLS)
                        .onChange(of: settings.mqttUseTLS) { useTLS in
                            // Auto-adjust port
                            if settings.mqttPort == 1883 || settings.mqttPort == 8883 {
                                settings.mqttPort = useTLS ? 8883 : 1883
                            }
                        }
                }
                
                Section("Authentication") {
                    TextField("Username (optional)", text: $settings.mqttUsername)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    
                    HStack {
                        Group {
                            if showPassword {
                                TextField("Password (optional)", text: $settings.mqttPassword)
                            } else {
                                SecureField("Password (optional)", text: $settings.mqttPassword)
                            }
                        }
                        .textContentType(.password)
                        .autocapitalization(.none)
                        
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Section("Topic Configuration") {
                    TextField("Base Topic", text: $settings.mqttBaseTopic)
                        .autocapitalization(.none)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        topicPreview("Drones", "\(settings.mqttBaseTopic)/drones/{mac}")
                        topicPreview("System", "\(settings.mqttBaseTopic)/system")
                        topicPreview("Status", "\(settings.mqttBaseTopic)/status")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                
                Section("Publishing Options") {
                    Picker("Quality of Service", selection: $settings.mqttQoS) {
                        ForEach(MQTTQoS.allCases, id: \.self) { qos in
                            Text(qos.displayName).tag(qos)
                        }
                    }
                    
                    Toggle("Retain Messages", isOn: $settings.mqttRetain)
                    
                    Toggle("Clean Session", isOn: $settings.mqttCleanSession)
                    
                    HStack {
                        Text("Keepalive")
                        Spacer()
                        Stepper("\(settings.mqttKeepalive)s", value: $settings.mqttKeepalive, in: 10...300, step: 10)
                    }
                }
                
                Section {
                    Toggle("Home Assistant Discovery", isOn: $settings.mqttHomeAssistantEnabled)
                    
                    if settings.mqttHomeAssistantEnabled {
                        TextField("Discovery Prefix", text: $settings.mqttHomeAssistantDiscoveryPrefix)
                            .autocapitalization(.none)
                        
                        Text("Automatically creates Home Assistant entities for detected drones and system status")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    HStack {
                        Image(systemName: "house.circle.fill")
                            .foregroundColor(.blue)
                        Text("Home Assistant")
                    }
                }
                
                Section("Advanced") {
                    DisclosureGroup(
                        isExpanded: .init(
                            get: { expandedSection == "qos" },
                            set: { expandedSection = $0 ? "qos" : nil }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            qosInfo(.atMostOnce)
                            Divider()
                            qosInfo(.atLeastOnce)
                            Divider()
                            qosInfo(.exactlyOnce)
                        }
                        .padding(.vertical, 8)
                    } label: {
                        HStack {
                            Image(systemName: "info.circle")
                            Text("QoS Information")
                        }
                    }
                    
                    HStack {
                        Text("Reconnect Delay")
                        Spacer()
                        Stepper("\(settings.mqttReconnectDelay)s", value: $settings.mqttReconnectDelay, in: 1...60, step: 1)
                    }
                }
                
                Section("Connection Test") {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            if isTesting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "network")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(!settings.mqttConfiguration.isValid || isTesting)
                    
                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Quick Setup", systemImage: "lightbulb")
                            .font(.headline)
                        
                        Text("1. Install an MQTT broker (Mosquitto, HiveMQ, etc.)")
                        Text("2. Enter broker hostname and port")
                        Text("3. Configure authentication if required")
                        Text("4. Set base topic (e.g., 'wardragon')")
                        Text("5. Test the connection")
                        
                        if settings.mqttHomeAssistantEnabled {
                            Divider()
                                .padding(.vertical, 4)
                            
                            Label("Home Assistant Setup", systemImage: "house")
                                .font(.headline)
                            
                            Text("1. Ensure MQTT integration is configured in Home Assistant")
                            Text("2. Discovery messages will be sent automatically")
                            Text("3. Entities appear in Home Assistant as device_tracker and sensors")
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("Setup Guide")
                }
            }
        }
        .navigationTitle("MQTT")
    }
    
    // MARK: - Helper Views
    
    private func topicPreview(_ label: String, _ topic: String) -> some View {
        HStack {
            Text("\(label):")
                .fontWeight(.medium)
            Text(topic)
                .fontDesign(.monospaced)
        }
    }
    
    private func qosInfo(_ qos: MQTTQoS) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("QoS \(qos.rawValue)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(qos.description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            do {
                let config = settings.mqttConfiguration
                let client = await MQTTClient(configuration: config)
                
                await client.connect()
                
                // Wait up to 5 seconds for connection
                try await Task.sleep(nanoseconds: 5_000_000_000)
                
                let state = await client.state
                
                await MainActor.run {
                    switch state {
                    case .connected:
                        testResult = "✓ Connection successful!"
                    case .connecting:
                        testResult = "⏳ Still connecting..."
                    case .failed(let error):
                        testResult = "✗ Connection failed: \(error.localizedDescription)"
                    case .disconnected:
                        testResult = "✗ Disconnected"
                    }
                    isTesting = false
                }
                
                // Try to publish a test message
                if case .connected = state {
                    let testMessage = MQTTStatusMessage(
                        status: "test",
                        timestamp: ISO8601DateFormatter().string(from: Date()),
                        device: UIDevice.current.name
                    )
                    try? await client.publish(
                        topic: "\(config.baseTopic)/test",
                        message: testMessage
                    )
                }
                
                await client.disconnect()
                
            } catch {
                await MainActor.run {
                    testResult = "✗ Test failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        MQTTSettingsView()
    }
}
