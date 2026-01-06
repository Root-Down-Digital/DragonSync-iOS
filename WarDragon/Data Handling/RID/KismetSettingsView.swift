import SwiftUI

struct KismetSettingsView: View {
    @StateObject private var settings = Settings.shared
    @State private var config: KismetClient.KismetConfiguration
    @State private var showingSaveConfirmation = false
    @State private var connectionStatus: String = "Not Connected"
    
    init() {
        _config = State(initialValue: Settings.shared.kismetConfiguration)
    }
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Kismet Integration", isOn: $config.enabled)
            } header: {
                Text("Kismet")
            } footer: {
                Text("Forward drone detections to Kismet for unified wireless monitoring. Kismet must be running and accessible on your network.")
            }
            
            if config.enabled {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(connectionStatus)
                            .foregroundColor(connectionStatus == "Connected" ? .green : .orange)
                    }
                } header: {
                    Text("Connection Status")
                }
                
                Section {
                    TextField("Server URL", text: $config.serverURL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                    
                    SecureField("API Key (Optional)", text: Binding(
                        get: { config.apiKey ?? "" },
                        set: { config.apiKey = $0.isEmpty ? nil : $0 }
                    ))
                    
                    Stepper("Poll Interval: \(Int(config.pollInterval))s",
                            value: $config.pollInterval,
                            in: 1...60)
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Kismet server URL (e.g., http://192.168.1.100:2501). API key is optional but recommended for security.")
                }
                
                Section {
                    ForEach(config.filterByType, id: \.self) { type in
                        HStack {
                            Text(type)
                            Spacer()
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        }
                    }
                } header: {
                    Text("Device Filters")
                } footer: {
                    Text("Only devices matching these types will be tracked. Default filters include Wi-Fi and Bluetooth devices.")
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
        .navigationTitle("Kismet Integration")
        .navigationBarTitleDisplayMode(.inline)
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
}

struct KismetSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            KismetSettingsView()
        }
    }
}
