//
//  DroneDataModels.swift
//  WarDragon
//
//  Migration to SwiftData for persistent storage
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - SwiftData Models

@Model
final class StoredDroneEncounter {
    @Attribute(.unique) var id: String
    var firstSeen: Date
    var lastSeen: Date
    var customName: String
    var trustStatusRaw: String
    var metadata: [String: String]
    var macAddresses: [String]
    
    // Cached computed values for performance
    var cachedMaxAltitude: Double = 0
    var cachedMaxSpeed: Double = 0
    var cachedAverageRSSI: Double = 0
    var cachedFlightPointCount: Int = 0
    var cachedSignatureCount: Int = 0
    
    @Relationship(deleteRule: .cascade) var flightPoints: [StoredFlightPoint] = []
    @Relationship(deleteRule: .cascade) var signatures: [StoredSignature] = []
    
    init(id: String, 
         firstSeen: Date, 
         lastSeen: Date,
         customName: String = "",
         trustStatusRaw: String = "unknown",
         metadata: [String: String] = [:],
         macAddresses: [String] = [],
         flightPoints: [StoredFlightPoint] = [],
         signatures: [StoredSignature] = []) {
        self.id = id
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.customName = customName
        self.trustStatusRaw = trustStatusRaw
        self.metadata = metadata
        self.macAddresses = macAddresses
        self.flightPoints = flightPoints
        self.signatures = signatures
        
        // Initialize cached values
        self.updateCachedStats()
    }
    
    // Call this after modifying flightPoints or signatures
    func updateCachedStats() {
        cachedFlightPointCount = flightPoints.count
        cachedSignatureCount = signatures.count
        cachedMaxAltitude = flightPoints.filter { !$0.isProximityPoint }.lazy.map { $0.altitude }.max() ?? 0
        cachedMaxSpeed = signatures.lazy.map { $0.speed }.max() ?? 0
        
        let validRSSI = signatures.lazy.map { $0.rssi }.filter { $0 != 0 }
        let rssiArray = Array(validRSSI)
        cachedAverageRSSI = rssiArray.isEmpty ? 0 : rssiArray.reduce(0, +) / Double(rssiArray.count)
    }
    
    // Computed properties - now use cached values for performance
    var trustStatus: DroneSignature.UserDefinedInfo.TrustStatus {
        get {
            DroneSignature.UserDefinedInfo.TrustStatus(rawValue: trustStatusRaw) ?? .unknown
        }
        set {
            trustStatusRaw = newValue.rawValue
        }
    }
    
    var maxAltitude: Double {
        // ALWAYS use cached value - NEVER access relationships in computed properties
        // Relationships can fault in SwiftData and cause crashes
        return cachedMaxAltitude
    }
    
    var maxSpeed: Double {
        // ALWAYS use cached value - NEVER access relationships in computed properties
        // Relationships can fault in SwiftData and cause crashes
        return cachedMaxSpeed
    }
    
    var averageRSSI: Double {
        // ALWAYS use cached value - NEVER access relationships in computed properties
        // Relationships can fault in SwiftData and cause crashes
        return cachedAverageRSSI
    }
    
    var totalFlightTime: TimeInterval {
        lastSeen.timeIntervalSince(firstSeen)
    }
    
    var headingDeg: Double {
        func parse(_ key: String) -> Double? {
            guard let raw = metadata[key]?
                .replacingOccurrences(of: "°", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = Double(raw)
            else { return nil }
            return value
        }
        
        let rawHeading = parse("course") ?? parse("bearing") ?? parse("direction") ?? 0
        return (rawHeading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
}

@Model
final class StoredFlightPoint {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: TimeInterval
    var homeLatitude: Double?
    var homeLongitude: Double?
    var isProximityPoint: Bool
    var proximityRssi: Double?
    var proximityRadius: Double?
    
    @Relationship(inverse: \StoredDroneEncounter.flightPoints) 
    var encounter: StoredDroneEncounter?
    
    init(latitude: Double,
         longitude: Double,
         altitude: Double,
         timestamp: TimeInterval,
         homeLatitude: Double? = nil,
         homeLongitude: Double? = nil,
         isProximityPoint: Bool = false,
         proximityRssi: Double? = nil,
         proximityRadius: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.homeLatitude = homeLatitude
        self.homeLongitude = homeLongitude
        self.isProximityPoint = isProximityPoint
        self.proximityRssi = proximityRssi
        self.proximityRadius = proximityRadius
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    var homeLocation: CLLocationCoordinate2D? {
        guard let homeLat = homeLatitude,
              let homeLon = homeLongitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: homeLat, longitude: homeLon)
    }
}

@Model
final class StoredSignature {
    var timestamp: TimeInterval
    var rssi: Double
    var speed: Double
    var height: Double
    var mac: String?
    
    @Relationship(inverse: \StoredDroneEncounter.signatures) 
    var encounter: StoredDroneEncounter?
    
    init(timestamp: TimeInterval,
         rssi: Double,
         speed: Double,
         height: Double,
         mac: String? = nil) {
        self.timestamp = timestamp
        self.rssi = rssi
        self.speed = speed
        self.height = height
        self.mac = mac
    }
    
    var isValid: Bool {
        rssi != 0
    }
}

@Model
final class StoredADSBEncounter {
    @Attribute(.unique) var id: String  // ICAO hex
    var callsign: String
    var firstSeen: Date
    var lastSeen: Date
    var maxAltitude: Double
    var minAltitude: Double
    var totalSightings: Int
    
    init(id: String,
         callsign: String,
         firstSeen: Date,
         lastSeen: Date,
         maxAltitude: Double,
         minAltitude: Double,
         totalSightings: Int) {
        self.id = id
        self.callsign = callsign
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.maxAltitude = maxAltitude
        self.minAltitude = minAltitude
        self.totalSightings = totalSightings
    }
    
    var displayName: String {
        callsign.isEmpty ? id.uppercased() : callsign
    }
    
    var duration: TimeInterval {
        lastSeen.timeIntervalSince(firstSeen)
    }
    
    var formattedDuration: String {
        let interval = duration
        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else {
            return "\(Int(interval / 3600))h \(Int((interval.truncatingRemainder(dividingBy: 3600)) / 60))m"
        }
    }
}

// MARK: - Migration Helper Extensions

extension StoredDroneEncounter {
    /// Convert old DroneEncounter to new SwiftData model
    static func from(legacy encounter: DroneEncounter, context: ModelContext) -> StoredDroneEncounter {
        // Build flight points array BEFORE creating the model
        let flightPoints = encounter.flightPath.map { point in
            StoredFlightPoint(
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                timestamp: point.timestamp,
                homeLatitude: point.homeLatitude,
                homeLongitude: point.homeLongitude,
                isProximityPoint: point.isProximityPoint,
                proximityRssi: point.proximityRssi,
                proximityRadius: point.proximityRadius
            )
        }
        
        // Build signatures array BEFORE creating the model
        let signatures = encounter.signatures.map { sig in
            StoredSignature(
                timestamp: sig.timestamp,
                rssi: sig.rssi,
                speed: sig.speed,
                height: sig.height,
                mac: sig.mac
            )
        }
        
        // Create the stored encounter with all data at once
        let stored = StoredDroneEncounter(
            id: encounter.id,
            firstSeen: encounter.firstSeen,
            lastSeen: encounter.lastSeen,
            customName: encounter.customName,
            trustStatusRaw: encounter.trustStatus.rawValue,
            metadata: encounter.metadata,
            macAddresses: Array(encounter.macHistory),
            flightPoints: flightPoints,
            signatures: signatures
        )
        
        return stored
    }
    
    /// Convert back to legacy format (for compatibility during migration)
    /// WARNING: This is expensive for encounters with many flight points/signatures
    /// Consider using toLegacyLightweight() for list views
    func toLegacy() -> DroneEncounter {
        let flightPath = flightPoints.map { point in
            FlightPathPoint(
                latitude: point.latitude,
                longitude: point.longitude,
                altitude: point.altitude,
                timestamp: point.timestamp,
                homeLatitude: point.homeLatitude,
                homeLongitude: point.homeLongitude,
                isProximityPoint: point.isProximityPoint,
                proximityRssi: point.proximityRssi,
                proximityRadius: point.proximityRadius
            )
        }
        
        let sigs = signatures.compactMap { sig in
            SignatureData(
                timestamp: sig.timestamp,
                rssi: sig.rssi,
                speed: sig.speed,
                height: sig.height,
                mac: sig.mac
            )
        }
        
        return DroneEncounter(
            id: id,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            flightPath: flightPath,
            signatures: sigs,
            metadata: metadata,
            macHistory: Set(macAddresses)
        )
    }
    
    /// Lightweight conversion that only includes essential data for list views
    /// This avoids converting thousands of flight points and signatures
    func toLegacyLightweight() -> DroneEncounter {
        // Only include last few flight points for preview (e.g., last 10)
        let recentFlightPoints = flightPoints
            .suffix(10)
            .map { point in
                FlightPathPoint(
                    latitude: point.latitude,
                    longitude: point.longitude,
                    altitude: point.altitude,
                    timestamp: point.timestamp,
                    homeLatitude: point.homeLatitude,
                    homeLongitude: point.homeLongitude,
                    isProximityPoint: point.isProximityPoint,
                    proximityRssi: point.proximityRssi,
                    proximityRadius: point.proximityRadius
                )
            }
        
        // Only include last few signatures (e.g., last 10)
        let recentSignatures = signatures
            .suffix(10)
            .compactMap { sig in
                SignatureData(
                    timestamp: sig.timestamp,
                    rssi: sig.rssi,
                    speed: sig.speed,
                    height: sig.height,
                    mac: sig.mac
                )
            }
        
        return DroneEncounter(
            id: id,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            flightPath: recentFlightPoints,
            signatures: recentSignatures,
            metadata: metadata,
            macHistory: Set(macAddresses)
        )
    }
}

extension StoredADSBEncounter {
    /// Convert old ADSBEncounter to new SwiftData model
    static func from(legacy encounter: StatusViewModel.ADSBEncounter) -> StoredADSBEncounter {
        StoredADSBEncounter(
            id: encounter.id,
            callsign: encounter.callsign,
            firstSeen: encounter.firstSeen,
            lastSeen: encounter.lastSeen,
            maxAltitude: encounter.maxAltitude,
            minAltitude: encounter.minAltitude,
            totalSightings: encounter.totalSightings
        )
    }
    
    /// Convert back to legacy format
    func toLegacy() -> StatusViewModel.ADSBEncounter {
        StatusViewModel.ADSBEncounter(
            id: id,
            callsign: callsign,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            maxAltitude: maxAltitude,
            minAltitude: minAltitude,
            totalSightings: totalSightings
        )
    }
}
