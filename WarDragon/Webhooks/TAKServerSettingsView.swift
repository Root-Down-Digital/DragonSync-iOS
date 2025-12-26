//
//  TAKServerSettingsView.swift
//  WarDragon
//
//  TAK Server configuration UI
//

import SwiftUI
import UniformTypeIdentifiers

struct TAKServerSettingsView: View {
    @StateObject private var settings = Settings.shared
    @State private var showingCertificatePicker = false
    @State private var showingPasswordAlert = false
    @State private var certificatePassword = ""
    @State private var selectedCertificateURL: URL?
    @State private var testResult: String?
    @State private var isTesting = false
    
    var body: some View {
        Form {
            Section {
                Toggle("Enable TAK Server", isOn: $settings.takEnabled)
            } header: {
                Label("TAK Server", systemImage: "antenna.radiowaves.left.and.right")
            } footer: {
                Text("Send Cursor-on-Target messages to a TAK server for sharing drone locations with ATAK/WinTAK/iTAK")
            }
            
            if settings.takEnabled {
                Section("Connection") {
                    TextField("Host", text: $settings.takHost)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", value: $settings.takPort, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    
                    Picker("Protocol", selection: $settings.takProtocol) {
                        ForEach(TAKProtocol.allCases, id: \.self) { proto in
                            HStack {
                                Image(systemName: proto.icon)
                                Text(proto.rawValue)
                            }
                            .tag(proto)
                        }
                    }
                    .onChange(of: settings.takProtocol) { newProtocol in
                        // Auto-adjust port when protocol changes
                        if settings.takPort == TAKProtocol.tcp.defaultPort ||
                           settings.takPort == TAKProtocol.tls.defaultPort {
                            settings.takPort = newProtocol.defaultPort
                        }
                    }
                }
                
                if settings.takProtocol == .tls {
                    Section {
                        HStack {
                            Text("Client Certificate")
                            Spacer()
                            if TAKConfiguration.loadP12FromKeychain() != nil {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        Button {
                            showingCertificatePicker = true
                        } label: {
                            HStack {
                                Image(systemName: "doc.badge.plus")
                                Text("Import P12 Certificate")
                            }
                        }
                        
                        if TAKConfiguration.loadP12FromKeychain() != nil {
                            Button(role: .destructive) {
                                TAKConfiguration.deleteP12FromKeychain()
                                settings.objectWillChange.send()
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Remove Certificate")
                                }
                            }
                        }
                        
                        Toggle("Skip Certificate Verification", isOn: $settings.takSkipVerification)
                            .foregroundColor(.orange)
                        
                        if settings.takSkipVerification {
                            Text("⚠️ UNSAFE: Only use for testing")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } header: {
                        Text("TLS Configuration")
                    } footer: {
                        Text("Import your TAK server client certificate (.p12 file) for secure TLS connections")
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
                    .disabled(!settings.takConfiguration.isValid || isTesting)
                    
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
                        
                        Text("1. Export your client certificate from TAK Server as a .p12 file")
                        Text("2. Import it using the button above")
                        Text("3. Enter your TAK server hostname and port")
                        Text("4. Test the connection")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("Setup Guide")
                }
            }
        }
        .navigationTitle("TAK Server")
        .fileImporter(
            isPresented: $showingCertificatePicker,
            allowedContentTypes: [UTType(filenameExtension: "p12")].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            handleCertificateImport(result)
        }
        .alert("Certificate Password", isPresented: $showingPasswordAlert) {
            SecureField("Password", text: $certificatePassword)
            Button("Cancel", role: .cancel) {
                selectedCertificateURL = nil
                certificatePassword = ""
            }
            Button("Import") {
                importCertificate()
            }
        } message: {
            Text("Enter the password for this P12 certificate (leave empty if none)")
        }
    }
    
    // MARK: - Certificate Import
    
    private func handleCertificateImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedCertificateURL = url
            showingPasswordAlert = true
            
        case .failure(let error):
            testResult = "Import failed: \(error.localizedDescription)"
        }
    }
    
    private func importCertificate() {
        guard let url = selectedCertificateURL else { return }
        
        do {
            let data = try Data(contentsOf: url)
            
            // Test that we can load the certificate with the provided password
            var config = settings.takConfiguration
            config.p12CertificateData = data
            config.p12Password = certificatePassword.isEmpty ? nil : certificatePassword
            
            // Save to keychain
            try config.saveP12ToKeychain()
            
            // Update settings
            settings.updateTAKConfiguration(config)
            
            testResult = "Certificate imported successfully"
            certificatePassword = ""
            selectedCertificateURL = nil
            
        } catch {
            testResult = "Certificate import failed: \(error.localizedDescription)"
            certificatePassword = ""
            selectedCertificateURL = nil
        }
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            do {
                let config = settings.takConfiguration
                let client = await TAKClient(configuration: config)
                
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
        TAKServerSettingsView()
    }
}
