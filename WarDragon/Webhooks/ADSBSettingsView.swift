//
//  ADSBSettingsView.swift
//  WarDragon
//
//  ADS-B/readsb configuration UI
//

import SwiftUI

struct ADSBSettingsView: View {
    @StateObject private var settings = Settings.shared
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var aircraftCount: Int = 0
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable ADS-B Tracking", isOn: $settings.adsbEnabled)
            } header: {
                Label("ADS-B Aircraft Tracking", systemImage: "airplane")
            } footer: {
                Text("Track aircraft via ADS-B using readsb HTTP API")
            }
            
            if settings.adsbEnabled {
                Section("Readsb Configuration") {
                    TextField("Readsb URL", text: $settings.adsbReadsbURL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Poll Interval")
                            Spacer()
                            Text("\(settings.adsbPollInterval, specifier: "%.1f")s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $settings.adsbPollInterval, in: 0.5...10, step: 0.5)
                    }
                    
                    Text("Full URL: \(settings.adsbReadsbURL)/data/aircraft.json")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Filters") {
                    Toggle("Filter by Distance", isOn: .init(
                        get: { settings.adsbMaxDistance > 0 },
                        set: { settings.adsbMaxDistance = $0 ? 50 : 0 }
                    ))
                    
                    if settings.adsbMaxDistance > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Max Distance")
                                Spacer()
                                Text("\(Int(settings.adsbMaxDistance)) km")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.adsbMaxDistance, in: 10...500, step: 10)
                        }
                    }
                    
                    Toggle("Filter by Altitude", isOn: .init(
                        get: { settings.adsbMinAltitude > 0 || settings.adsbMaxAltitude < 50000 },
                        set: { enabled in
                            if enabled {
                                settings.adsbMinAltitude = 1000
                                settings.adsbMaxAltitude = 40000
                            } else {
                                settings.adsbMinAltitude = 0
                                settings.adsbMaxAltitude = 50000
                            }
                        }
                    ))
                    
                    if settings.adsbMinAltitude > 0 || settings.adsbMaxAltitude < 50000 {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Min Altitude")
                                Spacer()
                                Text("\(Int(settings.adsbMinAltitude)) ft")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.adsbMinAltitude, in: 0...10000, step: 500)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Max Altitude")
                                Spacer()
                                Text("\(Int(settings.adsbMaxAltitude)) ft")
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $settings.adsbMaxAltitude, in: 10000...50000, step: 1000)
                        }
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
                                Image(systemName: "airplane.circle")
                            }
                            Text("Test Connection")
                        }
                    }
                    .disabled(!settings.adsbConfiguration.isValid || isTesting)
                    
                    if let result = testResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("Success") ? .green : .red)
                            
                            if aircraftCount > 0 {
                                Text("Found \(aircraftCount) aircraft with position data")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Quick Setup", systemImage: "lightbulb")
                            .font(.headline)
                        
                        Text("1. Install readsb on your Raspberry Pi or server:")
                            .font(.caption)
                        Text("   sudo apt install readsb")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        
                        Text("2. Configure readsb to listen on network:")
                            .font(.caption)
                        Text("   Edit /etc/default/readsb")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        
                        Text("3. Enter readsb URL above:")
                            .font(.caption)
                        Text("   http://your-pi-ip:8080")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        
                        Text("4. Test connection and adjust poll interval")
                            .font(.caption)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Text("Compatible with:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("• readsb")
                            .font(.caption)
                        Text("• dump1090")
                            .font(.caption)
                        Text("• tar1090")
                            .font(.caption)
                        Text("• Any service providing aircraft.json")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } header: {
                    Text("Setup Guide")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aircraft data from readsb will:")
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("• Appear on the map alongside drones")
                            .font(.caption)
                        Text("• Be published to MQTT if enabled")
                            .font(.caption)
                        Text("• Be sent to TAK server if enabled")
                            .font(.caption)
                        Text("• Use distinct aircraft icon")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } header: {
                    Text("Integration")
                }
            }
        }
        .navigationTitle("ADS-B Tracking")
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        aircraftCount = 0
        
        Task {
            let config = settings.adsbConfiguration
            let client = ADSBClient(configuration: config)
            
            await client.poll()
            
            let state = client.state
            let count = client.aircraft.count
            
            await MainActor.run {
                switch state {
                case .connected:
                    testResult = "✓ Connection successful!"
                    aircraftCount = count
                case .connecting:
                    testResult = "⏳ Connecting..."
                case .failed(let error):
                    testResult = "✗ Connection failed: \(error.localizedDescription)"
                case .disconnected:
                    testResult = "✗ Disconnected"
                }
                isTesting = false
            }
            
            await MainActor.run {
                testResult = "✗ Test completed"
                isTesting = false
            }
        }
    }
}

#Preview {
    NavigationView {
        ADSBSettingsView()
    }
}
