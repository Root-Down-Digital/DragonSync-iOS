//
//  DroneStorage.swift
//  WarDragon
//
//  Created by Luke on 1/21/25.
//

import Foundation
import CoreLocation
import UIKit


// Models
struct DroneEncounter: Codable, Identifiable, Hashable {
    let id: String
    let firstSeen: Date
    var lastSeen: Date
    var signatures: [SignatureData]
    var metadata: [String: String]
    var macHistory: Set<String>
    private var _flightPath: [FlightPathPoint]
    
    // Computed property for flight path
    var flightPath: [FlightPathPoint] {
        get {
            return _flightPath
        }
        set {
            _flightPath = newValue
        }
    }
    
    // CodingKeys to properly map private _flightPath property
    enum CodingKeys: String, CodingKey {
        case id
        case firstSeen
        case lastSeen
        case signatures
        case metadata
        case macHistory
        case _flightPath = "flightPath"
    }
    
    var headingDeg: Double {
        func parse(_ key: String) -> Double? {
            guard let raw = metadata[key]?
                .replacingOccurrences(of: "°", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  let value = Double(raw)
            else {
                return nil
            }
            return value
        }

        let rawHeading = parse("course") ?? parse("bearing") ?? parse("direction") ?? 0
        return (rawHeading.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    
    // User defined name/trust status
    var customName: String {
        get { metadata["customName"] ?? "" }
        set { metadata["customName"] = newValue }
    }

    var trustStatus: DroneSignature.UserDefinedInfo.TrustStatus {
        get {
            if let statusString = metadata["trustStatus"],
               let status = DroneSignature.UserDefinedInfo.TrustStatus(rawValue: statusString) {
                return status
            }
            return .unknown
        }
        set { metadata["trustStatus"] = newValue.rawValue }
    }
    
    // Initialize with private flight path
    init(id: String, firstSeen: Date, lastSeen: Date, flightPath: [FlightPathPoint], signatures: [SignatureData], metadata: [String: String], macHistory: Set<String>) {
        self.id = id
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self._flightPath = flightPath
        self.signatures = signatures
        self.metadata = metadata
        self.macHistory = macHistory
    }
    
    var maxAltitude: Double {
        let validAltitudes = flightPath.map { $0.altitude }.filter { $0 > 0 }
        return validAltitudes.max() ?? 0
    }

    var maxSpeed: Double {
        let validSpeeds = signatures.map { $0.speed }.filter { $0 > 0 }
        return validSpeeds.max() ?? 0
    }

    var averageRSSI: Double {
        let validRSSI = signatures.map { $0.rssi }.filter { $0 != 0 }
        guard !validRSSI.isEmpty else { return 0 }
        return validRSSI.reduce(0, +) / Double(validRSSI.count)
    }

    var totalFlightTime: TimeInterval {
        lastSeen.timeIntervalSince(firstSeen)
    }
}

struct FlightPathPoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let timestamp: TimeInterval
    let homeLatitude: Double?
    let homeLongitude: Double?
    let isProximityPoint: Bool
    let proximityRssi: Double?
    let proximityRadius: Double?
    
    enum CodingKeys: String, CodingKey {
            case latitude, longitude, altitude, timestamp, homeLatitude, homeLongitude, isProximityPoint, proximityRssi, proximityRadius
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

struct SignatureData: Codable, Hashable {
    let timestamp: TimeInterval
    let rssi: Double
    let speed: Double
    let height: Double
    let mac: String?
    
    // Ensure the charts are not messed up by mac randos
    var isValid: Bool {
        return rssi != 0
    }
    
    init?(timestamp: TimeInterval, rssi: Double, speed: Double, height: Double, mac: String?) {
        guard rssi != 0 else { return nil } // Skip invalid data - TODO decide how lean to be here for the elusive ones
        self.timestamp = timestamp
        self.rssi = rssi
        self.speed = speed
        self.height = height
        self.mac = mac
    }
}


//MARK: - CSV Export
extension DroneEncounter {
    static func csvHeaders() -> String {
        return "First Seen,First Seen Latitude,First Seen Longitude,First Seen Altitude (m)," +
        "Last Seen,Last Seen Latitude,Last Seen Longitude,Last Seen Altitude (m)," +
        "ID,CAA Registration,Primary MAC,Flight Path Points," +
        "Max Altitude (m),Max Speed (m/s),Average RSSI (dBm)," +
        "Flight Duration (HH:MM:SS),Height (m),Manufacturer," +
        "MAC Count,MAC History,Pilot Latitude,Pilot Longitude," +
        "Takeoff Latitude,Takeoff Longitude"
    }
    
    func toCSVRow() -> String {
        var row = [String]()
        
        let formatter = ISO8601DateFormatter()
        
        // First seen data
        row.append(formatter.string(from: firstSeen))
        if let firstPoint = flightPath.first {
            row.append(String(format: "%.6f", firstPoint.latitude))
            row.append(String(format: "%.6f", firstPoint.longitude))
            row.append(String(format: "%.1f", firstPoint.altitude))
        } else {
            row.append(contentsOf: ["","",""])
        }
        
        // Last seen data
        row.append(formatter.string(from: lastSeen))
        if let lastPoint = flightPath.last {
            row.append(String(format: "%.6f", lastPoint.latitude))
            row.append(String(format: "%.6f", lastPoint.longitude))
            row.append(String(format: "%.1f", lastPoint.altitude))
        } else {
            row.append(contentsOf: ["","",""])
        }
        
        // Identifiers
        row.append(id)
        row.append(metadata["caaRegistration"] ?? "")
        row.append(macHistory.isEmpty ? "" : macHistory.first ?? "")
        
        // Flight path stats
        row.append("\(flightPath.count)")
        
        // Flight metrics
        let maxAlt = flightPath.isEmpty ? 0 : flightPath.map { $0.altitude }.max() ?? 0
        row.append(String(format: "%.1f", maxAlt))
        
        let maxSpeed = signatures.isEmpty ? 0 : signatures.map { $0.speed }.max() ?? 0
        row.append(String(format: "%.1f", maxSpeed))
        
        let avgRssi = signatures.isEmpty ? 0 : signatures.map { $0.rssi }.reduce(0, +) / Double(signatures.count)
        row.append(String(format: "%.1f", avgRssi))
        
        // Flight duration
        let duration = lastSeen.timeIntervalSince(firstSeen)
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        row.append(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
        
        // Height and manufacturer
        let avgHeight = signatures.isEmpty ? 0 : signatures.map { $0.height }.reduce(0, +) / Double(signatures.count)
        row.append(String(format: "%.1f", avgHeight))
        row.append(metadata["manufacturer"] ?? "")
        
        // MAC info
        row.append("\(macHistory.count)")
        row.append(macHistory.joined(separator: ";"))
        
        // Pilot location
        if let pilotLat = metadata["pilotLat"], let pilotLon = metadata["pilotLon"] {
            row.append(pilotLat)
            row.append(pilotLon)
        } else {
            row.append("")
            row.append("")
        }
        
        // Takeoff location (using homeLat/homeLon)
        if let takeoffLat = metadata["homeLat"], let takeoffLon = metadata["homeLon"] {
            row.append(takeoffLat)
            row.append(takeoffLon)
        } else {
            row.append("")
            row.append("")
        }
        
        return row.map { "\"\($0)\"" }.joined(separator: ",")
    }
}

//MARK: - Storage Manager

@MainActor
class DroneStorageManager: ObservableObject {
    static let shared = DroneStorageManager()
    var cotViewModel: CoTViewModel?
    
    // Reference to SwiftData manager (single source of truth)
    private let swiftDataManager = SwiftDataStorageManager.shared
    
    // Lightweight cache for quick lookups (DO NOT use for writes)
    @Published private(set) var encounters: [String: DroneEncounter] = [:]
    
    init() {
        // Migration will happen automatically in app delegate
    }
    
    // Force save (call when app goes to background)
    func forceSave() {
        swiftDataManager.forceSave()
    }
    
    nonisolated func saveEncounter(_ message: CoTViewModel.CoTMessage, monitorStatus: StatusViewModel.StatusMessage? = nil) {
        Task { @MainActor in
            swiftDataManager.saveEncounter(message, monitorStatus: monitorStatus)
        }
    }

    func markAsDoNotTrack(id: String) {
        // Mark in SwiftData
        swiftDataManager.markAsDoNotTrack(id: id)
        
        // Update in-memory cache
        let baseId = id.replacingOccurrences(of: "drone-", with: "")
        let possibleIds = [id, "drone-\(id)", baseId, "drone-\(baseId)"]
        
        for possibleId in possibleIds {
            if var encounter = encounters[possibleId] {
                encounter.metadata["doNotTrack"] = "true"
                encounters[possibleId] = encounter
            }
        }
        print("Marked as do not track: \(possibleIds)")
    }
    
    //MARK: - Storage Functions/CRUD
    
    func updateDroneInfo(id: String, name: String, trustStatus: DroneSignature.UserDefinedInfo.TrustStatus) {
        // Update SwiftData
        swiftDataManager.updateDroneInfo(id: id, name: name, trustStatus: trustStatus)
        
        // Update in-memory cache
        if var encounter = encounters[id] {
            encounter.metadata["customName"] = name
            encounter.metadata["trustStatus"] = trustStatus.rawValue
            encounters[id] = encounter
            objectWillChange.send()
        }
        
        // Notify CoTViewModel to update its parsedMessages array
        NotificationCenter.default.post(
            name: Notification.Name("DroneInfoUpdated"),
            object: nil,
            userInfo: ["droneId": id, "customName": name, "trustStatus": trustStatus.rawValue]
        )
    }
    
    func deleteEncounter(id: String) {
        // Delete from SwiftData
        swiftDataManager.deleteEncounter(id: id)
        
        // Delete from in-memory cache
        encounters.removeValue(forKey: id)
        objectWillChange.send()
    }
    
    func deleteAllEncounters() {
        // Delete from SwiftData
        swiftDataManager.deleteAllEncounters()
        
        UserDefaults.standard.removeObject(forKey: "DroneEncounters")
        UserDefaults.standard.synchronize()
        print("🗑️ Cleared UserDefaults backup")
        
        // Clear in-memory cache
        encounters.removeAll()
        objectWillChange.send()
        
        print("✅ Deleted all encounters from SwiftData, UserDefaults, and in-memory cache")
    }
    
    func saveToStorage() {
        // Save all in-memory changes to SwiftData
        for (_, encounter) in encounters {
            swiftDataManager.saveEncounterDirect(encounter)
        }
        swiftDataManager.forceSave()
    }
    
    func loadFromStorage() {
        // Check if SwiftData manager has a ModelContext
        if SwiftDataStorageManager.shared.modelContext == nil {
            print("SwiftDataStorageManager.modelContext is nil - will fallback to UserDefaults")
        }
        
        // Check if migration has been completed
        let migrationCompleted = UserDefaults.standard.bool(forKey: "DataMigration_UserDefaultsToSwiftData_Completed")
        
        // Try to load from SwiftData first
        updateInMemoryCache()
        
        // Log what we loaded
        let swiftDataCount = encounters.count
        print("Loaded \(swiftDataCount) encounters from SwiftData")
        
        // Only fallback to UserDefaults if migration hasn't been completed yet
        // This prevents loading old data after it's been deleted from SwiftData
        if encounters.isEmpty && !migrationCompleted {
            if let data = UserDefaults.standard.data(forKey: "DroneEncounters"),
               let loaded = try? JSONDecoder().decode([String: DroneEncounter].self, from: data) {
                encounters = loaded
                print("SwiftData empty - Loaded \(encounters.count) encounters from UserDefaults (pre-migration)")
                print("Migration may not have completed yet or data needs to be migrated")
            } else {
                print("No encounters found in either SwiftData or UserDefaults (fresh install)")
            }
        } else if encounters.isEmpty && migrationCompleted {
            print("✅ Migration completed - SwiftData is intentionally empty (all data deleted or no encounters yet)")
        } else {
            print("✅ Using \(encounters.count) encounters from SwiftData")
        }
    }
    
    private func updateInMemoryCache() {
        // Get all encounters from SwiftData
        let stored = swiftDataManager.fetchAllEncounters()
        encounters = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.toLegacy()) })
    }
    
    /// Update a single encounter in the cache
    /// Used by SwiftDataStorageManager to keep cache in sync
    func updateEncounterInCache(_ encounter: DroneEncounter) {
        encounters[encounter.id] = encounter
        objectWillChange.send()
    }
    
    func updatePilotLocation(droneId: String, latitude: Double, longitude: Double) {
        // Fetch encounter from SwiftData
        guard let storedEncounter = swiftDataManager.fetchEncounter(id: droneId) else {
            print("Encounter not found: \(droneId)")
            return
        }
        
        // Update metadata
        var metadata = storedEncounter.metadata
        metadata["pilotLat"] = String(latitude)
        metadata["pilotLon"] = String(longitude)
        
        // Preserve in history
        let timestamp = Date().timeIntervalSince1970
        let pilotEntry = "\(timestamp):\(latitude),\(longitude)"
        
        if let existingHistory = metadata["pilotHistory"] {
            metadata["pilotHistory"] = existingHistory + ";" + pilotEntry
        } else {
            metadata["pilotHistory"] = pilotEntry
        }
        
        storedEncounter.metadata = metadata
        
        // Save to SwiftData
        swiftDataManager.forceSave()
        
        // Update in-memory cache
        if var encounter = encounters[droneId] {
            encounter.metadata = metadata
            encounters[droneId] = encounter
        }
        
        print("Updated pilot location history for \(droneId)")
    }

    // Update home location function to preserve history
    func updateHomeLocation(droneId: String, latitude: Double, longitude: Double) {
        // Fetch encounter from SwiftData
        guard let storedEncounter = swiftDataManager.fetchEncounter(id: droneId) else {
            print("Encounter not found: \(droneId)")
            return
        }
        
        // Update metadata
        var metadata = storedEncounter.metadata
        metadata["homeLat"] = String(latitude)
        metadata["homeLon"] = String(longitude)
        
        // Preserve in history
        let timestamp = Date().timeIntervalSince1970
        let homeEntry = "\(timestamp):\(latitude),\(longitude)"
        
        if let existingHistory = metadata["homeHistory"] {
            metadata["homeHistory"] = existingHistory + ";" + homeEntry
        } else {
            metadata["homeHistory"] = homeEntry
        }
        
        storedEncounter.metadata = metadata
        
        // Save to SwiftData
        swiftDataManager.forceSave()
        
        // Update in-memory cache
        if var encounter = encounters[droneId] {
            encounter.metadata = metadata
            encounters[droneId] = encounter
        }
        
        print("Updated home location history for \(droneId)")
    }

    // Helper function for distance calculation
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let location2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return location1.distance(from: location2)
    }

    
    func updateProximityPointsWithCorrectRadius() {
        // Fetch all encounters from SwiftData
        let allEncounters = swiftDataManager.fetchAllEncounters()
        
        for storedEncounter in allEncounters {
            guard storedEncounter.metadata["hasProximityPoints"] == "true" else { continue }
            
            var updatedFlightPoints: [StoredFlightPoint] = []
            var needsUpdate = false
            
            for point in storedEncounter.flightPoints {
                if point.isProximityPoint {
                    // Calculate from RSSI if needed
                    if let rssi = point.proximityRssi, (point.proximityRadius == nil || point.proximityRadius == 0) {
                        let generator = DroneSignatureGenerator()
                        var radius = generator.calculateDistance(rssi)
                        
                        // Ensure minimum radius
                        radius = max(radius, 50.0)
                        
                        // Create new point with calculated radius
                        let updatedPoint = StoredFlightPoint(
                            latitude: point.latitude,
                            longitude: point.longitude,
                            altitude: point.altitude,
                            timestamp: point.timestamp,
                            homeLatitude: point.homeLatitude,
                            homeLongitude: point.homeLongitude,
                            isProximityPoint: true,
                            proximityRssi: point.proximityRssi,
                            proximityRadius: radius
                        )
                        updatedFlightPoints.append(updatedPoint)
                        needsUpdate = true
                    } else {
                        updatedFlightPoints.append(point)
                    }
                } else {
                    updatedFlightPoints.append(point)
                }
            }
            
            if needsUpdate {
                // Remove old points and add updated ones
                storedEncounter.flightPoints.removeAll()
                storedEncounter.flightPoints.append(contentsOf: updatedFlightPoints)
            }
        }
        
        // Save all changes to SwiftData
        swiftDataManager.forceSave()
        
        // Refresh in-memory cache
        updateInMemoryCache()
    }
    
    func exportToCSV() -> String {
        // Use SwiftData manager for export
        return swiftDataManager.exportToCSV()
    }
    
    func shareCSV(from viewController: UIViewController? = nil) {
        // Delegate to SwiftData manager
        swiftDataManager.shareCSV(from: viewController)
    }
    
    class CSVDataItem: NSObject, UIActivityItemSource {
        private let fileURL: URL
        private let filename: String
        
        init(fileURL: URL, filename: String) {
            self.fileURL = fileURL
            self.filename = filename
            super.init()
        }
        
        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
            return fileURL
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
            return fileURL
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
            return "public.comma-separated-values-text"
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
            return filename
        }
        
        func activityViewController(_ activityViewController: UIActivityViewController, filenameForActivityType activityType: UIActivity.ActivityType?) -> String {
            return filename
        }
    }
    
    
}
