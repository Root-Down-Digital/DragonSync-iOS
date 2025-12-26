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
        Task { @MainActor [connection] in
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
        
        // Load P12 certificate if provided
        if let p12Data = configuration.p12CertificateData {
            let identity = try loadP12Identity(data: p12Data, password: configuration.p12Password)
            if let unwrappedIdentity = identity {
                sec_protocol_options_set_local_identity(options.securityProtocolOptions, unwrappedIdentity)
            }
        }
        
        // Skip verification (UNSAFE - for testing only)
        if configuration.skipVerification {
            logger.warning("⚠️ TLS verification disabled - UNSAFE for production!")
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
    private func loadP12Identity(data: Data, password: String?) throws -> sec_identity_t? {
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: password ?? ""
        ]
        
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        
        guard status == errSecSuccess,
              let itemsArray = items as? [[String: Any]],
              let firstItem = itemsArray.first,
              let identity = firstItem[kSecImportItemIdentity as String] else {
            throw TAKError.certificateLoadFailed
        }
        
        return sec_identity_create(identity as! SecIdentity)
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
