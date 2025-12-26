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
        case altitude = "alt_baro"
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
    }
    
    // MARK: - Initialization
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        hex = try container.decode(String.self, forKey: .hex)
        lat = try container.decodeIfPresent(Double.self, forKey: .lat)
        lon = try container.decodeIfPresent(Double.self, forKey: .lon)
        altitude = try container.decodeIfPresent(Double.self, forKey: .altitude)
        altitudeGeom = try container.decodeIfPresent(Double.self, forKey: .altitudeGeom)
        track = try container.decodeIfPresent(Double.self, forKey: .track)
        groundSpeed = try container.decodeIfPresent(Double.self, forKey: .groundSpeed)
        verticalRate = try container.decodeIfPresent(Int.self, forKey: .verticalRate)
        ias = try container.decodeIfPresent(Int.self, forKey: .ias)
        tas = try container.decodeIfPresent(Int.self, forKey: .tas)
        flight = try container.decodeIfPresent(String.self, forKey: .flight)
        squawk = try container.decodeIfPresent(String.self, forKey: .squawk)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        rssi = try container.decodeIfPresent(Double.self, forKey: .rssi)
        messages = try container.decodeIfPresent(Int.self, forKey: .messages)
        seen = try container.decodeIfPresent(Double.self, forKey: .seen)
        seenPos = try container.decodeIfPresent(Double.self, forKey: .seenPos)
        navQnh = try container.decodeIfPresent(Double.self, forKey: .navQnh)
        navAltitudeMcp = try container.decodeIfPresent(Int.self, forKey: .navAltitudeMcp)
        navHeading = try container.decodeIfPresent(Double.self, forKey: .navHeading)
        nacp = try container.decodeIfPresent(Int.self, forKey: .nacp)
        nacv = try container.decodeIfPresent(Int.self, forKey: .nacv)
        sil = try container.decodeIfPresent(Int.self, forKey: .sil)
        silType = try container.decodeIfPresent(String.self, forKey: .silType)
        emergency = try container.decodeIfPresent(String.self, forKey: .emergency)
        tisb = try container.decodeIfPresent([String].self, forKey: .tisb)
        
        lastSeen = Date()
    }
    
    init(hex: String, lat: Double? = nil, lon: Double? = nil, altitude: Double? = nil,
         track: Double? = nil, groundSpeed: Double? = nil, flight: String? = nil,
         squawk: String? = nil, rssi: Double? = nil) {
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
            "source": "adsb",
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
