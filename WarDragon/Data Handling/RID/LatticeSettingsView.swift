import SwiftUI

struct LatticeSettingsView: View {
    @StateObject private var settings = Settings.shared
    @State private var config: LatticeClient.LatticeConfiguration
    @State private var showingSaveConfirmation = false
    @State private var connectionStatus: String = "Not Connected"
    
    init() {
        _config = State(initialValue: Settings.shared.latticeConfiguration)
    }
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable Lattice Integration", isOn: $config.enabled)
            } header: {
                Text("Lattice")
            } footer: {
                Text("Report drone detections to Lattice Detection as a Service (DAS) platform for enterprise-grade tracking and analysis.")
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
                    
                    SecureField("API Token", text: Binding(
                        get: { config.apiToken ?? "" },
                        set: { config.apiToken = $0.isEmpty ? nil : $0 }
                    ))
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Lattice API server URL and authentication token. Contact your Lattice administrator for credentials.")
                }
                
                Section {
                    TextField("Organization ID", text: $config.organizationID)
                        .autocapitalization(.none)
                        .textContentType(.organizationName)
                    
                    TextField("Site ID", text: $config.siteID)
                        .autocapitalization(.none)
                } header: {
                    Text("Organization")
                } footer: {
                    Text("Your organization and site identifiers from the Lattice platform. These are required for proper detection attribution.")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Detection Format", systemImage: "doc.text")
                        Text("Detections are reported in Lattice-compatible JSON format including location, signal strength, and metadata.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Label("Data Privacy", systemImage: "lock.shield")
                        Text("All communications use HTTPS encryption. No detection data is stored locally after transmission.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Information")
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
        .navigationTitle("Lattice Integration")
        .navigationBarTitleDisplayMode(.inline)
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
}

struct LatticeSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LatticeSettingsView()
        }
    }
}
