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
    @State private var showingPEMCertPicker = false
    @State private var showingPEMKeyPicker = false
    @State private var showingPasswordAlert = false
    @State private var showingPEMPasswordAlert = false
    @State private var certificatePassword = ""
    @State private var pemKeyPassword = ""
    @State private var selectedCertificateURL: URL?
    @State private var selectedPEMCertURL: URL?
    @State private var selectedPEMKeyURL: URL?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var certificateType: CertificateType = .p12
    
    enum CertificateType {
        case p12
        case pem
    }
    
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
                    .onChange(of: settings.takProtocol) {
                        // Auto-adjust port when protocol changes
                        if settings.takPort == TAKProtocol.tcp.defaultPort ||
                           settings.takPort == TAKProtocol.tls.defaultPort {
                            settings.takPort = settings.takProtocol.defaultPort
                        }
                    }
                }
                
                if settings.takProtocol == .tls {
                    Section {
                        Picker("Certificate Type", selection: $certificateType) {
                            Text("P12 / PKCS12").tag(CertificateType.p12)
                            Text("PEM (Recommended)").tag(CertificateType.pem)
                        }
                        .pickerStyle(.segmented)
                        
                        if certificateType == .p12 {
                            // P12 Certificate
                            HStack {
                                Text("P12 Certificate")
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
                                if let certInfo = getCertificateInfo() {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Certificate Details:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(certInfo)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Button(role: .destructive) {
                                    TAKConfiguration.deleteP12FromKeychain()
                                    settings.objectWillChange.send()
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Remove P12 Certificate")
                                    }
                                }
                            }
                        } else {
                            // PEM Certificates
                            HStack {
                                Text("PEM Certificate")
                                Spacer()
                                if TAKConfiguration.loadPEMCertFromKeychain() != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            Button {
                                showingPEMCertPicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "doc.badge.plus")
                                    Text("Import PEM Certificate (.crt/.pem)")
                                }
                            }
                            
                            HStack {
                                Text("PEM Private Key")
                                Spacer()
                                if TAKConfiguration.loadPEMKeyFromKeychain() != nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            Button {
                                showingPEMKeyPicker = true
                            } label: {
                                HStack {
                                    Image(systemName: "key.fill")
                                    Text("Import PEM Private Key (.key)")
                                }
                            }
                            
                            if TAKConfiguration.loadPEMCertFromKeychain() != nil,
                               TAKConfiguration.loadPEMKeyFromKeychain() != nil {
                                if let pemInfo = getPEMCertificateInfo() {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Certificate Details:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(pemInfo)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Button(role: .destructive) {
                                    TAKConfiguration.deletePEMFromKeychain()
                                    settings.objectWillChange.send()
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Remove PEM Certificates")
                                    }
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
                        if certificateType == .pem {
                            Text("Import your TAK server client certificate (.pem or .crt) and private key (.key) files. Most TAK servers use PEM format.")
                        } else {
                            Text("Import your TAK server client certificate (.p12 file) for secure TLS connections. PEM format is recommended for TAK servers.")
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
                        
                        if certificateType == .pem {
                            Text("1. Get your client certificate (.pem or .crt) from TAK Server")
                            Text("2. Get your private key (.key) from TAK Server")
                            Text("3. Import both files using the buttons above")
                            Text("4. Enter your TAK server hostname and port")
                            Text("5. Test the connection")
                        } else {
                            Text("1. Export your client certificate from TAK Server as a .p12 file")
                            Text("2. Import it using the button above")
                            Text("3. Enter your TAK server hostname and port")
                            Text("4. Test the connection")
                        }
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
        .fileImporter(
            isPresented: $showingPEMCertPicker,
            allowedContentTypes: [
                UTType(filenameExtension: "pem"),
                UTType(filenameExtension: "crt"),
                UTType(filenameExtension: "cer")
            ].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            handlePEMCertImport(result)
        }
        .fileImporter(
            isPresented: $showingPEMKeyPicker,
            allowedContentTypes: [
                UTType(filenameExtension: "key"),
                UTType(filenameExtension: "pem")
            ].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            handlePEMKeyImport(result)
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
        .alert("Private Key Password", isPresented: $showingPEMPasswordAlert) {
            SecureField("Password (optional)", text: $pemKeyPassword)
            Button("Cancel", role: .cancel) {
                selectedPEMKeyURL = nil
                pemKeyPassword = ""
            }
            Button("Import") {
                importPEMKey()
            }
        } message: {
            Text("Enter the password for this private key if it's encrypted (leave empty if none)")
        }
    }
    
    // MARK: - Certificate Import
    
    private func getPEMCertificateInfo() -> String? {
        guard let pemCert = TAKConfiguration.loadPEMCertFromKeychain(),
              let certString = String(data: pemCert, encoding: .utf8) else {
            return nil
        }
        
        // Try to extract subject from PEM
        // This is a simplified version - real parsing would be more complex
        if certString.contains("BEGIN CERTIFICATE") {
            return "PEM certificate loaded"
        }
        
        return "Certificate loaded"
    }
    
    private func handlePEMCertImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importPEMCert(from: url)
            
        case .failure(let error):
            testResult = "PEM cert import failed: \(error.localizedDescription)"
        }
    }
    
    private func importPEMCert(from url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "com.wardragon", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Permission denied: Unable to access the selected file"
                ])
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            let data = try Data(contentsOf: url)
            
            // Validate it's a PEM certificate
            guard let certString = String(data: data, encoding: .utf8),
                  certString.contains("BEGIN CERTIFICATE") else {
                throw NSError(domain: "com.wardragon", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid PEM certificate file - no certificate found"
                ])
            }
            
            // Update configuration
            var config = settings.takConfiguration
            config.pemCertificateData = data
            
            // Save to keychain
            try config.savePEMCertToKeychain()
            
            // Update settings
            settings.updateTAKConfiguration(config)
            
            testResult = "✓ PEM certificate imported successfully"
            
        } catch {
            testResult = "✗ PEM cert import failed: \(error.localizedDescription)"
        }
    }
    
    private func handlePEMKeyImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            selectedPEMKeyURL = url
            // Always ask for password in case key is encrypted
            showingPEMPasswordAlert = true
            
        case .failure(let error):
            testResult = "PEM key import failed: \(error.localizedDescription)"
        }
    }
    
    private func importPEMKey() {
        guard let url = selectedPEMKeyURL else { return }
        
        do {
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "com.wardragon", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Permission denied: Unable to access the selected file"
                ])
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            let data = try Data(contentsOf: url)
            
            // Validate it's a PEM private key
            guard let keyString = String(data: data, encoding: .utf8),
                  (keyString.contains("BEGIN PRIVATE KEY") ||
                   keyString.contains("BEGIN RSA PRIVATE KEY") ||
                   keyString.contains("BEGIN EC PRIVATE KEY")) else {
                throw NSError(domain: "com.wardragon", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Invalid PEM private key file - no private key found"
                ])
            }
            
            // Update configuration
            var config = settings.takConfiguration
            config.pemKeyData = data
            config.pemKeyPassword = pemKeyPassword.isEmpty ? nil : pemKeyPassword
            
            // Save to keychain
            try config.savePEMKeyToKeychain()
            
            // Update settings
            settings.updateTAKConfiguration(config)
            
            testResult = "✓ PEM private key imported successfully"
            pemKeyPassword = ""
            selectedPEMKeyURL = nil
            
        } catch {
            testResult = "✗ PEM key import failed: \(error.localizedDescription)"
            pemKeyPassword = ""
            selectedPEMKeyURL = nil
        }
    }
    
    private func getCertificateInfo() -> String? {
        guard let p12Data = TAKConfiguration.loadP12FromKeychain() else {
            return nil
        }
        
        let password = settings.takP12Password
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password
        ]
        
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        
        guard status == errSecSuccess,
              let itemsArray = items as? [[String: Any]],
              let firstItem = itemsArray.first else {
            return "Unable to read certificate"
        }
        
        if let cert = firstItem[kSecImportItemCertChain as String] as? [SecCertificate],
           let firstCert = cert.first,
           let summary = SecCertificateCopySubjectSummary(firstCert) as String? {
            return summary
        }
        
        return "Certificate loaded"
    }
    
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
            // Start accessing security-scoped resource
            guard url.startAccessingSecurityScopedResource() else {
                throw NSError(domain: "com.wardragon", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Permission denied: Unable to access the selected file"
                ])
            }
            
            defer {
                url.stopAccessingSecurityScopedResource()
            }
            
            let data = try Data(contentsOf: url)
            
            // Validate the P12 file and password before saving
            let password = certificatePassword.isEmpty ? nil : certificatePassword
            let validationOptions: [String: Any] = [
                kSecImportExportPassphrase as String: password ?? ""
            ]
            
            var items: CFArray?
            let status = SecPKCS12Import(data as CFData, validationOptions as CFDictionary, &items)
            
            guard status == errSecSuccess else {
                let errorMessage: String
                switch status {
                case errSecAuthFailed:
                    errorMessage = "Incorrect certificate password"
                case errSecDecode:
                    errorMessage = "Invalid P12 file format"
                case errSecPkcs12VerifyFailure:
                    errorMessage = "P12 verification failed - check password"
                default:
                    errorMessage = "P12 import failed (status: \(status))"
                }
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                    NSLocalizedDescriptionKey: errorMessage
                ])
            }
            
            // Verify we got identity from the P12
            guard let itemsArray = items as? [[String: Any]],
                  let firstItem = itemsArray.first,
                  firstItem[kSecImportItemIdentity as String] != nil else {
                throw NSError(domain: "com.wardragon", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "No valid identity found in P12 file"
                ])
            }
            
            // Get certificate info for confirmation
            var certSummary = "Unknown"
            if let cert = firstItem[kSecImportItemCertChain as String] as? [SecCertificate],
               let firstCert = cert.first,
               let summary = SecCertificateCopySubjectSummary(firstCert) as String? {
                certSummary = summary
            }
            
            // Update configuration
            var config = settings.takConfiguration
            config.p12CertificateData = data
            config.p12Password = password
            
            // Save to keychain
            try config.saveP12ToKeychain()
            
            // Update settings
            settings.updateTAKConfiguration(config)
            
            testResult = "✓ Certificate imported: \(certSummary)"
            certificatePassword = ""
            selectedCertificateURL = nil
            
        } catch {
            testResult = "✗ Import failed: \(error.localizedDescription)"
            certificatePassword = ""
            selectedCertificateURL = nil
        }
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            let client: TAKClient? 
            do {
                let config = settings.takConfiguration
                client = TAKClient(configuration: config)
                
                client?.connect()
                
                // Wait up to 5 seconds for connection
                try await Task.sleep(nanoseconds: 5_000_000_000)
                
                let state = client?.state ?? .disconnected
                
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
                
            } catch {
                await MainActor.run {
                    testResult = "✗ Test failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
            
            // Always disconnect the client, even if an error occurred
            client?.disconnect()
        }
    }
}

#Preview {
    NavigationView {
        TAKServerSettingsView()
    }
}
