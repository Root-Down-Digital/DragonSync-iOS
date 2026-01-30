//
//  AircraftModel.swift
//  WarDragon
//
//  Aircraft data model for ADS-B tracking via readsb
//

import Foundation
import CoreLocation

/// Aircraft track from ADS-B (via readsb)
struct Aircraft: Identifiable, Codable, Equatable {
    let hex: String  // ICAO 24-bit address (unique identifier)
    
    // Position
    var lat: Double?
    var lon: Double?
    var altitude: Double?  // Barometric altitude in feet
    var altitudeGeom: Double?  // Geometric (GNSS/INS) altitude in feet
    
    // Velocity
    var track: Double?  // True track over ground in degrees (0-359)
    var groundSpeed: Double?  // Ground speed in knots
    var verticalRate: Int?  // Vertical rate in feet/minute
    var ias: Int?  // Indicated air speed in knots
    var tas: Int?  // True air speed in knots
    
    // Aircraft info
    var flight: String?  // Callsign/flight number (with whitespace removed)
    var squawk: String?  // Mode A code (Squawk)
    var category: String?  // Emitter category
    
    // Signal quality
    var rssi: Double?  // Signal strength in dBFS
    var messages: Int?  // Number of Mode S messages received
    var seen: Double?  // Seconds since last message
    var seenPos: Double?  // Seconds since last position message
    
    // Accuracy
    var navQnh: Double?  // Altimeter setting (QNH/QFE) in millibars
    var navAltitudeMcp: Int?  // MCP/FCU selected altitude
    var navHeading: Double?  // Selected heading
    var nacp: Int?  // Navigation Accuracy Category - Position
    var nacv: Int?  // Navigation Accuracy Category - Velocity
    var sil: Int?  // Source Integrity Level
    var silType: String?  // SIL supplement
    
    // Metadata
    var emergency: String?  // Emergency/priority status
    var tisb: [String]?  // TIS-B flags
    var lastSeen: Date  // Local timestamp when received
    var source: AircraftSource = .adsb  // Track whether from ADS-B or OpenSky
    
    // Flight path history (not from readsb, tracked locally)
    var positionHistory: [PositionHistoryPoint] = []
    
    enum AircraftSource: String, Codable {
        case adsb = "ADS-B"
        case opensky = "OpenSky"
    }
    
    // MARK: - Position History
    
    /// A single point in the aircraft's position history
    struct PositionHistoryPoint: Codable, Equatable {
        let latitude: Double
        let longitude: Double
        let altitude: Double?  // in feet
        let timestamp: Date
        
        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    
    // MARK: - Computed Properties
    
    var id: String { hex }
    
    var coordinate: CLLocationCoordinate2D? {
        guard let lat = lat, let lon = lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    var callsign: String {
        flight?.trimmingCharacters(in: .whitespaces) ?? "N/A"
    }
    
    var displayName: String {
        if let flight = flight?.trimmingCharacters(in: .whitespaces), !flight.isEmpty {
            return flight
        }
        return hex.uppercased()
    }
    
    var altitudeFeet: Int? {
        guard let alt = altitude else { return nil }
        return Int(alt)
    }
    
    var altitudeMeters: Double? {
        guard let alt = altitude else { return nil }
        return alt * 0.3048  // feet to meters
    }
    
    var speedKnots: Int? {
        guard let speed = groundSpeed else { return nil }
        return Int(speed)
    }
    
    var speedMPS: Double? {
        guard let speed = groundSpeed else { return nil }
        return speed * 0.514444  // knots to m/s
    }
    
    var isOnGround: Bool {
        guard let alt = altitude else { return false }
        return alt < 100  // Below 100ft assumed on ground
    }
    
    var isEmergency: Bool {
        emergency != nil && emergency != "none"
    }
    
    var signalQuality: SignalQuality {
        guard let rssi = rssi else { return .unknown }
        
        switch rssi {
        case -10...0: return .excellent
        case -20..<(-10): return .good
        case -30..<(-20): return .fair
        default: return .poor
        }
    }
    
    var dataAge: TimeInterval {
        Date().timeIntervalSince(lastSeen)
    }
    
    var isStale: Bool {
        dataAge > 30  // No updates in 30 seconds
    }
    
    enum SignalQuality {
        case excellent, good, fair, poor, unknown
        
        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .poor: return "red"
            case .unknown: return "gray"
            }
        }
    }
    
    // MARK: - Codable Keys
    
    enum CodingKeys: String, CodingKey {
        case hex, lat, lon
        case altitude = "alt_baro"  // readsb format
        case altitudeGeom = "alt_geom"
        case track
        case groundSpeed = "gs"
        case verticalRate = "baro_rate"
        case ias, tas
        case flight, squawk, category
        case rssi, messages, seen
        case seenPos = "seen_pos"
        case navQnh = "nav_qnh"
        case navAltitudeMcp = "nav_altitude_mcp"
        case navHeading = "nav_heading"
        case nacp = "nac_p"
        case nacv = "nac_v"
        case sil
        case silType = "sil_type"
        case emergency
        case tisb
        case source  // Track aircraft source (ADS-B or OpenSky)
    }
    
    // Support for dump1090 original format (uses "altitude" instead of "alt_baro")
    enum Dump1090CodingKeys: String, CodingKey {
        case hex, lat, lon
        case altitude  // dump1090 format - simple "altitude" key
        case track
        case speed  // dump1090 uses "speed" instead of "gs"
        case vert_rate  // dump1090 uses "vert_rate" instead of "baro_rate"
        case flight, squawk, category
        case rssi, messages, seen
        case seen_pos
    }
    
    // MARK: - Initialization
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        hex = try container.decode(String.self, forKey: .hex)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lon = try container.decodeIfPresent(Double.self, forKey: .lon)
        
        // Try readsb format first (alt_baro)
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        
        // If readsb format didn't work, try dump1090 format (altitude)
        if altitude == nil {
            let dump1090Container = try? decoder.container(keyedBy: Dump1090CodingKeys.self)
            
            // dump1090 can send "ground" as a string value for altitude
            // Try to decode as Double first
            if let altitudeValue = try dump1090Container?.decodeIfPresent(Double.self, forKey: .altitude) {
                altitude = altitudeValue
            } else if let altitudeString = try dump1090Container?.decodeIfPresent(String.self, forKey: .altitude),
                      altitudeString == "ground" {
                // If it's the string "ground", set altitude to 0
                altitude = 0.0
            }
        }
        
        altitudeGeom = try container.decodeIfPresent(Double.self, forKey: .altitudeGeom)
        track = try container.decodeIfPresent(Double.self, forKey: .track)
        
        // Try readsb format first (gs)
        groundSpeed = try container.decodeIfPresent(Double.self, forKey: .groundSpeed)
        
        // If readsb format didn't work, try dump1090 format (speed)
        if groundSpeed == nil {
            let dump1090Container = try? decoder.container(keyedBy: Dump1090CodingKeys.self)
            groundSpeed = try dump1090Container?.decodeIfPresent(Double.self, forKey: .speed)
        }
        
        // Try readsb format first (baro_rate)
        verticalRate = try container.decodeIfPresent(Int.self, forKey: .verticalRate)
        
        // If readsb format didn't work, try dump1090 format (vert_rate)
        if verticalRate == nil {
            let dump1090Container = try? decoder.container(keyedBy: Dump1090CodingKeys.self)
            verticalRate = try dump1090Container?.decodeIfPresent(Int.self, forKey: .vert_rate)
        }
        
        ias = try container.decodeIfPresent(Int.self, forKey: .ias)
        tas = try container.decodeIfPresent(Int.self, forKey: .tas)
        flight = try container.decodeIfPresent(String.self, forKey: .flight)
        squawk = try container.decodeIfPresent(String.self, forKey: .squawk)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        rssi = try container.decodeIfPresent(Double.self, forKey: .rssi)
        messages = try container.decodeIfPresent(Int.self, forKey: .messages)
        seen = try container.decodeIfPresent(Double.self, forKey: .seen)
        
        // Try readsb format first (seen_pos)
        seenPos = try container.decodeIfPresent(Double.self, forKey: .seenPos)
        
        // If readsb format didn't work, try dump1090 format (seen_pos with underscore)
        if seenPos == nil {
            let dump1090Container = try? decoder.container(keyedBy: Dump1090CodingKeys.self)
            seenPos = try dump1090Container?.decodeIfPresent(Double.self, forKey: .seen_pos)
        }
        
        navQnh = try container.decodeIfPresent(Double.self, forKey: .navQnh)
        navAltitudeMcp = try container.decodeIfPresent(Int.self, forKey: .navAltitudeMcp)
        navHeading = try container.decodeIfPresent(Double.self, forKey: .navHeading)
        nacp = try container.decodeIfPresent(Int.self, forKey: .nacp)
        nacv = try container.decodeIfPresent(Int.self, forKey: .nacv)
        sil = try container.decodeIfPresent(Int.self, forKey: .sil)
        silType = try container.decodeIfPresent(String.self, forKey: .silType)
        emergency = try container.decodeIfPresent(String.self, forKey: .emergency)
        tisb = try container.decodeIfPresent([String].self, forKey: .tisb)
        
        // Try to decode source, default to ADS-B if not present (backward compatibility)
        source = try container.decodeIfPresent(AircraftSource.self, forKey: .source) ?? .adsb
        
        lastSeen = Date()
        positionHistory = []  // Initialize empty history
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(hex, forKey: .hex)
        try container.encodeIfPresent(lat, forKey: .lat)
        try container.encodeIfPresent(lon, forKey: .lon)
        try container.encodeIfPresent(altitude, forKey: .altitude)
        try container.encodeIfPresent(altitudeGeom, forKey: .altitudeGeom)
        try container.encodeIfPresent(track, forKey: .track)
        try container.encodeIfPresent(groundSpeed, forKey: .groundSpeed)
        try container.encodeIfPresent(verticalRate, forKey: .verticalRate)
        try container.encodeIfPresent(ias, forKey: .ias)
        try container.encodeIfPresent(tas, forKey: .tas)
        try container.encodeIfPresent(flight, forKey: .flight)
        try container.encodeIfPresent(squawk, forKey: .squawk)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(rssi, forKey: .rssi)
        try container.encodeIfPresent(messages, forKey: .messages)
        try container.encodeIfPresent(seen, forKey: .seen)
        try container.encodeIfPresent(seenPos, forKey: .seenPos)
        try container.encodeIfPresent(navQnh, forKey: .navQnh)
        try container.encodeIfPresent(navAltitudeMcp, forKey: .navAltitudeMcp)
        try container.encodeIfPresent(navHeading, forKey: .navHeading)
        try container.encodeIfPresent(nacp, forKey: .nacp)
        try container.encodeIfPresent(nacv, forKey: .nacv)
        try container.encodeIfPresent(sil, forKey: .sil)
        try container.encodeIfPresent(silType, forKey: .silType)
        try container.encodeIfPresent(emergency, forKey: .emergency)
        try container.encodeIfPresent(tisb, forKey: .tisb)
        try container.encode(source, forKey: .source)
        // Note: positionHistory is not encoded (local tracking only)
    }
    
    init(hex: String, lat: Double? = nil, lon: Double? = nil, altitude: Double? = nil,
         track: Double? = nil, groundSpeed: Double? = nil, flight: String? = nil,
         squawk: String? = nil, rssi: Double? = nil, source: AircraftSource = .adsb) {
        self.hex = hex
        self.lat = lat
        self.lon = lon
        self.altitude = altitude
        self.track = track
        self.groundSpeed = groundSpeed
        self.flight = flight
        self.squawk = squawk
        self.rssi = rssi
        self.lastSeen = Date()
        self.source = source
        self.positionHistory = []
    }
    
    // MARK: - History Management
    
    /// Add current position to history (called when aircraft updates)
    mutating func recordPosition() {
        guard let lat = lat, let lon = lon else { return }
        
        // Only record if position has changed significantly (avoid duplicate points)
        if let lastPoint = positionHistory.last {
            let latDiff = abs(lastPoint.latitude - lat)
            let lonDiff = abs(lastPoint.longitude - lon)
            
            // Skip if position hasn't changed by at least 0.0001 degrees (~11 meters)
            if latDiff < 0.0001 && lonDiff < 0.0001 {
                return
            }
        }
        
        let point = PositionHistoryPoint(
            latitude: lat,
            longitude: lon,
            altitude: altitude,
            timestamp: Date()
        )
        
        positionHistory.append(point)
    }
    
    /// Remove position history older than the specified retention time
    mutating func cleanupOldHistory(retentionMinutes: Double) {
        let cutoffDate = Date().addingTimeInterval(-retentionMinutes * 60)
        positionHistory.removeAll { $0.timestamp < cutoffDate }
    }
}

// MARK: - Readsb API Response

struct ReadsbResponse: Codable {
    let now: Double  // Unix timestamp
    let messages: Int  // Total messages processed
    let aircraft: [Aircraft]  // Array of aircraft
}

// MARK: - Aircraft Extensions

extension Aircraft {
    /// Convert to CoT XML for TAK server
    func toCoTXML() -> String {
        let dateFormatter = ISO8601DateFormatter()
        let now = dateFormatter.string(from: Date())
        let stale = dateFormatter.string(from: Date().addingTimeInterval(60))  // 1 minute stale
        
        let lat = self.lat ?? 0.0
        let lon = self.lon ?? 0.0
        let hae = altitudeMeters ?? 0.0
        
        // CoT type for aircraft: a-f-A (air, friend, aircraft)
        let cotType = "a-f-A"
        
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <event version="2.0" uid="ADSB-\(hex)" type="\(cotType)" time="\(now)" start="\(now)" stale="\(stale)" how="m-g">
            <point lat="\(lat)" lon="\(lon)" hae="\(hae)" ce="50.0" le="50.0"/>
            <detail>
                <contact callsign="\(displayName)"/>
                <track course="\(track ?? 0)" speed="\(speedMPS ?? 0)"/>
                <remarks>ADS-B Aircraft - \(displayName) - Alt: \(altitudeFeet ?? 0)ft - Speed: \(speedKnots ?? 0)kts</remarks>
                <link uid="ADSB-\(hex)" type="a-f-A" relation="p-p"/>
            </detail>
        </event>
        """
        
        return xml
    }
    
    /// Convert to MQTT message format
    func toMQTTMessage() -> [String: Any] {
        var dict: [String: Any] = [
            "hex": hex,
            "type": "aircraft",
            "source": source.rawValue.lowercased(),
            "timestamp": ISO8601DateFormatter().string(from: lastSeen)
        ]
        
        if let lat = lat { dict["latitude"] = lat }
        if let lon = lon { dict["longitude"] = lon }
        if let alt = altitude { dict["altitude_feet"] = Int(alt) }
        if let altMeters = altitudeMeters { dict["altitude_meters"] = altMeters }
        if let track = track { dict["track"] = track }
        if let gs = groundSpeed { dict["ground_speed_knots"] = Int(gs) }
        if let speedMPS = speedMPS { dict["ground_speed_mps"] = speedMPS }
        if let vr = verticalRate { dict["vertical_rate_fpm"] = vr }
        if let flight = flight { dict["callsign"] = flight.trimmingCharacters(in: .whitespaces) }
        if let squawk = squawk { dict["squawk"] = squawk }
        if let category = category { dict["category"] = category }
        if let rssi = rssi { dict["rssi"] = rssi }
        if let messages = messages { dict["messages"] = messages }
        if let seen = seen { dict["seen"] = seen }
        
        dict["on_ground"] = isOnGround
        dict["emergency"] = isEmergency
        dict["signal_quality"] = signalQuality.color
        
        return dict
    }
}
