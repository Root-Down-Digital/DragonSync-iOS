//
//  ADSBClient.swift
//  WarDragon
//
//  ADS-B client for fetching aircraft data from readsb HTTP API
//

import Foundation
import Combine
import CoreLocation
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
    var readsbURL: String
    var dataPath: String
    var pollInterval: TimeInterval  // Seconds between polls
    var maxDistance: Double?  // Maximum distance in km (optional filter)
    var minAltitude: Double?  // Minimum altitude in feet (optional filter)
    var maxAltitude: Double?  // Maximum altitude in feet (optional filter)
    var maxAircraftCount: Int  // Maximum number of aircraft to display (sorted by distance)
    
    init(
        enabled: Bool = false,
        readsbURL: String = "http://localhost:8080",
        dataPath: String = "/data/aircraft.json",
        pollInterval: TimeInterval = 2.0,
        maxDistance: Double? = nil,
        minAltitude: Double? = nil,
        maxAltitude: Double? = nil,
        maxAircraftCount: Int = 25
    ) {
        self.enabled = enabled
        self.readsbURL = readsbURL
        self.dataPath = dataPath
        self.pollInterval = pollInterval
        self.maxDistance = maxDistance
        self.minAltitude = minAltitude
        self.maxAltitude = maxAltitude
        self.maxAircraftCount = maxAircraftCount
    }
    
    var isValid: Bool {
        !readsbURL.isEmpty && pollInterval > 0 && dataPath.hasSuffix(".json")
    }
    
    /// Full URL for aircraft data endpoint
    var aircraftDataURL: URL? {
        // Clean up the base URL
        var urlString = readsbURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If no scheme is provided, prepend http://
        if !urlString.lowercased().hasPrefix("http://") && !urlString.lowercased().hasPrefix("https://") {
            urlString = "http://" + urlString
        }
        
        // First, ensure the base URL is valid
        guard let baseURL = URL(string: urlString) else {
            print("DEBUG: Failed to create URL from readsbURL: '\(urlString)'")
            return nil
        }
        
        // Ensure data path ends with .json
        guard dataPath.hasSuffix(".json") else {
            print("DEBUG: Data path must end with .json: '\(dataPath)'")
            return nil
        }
        
        // Combine base URL with the data path
        let finalURL = baseURL.appendingPathComponent(dataPath)
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
    
    // MARK: - Callbacks
    
    /// Called when the client gives up after max consecutive errors
    var onConnectionFailed: (() -> Void)?
    
    // MARK: - Private Properties
    
    private var configuration: ADSBConfiguration
    private let logger = Logger(subsystem: "com.wardragon", category: "ADSBClient")
    
    private var pollTimer: Timer?
    private var session: URLSession
    private var consecutiveErrors: Int = 0
    private let maxConsecutiveErrors = 30  // Increased from 10 to give more time for server to start
    private var isInitialConnection = true
    private let initialConnectionGracePeriod = 10  // More lenient during first 10 attempts
    
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
            
            // Distance filtering if enabled and user location is available
            if let maxDistance = configuration.maxDistance,
               maxDistance > 0,
               let userLocation = LocationManager.shared.userLocation {
                filteredAircraft = filteredAircraft.filter { aircraft in
                    guard let aircraftCoord = aircraft.coordinate else { return false }
                    let aircraftLocation = CLLocation(latitude: aircraftCoord.latitude, longitude: aircraftCoord.longitude)
                    let distance = userLocation.distance(from: aircraftLocation) / 1000.0 // Convert to km
                    return distance <= maxDistance
                }
            }
            
            if let minAlt = configuration.minAltitude {
                filteredAircraft = filteredAircraft.filter { ($0.altitude ?? 0) >= minAlt }
            }
            
            if let maxAlt = configuration.maxAltitude {
                filteredAircraft = filteredAircraft.filter { ($0.altitude ?? 0) <= maxAlt }
            }
            
            // Limit to closest N aircraft if user location is available
            if let userLocation = LocationManager.shared.userLocation, configuration.maxAircraftCount > 0 {
                // Calculate distance for each aircraft and sort by proximity
                let aircraftWithDistance = filteredAircraft.compactMap { aircraft -> (aircraft: Aircraft, distance: Double)? in
                    guard let coord = aircraft.coordinate else { return nil }
                    let aircraftLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let distance = userLocation.distance(from: aircraftLocation)
                    return (aircraft, distance)
                }
                
                // Sort by distance and take the closest N
                filteredAircraft = aircraftWithDistance
                    .sorted { $0.distance < $1.distance }
                    .prefix(configuration.maxAircraftCount)
                    .map { $0.aircraft }
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
                // During initial connection (first N attempts), be less noisy with warnings
                if isInitialConnection && consecutiveErrors <= initialConnectionGracePeriod {
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
                
                // Notify that we're giving up - this allows the parent to disable ADS-B in settings
                logger.error("Max consecutive errors reached, stopped polling. Check that readsb is running at: \(url.absoluteString)")
                logger.warning("ADS-B will be automatically disabled in settings to prevent further connection attempts")
                
                stop()
                
                // Call the failure callback to notify the view model
                onConnectionFailed?()
                
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
