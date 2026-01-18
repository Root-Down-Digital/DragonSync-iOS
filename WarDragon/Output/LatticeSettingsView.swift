import SwiftUI

struct LatticeSettingsView: View {
    @StateObject private var settings = Settings.shared
    @State private var config: LatticeClient.LatticeConfiguration
    @State private var showingSaveConfirmation = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showPassword = false
    
    init() {
        _config = State(initialValue: Settings.shared.latticeConfiguration)
    }
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Lattice Integration", isOn: $config.enabled)
            } header: {
                Label("Lattice DAS", systemImage: "grid.circle.fill")
            } footer: {
                Text("Report drone detections to Lattice Detection as a Service (DAS) platform for enterprise-grade tracking and analysis.")
            }
            
            if config.enabled {
                Section {
                    Picker("Environment", selection: $config.serverURL) {
                        Text("Sandbox").tag("https://sandbox.lattice-das.com")
                        Text("Production").tag("https://api.lattice-das.com")
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Group {
                            if showPassword {
                                TextField("API Token", text: Binding(
                                    get: { config.apiToken ?? "" },
                                    set: { config.apiToken = $0.isEmpty ? nil : $0 }
                                ))
                            } else {
                                SecureField("API Token", text: Binding(
                                    get: { config.apiToken ?? "" },
                                    set: { config.apiToken = $0.isEmpty ? nil : $0 }
                                ))
                            }
                        }
                        .autocapitalization(.none)
                        
                        Button {
                            showPassword.toggle()
                        } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Select your environment and enter your API authentication token.")
                        Text("• Sandbox: For testing and development")
                            .font(.caption2)
                        Text("• Production: For live deployment")
                            .font(.caption2)
                    }
                }
                
                Section {
                    TextField("Organization ID", text: $config.organizationID, prompt: Text("org_abc123"))
                        .autocapitalization(.none)
                        .textContentType(.organizationName)
                    
                    TextField("Site ID", text: $config.siteID, prompt: Text("site_xyz789"))
                        .autocapitalization(.none)
                } header: {
                    Text("Organization")
                } footer: {
                    Text("Your organization and site identifiers from the Lattice platform. These are required for proper detection attribution. Contact your Lattice administrator for credentials.")
                }
                
                Section {
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
                    .disabled(!config.isValid || isTesting)
                    
                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("Success") ? .green : .red)
                    }
                } header: {
                    Text("Connection Test")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Detection Format", systemImage: "doc.text")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Detections are reported in Lattice-compatible JSON format including location, signal strength, and metadata.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Label("Data Privacy", systemImage: "lock.shield")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("All communications use HTTPS encryption. No detection data is stored locally after transmission.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Divider()
                            .padding(.vertical, 4)
                        
                        Label("Real-time Reporting", systemImage: "bolt.circle")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text("Detections are sent immediately to the Lattice platform as they occur, enabling real-time threat awareness.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Information")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Quick Setup", systemImage: "lightbulb")
                            .font(.headline)
                        
                        Text("1. Contact Lattice to get your credentials")
                            .font(.caption)
                        Text("2. Start with sandbox environment for testing")
                            .font(.caption)
                        Text("3. Enter Organization ID and Site ID")
                            .font(.caption)
                        Text("4. Add your API token")
                            .font(.caption)
                        Text("5. Test the connection")
                            .font(.caption)
                        Text("6. Switch to production when ready")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                } header: {
                    Text("Setup Guide")
                }
            }
            
            Section {
                Button(action: saveConfiguration) {
                    HStack {
                        Spacer()
                        Text("Save Configuration")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(!config.isValid && config.enabled)
            }
        }
        .navigationTitle("Lattice DAS")
        .alert("Configuration Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Lattice configuration has been saved successfully.")
        }
    }
    
    private func saveConfiguration() {
        Settings.shared.latticeConfiguration = config
        showingSaveConfirmation = true
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            do {
                let client = LatticeClient(configuration: config)
                
                // Create a test detection with all required fields
                var testDetection = CoTViewModel.CoTMessage(
                    uid: "test-\(UUID().uuidString)",
                    type: "a-f-A-M-H-Q",
                    lat: "0.0",
                    lon: "0.0",
                    homeLat: "0.0",
                    homeLon: "0.0",
                    speed: "0.0",
                    vspeed: "0.0",
                    alt: "0.0",
                    pilotLat: "0.0",
                    pilotLon: "0.0",
                    description: "Test Detection",
                    selfIDText: "TEST",
                    uaType: .none,
                    idType: "test",
                    rawMessage: [
                        "uid": "test-\(UUID().uuidString)",
                        "type": "test",
                        "source": "lattice_test"
                    ]
                )
                testDetection.mac = nil
                testDetection.manufacturer = "Test"
                testDetection.rssi = -50
                
                // Try to publish test detection
                try await client.publish(detection: testDetection)
                
                await MainActor.run {
                    testResult = "✓ Connection successful!"
                    isTesting = false
                }
                
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
    NavigationStack {
        LatticeSettingsView()
    }
}
