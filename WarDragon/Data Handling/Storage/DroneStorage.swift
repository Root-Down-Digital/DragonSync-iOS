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
        "MAC Count,MAC History"
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
        row.append(macHistory.isEmpty ? "" : macHistory.first ?? "")  // Primary MAC
        row.append(String(flightPath.count))  // Flight Path Points
        
        // Flight stats
        row.append(String(format: "%.1f", maxAltitude))
        row.append(String(format: "%.1f", maxSpeed))
        row.append(String(format: "%.1f", averageRSSI))
        
        // Format flight duration as HH:MM:SS
        let duration = Int(totalFlightTime)
        let hours = duration / 3600
        let minutes = (duration % 3600) / 60
        let seconds = duration % 60
        row.append(String(format: "%02d:%02d:%02d", hours, minutes, seconds))
        
        // Height and manufacturer
        row.append(String(format: "%.1f", signatures.last?.height ?? 0.0))
        row.append(metadata["manufacturer"] ?? "")
        
        // MAC Count and MAC History
        row.append(String(macHistory.count))
        row.append(macHistory.joined(separator: ";"))
        
        return row.joined(separator: ",")
    }
}

//MARK: - Storage Manager

class DroneStorageManager: ObservableObject {
    static let shared = DroneStorageManager()
    var cotViewModel: CoTViewModel?
    @Published private(set) var encounters: [String: DroneEncounter] = [:]
    
    init() {
        loadFromStorage()
        updateProximityPointsWithCorrectRadius()
    }
    
    func saveEncounter(_ message: CoTViewModel.CoTMessage, monitorStatus: StatusViewModel.StatusMessage? = nil) {
        // Allow zero coordinates for encrypted messages
        let lat = Double(message.lat) ?? 0
        let lon = Double(message.lon) ?? 0
        
        let droneId = message.uid
        
        if message.idType.contains("CAA"),
           let mac = message.mac,
           let existingId = encounters.first(where: { $0.value.metadata["mac"] == mac })?.key {
            var encounter = encounters[existingId]!
            encounter.lastSeen = Date()
            encounter.metadata["caaRegistration"] = message.uid
            encounters[existingId] = encounter
            return
        }
        
        var encounter = encounters[droneId] ?? DroneEncounter(
            id: droneId,
            firstSeen: Date(),
            lastSeen: Date(),
            flightPath: [],
            signatures: [],
            metadata: [:],
            macHistory: []
        )
        
        encounter.lastSeen = Date()
        var didAddPoint = false
        
        // Handle proximity points for encrypted devices
        if ((lat == 0 && lon == 0) && message.rssi != nil && message.rssi != 0) {
            var pointToAdd: FlightPathPoint? = nil
            
            // --- PRIORITY 1: Use monitorStatus if available ---
            if let monitor = monitorStatus, let rssiValue = message.rssi {
                var calculatedRadius: Double = 0.0 // Default to 0.0
                
                if rssiValue > 0 {
                    // Get the ACTUAL radius from alert ring if available
                    if let ring = cotViewModel?.alertRings.first(where: { $0.droneId == message.uid }) {
                        calculatedRadius = ring.radius // Use the ACTUAL radius from the alert ring
                        print("✅ Proximity: Using actual ring radius (\(calculatedRadius)m) for RSSI \(rssiValue)")
                    }
                } else {
                    // RSSI is zero or otherwise unexpected
                    print("⚠️ Proximity: RSSI (\(rssiValue)) is zero or invalid, using default radius.")
                    calculatedRadius = 100.0 // Use a default radius instead of 0
                }
                
                pointToAdd = FlightPathPoint(
                    latitude: monitor.gpsData.latitude,
                    longitude: monitor.gpsData.longitude,
                    altitude: monitor.gpsData.altitude, // Use monitor altitude
                    timestamp: Date().timeIntervalSince1970,
                    homeLatitude: nil,
                    homeLongitude: nil,
                    isProximityPoint: true,
                    proximityRssi: Double(rssiValue),
                    proximityRadius: calculatedRadius
                )
                print("💾 Added proximity point using Monitor Status for \(droneId)")
            }
            
            // Add the point if one was created
            if let point = pointToAdd {
                encounter.flightPath.append(point)
                encounter.metadata["hasProximityPoints"] = "true"
                didAddPoint = true
            } else {
                print("⚠️ Could not add proximity point for \(droneId) - No Monitor Status or CoT Ring found.")
            }
            
            
            // --- PRIORITY 2: Fallback to cotViewModel.alertRings if no point added yet ---
            if pointToAdd == nil, let currentRing = cotViewModel?.alertRings.first(where: { $0.droneId == droneId }) {
                // Use data from the existing alert ring
                pointToAdd = FlightPathPoint(
                    latitude: currentRing.centerCoordinate.latitude,
                    longitude: currentRing.centerCoordinate.longitude,
                    altitude: 0, // Altitude might not be known from the ring, default or use monitor if available?
                    timestamp: Date().timeIntervalSince1970, // Use current time for the point
                    homeLatitude: nil,
                    homeLongitude: nil,
                    isProximityPoint: true,
                    proximityRssi: Double(currentRing.rssi),
                    proximityRadius: Double(currentRing.radius)
                )
                print("💾 Added proximity point using CoTViewModel Ring for \(droneId)")
            }
            
            // Add the point if one was created
            if let point = pointToAdd {
                encounter.flightPath.append(point)
                encounter.metadata["hasProximityPoints"] = "true"
                didAddPoint = true
            } else {
                print("⚠️ Could not add proximity point for \(droneId) - No Monitor Status or CoT Ring found.")
            }
            
        }
        
        if !didAddPoint && (lat != 0 || lon != 0) {
            let point = FlightPathPoint(
                latitude: lat,
                longitude: lon,
                altitude: Double(message.alt) ?? 0.0,
                timestamp: Date().timeIntervalSince1970,
                homeLatitude: Double(message.homeLat),
                homeLongitude: Double(message.homeLon),
                isProximityPoint: false,
                proximityRssi: nil,
                proximityRadius: nil
            )
            encounter.flightPath.append(point)
            print("💾 Added regular flight point for \(droneId)")
            didAddPoint = true
        }
        
        // If no point was added at all (e.g., zero coords, no RSSI, no monitor, no ring), log it.
        if !didAddPoint {
            print("🚫 No flight point added for this update for \(droneId). Message: \(message)")
        }
        
        // Update MAC history from signal sources
        for source in message.signalSources {
            if !source.mac.isEmpty {
                encounter.macHistory.insert(source.mac)
            }
        }
        
        if let mac = message.mac, !mac.isEmpty {
            encounter.macHistory.insert(mac)
        }
        
        // Validate the new signature before adding
        if let sig = SignatureData(
            timestamp: Date().timeIntervalSince1970,
            rssi: Double(message.rssi ?? 0),
            speed: Double(message.speed) ?? 0.0,
            height: Double(message.height ?? "0.0") ?? 0.0,
            mac: String(message.mac ?? "")
        ) {
            
            encounter.signatures.append(sig) // Only add valid signatures
        }
        
        var updatedMetadata = encounter.metadata

        // Add other metadata first
        if let mac = message.mac {
            updatedMetadata["mac"] = mac
        }

        if let caaReg = message.caaRegistration {
            updatedMetadata["caaRegistration"] = caaReg
        }

        if let manufacturer = message.manufacturer {
            updatedMetadata["manufacturer"] = manufacturer
        }

        // Add pilot location
        if let pilotLat = Double(message.pilotLat), let pilotLon = Double(message.pilotLon),
           pilotLat != 0 || pilotLon != 0 {
            updatedMetadata["pilotLat"] = message.pilotLat
            updatedMetadata["pilotLon"] = message.pilotLon
        }

        // Add home location
        if let homeLat = Double(message.homeLat), let homeLon = Double(message.homeLon),
           homeLat != 0 || homeLon != 0 {
            updatedMetadata["homeLat"] = message.homeLat
            updatedMetadata["homeLon"] = message.homeLon
        }

        // Apply the updated metadata to the encounter
        encounter.metadata = updatedMetadata
        // Add pilot location
        if let pilotLat = Double(message.pilotLat), let pilotLon = Double(message.pilotLon),
           pilotLat != 0 || pilotLon != 0 {
            updatedMetadata["pilotLat"] = message.pilotLat
            updatedMetadata["pilotLon"] = message.pilotLon
        }

        // Add home location (which you're calling takeoff)
        if let lat = Double(message.homeLat), let lon = Double(message.homeLon),
           lat != 0 || lon != 0 {
            updatedMetadata["takeoffLat"] = message.homeLat
            updatedMetadata["takeoffLon"] = message.homeLon
        }
        
        // Update name or trust status
        if encounters[droneId] != nil {
            let existingName = encounters[droneId]?.customName ?? ""
            let existingTrust = encounters[droneId]?.trustStatus ?? .unknown
            
            if !existingName.isEmpty {
                encounter.customName = existingName
            }
            
            if existingTrust != .unknown {
                encounter.trustStatus = existingTrust
            }
        }
        
        // Save the drone encounters array and device
        encounters[droneId] = encounter
        saveToStorage()
    }
    
    //MARK: - Storage Functions/CRUD
    
    func updateDroneInfo(id: String, name: String, trustStatus: DroneSignature.UserDefinedInfo.TrustStatus) {
        if var encounter = encounters[id] {
            encounter.metadata["customName"] = name
            encounter.metadata["trustStatus"] = trustStatus.rawValue
            encounters[id] = encounter
            saveToStorage()
            objectWillChange.send()
        }
    }
    
    func deleteEncounter(id: String) {
        encounters.removeValue(forKey: id)
        UserDefaults.standard.set(try? JSONEncoder().encode(encounters), forKey: "DroneEncounters")
        saveToStorage()
    }
    
    func deleteAllEncounters() {
        encounters.removeAll()
        UserDefaults.standard.removeObject(forKey: "DroneEncounters")
        saveToStorage() // Optional, but ensures clean state
    }
    
    func saveToStorage() {
        if let data = try? JSONEncoder().encode(encounters) {
            UserDefaults.standard.set(data, forKey: "DroneEncounters")
            print("✅ Saved \(encounters.count) encounters to storage")
        } else {
            print("❌ Failed to encode encounters")
        }
    }
    
    func loadFromStorage() {
        if let data = UserDefaults.standard.data(forKey: "DroneEncounters"),
           let loaded = try? JSONDecoder().decode([String: DroneEncounter].self, from: data) {
            encounters = loaded
        }
    }
    
    func updatePilotLocation(droneId: String, latitude: Double, longitude: Double) {
        if var encounter = encounters[droneId] {
            encounter.metadata["pilotLat"] = String(latitude)
            encounter.metadata["pilotLon"] = String(longitude)
            encounters[droneId] = encounter
            saveToStorage()
        }
    }

    func updateHomeLocation(droneId: String, latitude: Double, longitude: Double) {
        if var encounter = encounters[droneId] {
            encounter.metadata["homeLat"] = String(latitude)
            encounter.metadata["homeLon"] = String(longitude)
            encounters[droneId] = encounter
            saveToStorage()
        }
    }

    
    
    func updateProximityPointsWithCorrectRadius() {
        for (id, encounter) in encounters {
            if encounter.metadata["hasProximityPoints"] == "true" {
                var updatedEncounter = encounter
                var updatedFlightPath: [FlightPathPoint] = []
                
                for point in encounter.flightPath {
                    if point.isProximityPoint {
                        var radius: Double
                        
                        // Calculate from RSSI if needed
                        if let rssi = point.proximityRssi, (point.proximityRadius == nil || point.proximityRadius == 0) {
                            let generator = DroneSignatureGenerator()
                            radius = generator.calculateDistance(rssi)
                            
                            // Ensure minimum radius - TODO decide if needede
                            
                            radius = max(radius, 50.0)
                            
                            // Create new point with calculated radius
                            let updatedPoint = FlightPathPoint(
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
                            updatedFlightPath.append(updatedPoint)
                        } else {
                            updatedFlightPath.append(point)
                        }
                    } else {
                        updatedFlightPath.append(point)
                    }
                }
                
                if updatedFlightPath.count > 0 {
                    updatedEncounter.flightPath = updatedFlightPath
                    encounters[id] = updatedEncounter
                }
            }
        }
        saveToStorage()
    }
    
    func exportToCSV() -> String {
        var csv = DroneEncounter.csvHeaders() + "\n"
        
        for encounter in encounters.values {
            csv += encounter.toCSVRow() + "\n"
        }
        
        return csv
    }
    
    func shareCSV(from viewController: UIViewController? = nil) {
        // Build CSV content using our existing functions
        var csvContent = DroneEncounter.csvHeaders() + "\n"
        let sortedEncounters = encounters.values.sorted { $0.lastSeen > $1.lastSeen }
        
        for encounter in sortedEncounters {
            csvContent += encounter.toCSVRow() + "\n"
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date()).replacingOccurrences(of: ":", with: "_")
        let filename = "drone_encounters_\(timestamp).csv"
        
        // Create a temporary file URL to store the CSV data
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        // Write CSV data to the file
        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Failed to write CSV data to file: \(error)")
            return
        }
        
        let csvDataItem = CSVDataItem(fileURL: fileURL, filename: filename)
        
        let activityVC = UIActivityViewController(
            activityItems: [csvDataItem],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                activityVC.popoverPresentationController?.sourceView = window
                activityVC.popoverPresentationController?.sourceRect = CGRect(
                    x: window.bounds.midX,
                    y: window.bounds.midY,
                    width: 0,
                    height: 0
                )
                activityVC.popoverPresentationController?.permittedArrowDirections = []
            }
            
            DispatchQueue.main.async {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
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
