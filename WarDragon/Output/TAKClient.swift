//
//  TAKClient.swift
//  WarDragon
//
//  TAK Server client using Network.framework
//

import Foundation
import Network
import Combine
import os.log

/// TAK client connection state
enum TAKConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(Error)
    
    static func == (lhs: TAKConnectionState, rhs: TAKConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected):
            return true
        case (.failed(let lhsError), .failed(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        default:
            return false
        }
    }
}

/// TAK client for sending CoT messages to TAK servers
@MainActor
class TAKClient: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var state: TAKConnectionState = .disconnected
    @Published private(set) var messagesSent: Int = 0
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private var connection: NWConnection?
    private var reconnectTask: Task<Void, Never>?
    private let configuration: TAKConfiguration
    private let logger = Logger(subsystem: "com.wardragon", category: "TAKClient")
    
    // Reconnection parameters
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = -1  // Infinite retries like Python
    private let baseReconnectDelay: TimeInterval = 2.0
    private let maxReconnectDelay: TimeInterval = 60.0
    
    // Message queue for when disconnected
    private var messageQueue: [Data] = []
    private let maxQueueSize = 100
    
    // MARK: - Initialization
    
    init(configuration: TAKConfiguration) {
        self.configuration = configuration
    }
    
    deinit {
        Task { @MainActor [connection, reconnectTask] in
            reconnectTask?.cancel()
            connection?.cancel()
        }
    }
    
    // MARK: - Public Methods
    
    /// Start connection and automatic reconnection loop
    func connect() {
        guard configuration.isValid else {
            logger.error("Invalid TAK configuration")
            state = .failed(TAKError.invalidConfiguration)
            return
        }
        
        guard state == .disconnected || state == .failed(TAKError.connectionFailed) else {
            logger.debug("Already connecting or connected")
            return
        }
        
        state = .connecting
        reconnectAttempts = 0
        
        // Start background reconnection loop
        reconnectTask?.cancel()
        reconnectTask = Task {
            await runConnectLoop()
        }
    }
    
    /// Disconnect from TAK server
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        
        connection?.cancel()
        connection = nil
        
        state = .disconnected
        logger.info("Disconnected from TAK server")
    }
    
    /// Send CoT XML to TAK server
    func send(_ cotXML: Data) async throws {
        // Queue message if not connected
        guard case .connected = state else {
            if messageQueue.count < maxQueueSize {
                messageQueue.append(cotXML)
                logger.debug("Queued message (queue size: \(self.messageQueue.count))")
            } else {
                logger.warning("Message queue full, dropping message")
            }
            throw TAKError.notConnected
        }
        
        guard let connection = connection else {
            throw TAKError.notConnected
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: cotXML, completion: .contentProcessed { error in
                if let error = error {
                    self.logger.error("Send failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                } else {
                    Task { @MainActor in
                        self.messagesSent += 1
                    }
                    continuation.resume()
                }
            })
        }
        
        logger.debug("Sent CoT message (\(cotXML.count) bytes)")
    }
    
    /// Send CoT XML string
    func send(_ cotXML: String) async throws {
        guard let data = cotXML.data(using: .utf8) else {
            throw TAKError.invalidData
        }
        try await send(data)
    }
    
    // MARK: - Private Methods
    
    /// Background reconnection loop (matches Python behavior)
    private func runConnectLoop() async {
        while !Task.isCancelled {
            do {
                try await establishConnection()
                
                // Wait for connection to fail before retrying
                await withTaskCancellationHandler {
                    try? await Task.sleep(nanoseconds: UInt64.max)
                } onCancel: {
                    // Cancelled by disconnect() or deinit
                }
                
            } catch {
                let delay = calculateReconnectDelay()
                logger.warning("Connection failed: \(error.localizedDescription). Retrying in \(delay)s...")
                
                await MainActor.run {
                    self.state = .failed(error)
                    self.lastError = error
                }
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    // Task cancelled during sleep
                    break
                }
                
                reconnectAttempts += 1
            }
        }
    }
    
    /// Establish connection to TAK server
    private func establishConnection() async throws {
        await MainActor.run {
            self.state = .connecting
        }
        
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(configuration.host),
            port: NWEndpoint.Port(integerLiteral: UInt16(configuration.port))
        )
        
        let parameters: NWParameters
        
        switch configuration.protocol {
        case .tcp:
            parameters = .tcp
            
        case .tls:
            guard let tlsOptions = try? createTLSOptions() else {
                throw TAKError.tlsSetupFailed
            }
            parameters = NWParameters(tls: tlsOptions, tcp: .init())
            
        case .udp:
            parameters = .udp
        }
        
        let newConnection = NWConnection(to: endpoint, using: parameters)
        
        // Set up state handler
        newConnection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                await self?.handleStateChange(newState)
            }
        }
        
        // Start connection
        newConnection.start(queue: .global(qos: .userInitiated))
        
        await MainActor.run {
            self.connection = newConnection
        }
        
        // Wait for connection to establish or fail
        try await waitForConnection()
        
        // Flush queued messages
        await flushMessageQueue()
    }
    
    /// Create TLS options from configuration
    private func createTLSOptions() throws -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        
        // Configure minimum/maximum TLS versions
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        
        // Load client certificate - try PEM first, then P12
        if let pemCert = configuration.pemCertificateData,
           let pemKey = configuration.pemKeyData {
            // PEM certificate provided
            do {
                let identity = try loadPEMIdentity(
                    certificate: pemCert,
                    privateKey: pemKey,
                    password: configuration.pemKeyPassword
                )
                sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
                logger.info("✓ PEM client certificate loaded successfully")
            } catch {
                logger.error("Failed to load PEM client certificate: \(error.localizedDescription)")
                throw error
            }
        } else if let p12Data = configuration.p12CertificateData {
            // P12 certificate provided
            do {
                let identity = try loadP12Identity(data: p12Data, password: configuration.p12Password)
                sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
                logger.info("✓ P12 client certificate loaded successfully")
            } catch {
                logger.error("Failed to load P12 client certificate: \(error.localizedDescription)")
                throw error
            }
        } else {
            logger.warning("No client certificate provided - connection may fail if server requires mutual TLS")
        }
        
        // Skip verification (UNSAFE - for testing only)
        if configuration.skipVerification {
            logger.warning("⚠️ TLS verification disabled - UNSAFE for production!")
            
            // Disable peer verification completely
            sec_protocol_options_set_peer_authentication_required(options.securityProtocolOptions, false)
            
            // Also set a verify block that always succeeds
            sec_protocol_options_set_verify_block(
                options.securityProtocolOptions,
                { _, _, completion in
                    completion(true)
                },
                .global(qos: .userInitiated)
            )
        }
        
        return options
    }
    
    /// Load P12 identity from data
    private func loadP12Identity(data: Data, password: String?) throws -> sec_identity_t {
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password ?? ""
        ]
        
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        
        // Provide detailed error messages
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
                errorMessage = "P12 import failed with status: \(status)"
            }
            logger.error("Certificate import error: \(errorMessage)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: errorMessage
            ])
        }
        
        guard let itemsArray = items as? [[String: Any]],
              let firstItem = itemsArray.first else {
            throw TAKError.certificateLoadFailed
        }
        
        guard let secIdentity = firstItem[kSecImportItemIdentity as String] else {
            throw TAKError.certificateLoadFailed
        }
        
        // Log certificate details for debugging
        var certRef: SecCertificate?
        SecIdentityCopyCertificate(secIdentity as! SecIdentity, &certRef)
        if let cert = certRef {
            if let summary = SecCertificateCopySubjectSummary(cert) as String? {
                logger.info("P12 Certificate subject: \(summary)")
            }
        }
        
        guard let identity = sec_identity_create(secIdentity as! SecIdentity) else {
            throw TAKError.certificateLoadFailed
        }
        
        return identity
    }
    
    /// Load PEM identity from certificate and private key data
    private func loadPEMIdentity(certificate: Data, privateKey: Data, password: String?) throws -> sec_identity_t {
        // Parse PEM certificate
        guard let certString = String(data: certificate, encoding: .utf8) else {
            throw TAKError.certificateLoadFailed
        }
        
        // Extract certificate data between BEGIN/END markers
        let certPattern = "-----BEGIN CERTIFICATE-----(.+?)-----END CERTIFICATE-----"
        guard let certRegex = try? NSRegularExpression(pattern: certPattern, options: .dotMatchesLineSeparators),
              let certMatch = certRegex.firstMatch(in: certString, range: NSRange(certString.startIndex..., in: certString)),
              let certRange = Range(certMatch.range(at: 1), in: certString) else {
            logger.error("Failed to parse PEM certificate - no valid certificate found")
            throw TAKError.certificateLoadFailed
        }
        
        let certBase64 = certString[certRange]
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard let certData = Data(base64Encoded: certBase64) else {
            logger.error("Failed to decode PEM certificate base64")
            throw TAKError.certificateLoadFailed
        }
        
        guard let secCert = SecCertificateCreateWithData(nil, certData as CFData) else {
            logger.error("Failed to create SecCertificate from PEM data")
            throw TAKError.certificateLoadFailed
        }
        
        // Parse PEM private key
        guard let keyString = String(data: privateKey, encoding: .utf8) else {
            throw TAKError.certificateLoadFailed
        }
        
        // Support different key formats
        var keyPattern = "-----BEGIN PRIVATE KEY-----(.+?)-----END PRIVATE KEY-----"
        var keyRegex = try? NSRegularExpression(pattern: keyPattern, options: .dotMatchesLineSeparators)
        var keyMatch = keyRegex?.firstMatch(in: keyString, range: NSRange(keyString.startIndex..., in: keyString))
        
        // Try RSA PRIVATE KEY format
        if keyMatch == nil {
            keyPattern = "-----BEGIN RSA PRIVATE KEY-----(.+?)-----END RSA PRIVATE KEY-----"
            keyRegex = try? NSRegularExpression(pattern: keyPattern, options: .dotMatchesLineSeparators)
            keyMatch = keyRegex?.firstMatch(in: keyString, range: NSRange(keyString.startIndex..., in: keyString))
        }
        
        // Try EC PRIVATE KEY format
        if keyMatch == nil {
            keyPattern = "-----BEGIN EC PRIVATE KEY-----(.+?)-----END EC PRIVATE KEY-----"
            keyRegex = try? NSRegularExpression(pattern: keyPattern, options: .dotMatchesLineSeparators)
            keyMatch = keyRegex?.firstMatch(in: keyString, range: NSRange(keyString.startIndex..., in: keyString))
        }
        
        guard let match = keyMatch,
              let keyRange = Range(match.range(at: 1), in: keyString) else {
            logger.error("Failed to parse PEM private key - no valid key found")
            throw TAKError.certificateLoadFailed
        }
        
        let keyBase64 = keyString[keyRange]
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")
        
        guard let keyData = Data(base64Encoded: keyBase64) else {
            logger.error("Failed to decode PEM private key base64")
            throw TAKError.certificateLoadFailed
        }
        
        // Import private key into keychain temporarily
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(keyData as CFData, keyAttributes as CFDictionary, &error) else {
            if let err = error?.takeRetainedValue() {
                logger.error("Failed to create SecKey: \(err)")
            }
            throw TAKError.certificateLoadFailed
        }
        
        // Create identity from certificate and private key
        let tempTag = "com.wardragon.tak.temp.\(UUID().uuidString)"
        
        // Add certificate to keychain
        let certAddQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: secCert,
            kSecAttrLabel as String: tempTag
        ]
        
        _ = SecItemAdd(certAddQuery as CFDictionary, nil)
        
        // Add key to keychain
        let keyAddQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: secKey,
            kSecAttrApplicationTag as String: tempTag.data(using: .utf8)!
        ]
        
        _ = SecItemAdd(keyAddQuery as CFDictionary, nil)
        
        // Create identity
        let identityQuery: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnRef as String: true,
            kSecAttrLabel as String: tempTag
        ]
        
        var identityRef: AnyObject?
        let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identityRef)
        
        // Clean up temporary items
        SecItemDelete(certAddQuery as CFDictionary)
        SecItemDelete(keyAddQuery as CFDictionary)
        
        guard identityStatus == errSecSuccess,
              let identityItem = identityRef else {
            logger.error("Failed to create identity from PEM cert and key (status: \(identityStatus))")
            throw TAKError.certificateLoadFailed
        }
        
        // Log certificate details
        if let summary = SecCertificateCopySubjectSummary(secCert) as String? {
            logger.info("PEM Certificate subject: \(summary)")
        }
        
        guard let identity = sec_identity_create(identityItem as! SecIdentity) else {
            logger.error("Failed to create sec_identity_t from SecIdentity")
            throw TAKError.certificateLoadFailed
        }
        
        return identity
    }
    
    /// Wait for connection to establish
    private func waitForConnection() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            
            Task {
                // Wait up to 10 seconds for connection
                for _ in 0..<100 {
                    if Task.isCancelled { break }
                    
                    let currentState = await MainActor.run { self.state }
                    
                    switch currentState {
                    case .connected:
                        if !resumed {
                            resumed = true
                            continuation.resume()
                        }
                        return
                        
                    case .failed(let error):
                        if !resumed {
                            resumed = true
                            continuation.resume(throwing: error)
                        }
                        return
                        
                    default:
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    }
                }
                
                if !resumed {
                    resumed = true
                    continuation.resume(throwing: TAKError.connectionTimeout)
                }
            }
        }
    }
    
    /// Handle connection state changes
    private func handleStateChange(_ newState: NWConnection.State) async {
        switch newState {
        case .ready:
            logger.info("Connected to TAK server \(self.configuration.host):\(self.configuration.port)")
            await MainActor.run {
                self.state = .connected
                self.reconnectAttempts = 0
            }
            
        case .failed(let error):
            logger.error("Connection failed: \(error.localizedDescription)")
            await MainActor.run {
                self.state = .failed(error)
                self.lastError = error
                self.connection = nil
            }
            
        case .waiting(let error):
            logger.warning("Connection waiting: \(error.localizedDescription)")
            
        case .cancelled:
            logger.info("Connection cancelled")
            await MainActor.run {
                self.state = .disconnected
                self.connection = nil
            }
            
        default:
            break
        }
    }
    
    /// Flush queued messages after connection
    private func flushMessageQueue() async {
        let queue = await MainActor.run {
            let current = self.messageQueue
            self.messageQueue.removeAll()
            return current
        }
        
        guard !queue.isEmpty else { return }
        
        logger.info("Flushing \(queue.count) queued messages")
        
        for message in queue {
            do {
                try await send(message)
            } catch {
                logger.error("Failed to flush queued message: \(error.localizedDescription)")
            }
        }
    }
    
    /// Calculate exponential backoff delay
    private func calculateReconnectDelay() -> TimeInterval {
        let delay = min(
            baseReconnectDelay * pow(2.0, Double(reconnectAttempts)),
            maxReconnectDelay
        )
        return delay
    }
}

// MARK: - Error Types

enum TAKError: LocalizedError {
    case invalidConfiguration
    case notConnected
    case invalidData
    case tlsSetupFailed
    case certificateLoadFailed
    case connectionFailed
    case connectionTimeout
    
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid TAK server configuration"
        case .notConnected:
            return "Not connected to TAK server"
        case .invalidData:
            return "Invalid data format"
        case .tlsSetupFailed:
            return "Failed to set up TLS connection"
        case .certificateLoadFailed:
            return "Failed to load P12 certificate"
        case .connectionFailed:
            return "Connection to TAK server failed"
        case .connectionTimeout:
            return "Connection timeout"
        }
    }
}
