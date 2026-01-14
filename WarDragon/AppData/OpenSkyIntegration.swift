//
//  OpenSkyIntegration.swift
//  Complete OpenSky Network Integration
//
//  Created on January 14, 2026.
//
//

import Foundation
import Security
import SwiftData
import SwiftUI
import MapKit
import CoreLocation

// MARK: - SwiftData Models

@Model
final class OpenSkySettings {
    /// Unique identifier (singleton pattern)
    @Attribute(.unique) var id: String = "default"
    
    /// Whether the OpenSky service is enabled
    var isEnabled: Bool = false
    
    /// Whether to use authentication
    var useAuthentication: Bool = false
    
    /// Username for OpenSky API (stored here, password in Keychain)
    var username: String?
    
    /// Whether automatic polling is enabled
    var autoPollingEnabled: Bool = false
    
    /// Polling interval in seconds
    var pollingInterval: Double = 10.0
    
    /// Whether to use bounding box filtering
    var useBoundingBox: Bool = false
    
    /// Bounding box coordinates
    var boundingBoxMinLat: Double?
    var boundingBoxMinLon: Double?
    var boundingBoxMaxLat: Double?
    var boundingBoxMaxLon: Double?
    
    /// Selected preset bounding box
    var selectedPreset: String?
    
    /// Last successful fetch timestamp
    var lastFetchDate: Date?
    
    /// Number of aircraft in last fetch (raw API response)
    var lastAircraftCount: Int = 0
    
    /// Number of aircraft actually displayed after filtering
    var lastDisplayedCount: Int = 0
    
    /// Whether to show only airborne aircraft
    var showOnlyAirborne: Bool = false
    
    /// Minimum altitude filter (feet)
    var minimumAltitude: Double?
    
    /// Maximum distance filter (kilometers)
    var maxDistanceKm: Double = 10.0
    
    /// Maximum number of aircraft to display
    var maxAircraftCount: Int = 50
    
    /// Whether to show notifications for new aircraft
    var notificationsEnabled: Bool = false
    
    init() {}
    
    /// Current bounding box if enabled
    var currentBoundingBox: BoundingBox? {
        guard useBoundingBox,
              let minLat = boundingBoxMinLat,
              let minLon = boundingBoxMinLon,
              let maxLat = boundingBoxMaxLat,
              let maxLon = boundingBoxMaxLon else {
            return nil
        }
        
        return BoundingBox(
            minLatitude: minLat,
            minLongitude: minLon,
            maxLatitude: maxLat,
            maxLongitude: maxLon
        )
    }
    
    /// Set bounding box from struct
    func setBoundingBox(_ box: BoundingBox?) {
        if let box = box {
            useBoundingBox = true
            boundingBoxMinLat = box.minLatitude
            boundingBoxMinLon = box.minLongitude
            boundingBoxMaxLat = box.maxLatitude
            boundingBoxMaxLon = box.maxLongitude
        } else {
            useBoundingBox = false
            boundingBoxMinLat = nil
            boundingBoxMinLon = nil
            boundingBoxMaxLat = nil
            boundingBoxMaxLon = nil
        }
    }
    
    /// Set preset bounding box
    func setPreset(_ preset: BoundingBoxPreset) {
        selectedPreset = preset.rawValue
        setBoundingBox(preset.boundingBox)
    }
}

@Model
final class CachedAircraft {
    /// ICAO24 unique identifier
    @Attribute(.unique) var icao24: String
    
    /// Callsign
    var callsign: String?
    
    /// Origin country
    var originCountry: String?
    
    /// Coordinates
    var longitude: Double?
    var latitude: Double?
    
    /// Altitude in meters
    var baroAltitude: Double?
    
    /// On ground status
    var onGround: Bool = false
    
    /// Velocity in m/s
    var velocity: Double?
    
    /// Heading in degrees
    var trueTrack: Double?
    
    /// Vertical rate in m/s
    var verticalRate: Double?
    
    /// Last seen timestamp
    var lastSeen: Date
    
    /// First seen timestamp (for tracking new aircraft)
    var firstSeen: Date
    
    init(from aircraft: OpenSkyAircraft) {
        self.icao24 = aircraft.icao24
        self.callsign = aircraft.callsign
        self.originCountry = aircraft.originCountry
        self.longitude = aircraft.longitude
        self.latitude = aircraft.latitude
        self.baroAltitude = aircraft.baroAltitude
        self.onGround = aircraft.onGround
        self.velocity = aircraft.velocity
        self.trueTrack = aircraft.trueTrack
        self.verticalRate = aircraft.verticalRate
        self.lastSeen = Date()
        self.firstSeen = Date()
    }
    
    /// Update with new aircraft data
    func update(from aircraft: OpenSkyAircraft) {
        self.callsign = aircraft.callsign
        self.originCountry = aircraft.originCountry
        self.longitude = aircraft.longitude
        self.latitude = aircraft.latitude
        self.baroAltitude = aircraft.baroAltitude
        self.onGround = aircraft.onGround
        self.velocity = aircraft.velocity
        self.trueTrack = aircraft.trueTrack
        self.verticalRate = aircraft.verticalRate
        self.lastSeen = Date()
    }
}

// MARK: - Bounding Box Presets

enum BoundingBoxPreset: String, CaseIterable, Identifiable {
    case sanFrancisco = "San Francisco Bay Area"
    case newYork = "New York City"
    case london = "London"
    case losAngeles = "Los Angeles"
    case chicago = "Chicago"
    case tokyo = "Tokyo"
    case paris = "Paris"
    case sydney = "Sydney"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var boundingBox: BoundingBox? {
        switch self {
        case .sanFrancisco:
            return .sanFranciscoBayArea
        case .newYork:
            return .newYorkCity
        case .london:
            return .london
        case .losAngeles:
            return BoundingBox(minLatitude: 33.5, minLongitude: -118.5,
                             maxLatitude: 34.5, maxLongitude: -117.5)
        case .chicago:
            return BoundingBox(minLatitude: 41.5, minLongitude: -88.0,
                             maxLatitude: 42.5, maxLongitude: -87.0)
        case .tokyo:
            return BoundingBox(minLatitude: 35.0, minLongitude: 139.0,
                             maxLatitude: 36.0, maxLongitude: 140.0)
        case .paris:
            return BoundingBox(minLatitude: 48.5, minLongitude: 2.0,
                             maxLatitude: 49.0, maxLongitude: 2.7)
        case .sydney:
            return BoundingBox(minLatitude: -34.0, minLongitude: 150.5,
                             maxLatitude: -33.5, maxLongitude: 151.5)
        case .custom:
            return nil
        }
    }
}

// MARK: - Models for API

/// Represents the complete OpenSky API response
struct OpenSkyResponse: Codable {
    let time: Int
    let states: [[OpenSkyStateValue]]?
    
    /// Parsed aircraft states with properly typed fields
    var aircraft: [OpenSkyAircraft] {
        guard let states = states else { return [] }
        return states.compactMap { OpenSkyAircraft(from: $0) }
    }
}

/// Heterogeneous JSON value type for decoding the states array
enum OpenSkyStateValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .null
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
    
    var stringValue: String? {
        if case .string(let value) = self {
            return value.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }
    
    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .int(let value):
            return Double(value)
        default:
            return nil
        }
    }
    
    var boolValue: Bool? {
        if case .bool(let value) = self {
            return value
        }
        return nil
    }
}

/// Represents a single aircraft with parsed fields from OpenSky Network
struct OpenSkyAircraft: Identifiable {
    let icao24: String
    let callsign: String?
    let originCountry: String?
    let longitude: Double?
    let latitude: Double?
    let baroAltitude: Double? // meters
    let onGround: Bool
    let velocity: Double? // m/s
    let trueTrack: Double? // degrees
    let verticalRate: Double? // m/s
    
    var id: String { icao24 }
    
    /// Velocity in knots (nautical miles per hour)
    var velocityKnots: Double? {
        velocity.map { $0 * 1.94384 }
    }
    
    /// Altitude in feet
    var altitudeFeet: Double? {
        baroAltitude.map { $0 * 3.28084 }
    }
    
    /// Initialize from OpenSky state array
    init?(from state: [OpenSkyStateValue]) {
        guard state.count >= 17,
              let icao24 = state[0].stringValue else {
            return nil
        }
        
        self.icao24 = icao24
        self.callsign = state[1].stringValue
        self.originCountry = state[2].stringValue
        self.longitude = state[5].doubleValue
        self.latitude = state[6].doubleValue
        self.baroAltitude = state[7].doubleValue
        self.onGround = state[8].boolValue ?? false
        self.velocity = state[9].doubleValue
        self.trueTrack = state[10].doubleValue
        self.verticalRate = state[11].doubleValue
    }
}

/// Geographic bounding box for filtering aircraft
struct BoundingBox {
    let minLatitude: Double
    let minLongitude: Double
    let maxLatitude: Double
    let maxLongitude: Double
    
    /// Returns query parameters for the API request
    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "lamin", value: "\(minLatitude)"),
            URLQueryItem(name: "lomin", value: "\(minLongitude)"),
            URLQueryItem(name: "lamax", value: "\(maxLatitude)"),
            URLQueryItem(name: "lomax", value: "\(maxLongitude)")
        ]
    }
    
    /// San Francisco Bay Area
    static let sanFranciscoBayArea = BoundingBox(
        minLatitude: 37.0,
        minLongitude: -123.0,
        maxLatitude: 38.5,
        maxLongitude: -121.0
    )
    
    /// New York City area
    static let newYorkCity = BoundingBox(
        minLatitude: 40.0,
        minLongitude: -74.5,
        maxLatitude: 41.0,
        maxLongitude: -73.0
    )
    
    /// London area
    static let london = BoundingBox(
        minLatitude: 51.0,
        minLongitude: -0.5,
        maxLatitude: 52.0,
        maxLongitude: 0.5
    )
}

// MARK: - OpenSky Service Error

enum OpenSkyError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(statusCode: Int)
    case decodingError(Error)
    case rateLimitExceeded
    case unauthorized
    case keychainError(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .rateLimitExceeded:
            return "API rate limit exceeded. Consider authenticating for higher limits."
        case .unauthorized:
            return "Authentication failed. Check your credentials."
        case .keychainError(let status):
            return "Keychain error: \(status)"
        }
    }
}

// MARK: - Keychain Helper

actor KeychainHelper {
    static let shared = KeychainHelper()
    
    private let service = "com.opensky.credentials"
    private let usernameKey = "username"
    private let passwordKey = "password"
    
    private init() {}
    
    func saveCredentials(username: String, password: String) throws {
        try saveItem(key: usernameKey, value: username)
        try saveItem(key: passwordKey, value: password)
    }
    
    func retrieveCredentials() throws -> (username: String, password: String)? {
        guard let username = try retrieveItem(key: usernameKey),
              let password = try retrieveItem(key: passwordKey) else {
            return nil
        }
        return (username, password)
    }
    
    func deleteCredentials() throws {
        try deleteItem(key: usernameKey)
        try deleteItem(key: passwordKey)
    }
    
    private func saveItem(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw OpenSkyError.keychainError(errSecParam)
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw OpenSkyError.keychainError(status)
        }
    }
    
    private func retrieveItem(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status != errSecItemNotFound else {
            return nil
        }
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            throw OpenSkyError.keychainError(status)
        }
        
        return string
    }
    
    private func deleteItem(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw OpenSkyError.keychainError(status)
        }
    }
}

// MARK: - OpenSky Network Service

@MainActor
final class OpenSkyService: ObservableObject {
    static let shared = OpenSkyService()
    
    private let baseURL = "https://opensky-network.org/api/states/all"
    private let session: URLSession
    
    @Published private(set) var isAuthenticated = false
    @Published private(set) var currentAircraft: [OpenSkyAircraft] = []
    @Published private(set) var lastUpdateTime: Date?
    @Published private(set) var isEnabled = false
    @Published private(set) var isPolling = false
    
    let recommendedPollingInterval: TimeInterval = 10.0
    
    private var pollingTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    private var settings: OpenSkySettings?
    
    weak var cotViewModel: CoTViewModel?
    let locationManager = LocationManager.shared
    
    init(session: URLSession = .shared) {
        self.session = session
        
        Task {
            await checkAuthenticationStatus()
        }
    }
    
    func configure(with context: ModelContext) {
        self.modelContext = context
        loadSettings()
    }
    
    private func loadSettings() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<OpenSkySettings>()
        
        do {
            let results = try context.fetch(descriptor)
            
            if let existingSettings = results.first {
                self.settings = existingSettings
            } else {
                let newSettings = OpenSkySettings()
                context.insert(newSettings)
                try context.save()
                self.settings = newSettings
            }
            
            applySettings()
        } catch {
            print("Failed to load OpenSky settings: \(error)")
        }
    }
    
    private func applySettings() {
        guard let settings = settings else { return }
        
        isEnabled = settings.isEnabled
        
        if settings.isEnabled {
            locationManager.requestLocationPermission()
        }
        
        if settings.isEnabled && settings.autoPollingEnabled && !isPolling {
            startPollingFromSettings()
        } else if (!settings.isEnabled || !settings.autoPollingEnabled) && isPolling {
            stopPolling()
        }
    }
    
    private func startPollingFromSettings() {
        guard let settings = settings else { return }
        
        startPolling(
            interval: settings.pollingInterval,
            boundingBox: settings.currentBoundingBox
        )
    }
    
    func updateSettings(_ update: (OpenSkySettings) -> Void) {
        guard let settings = settings, let context = modelContext else { return }
        
        update(settings)
        
        do {
            try context.save()
            applySettings()
        } catch {
            print("Failed to save OpenSky settings: \(error)")
        }
    }
    
    func getSettings() -> OpenSkySettings? {
        return settings
    }
    
    private func updateAircraftCache(_ aircraft: [OpenSkyAircraft]) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<CachedAircraft>()
        guard let existing = try? context.fetch(descriptor) else { return }
        
        let existingDict = Dictionary(uniqueKeysWithValues: existing.map { ($0.icao24, $0) })
        let currentICAOs = Set(aircraft.map { $0.icao24 })
        
        for plane in aircraft {
            if let cached = existingDict[plane.icao24] {
                cached.update(from: plane)
            } else {
                let newCached = CachedAircraft(from: plane)
                context.insert(newCached)
            }
        }
        
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        for cached in existing where !currentICAOs.contains(cached.icao24) {
            if cached.lastSeen < fiveMinutesAgo {
                context.delete(cached)
            }
        }
        
        try? context.save()
    }
    
    func saveCredentials(username: String, password: String) async throws {
        try await KeychainHelper.shared.saveCredentials(username: username, password: password)
        isAuthenticated = true
    }
    
    func removeCredentials() async throws {
        try await KeychainHelper.shared.deleteCredentials()
        isAuthenticated = false
    }
    
    private func checkAuthenticationStatus() async {
        do {
            isAuthenticated = try await KeychainHelper.shared.retrieveCredentials() != nil
        } catch {
            isAuthenticated = false
        }
    }
    
    private func getCredentials() async throws -> (username: String, password: String)? {
        try await KeychainHelper.shared.retrieveCredentials()
    }
    
    func fetchAircraft(boundingBox: BoundingBox? = nil) async throws -> [OpenSkyAircraft] {
        guard var components = URLComponents(string: baseURL) else {
            throw OpenSkyError.invalidURL
        }
        
        if let boundingBox = boundingBox {
            components.queryItems = boundingBox.queryItems
        }
        
        guard let url = components.url else {
            throw OpenSkyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        
        if let credentials = try? await getCredentials() {
            let credentialString = "\(credentials.username):\(credentials.password)"
            if let credentialData = credentialString.data(using: .utf8) {
                let base64Credentials = credentialData.base64EncodedString()
                request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
            }
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenSkyError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw OpenSkyError.unauthorized
        case 429:
            throw OpenSkyError.rateLimitExceeded
        default:
            throw OpenSkyError.httpError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            let openSkyResponse = try decoder.decode(OpenSkyResponse.self, from: data)
            let aircraft = openSkyResponse.aircraft
            
            currentAircraft = aircraft
            lastUpdateTime = Date(timeIntervalSince1970: TimeInterval(openSkyResponse.time))
            
            updateAircraftCache(aircraft)
            
            if let settings = settings {
                settings.lastFetchDate = Date()
                settings.lastAircraftCount = aircraft.count // Raw count from API
                try? modelContext?.save()
            }
            
            return aircraft
        } catch {
            throw OpenSkyError.decodingError(error)
        }
    }
    
    func startPolling(interval: TimeInterval? = nil, boundingBox: BoundingBox? = nil) {
        stopPolling()
        
        let pollingInterval = interval ?? recommendedPollingInterval
        isPolling = true
        
        pollingTask = Task { @MainActor in
            while !Task.isCancelled {
                do {
                    if let userLocation = locationManager.userLocation {
                        // Use radius from settings (default 50km)
                        let radiusKm = settings?.maxDistanceKm ?? 10.0
                        let locationBasedBox = BoundingBox.fromLocation(userLocation.coordinate, radiusKm: radiusKm)
                        let aircraft = try await fetchAircraft(boundingBox: boundingBox ?? locationBasedBox)
                        
                        if let cotViewModel = cotViewModel {
                            var convertedAircraft = aircraft.compactMap { convertToAppAircraft($0) }
                            
                            let originalCount = convertedAircraft.count
                            
                            // Apply display filters
                            convertedAircraft = applyDisplayFilters(to: convertedAircraft)
                            
                            // Limit to closest N aircraft based on OpenSky settings
                            let maxCount = settings?.maxAircraftCount ?? 50
                            if convertedAircraft.count > maxCount {
                                // Sort by distance and take closest N
                                let aircraftWithDistance = convertedAircraft.compactMap { aircraft -> (aircraft: Aircraft, distance: Double)? in
                                    guard let coord = aircraft.coordinate else { return nil }
                                    let aircraftLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                                    let distance = userLocation.distance(from: aircraftLocation)
                                    return (aircraft, distance)
                                }
                                
                                convertedAircraft = aircraftWithDistance
                                    .sorted { $0.distance < $1.distance }
                                    .prefix(maxCount)
                                    .map { $0.aircraft }
                                
                                print("OpenSky: Filtered to \(convertedAircraft.count) aircraft (from \(originalCount), max: \(maxCount), radius: \(radiusKm)km)")
                            } else {
                                print("OpenSky: Showing \(convertedAircraft.count) aircraft (filtered from \(originalCount), under limit of \(maxCount), radius: \(radiusKm)km)")
                            }
                            
                            // Update displayed count
                            if let settings = settings {
                                settings.lastDisplayedCount = convertedAircraft.count
                                try? modelContext?.save()
                            }
                            
                            cotViewModel.updateOpenSkyAircraft(convertedAircraft)
                        }
                    } else {
                        _ = try await fetchAircraft(boundingBox: boundingBox)
                    }
                } catch {
                    print("OpenSky polling error: \(error.localizedDescription)")
                }
                
                try? await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
            }
        }
    }
    
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }
    
    func requestLocationAndFetch() async throws {
        locationManager.requestLocationPermission()
        
        guard locationManager.locationPermissionStatus == .authorizedWhenInUse || 
              locationManager.locationPermissionStatus == .authorizedAlways else {
            throw OpenSkyError.networkError(NSError(domain: "OpenSky", code: -1, userInfo: [NSLocalizedDescriptionKey: "Location permission required"]))
        }
        
        guard let userLocation = locationManager.userLocation else {
            throw OpenSkyError.networkError(NSError(domain: "OpenSky", code: -2, userInfo: [NSLocalizedDescriptionKey: "Location not available"]))
        }
        
        // Use radius from settings (default 50km)
        let radiusKm = settings?.maxDistanceKm ?? 10.0
        let boundingBox = BoundingBox.fromLocation(userLocation.coordinate, radiusKm: radiusKm)
        
        let aircraft = try await fetchAircraft(boundingBox: boundingBox)
        
        if let cotViewModel = cotViewModel {
            var convertedAircraft = aircraft.compactMap { convertToAppAircraft($0) }
            
            let originalCount = convertedAircraft.count
            
            // Apply display filters
            convertedAircraft = applyDisplayFilters(to: convertedAircraft)
            
            // Limit to closest N aircraft based on OpenSky settings
            let maxCount = settings?.maxAircraftCount ?? 50
            if convertedAircraft.count > maxCount {
                // Sort by distance and take closest N
                let aircraftWithDistance = convertedAircraft.compactMap { aircraft -> (aircraft: Aircraft, distance: Double)? in
                    guard let coord = aircraft.coordinate else { return nil }
                    let aircraftLocation = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
                    let distance = userLocation.distance(from: aircraftLocation)
                    return (aircraft, distance)
                }
                
                convertedAircraft = aircraftWithDistance
                    .sorted { $0.distance < $1.distance }
                    .prefix(maxCount)
                    .map { $0.aircraft }
                
                print("OpenSky manual fetch: Filtered to \(convertedAircraft.count) aircraft (from \(originalCount), max: \(maxCount), radius: \(radiusKm)km)")
            } else {
                print("OpenSky manual fetch: Showing \(convertedAircraft.count) aircraft (filtered from \(originalCount), under limit of \(maxCount), radius: \(radiusKm)km)")
            }
            
            // Update displayed count
            if let settings = settings {
                settings.lastDisplayedCount = convertedAircraft.count
                try? modelContext?.save()
            }
            
            cotViewModel.updateOpenSkyAircraft(convertedAircraft)
        }
    }
    
    private func convertToAppAircraft(_ openSkyAircraft: OpenSkyAircraft) -> Aircraft? {
        guard let lat = openSkyAircraft.latitude,
              let lon = openSkyAircraft.longitude else {
            return nil
        }
        
        let altitudeFeet = openSkyAircraft.altitudeFeet
        let groundSpeedKnots = openSkyAircraft.velocityKnots
        
        return Aircraft(
            hex: openSkyAircraft.icao24,
            lat: lat,
            lon: lon,
            altitude: altitudeFeet,
            track: openSkyAircraft.trueTrack,
            groundSpeed: groundSpeedKnots,
            flight: openSkyAircraft.callsign
        )
    }
    
    /// Apply display filters based on OpenSky settings
    private func applyDisplayFilters(to aircraft: [Aircraft]) -> [Aircraft] {
        guard let settings = settings else { return aircraft }
        
        var filtered = aircraft
        
        // Filter: Show only airborne
        if settings.showOnlyAirborne {
            filtered = filtered.filter { aircraft in
                // Aircraft is airborne if it has an altitude > 0 (on ground typically reports 0 or nil)
                if let altitude = aircraft.altitude {
                    return altitude > 0
                }
                return false
            }
        }
        
        // Filter: Minimum altitude
        if let minAltitude = settings.minimumAltitude {
            filtered = filtered.filter { aircraft in
                if let altitude = aircraft.altitude {
                    return altitude >= minAltitude
                }
                return false
            }
        }
        
        return filtered
    }
}

extension BoundingBox {
    static func fromLocation(_ coordinate: CLLocationCoordinate2D, radiusKm: Double) -> BoundingBox {
        let latDelta = radiusKm / 111.0
        let lonDelta = radiusKm / (111.0 * cos(coordinate.latitude * .pi / 180.0))
        
        return BoundingBox(
            minLatitude: coordinate.latitude - latDelta,
            minLongitude: coordinate.longitude - lonDelta,
            maxLatitude: coordinate.latitude + latDelta,
            maxLongitude: coordinate.longitude + lonDelta
        )
    }
}
// MARK: - Settings View

struct OpenSkySettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var service = OpenSkyService.shared
    
    @Query private var settingsQuery: [OpenSkySettings]
    
    @State private var showAuthSheet = false
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    
    private var settings: OpenSkySettings? {
        settingsQuery.first
    }
    
    private var locationPermissionText: String {
        switch service.locationManager.locationPermissionStatus {
        case .authorizedWhenInUse:
            return "Authorized"
        case .authorizedAlways:
            return "Authorized"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Set"
        @unknown default:
            return "Unknown"
        }
    }
    
    var body: some View {
        Form {
            // Enable/Disable Section
            Section {
                Toggle("Enable OpenSky Network", isOn: Binding(
                    get: { settings?.isEnabled ?? false },
                    set: { newValue in
                        service.updateSettings { $0.isEnabled = newValue }
                        if newValue {
                            service.locationManager.requestLocationPermission()
                        }
                    }
                ))
                
                if settings?.isEnabled == true {
                    HStack {
                        Image(systemName: service.isPolling ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                            .foregroundStyle(service.isPolling ? .green : .secondary)
                        
                        Text(service.isPolling ? "Active" : "Inactive")
                            .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        if let displayed = settings?.lastDisplayedCount {
                            Text("\(displayed) displayed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    if let fetched = settings?.lastAircraftCount, let displayed = settings?.lastDisplayedCount, fetched > displayed {
                        HStack {
                            Text("Last fetch")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(fetched) fetched → \(displayed) shown")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Service")
            } footer: {
                Text("Enable to receive real-time ADS-B aircraft data from OpenSky Network API")
            }
            
            if settings?.isEnabled == true {
                Section {
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(service.locationManager.locationPermissionStatus == .authorizedWhenInUse || service.locationManager.locationPermissionStatus == .authorizedAlways ? .green : .orange)
                        
                        Text("Location Permission")
                        
                        Spacer()
                        
                        Text(locationPermissionText)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    
                    if service.locationManager.locationPermissionStatus != .authorizedWhenInUse && service.locationManager.locationPermissionStatus != .authorizedAlways {
                        Button("Request Permission") {
                            service.locationManager.requestLocationPermission()
                        }
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Location is used to find aircraft near you. Search radius is configured in Display Filters below.")
                }
            }
            
            // Authentication
            if settings?.isEnabled == true {
                Section {
                    Toggle("Use Authentication", isOn: Binding(
                        get: { settings?.useAuthentication ?? false },
                        set: { newValue in
                            service.updateSettings { $0.useAuthentication = newValue }
                            if !newValue {
                                Task { try? await service.removeCredentials() }
                            }
                        }
                    ))
                    
                    if settings?.useAuthentication == true {
                        HStack {
                            Image(systemName: service.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(service.isAuthenticated ? .green : .orange)
                            
                            Text(service.isAuthenticated ? "Authenticated" : "Not Authenticated")
                            
                            Spacer()
                            
                            Button(service.isAuthenticated ? "Change" : "Setup") {
                                showAuthSheet = true
                            }
                        }
                    }
                } header: {
                    Text("Authentication")
                } footer: {
                    Text(settings?.useAuthentication == true ? "Authenticated: ~400 requests/day. Anonymous: ~100 requests/day" : "Optional - increases rate limits 4x")
                }
            }
            
            // Auto Polling
            if settings?.isEnabled == true {
                Section {
                    Toggle("Auto-Refresh", isOn: Binding(
                        get: { settings?.autoPollingEnabled ?? false },
                        set: { newValue in
                            service.updateSettings { $0.autoPollingEnabled = newValue }
                        }
                    ))
                    
                    if settings?.autoPollingEnabled == true {
                        Picker("Interval", selection: Binding(
                            get: { settings?.pollingInterval ?? 10.0 },
                            set: { newValue in
                                service.updateSettings { $0.pollingInterval = newValue }
                            }
                        )) {
                            Text("10 seconds").tag(10.0)
                            Text("15 seconds").tag(15.0)
                            Text("30 seconds").tag(30.0)
                            Text("1 minute").tag(60.0)
                        }
                    }
                } header: {
                    Text("Automatic Updates")
                } footer: {
                    Text("Automatically fetch aircraft data at regular intervals")
                }
            }
            
            // Display Filters
            if settings?.isEnabled == true {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Aircraft to Display")
                            Spacer()
                            Text("\(settings?.maxAircraftCount ?? 50)")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings?.maxAircraftCount ?? 50) },
                                set: { newValue in
                                    service.updateSettings { settings in
                                        settings.maxAircraftCount = Int(newValue)
                                    }
                                }
                            ),
                            in: 10...200,
                            step: 10
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Search Radius")
                            Spacer()
                            Text("\(Int(settings?.maxDistanceKm ?? 10)) km")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { settings?.maxDistanceKm ?? 10.0 },
                                set: { newValue in
                                    service.updateSettings { settings in
                                        settings.maxDistanceKm = newValue
                                    }
                                }
                            ),
                            in: 5...100,
                            step: 5
                        )
                    }
                    
                    Toggle("Show Only Airborne", isOn: Binding(
                        get: { settings?.showOnlyAirborne ?? false },
                        set: { newValue in
                            service.updateSettings { $0.showOnlyAirborne = newValue }
                        }
                    ))
                    
                    Toggle("Minimum Altitude Filter", isOn: Binding(
                        get: { settings?.minimumAltitude != nil },
                        set: { newValue in
                            service.updateSettings { settings in
                                settings.minimumAltitude = newValue ? 5000 : nil
                            }
                        }
                    ))
                    
                    if settings?.minimumAltitude != nil {
                        Picker("Minimum Altitude", selection: Binding(
                            get: { settings?.minimumAltitude ?? 5000 },
                            set: { newValue in
                                service.updateSettings { settings in
                                    settings.minimumAltitude = newValue
                                }
                            }
                        )) {
                            Text("5,000 ft").tag(5000.0)
                            Text("10,000 ft").tag(10000.0)
                            Text("20,000 ft").tag(20000.0)
                            Text("30,000 ft").tag(30000.0)
                        }
                        .pickerStyle(.menu)
                    }
                } header: {
                    Text("Display Filters")
                } footer: {
                    Text("API fetches all aircraft within bounding box. Filters reduce what's shown.")
                }
            }
            
            // Manual Test
            if settings?.isEnabled == true {
                Section {
                    Button {
                        Task {
                            do {
                                try await service.requestLocationAndFetch()
                                if let count = service.currentAircraft.count as Int? {
                                    errorMessage = "✓ Found \(count) aircraft"
                                }
                            } catch {
                                errorMessage = "✗ \(error.localizedDescription)"
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Test Fetch")
                        }
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(error.hasPrefix("✓") ? .green : .red)
                    }
                }
            }
            
            // Info
            Section {
                Link(destination: URL(string: "https://opensky-network.org")!) {
                    HStack {
                        Text("OpenSky Network")
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(.caption)
                    }
                }
                
                HStack {
                    Text("Current Rate")
                    Spacer()
                    Text(service.isAuthenticated ? "~400/day" : "~100/day")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Information")
            }
        }
        .navigationTitle("OpenSky Network")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAuthSheet) {
            authSheet
        }
    }
    
    private var authSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Register free at opensky-network.org")
                }
            }
            .navigationTitle("Credentials")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showAuthSheet = false
                        username = ""
                        password = ""
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            do {
                                try await service.saveCredentials(username: username, password: password)
                                service.updateSettings { $0.username = username }
                                showAuthSheet = false
                                username = ""
                                password = ""
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(username.isEmpty || password.isEmpty)
                }
            }
        }
    }
}

// MARK: - Aircraft List View

struct OpenSkyAircraftListView: View {
    @StateObject private var service = OpenSkyService.shared
    @Query private var settingsQuery: [OpenSkySettings]
    
    @State private var searchText = ""
    
    private var settings: OpenSkySettings? {
        settingsQuery.first
    }
    
    private var filteredAircraft: [OpenSkyAircraft] {
        guard searchText.isEmpty else {
            return service.currentAircraft.filter { aircraft in
                aircraft.callsign?.localizedCaseInsensitiveContains(searchText) == true ||
                aircraft.icao24.localizedCaseInsensitiveContains(searchText) ||
                aircraft.originCountry?.localizedCaseInsensitiveContains(searchText) == true
            }
        }
        return service.currentAircraft
    }
    
    var body: some View {
        Group {
            if settings?.isEnabled != true {
                ContentUnavailableView {
                    Label("OpenSky Disabled", systemImage: "airplane.departure")
                } description: {
                    Text("Enable OpenSky Network in Settings")
                } actions: {
                    NavigationLink("Open Settings") {
                        OpenSkySettingsView()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if filteredAircraft.isEmpty {
                ContentUnavailableView {
                    Label("No Aircraft", systemImage: "airplane.departure")
                } description: {
                    Text(searchText.isEmpty ? "Waiting for aircraft data..." : "No aircraft match '\(searchText)'")
                } actions: {
                    if !service.isPolling {
                        Button("Refresh") {
                            Task {
                                try? await service.fetchAircraft()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List {
                    ForEach(filteredAircraft) { aircraft in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(aircraft.callsign ?? "Unknown")
                                        .font(.headline)
                                    Text(aircraft.icao24.uppercased())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                Spacer()
                                
                                Image(systemName: aircraft.onGround ? "airplane.arrival" : "airplane.departure")
                                    .foregroundStyle(aircraft.onGround ? .orange : .green)
                            }
                            
                            HStack(spacing: 16) {
                                if let alt = aircraft.altitudeFeet {
                                    Label("\(Int(alt)) ft", systemImage: "arrow.up")
                                        .font(.caption)
                                }
                                
                                if let speed = aircraft.velocityKnots {
                                    Label("\(Int(speed)) kts", systemImage: "speedometer")
                                        .font(.caption)
                                }
                                
                                if let country = aircraft.originCountry {
                                    Text(country)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .refreshable {
                    _ = try? await service.fetchAircraft()
                }
            }
        }
        .navigationTitle("Aircraft (\(filteredAircraft.count))")
        .searchable(text: $searchText, prompt: "Search callsign, ICAO24, or country")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        Task { try? await service.fetchAircraft() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(service.isPolling)
                    
                    NavigationLink {
                        OpenSkySettingsView()
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task {
            if !service.isPolling && settings?.isEnabled == true {
                _ = try? await service.fetchAircraft()
            }
        }
    }
}

