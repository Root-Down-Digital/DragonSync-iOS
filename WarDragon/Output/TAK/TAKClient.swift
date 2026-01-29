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

@MainActor
class TAKClient: ObservableObject {
    @Published private(set) var state: TAKConnectionState = .disconnected
    @Published private(set) var messagesSent: Int = 0
    @Published private(set) var lastError: Error?
    
    private var connection: NWConnection?
    private var reconnectTask: Task<Void, Never>?
    private let configuration: TAKConfiguration
    private let logger = Logger(subsystem: "com.wardragon", category: "TAKClient")
    private let enrollmentManager: TAKEnrollmentManager?
    
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = -1
    private let baseReconnectDelay: TimeInterval = 2.0
    private let maxReconnectDelay: TimeInterval = 60.0
    
    private var messageQueue: [Data] = []
    private let maxQueueSize = 100
    
    // Certificate mode tracking removed - enrollment is now the only option for TLS
    
    init(configuration: TAKConfiguration, enrollmentManager: TAKEnrollmentManager? = nil) {
        self.configuration = configuration
        self.enrollmentManager = enrollmentManager
    }
    
    deinit {
        let conn = connection
        Task { @MainActor in
            conn?.cancel()
        }
    }
    
    func connect() {
        guard configuration.enabled else {
            logger.info("TAK Server is disabled")
            return
        }
        
        if configuration.protocol == .udp {
            guard !configuration.host.isEmpty && configuration.port > 0 && configuration.port < 65536 else {
                logger.error("Invalid UDP configuration")
                state = .failed(TAKError.invalidConfiguration)
                return
            }
        } else {
            guard configuration.isValid else {
                logger.error("Invalid TAK configuration")
                state = .failed(TAKError.invalidConfiguration)
                return
            }
        }
        
        guard !(state == .connecting || state == .connected) else {
            logger.debug("Already connecting or connected")
            return
        }
        
        state = .connecting
        reconnectAttempts = 0
        
        reconnectTask?.cancel()
        reconnectTask = Task {
            await runConnectLoop()
        }
    }
    
    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        connection?.cancel()
        connection = nil
        state = .disconnected
        logger.info("Disconnected from TAK server")
    }
    
    func send(_ cotXML: Data) async throws {
        let canSend: Bool
        if configuration.protocol == .udp {
            // UDP can send anytime the socket exists
            canSend = connection != nil
        } else {
            // TCP/TLS require full connection
            canSend = state == .connected
        }
        
        guard canSend else {
            if self.messageQueue.count < self.maxQueueSize {
                self.messageQueue.append(cotXML)
                logger.debug("Queued message (queue size: \(self.messageQueue.count))")
            } else {
                logger.warning("Message queue full, dropping message")
            }
            throw TAKError.notConnected
        }
        
        guard let connection = connection else {
            throw TAKError.notConnected
        }
        
        // Frame the message according to TAK protocol
        let framedData: Data
        switch configuration.protocol {
        case .udp:
            // UDP typically doesn't need framing but should be protobuf for modern TAK
            // For now, send raw XML (legacy support)
            framedData = cotXML
            
        case .tcp, .tls:
            // TCP/TLS requires length-prefixed framing
            // TAK protocol: 32-bit big-endian length prefix + data
            framedData = frameTCPMessage(cotXML)
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: framedData, completion: .contentProcessed { [weak self] error in
                if let error = error {
                    if self?.configuration.protocol == .udp {
                        // UDP is fire-and-forget, but log real errors
                        if case .posix(let code) = error {
                            switch code {
                            case .ECONNREFUSED:
                                // Server not listening - this is a real problem
                                self?.logger.warning("UDP destination unreachable - server may not be running")
                            case .ENETUNREACH, .EHOSTUNREACH:
                                // Network routing issues
                                self?.logger.error("Network unreachable: \(error.localizedDescription)")
                            default:
                                self?.logger.debug("UDP send warning: \(error.localizedDescription)")
                            }
                        }
                        // Still count as sent for UDP (fire-and-forget protocol)
                        Task { @MainActor [weak self] in
                            self?.messagesSent += 1
                        }
                        continuation.resume()
                    } else {
                        self?.logger.error("Send failed: \(error.localizedDescription, privacy: .public)")
                        continuation.resume(throwing: error)
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.messagesSent += 1
                    }
                    continuation.resume()
                }
            })
        }
        
        logger.debug("Sent CoT message (\(framedData.count) bytes, \(cotXML.count) payload)")
    }
    
    /// Frame a message for TCP/TLS transmission using TAK protocol
    /// TAK protocol uses 32-bit big-endian length prefix
    private func frameTCPMessage(_ payload: Data) -> Data {
        var framedData = Data()
        
        // Write 32-bit big-endian length
        let length = UInt32(payload.count)
        withUnsafeBytes(of: length.bigEndian) { bytes in
            framedData.append(contentsOf: bytes)
        }
        
        // Append payload
        framedData.append(payload)
        
        return framedData
    }
    
    func send(_ cotXML: String) async throws {
        guard let data = cotXML.data(using: .utf8) else {
            throw TAKError.invalidData
        }
        try await send(data)
    }
    
    private func runConnectLoop() async {
        while !Task.isCancelled {
            do {
                try await establishConnection()
                
                await withTaskCancellationHandler {
                    try? await Task.sleep(nanoseconds: UInt64.max)
                } onCancel: {
                }
                
            } catch {
                let delay = calculateReconnectDelay()
                logger.warning("Connection failed: \(error.localizedDescription, privacy: .public). Retrying in \(delay, privacy: .public)s...")
                
                await MainActor.run {
                    self.state = .failed(error)
                    self.lastError = error
                }
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    break
                }
                
                reconnectAttempts += 1
            }
        }
        
        await MainActor.run {
            if case .connecting = self.state {
                self.state = .disconnected
            }
        }
    }
    
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
            let tlsOptions = try createTLSOptions()
            parameters = NWParameters(tls: tlsOptions, tcp: .init())
        case .udp:
            parameters = .udp
        }
        
        let newConnection = NWConnection(to: endpoint, using: parameters)
        newConnection.stateUpdateHandler = { [weak self] newState in
            Task { @MainActor in
                await self?.handleStateChange(newState)
            }
        }
        
        newConnection.start(queue: .global(qos: .userInitiated))
        
        await MainActor.run {
            self.connection = newConnection
        }
        
        try await waitForConnection()
        await flushMessageQueue()
        
        // TODO: Setup receive handler for incoming CoT messages
        // TCP/TLS incoming messages will also be framed with 32-bit length prefix
        // UDP messages may not be framed (depends on TAK Server config)
        // startReceiving()
    }
    
    private func createTLSOptions() throws -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        
        logger.info("Using enrollment certificate for TLS")
        
        // TLS requires enrolled certificate
        guard let enrollmentManager = enrollmentManager else {
            logger.error("Enrollment manager not provided")
            throw TAKError.tlsSetupFailed
        }
        
        guard enrollmentManager.enrollmentState.isValid else {
            logger.error("Certificate not enrolled or expired")
            throw TAKError.certificateLoadFailed
        }
        
        try setupClientIdentity(options: options, enrollmentManager: enrollmentManager)
        
        if configuration.skipVerification {
            logger.warning("TLS verification disabled - UNSAFE for production!")
            sec_protocol_options_set_peer_authentication_required(
                options.securityProtocolOptions,
                false
            )
        }
        
        return options
    }
    
    private func setupClientIdentity(
        options: NWProtocolTLS.Options,
        enrollmentManager: TAKEnrollmentManager
    ) throws {
        do {
            guard let identity = try enrollmentManager.getIdentity() else {
                throw TAKError.certificateLoadFailed
            }
            
            guard let secIdentity = sec_identity_create(identity) else {
                throw TAKError.certificateLoadFailed
            }
            
            sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
            logger.info("✓ Client identity configured for TLS")
            
        } catch {
            logger.error("Failed to setup enrolled certificate: \(error, privacy: .public)")
            throw TAKError.certificateLoadFailed
        }
    }
    
    // P12 certificate support removed - use TAKEnrollmentManager instead

    
    private func waitForConnection() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var resumed = false
            
            Task {
                for _ in 0..<100 {
                    if Task.isCancelled {
                        if !resumed {
                            resumed = true
                            continuation.resume(throwing: CancellationError())
                        }
                        return
                    }
                    
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
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
                
                if !resumed {
                    resumed = true
                    continuation.resume(throwing: TAKError.connectionTimeout)
                }
            }
        }
    }
    
    private func handleStateChange(_ newState: NWConnection.State) async {
        switch newState {
        case .ready:
            logger.info("Connected to TAK server \(self.configuration.host, privacy: .public):\(self.configuration.port, privacy: .public)")
            await MainActor.run {
                self.state = .connected
                self.reconnectAttempts = 0
            }
            
        case .failed(let error):
            logger.error("Connection failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.state = .failed(error)
                self.lastError = error
                self.connection = nil
            }
            
        case .waiting(let error):
            if configuration.protocol == .udp {
                logger.info("UDP socket ready")
                await MainActor.run {
                    self.state = .connected
                    self.reconnectAttempts = 0
                }
            } else {
                logger.debug("Connection waiting: \(error.localizedDescription, privacy: .public)")
            }
            
        case .cancelled:
            logger.info("Connection cancelled")
            await MainActor.run {
                self.state = .disconnected
                self.connection = nil
            }
            
        case .preparing:
            logger.debug("Connection preparing...")
            
        case .setup:
            logger.debug("Connection setup...")
            
        @unknown default:
            logger.warning("Unknown connection state")
        }
    }
    
    private func flushMessageQueue() async {
        let queue = await MainActor.run {
            let current = self.messageQueue
            self.messageQueue.removeAll()
            return current
        }
        
        guard !queue.isEmpty else { return }
        logger.info("Flushing \(queue.count, privacy: .public) queued messages")
        
        for message in queue {
            do {
                try await send(message)
            } catch {
                logger.error("Failed to flush queued message: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    private func calculateReconnectDelay() -> TimeInterval {
        let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        return delay
    }
}

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
            return "Failed to load certificate"
        case .connectionFailed:
            return "Connection to TAK server failed"
        case .connectionTimeout:
            return "Connection timeout"
        }
    }
}
