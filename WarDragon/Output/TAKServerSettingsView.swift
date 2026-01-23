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
    @StateObject private var enrollmentManager = TAKEnrollmentManager()
    
    @State private var testResult: String?
    @State private var isTesting = false
    
    // Enrollment fields
    @State private var enrollmentUsername = ""
    @State private var enrollmentPassword = ""
    @State private var isEnrolling = false
    
    // Manual certificate import
    @State private var showingP12Picker = false
    @State private var p12Password = ""
    @State private var showingP12PasswordPrompt = false
    @State private var pendingP12Data: Data?
    
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
                Section {
                    TextField("Host", text: $settings.takHost)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .keyboardType(.URL)
                    
                    HStack {
                        Text("Streaming Port")
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
                    .onChange(of: settings.takProtocol) { oldValue, newValue in
                        settings.takPort = newValue.defaultPort
                    }
                } header: {
                    Text("Connection")
                } footer: {
                    Text("Streaming port for sending CoT data. Common ports:\n• TAK Server: UDP 8089 or 8054\n• TCP: 8087\n• TLS: 8089\n• Enrollment API: 8446\n\nCheck your TAK Server's CoreConfig.xml or docker-compose.yml for the correct port.")
                }
                
                if settings.takProtocol == .tls {
                    Section {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(enrollmentManager.enrollmentState.statusText)
                                .foregroundColor(enrollmentManager.enrollmentState.isValid ? .green : .orange)
                        }
                        
                        if let certInfo = enrollmentManager.certificateInfo {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Subject: \(certInfo.subject)")
                                    .font(.caption)
                                Text("Expires: \(certInfo.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                if certInfo.daysUntilExpiry < 30 {
                                    Text("⚠️ Expires in \(certInfo.daysUntilExpiry) days")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        
                        if !enrollmentManager.enrollmentState.isValid {
                            TextField("Username", text: $enrollmentUsername)
                                .autocapitalization(.none)
                                .textContentType(.username)
                            
                            SecureField("Password", text: $enrollmentPassword)
                                .textContentType(.password)
                            
                            Button {
                                performAPIEnrollment()
                            } label: {
                                HStack {
                                    if isEnrolling {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "checkmark.shield")
                                    }
                                    Text(isEnrolling ? "Enrolling..." : "Enroll via API (Recommended)")
                                }
                            }
                            .disabled(enrollmentUsername.isEmpty || enrollmentPassword.isEmpty || isEnrolling)
                            .buttonStyle(.borderedProminent)
                            
                            Button {
                                performEnrollment()
                            } label: {
                                HStack {
                                    if isEnrolling {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.down.circle")
                                    }
                                    Text(isEnrolling ? "Enrolling..." : "Enroll via CSR (Legacy)")
                                }
                            }
                            .disabled(enrollmentUsername.isEmpty || enrollmentPassword.isEmpty || isEnrolling)
                            
                            Text("Try 'API' first. If it fails, try 'CSR' or manual import below.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Button {
                                testEnrollmentEndpoint()
                            } label: {
                                HStack {
                                    Image(systemName: "network.badge.shield.half.filled")
                                    Text("Test Enrollment Port")
                                }
                            }
                            .disabled(settings.takHost.isEmpty || isEnrolling)
                            
                            if isEnrolling {
                                Text(enrollmentManager.enrollmentProgress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let error = enrollmentManager.lastError {
                                Text("Error: \(error.localizedDescription)")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        if enrollmentManager.enrollmentState.isValid {
                            Button(role: .destructive) {
                                enrollmentManager.unenroll()
                            } label: {
                                HStack {
                                    Image(systemName: "trash")
                                    Text("Remove Certificate")
                                }
                            }
                        }
                        
                        if !enrollmentManager.enrollmentState.isValid {
                            Text("Alternative: Import Certificate File")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Button {
                                showingP12Picker = true
                            } label: {
                                HStack {
                                    Image(systemName: "folder")
                                    Text("Import P12 Certificate")
                                }
                            }
                            
                            Text("If automatic enrollment fails, download your certificate from TAK Server's web UI and import it here.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if case .expired = enrollmentManager.enrollmentState {
                            Button {
                                let username = settings.takEnrollmentUsername
                                let password = settings.takEnrollmentPassword
                                if !username.isEmpty && !password.isEmpty {
                                    enrollmentUsername = username
                                    enrollmentPassword = password
                                    performEnrollment()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Renew Certificate")
                                }
                            }
                        }
                    } header: {
                        Text("Certificate Enrollment")
                    } footer: {
                        Text("Automatic enrollment with TAK Server using username and password. TLS requires certificate enrollment.")
                    }
                    
                    Section {
                        Toggle("Skip Certificate Verification", isOn: $settings.takSkipVerification)
                            .foregroundColor(.orange)
                        
                        if settings.takSkipVerification {
                            Text("⚠️ UNSAFE: Only use for testing")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } header: {
                        Text("Security Options")
                    }
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
                            Text("Test Streaming Connection")
                        }
                    }
                    .disabled(!settings.takConfiguration.isValid || isTesting)
                    
                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.contains("Success") || result.contains("✓") ? .green : .red)
                    }
                } header: {
                    Text("Connection Test")
                } footer: {
                    Text("Tests connection to the COT data streaming port (\(settings.takPort)). Enrollment uses a different port (8446).")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Quick Setup", systemImage: "lightbulb")
                            .font(.headline)
                        
                        Text("1. Enter TAK Server hostname (e.g., takserver.local)")
                        Text("2. Select protocol and port:")
                        Text("   • TLS (8089) - Secure, requires enrollment")
                        Text("   • TCP (8087) - No encryption")
                        Text("   • UDP (8087) - No encryption")
                        Text("3. For TLS: Test enrollment port (8446)")
                        Text("4. For TLS: Enter credentials and enroll")
                        Text("5. Test streaming connection")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                } header: {
                    Text("Setup Guide")
                } footer: {
                    Text("Note: Port 8446 is for enrollment/API, while 8089/8087 are for COT data streaming. Only TLS requires a certificate.")
                        .font(.caption2)
                }
            }
        }
        .navigationTitle("TAK Server")
        .onAppear {
            if settings.takPort == 0 {
                settings.takPort = settings.takProtocol.defaultPort
            }
        }
        .fileImporter(
            isPresented: $showingP12Picker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                handleP12Import(url: url)
            case .failure(let error):
                testResult = "✗ Failed to select file: \(error.localizedDescription)"
            }
        }
        .alert("P12 Password", isPresented: $showingP12PasswordPrompt) {
            SecureField("Password", text: $p12Password)
            Button("Cancel", role: .cancel) {
                p12Password = ""
                pendingP12Data = nil
            }
            Button("Import") {
                importP12()
            }
        } message: {
            Text("Enter the password for the P12 certificate file")
        }
    }
    
    // MARK: - P12 Import
    
    private func handleP12Import(url: URL) {
        do {
            guard url.startAccessingSecurityScopedResource() else {
                testResult = "✗ Cannot access file"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let data = try Data(contentsOf: url)
            pendingP12Data = data
            showingP12PasswordPrompt = true
            
        } catch {
            testResult = "✗ Failed to read file: \(error.localizedDescription)"
        }
    }
    
    private func importP12() {
        guard let data = pendingP12Data else { return }
        
        Task {
            do {
                try enrollmentManager.importP12Certificate(data: data, password: p12Password)
                await MainActor.run {
                    testResult = "✓ Certificate imported successfully!"
                    p12Password = ""
                    pendingP12Data = nil
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ Import failed: \(error.localizedDescription)"
                    p12Password = ""
                    pendingP12Data = nil
                }
            }
        }
    }
    
    // MARK: - Enrollment
    
    private func testEnrollmentEndpoint() {
        Task {
            do {
                testResult = "Testing enrollment endpoint..."
                
                let urlString = "https://\(settings.takHost):8446/Marti/api/tls"
                guard let url = URL(string: urlString) else {
                    await MainActor.run {
                        testResult = "✗ Invalid URL: \(urlString)"
                    }
                    return
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                
                let config = URLSessionConfiguration.ephemeral
                let session = URLSession(configuration: config, delegate: TrustAllDelegate(), delegateQueue: nil)
                
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse {
                    await MainActor.run {
                        if httpResponse.statusCode == 200 {
                            testResult = "✓ Enrollment port is accessible! Received \(data.count) bytes"
                        } else {
                            testResult = "⚠️ Endpoint responded with status \(httpResponse.statusCode)"
                        }
                    }
                }
                
            } catch let urlError as URLError {
                await MainActor.run {
                    switch urlError.code {
                    case .timedOut:
                        testResult = "✗ Connection timed out. Port 8446 may be blocked or server is not running."
                    case .cannotFindHost:
                        testResult = "✗ Cannot find host '\(settings.takHost)'. Check the hostname."
                    case .cannotConnectToHost:
                        testResult = "✗ Cannot connect to host. Server may be down or port is wrong."
                    case .secureConnectionFailed:
                        testResult = "✗ SSL/TLS handshake failed. Check if port 8446 is the enrollment port."
                    default:
                        testResult = "✗ Network error: \(urlError.localizedDescription)"
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func performAPIEnrollment() {
        isEnrolling = true
        
        Task {
            do {
                // Save credentials for future renewal
                var config = settings.takConfiguration
                config.enrollmentUsername = enrollmentUsername
                config.enrollmentPassword = enrollmentPassword
                settings.updateTAKConfiguration(config)
                
                // Perform API-based enrollment (TAK Server 4.0+ style)
                try await enrollmentManager.enrollWithAPI(
                    host: settings.takHost,
                    username: enrollmentUsername,
                    password: enrollmentPassword,
                    callsign: enrollmentUsername  // Use username as callsign by default
                )
                
                await MainActor.run {
                    isEnrolling = false
                    testResult = "✓ Certificate enrolled via API successfully!"
                }
                
            } catch {
                await MainActor.run {
                    isEnrolling = false
                    testResult = "✗ API enrollment failed: \(error.localizedDescription)\nTry 'CSR (Legacy)' or manual import."
                }
            }
        }
    }
    
    private func performEnrollment() {
        isEnrolling = true
        
        Task {
            do {
                // Save credentials for future renewal
                var config = settings.takConfiguration
                config.enrollmentUsername = enrollmentUsername
                config.enrollmentPassword = enrollmentPassword
                settings.updateTAKConfiguration(config)
                
                // Perform enrollment
                try await enrollmentManager.enroll(
                    host: settings.takHost,
                    username: enrollmentUsername,
                    password: enrollmentPassword
                )
                
                await MainActor.run {
                    isEnrolling = false
                    testResult = "✓ Certificate enrolled successfully!"
                }
                
            } catch {
                await MainActor.run {
                    isEnrolling = false
                    testResult = "✗ Enrollment failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Connection Test
    
    private func testConnection() {
        isTesting = true
        testResult = nil
        
        Task {
            let config = settings.takConfiguration
            
            // Create a client and attempt to connect
            let client = TAKClient(configuration: config, enrollmentManager: enrollmentManager)
            
            await MainActor.run {
                client.connect()
            }
            
            // Wait for connection to establish (or fail)
            for i in 1...10 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                
                let state = await MainActor.run { client.state }
                
                switch state {
                case .connected:
                    await MainActor.run {
                        switch config.protocol {
                        case .udp:
                            testResult = "✓ UDP socket ready! Server: \(config.host):\(config.port)\n\nNote: UDP is a fire-and-forget protocol. Check console logs when drones are detected to verify data is being sent."
                        case .tcp:
                            testResult = "✓ TCP connection established! Server is reachable at \(config.host):\(config.port)"
                        case .tls:
                            testResult = "✓ TLS handshake successful! Secure connection established to \(config.host):\(config.port)"
                        }
                        isTesting = false
                    }
                    
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await MainActor.run {
                        client.disconnect()
                    }
                    return
                    
                case .failed(let error):
                    await MainActor.run {
                        testResult = "✗ Connection failed: \(error.localizedDescription)"
                        isTesting = false
                    }
                    await MainActor.run {
                        client.disconnect()
                    }
                    return
                    
                case .connecting:
                    if i % 3 == 0 {
                        await MainActor.run {
                            testResult = "Connecting... (\(i)s)"
                        }
                    }
                    
                default:
                    break
                }
                
                if i == 10 {
                    await MainActor.run {
                        testResult = "⏳ Connection timeout - server may not be running on \(config.host):\(config.port)\n\nCheck:\n• Server is running\n• Host and port are correct\n• Network connectivity"
                        isTesting = false
                        client.disconnect()
                    }
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

// MARK: - URL Session Delegate for Testing
/// Delegate that trusts all certificates (for testing connectivity only)
private class TrustAllDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}



