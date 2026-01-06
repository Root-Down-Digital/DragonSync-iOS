import SwiftUI

struct KismetSettingsView: View {
    @StateObject private var settings = Settings.shared
    @State private var config: KismetClient.KismetConfiguration
    @State private var showingSaveConfirmation = false
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var deviceCount: Int = 0
    
    init() {
        _config = State(initialValue: Settings.shared.kismetConfiguration)
    }
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Kismet Integration", isOn: $config.enabled)
            } header: {
                Label("Kismet Server", systemImage: "wifi.circle.fill")
            } footer: {
                Text("Forward drone detections to Kismet for unified wireless monitoring. Kismet must be running and accessible on your network.")
            }
            
            if config.enabled {
                Section {
                    TextField("Server URL", text: $config.serverURL, prompt: Text("http://192.168.1.100:2501"))
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                    
                    SecureField("API Key (Optional)", text: Binding(
                        get: { config.apiKey ?? "" },
                        set: { config.apiKey = $0.isEmpty ? nil : $0 }
                    ))
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Poll Interval")
                            Spacer()
                            Text("\(Int(config.pollInterval))s")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $config.pollInterval, in: 1...60, step: 1)
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Kismet server URL including port (default 2501). API key is optional but recommended for security.")
                }
                
                Section {
                    ForEach(config.filterByType, id: \.self) { type in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(type)
                        }
                    }
                } header: {
                    Text("Device Filters")
                } footer: {
                    Text("Only devices matching these types will be tracked from Kismet.")
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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result)
                                .font(.caption)
                                .foregroundColor(result.contains("Success") ? .green : .red)
                            
                            if deviceCount > 0 {
                                Text("Found \(deviceCount) devices")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Connection Test")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Quick Setup", systemImage: "lightbulb")
                            .font(.headline)
                        
                        Text("1. Install Kismet on your server:")
                            .font(.caption)
                        Text("   sudo apt install kismet")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        
                        Text("2. Start Kismet with web UI enabled:")
                            .font(.caption)
                        Text("   sudo kismet")
                            .font(.caption)
                            .fontDesign(.monospaced)
                        
                        Text("3. Generate an API key in Kismet settings")
                            .font(.caption)
                        
                        Text("4. Enter server URL and test connection")
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
        .navigationTitle("Kismet")
        .alert("Configuration Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Kismet configuration has been saved successfully.")
        }
    }
    
    private func saveConfiguration() {
        Settings.shared.kismetConfiguration = config
        showingSaveConfirmation = true
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        deviceCount = 0
        
        Task {
            let client = KismetClient(configuration: config)
            
            client.start()
            
            // Wait a bit for initial poll
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            let state = client.state
            let count = client.devices.count
            
            await MainActor.run {
                switch state {
                case .connected:
                    testResult = "✓ Connection successful!"
                    deviceCount = count
                case .connecting:
                    testResult = "⏳ Still connecting..."
                case .failed(let error):
                    testResult = "✗ Connection failed: \(error.localizedDescription)"
                case .disconnected:
                    testResult = "✗ Disconnected"
                }
                isTesting = false
            }
            
            client.stop()
        }
    }
}

#Preview {
    NavigationStack {
        KismetSettingsView()
    }
}
