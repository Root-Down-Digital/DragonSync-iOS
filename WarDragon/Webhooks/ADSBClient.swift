//
//  ADSBClient.swift
//  WarDragon
//
//  ADS-B client for fetching aircraft data from readsb HTTP API
//

import Foundation
import Combine
import os.log

/// ADS-B client connection state
enum ADSBConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case failed(Error)
    
    static func == (lhs: ADSBConnectionState, rhs: ADSBConnectionState) -> Bool {
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

/// Configuration for ADS-B client
struct ADSBConfiguration: Codable, Equatable {
    var enabled: Bool
    var readsbURL: String  // e.g., "http://192.168.1.100:8080"
    var pollInterval: TimeInterval  // Seconds between polls
    var maxDistance: Double?  // Maximum distance in km (optional filter)
    var minAltitude: Double?  // Minimum altitude in feet (optional filter)
    var maxAltitude: Double?  // Maximum altitude in feet (optional filter)
    
    init(
        enabled: Bool = false,
        readsbURL: String = "http://localhost:8080",
        pollInterval: TimeInterval = 2.0,
        maxDistance: Double? = nil,
        minAltitude: Double? = nil,
        maxAltitude: Double? = nil
    ) {
        self.enabled = enabled
        self.readsbURL = readsbURL
        self.pollInterval = pollInterval
        self.maxDistance = maxDistance
        self.minAltitude = minAltitude
        self.maxAltitude = maxAltitude
    }
    
    var isValid: Bool {
        !readsbURL.isEmpty && pollInterval > 0
    }
    
    /// Full URL for aircraft data endpoint
    var aircraftDataURL: URL? {
        // readsb provides data at /data/aircraft.json
        // First, ensure the base URL is valid
        guard let baseURL = URL(string: readsbURL) else {
            print("DEBUG: Failed to create URL from readsbURL: '\(readsbURL)'")
            return nil
        }
        
        // Append the path to the base URL
        let finalURL = baseURL.appendingPathComponent("data").appendingPathComponent("aircraft.json")
        return finalURL
    }
}

/// ADS-B client for polling readsb HTTP API
@MainActor
class ADSBClient: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var state: ADSBConnectionState = .disconnected
    @Published private(set) var aircraft: [Aircraft] = []
    @Published private(set) var totalMessages: Int = 0
    @Published private(set) var lastUpdate: Date?
    @Published private(set) var lastError: Error?
    
    // MARK: - Private Properties
    
    private var configuration: ADSBConfiguration
    private let logger = Logger(subsystem: "com.wardragon", category: "ADSBClient")
    
    private var pollTimer: Timer?
    private var session: URLSession
    private var consecutiveErrors: Int = 0
    private let maxConsecutiveErrors = 10
    private var isInitialConnection = true
    
    // MARK: - Initialization
    
    init(configuration: ADSBConfiguration) {
        self.configuration = configuration
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 15.0
        self.session = URLSession(configuration: config)
    }
    
    deinit {
        // Must invalidate timer synchronously to prevent retain cycle
        pollTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Start polling readsb API
    func start() {
        guard configuration.isValid else {
            logger.error("Invalid ADS-B configuration")
            state = .failed(ADSBError.invalidConfiguration)
            return
        }
        
        // Stop any existing timer first to prevent duplicates
        if let existingTimer = pollTimer {
            existingTimer.invalidate()
            pollTimer = nil
        }
        
        // Don't start if already connecting or connected
        guard state == .disconnected || state == .failed(ADSBError.connectionFailed) else {
            logger.debug("Already started (state: \(String(describing: self.state)))")
            return
        }
        
        state = .connecting
        consecutiveErrors = 0
        isInitialConnection = true  // Reset flag when starting
        
        logger.info("Starting ADS-B polling (interval: \(self.configuration.pollInterval)s)")
        
        // Poll immediately first
        Task {
            await poll()
            
            // Then start the repeating timer on main thread
            await MainActor.run {
                self.pollTimer = Timer.scheduledTimer(
                    withTimeInterval: self.configuration.pollInterval,
                    repeats: true
                ) { [weak self] _ in
                    Task { @MainActor in
                        await self?.poll()
                    }
                }
                
                // Ensure timer runs even during UI updates
                if let timer = self.pollTimer {
                    RunLoop.main.add(timer, forMode: .common)
                }
                
                self.logger.info("ADS-B polling timer started successfully")
            }
        }
    }
    
    /// Stop polling
    func stop() {
        // Invalidate timer on main thread to prevent retain cycles
        if let timer = pollTimer {
            timer.invalidate()
            pollTimer = nil
        }
        
        // Clear state
        state = .disconnected
        consecutiveErrors = 0
        
        logger.info("Stopped ADS-B polling")
    }
    
    /// Manually poll once
    func poll() async {
        guard let url = configuration.aircraftDataURL else {
            logger.error("Invalid readsb URL")
            state = .failed(ADSBError.invalidURL)
            return
        }
        
        do {
            let (data, response) = try await session.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ADSBError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                throw ADSBError.httpError(httpResponse.statusCode)
            }
            
            let decoder = JSONDecoder()
            let readsbResponse = try decoder.decode(ReadsbResponse.self, from: data)
            
            // Filter aircraft based on configuration
            var filteredAircraft = readsbResponse.aircraft.filter { $0.coordinate != nil }
            
            if configuration.maxDistance != nil {
                // TODO: Add distance filtering if user location available
            }
            
            if let minAlt = configuration.minAltitude {
                filteredAircraft = filteredAircraft.filter { ($0.altitude ?? 0) >= minAlt }
            }
            
            if let maxAlt = configuration.maxAltitude {
                filteredAircraft = filteredAircraft.filter { ($0.altitude ?? 0) <= maxAlt }
            }
            
            // Update state
            aircraft = filteredAircraft
            totalMessages = readsbResponse.messages
            lastUpdate = Date()
            state = .connected
            consecutiveErrors = 0
            isInitialConnection = false  // Successfully connected
            
            logger.debug("Polled \(filteredAircraft.count) aircraft (\(readsbResponse.messages) messages)")
            
        } catch {
            consecutiveErrors += 1
            lastError = error
            
            // Check if it's a connection error (server not running)
            let isConnectionError = (error as NSError).code == -1004 || (error as NSError).code == -1003 || (error as NSError).code == -1001
            
            if isConnectionError {
                // During initial connection, be less noisy with warnings
                if isInitialConnection && consecutiveErrors <= 3 {
                    logger.debug("Initial connection attempt \(self.consecutiveErrors): server not ready yet")
                } else {
                    logger.warning("Connection failed (attempt \(self.consecutiveErrors)/\(self.maxConsecutiveErrors)): readsb server may not be running at \(url.absoluteString)")
                }
            } else {
                logger.error("Poll failed (\(self.consecutiveErrors)/\(self.maxConsecutiveErrors)): \(error.localizedDescription)")
            }
            
            // Only stop after max consecutive errors
            if consecutiveErrors >= maxConsecutiveErrors {
                state = .failed(error)
                stop()
                logger.error("Max consecutive errors reached, stopped polling. Check that readsb is running at: \(url.absoluteString)")
            } else if consecutiveErrors == 1 {
                // On first error, update state but keep polling
                state = .failed(error)
            }
        }
    }
    
    /// Update configuration
    func updateConfiguration(_ config: ADSBConfiguration) {
        let wasRunning = state == .connected || state == .connecting
        
        if wasRunning {
            stop()
        }
        
        configuration = config
        
        if wasRunning && config.enabled {
            start()
        }
    }
    
    /// Get aircraft by ICAO hex
    func aircraft(forHex hex: String) -> Aircraft? {
        aircraft.first { $0.hex.lowercased() == hex.lowercased() }
    }
    
    /// Get aircraft count by category
    func aircraftCount(category: String? = nil) -> Int {
        if let category = category {
            return aircraft.filter { $0.category == category }.count
        }
        return aircraft.count
    }
}

// MARK: - Error Types

enum ADSBError: LocalizedError {
    case invalidConfiguration
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case connectionFailed
    case decodingFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Invalid ADS-B configuration"
        case .invalidURL:
            return "Invalid readsb URL"
        case .invalidResponse:
            return "Invalid response from readsb"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .connectionFailed:
            return "Connection to readsb failed"
        case .decodingFailed:
            return "Failed to decode readsb data"
        }
    }
}
