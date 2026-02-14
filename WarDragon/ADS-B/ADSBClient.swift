//
//  ADSBClient.swift
//  WarDragon
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
    var flightPathRetentionMinutes: Double  // How long to keep flight path history
    
    init(
        enabled: Bool = false,
        readsbURL: String = "http://localhost:8080",
        dataPath: String = "/data/aircraft.json",
        pollInterval: TimeInterval = 2.0,
        maxDistance: Double? = nil,
        minAltitude: Double? = nil,
        maxAltitude: Double? = nil,
        maxAircraftCount: Int = 25,
        flightPathRetentionMinutes: Double = 30.0
    ) {
        self.enabled = enabled
        self.readsbURL = readsbURL
        self.dataPath = dataPath
        self.pollInterval = pollInterval
        self.maxDistance = maxDistance
        self.minAltitude = minAltitude
        self.maxAltitude = maxAltitude
        self.maxAircraftCount = maxAircraftCount
        self.flightPathRetentionMinutes = flightPathRetentionMinutes
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
        
        // Ensure data path ends with .json
        guard dataPath.hasSuffix(".json") else {
            print("DEBUG: Data path must end with .json: '\(dataPath)'")
            return nil
        }
        
        // Clean up the data path
        let cleanPath = dataPath.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove trailing slash from base URL if present
        if urlString.hasSuffix("/") {
            urlString.removeLast()
        }
        
        // Ensure path starts with / if it doesn't already
        let finalPath = cleanPath.hasPrefix("/") ? cleanPath : "/" + cleanPath
        
        // Combine base URL and path directly as strings
        let fullURLString = urlString + finalPath
        
        guard let finalURL = URL(string: fullURLString) else {
            print("DEBUG: Failed to create URL from: '\(fullURLString)'")
            return nil
        }
        
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
    
    // Aircraft history tracking (persists beyond current visibility)
    private var aircraftHistory: [String: Aircraft] = [:]  // Keyed by hex
    
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
    
    // Race condition protection
    private var isPolling = false  // Prevents concurrent poll operations
    private let maxAircraftHistorySize = 500  // Limit history size to prevent unbounded growth
    
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
        
        // Clear aircraft history to release memory
        aircraftHistory.removeAll()
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
        stopTimer()
        
        // Don't start if already connecting or connected
        guard state == .disconnected || state == .failed(ADSBError.connectionFailed) else {
            logger.debug("Already started (state: \(String(describing: self.state)))")
            return
        }
        
        state = .connecting
        consecutiveErrors = 0
        isInitialConnection = true  // Reset flag when starting
        isPolling = false  // Reset polling flag
        
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
    
    /// Stop timer safely
    private func stopTimer() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
    
    func stop() {
        stopTimer()
        
        saveAircraftToStorage()
        
        // Don't clear aircraft/history when stopping - let them persist
        // Only clear the timer and reset state
        // aircraftHistory.removeAll()
        // aircraft.removeAll()
        
        state = .disconnected
        consecutiveErrors = 0
        isPolling = false  // Reset polling flag
        
        logger.info("Stopped ADS-B polling (aircraft data preserved)")
    }
    
    /// Clear all aircraft data (call this separately when needed)
    func clearAircraft() {
        aircraftHistory.removeAll()
        aircraft.removeAll()
        logger.info("Cleared all aircraft data")
    }
    
    private func saveAircraftToStorage() {
        guard !aircraft.isEmpty else { return }
        
        let aircraftToSave = Array(self.aircraft.prefix(100))
        
        Task.detached {
            for aircraft in aircraftToSave {
                let aircraftId = "aircraft-\(aircraft.hex)"
                guard let coord = aircraft.coordinate else { continue }
                
                await MainActor.run {
                    let stored = self.fetchOrCreateAircraftEncounter(id: aircraftId, aircraft: aircraft)
                    
                    let flightPoint = StoredFlightPoint(
                        latitude: coord.latitude,
                        longitude: coord.longitude,
                        altitude: aircraft.altitude ?? 0,
                        timestamp: aircraft.lastSeen.timeIntervalSince1970,
                        homeLatitude: nil,
                        homeLongitude: nil,
                        isProximityPoint: false,
                        proximityRssi: nil,
                        proximityRadius: nil
                    )
                    
                    stored.lastSeen = aircraft.lastSeen
                    
                    if let lastPoint = stored.flightPoints.last {
                        let loc1 = CLLocation(latitude: lastPoint.latitude, longitude: lastPoint.longitude)
                        let loc2 = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                        if loc1.distance(from: loc2) > 10 {
                            stored.flightPoints.append(flightPoint)
                        }
                    } else {
                        stored.flightPoints.append(flightPoint)
                    }
                    
                    if stored.flightPoints.count > 1000 {
                        let toRemove = Array(stored.flightPoints.prefix(500))
                        guard let context = SwiftDataStorageManager.shared.modelContext else { return }
                        toRemove.forEach { context.delete($0) }
                        stored.flightPoints.removeFirst(500)
                    }
                    
                    stored.metadata["callsign"] = aircraft.flight ?? ""
                    stored.metadata["squawk"] = aircraft.squawk ?? ""
                    stored.metadata["category"] = aircraft.category ?? ""
                    stored.metadata["source"] = "ADS-B"
                    
                    if let rssi = aircraft.rssi, rssi != 0 {
                        let signature = StoredSignature(
                            timestamp: aircraft.lastSeen.timeIntervalSince1970,
                            rssi: rssi,
                            speed: aircraft.groundSpeed ?? 0,
                            height: aircraft.altitude ?? 0,
                            mac: nil
                        )
                        stored.signatures.append(signature)
                        if stored.signatures.count > 500 {
                            let toRemove = Array(stored.signatures.prefix(250))
                            guard let context = SwiftDataStorageManager.shared.modelContext else { return }
                            toRemove.forEach { context.delete($0) }
                            stored.signatures.removeFirst(250)
                        }
                    }
                    
                    stored.updateCachedStats()
                }
            }
            
            await MainActor.run {
                SwiftDataStorageManager.shared.forceSave()
            }
        }
    }
    
    private func fetchOrCreateAircraftEncounter(id: String, aircraft: Aircraft) -> StoredDroneEncounter {
        if let existing = SwiftDataStorageManager.shared.fetchFullEncounter(id: id) {
            return existing
        }
        
        let metadata: [String: String] = [
            "callsign": aircraft.flight ?? "",
            "squawk": aircraft.squawk ?? "",
            "category": aircraft.category ?? "",
            "source": "ADS-B"
        ]
        
        let new = StoredDroneEncounter(
            id: id,
            firstSeen: aircraft.lastSeen,
            lastSeen: aircraft.lastSeen,
            customName: "",
            trustStatusRaw: "unknown",
            metadata: metadata,
            macAddresses: []
        )
        
        guard let context = SwiftDataStorageManager.shared.modelContext else {
            return new
        }
        
        context.insert(new)
        return new
    }
    
    private func calculateDistanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let location2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return location1.distance(from: location2)
    }
    
    func poll() async {
        guard !isPolling else { return }
        
        isPolling = true
        defer { isPolling = false }
        
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
            
            let readsbResponse = try JSONDecoder().decode(ReadsbResponse.self, from: data)
            
            var updatedAircraft: [Aircraft] = []
            for var aircraft in readsbResponse.aircraft {
                if var existing = aircraftHistory[aircraft.hex] {
                    existing.lat = aircraft.lat
                    existing.lon = aircraft.lon
                    existing.altitude = aircraft.altitude
                    existing.track = aircraft.track
                    existing.groundSpeed = aircraft.groundSpeed
                    existing.verticalRate = aircraft.verticalRate
                    existing.flight = aircraft.flight
                    existing.squawk = aircraft.squawk
                    existing.rssi = aircraft.rssi
                    existing.lastSeen = Date()
                    existing.recordPosition()
                    existing.cleanupOldHistory(retentionMinutes: configuration.flightPathRetentionMinutes)
                    aircraftHistory[aircraft.hex] = existing
                    updatedAircraft.append(existing)
                } else {
                    aircraft.recordPosition()
                    aircraftHistory[aircraft.hex] = aircraft
                    updatedAircraft.append(aircraft)
                }
            }
            
            let cutoffDate = Date().addingTimeInterval(-configuration.flightPathRetentionMinutes * 60)
            aircraftHistory = aircraftHistory.filter { $0.value.lastSeen > cutoffDate }
            
            if aircraftHistory.count > self.maxAircraftHistorySize {
                let sorted = aircraftHistory.sorted { $0.value.lastSeen > $1.value.lastSeen }
                aircraftHistory = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(self.maxAircraftHistorySize)))
            }

            var filtered = Array(aircraftHistory.values).filter { $0.coordinate != nil }
            
            if let maxDistance = configuration.maxDistance, maxDistance > 0,
               let userLocation = LocationManager.shared.userLocation {
                filtered = filtered.filter {
                    guard let coord = $0.coordinate else { return false }
                    let dist = userLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) / 1000.0
                    return dist <= maxDistance
                }
            }
            
            if let minAlt = configuration.minAltitude {
                filtered = filtered.filter { ($0.altitude ?? 0) >= minAlt }
            }
            
            if let maxAlt = configuration.maxAltitude {
                filtered = filtered.filter { ($0.altitude ?? 0) <= maxAlt }
            }
            
            if let userLocation = LocationManager.shared.userLocation, configuration.maxAircraftCount > 0, filtered.count > configuration.maxAircraftCount {
                let withDist = filtered.compactMap { aircraft -> (aircraft: Aircraft, distance: Double)? in
                    guard let coord = aircraft.coordinate else { return nil }
                    let dist = userLocation.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
                    return (aircraft, dist)
                }
                filtered = withDist.sorted { $0.distance < $1.distance }.prefix(configuration.maxAircraftCount).map { $0.aircraft }
            }
            
            aircraft = filtered
            totalMessages = readsbResponse.messages
            lastUpdate = Date()
            state = .connected
            consecutiveErrors = 0
            isInitialConnection = false
            
        } catch {
            consecutiveErrors += 1
            lastError = error
            
            let nsError = error as NSError
            
            if nsError.code == -1022 {
                logger.error("App Transport Security blocking connection")
                state = .failed(ADSBError.appTransportSecurity)
                stop()
                return
            } else if nsError.code == -1004 || nsError.code == -1003 || nsError.code == -1001 {
                if aircraftHistory.count > self.maxAircraftHistorySize / 2 {
                    let sorted = aircraftHistory.sorted { $0.value.lastSeen > $1.value.lastSeen }
                    aircraftHistory = Dictionary(uniqueKeysWithValues: Array(sorted.prefix(self.maxAircraftHistorySize / 2)))
                }
            }
            
            if consecutiveErrors >= maxConsecutiveErrors {
                state = .failed(error)
                stop()
                onConnectionFailed?()
            } else if consecutiveErrors == 1 {
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
    case appTransportSecurity
    
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
        case .appTransportSecurity:
            return "App Transport Security blocked the connection. Add NSAllowsLocalNetworking to Info.plist"
        }
    }
}
