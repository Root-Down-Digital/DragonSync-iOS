//
//  SwiftDataStorageManager.swift
//  WarDragon
//
//  New storage manager using SwiftData instead of UserDefaults
//

import Foundation
import SwiftData
import CoreLocation
import UIKit
import OSLog

@MainActor
class SwiftDataStorageManager: ObservableObject {
    static let shared = SwiftDataStorageManager()
    
    private let logger = Logger(subsystem: "com.wardragon", category: "Storage")
    var cotViewModel: CoTViewModel?
    
    @Published private(set) var encounters: [String: DroneEncounter] = [:]
    
    // Reference to model context (will be set from ContentView)
    var modelContext: ModelContext?
    
    private init() {}
    
    // MARK: - Save Operations
    
    func saveEncounter(_ message: CoTViewModel.CoTMessage, monitorStatus: StatusViewModel.StatusMessage? = nil) {
        guard let context = modelContext else {
            logger.error("ModelContext not set")
            return
        }
        
        let lat = Double(message.lat) ?? 0
        let lon = Double(message.lon) ?? 0
        let droneId = message.uid
        
        var targetId: String = droneId
        
        // Check for existing encounter by MAC or CAA
        if let mac = message.mac, !mac.isEmpty {
            if let existing = findEncounterByMAC(mac, context: context) {
                targetId = existing.id
            }
        } else if message.idType.contains("CAA"), let caaReg = message.caaRegistration {
            if let existing = findEncounterByCAA(caaReg, context: context) {
                targetId = existing.id
            }
        }
        
        // Fetch or create encounter
        let encounter = fetchOrCreateEncounter(id: targetId, message: message, context: context)
        
        // Add flight point if valid
        var didAddPoint = false
        if lat != 0 || lon != 0 {
            let newPoint = StoredFlightPoint(
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
            
            if let lastPoint = encounter.flightPoints.last {
                let distance = calculateDistance(
                    from: CLLocationCoordinate2D(latitude: lastPoint.latitude, longitude: lastPoint.longitude),
                    to: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                let timeGap = newPoint.timestamp - lastPoint.timestamp
                
                if distance > 0.1 || timeGap > 2 {
                    encounter.flightPoints.append(newPoint)
                    didAddPoint = true
                }
            } else {
                encounter.flightPoints.append(newPoint)
                didAddPoint = true
            }
        }
        
        // Add proximity point if no flight point added
        if !didAddPoint && message.rssi != nil && message.rssi != 0 {
            if let monitorStatus = monitorStatus {
                let currentCount = Int(encounter.metadata["totalDetections"] ?? "0") ?? 0
                encounter.metadata["totalDetections"] = "\(currentCount + 1)"
                
                let proximityPoint = StoredFlightPoint(
                    latitude: monitorStatus.gpsData.latitude,
                    longitude: monitorStatus.gpsData.longitude,
                    altitude: 0,
                    timestamp: Date().timeIntervalSince1970,
                    homeLatitude: Double(message.homeLat),
                    homeLongitude: Double(message.homeLon),
                    isProximityPoint: true,
                    proximityRssi: Double(message.rssi!),
                    proximityRadius: nil
                )
                
                let proximityPoints = encounter.flightPoints.filter { $0.isProximityPoint && $0.proximityRssi != nil }
                
                if proximityPoints.count < 3 {
                    encounter.flightPoints.append(proximityPoint)
                    encounter.metadata["hasProximityPoints"] = "true"
                } else {
                    // Replace middle proximity point
                    let rssiValues = proximityPoints.compactMap { $0.proximityRssi }
                    let minRssi = rssiValues.min() ?? Double(message.rssi!)
                    let maxRssi = rssiValues.max() ?? Double(message.rssi!)
                    
                    if let replaceIndex = encounter.flightPoints.firstIndex(where: { point in
                        point.isProximityPoint && point.proximityRssi != nil &&
                        point.proximityRssi != minRssi && point.proximityRssi != maxRssi
                    }) {
                        encounter.flightPoints[replaceIndex] = proximityPoint
                    }
                }
            }
        }
        
        // Track MAC addresses
        for source in message.signalSources {
            if !source.mac.isEmpty && !encounter.macAddresses.contains(source.mac) {
                encounter.macAddresses.append(source.mac)
            }
        }
        if let mac = message.mac, !mac.isEmpty && !encounter.macAddresses.contains(mac) {
            encounter.macAddresses.append(mac)
        }
        
        // Add signature
        if let rssi = message.rssi, rssi != 0 {
            let sig = StoredSignature(
                timestamp: Date().timeIntervalSince1970,
                rssi: Double(rssi),
                speed: Double(message.speed) ?? 0.0,
                height: Double(message.height ?? "0.0") ?? 0.0,
                mac: message.mac
            )
            encounter.signatures.append(sig)
            
            // Limit signatures to prevent bloat
            if encounter.signatures.count > 500 {
                let toRemove = encounter.signatures.prefix(100)
                toRemove.forEach { context.delete($0) }
            }
        }
        
        // Update metadata
        updateMetadata(encounter: encounter, message: message)
        
        // Update last seen
        encounter.lastSeen = Date()
        
        // Save context
        do {
            try context.save()
            logger.debug("Saved encounter: \(encounter.id)")
            
            // Update in-memory cache for backward compatibility
            updateInMemoryCache()
        } catch {
            logger.error("Failed to save encounter: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Query Operations
    
    func fetchAllEncounters() -> [StoredDroneEncounter] {
        guard let context = modelContext else { return [] }
        
        let descriptor = FetchDescriptor<StoredDroneEncounter>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch encounters: \(error.localizedDescription)")
            return []
        }
    }
    
    func fetchEncounter(id: String) -> StoredDroneEncounter? {
        guard let context = modelContext else { return nil }
        
        let predicate = #Predicate<StoredDroneEncounter> { encounter in
            encounter.id == id
        }
        let descriptor = FetchDescriptor(predicate: predicate)
        
        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch encounter \(id): \(error.localizedDescription)")
            return nil
        }
    }
    
    func deleteEncounter(id: String) {
        guard let context = modelContext else { return }
        
        if let encounter = fetchEncounter(id: id) {
            context.delete(encounter)
            
            do {
                try context.save()
                updateInMemoryCache()
                logger.info("Deleted encounter: \(id)")
            } catch {
                logger.error("Failed to delete encounter: \(error.localizedDescription)")
            }
        }
    }
    
    func deleteAllEncounters() {
        guard let context = modelContext else { return }
        
        do {
            // Fetch all encounters fresh from context to ensure we have valid references
            let descriptor = FetchDescriptor<StoredDroneEncounter>()
            let encounters = try context.fetch(descriptor)
            
            logger.info("🗑️ Deleting \(encounters.count) drone encounters...")
            
            // Delete all encounters
            for encounter in encounters {
                context.delete(encounter)
            }
            
            // Save the deletions
            try context.save()
            
            // Update in-memory cache after successful save
            updateInMemoryCache()
            
            logger.info("Successfully deleted all encounters")
        } catch {
            logger.error("❌ Failed to delete all encounters: \(error.localizedDescription)")
            
            // Even if deletion failed, try to sync in-memory cache with actual state
            updateInMemoryCache()
        }
    }
    
    func updateDroneInfo(id: String, name: String, trustStatus: DroneSignature.UserDefinedInfo.TrustStatus) {
        guard let encounter = fetchEncounter(id: id) else { return }
        
        encounter.customName = name
        encounter.trustStatus = trustStatus
        
        do {
            try modelContext?.save()
            updateInMemoryCache()
            
            // Notify CoTViewModel
            NotificationCenter.default.post(
                name: Notification.Name("DroneInfoUpdated"),
                object: nil,
                userInfo: ["droneId": id, "customName": name, "trustStatus": trustStatus.rawValue]
            )
            
            logger.info("Updated drone info: \(id)")
        } catch {
            logger.error("Failed to update drone info: \(error.localizedDescription)")
        }
    }
    
    func markAsDoNotTrack(id: String) {
        let baseId = id.replacingOccurrences(of: "drone-", with: "")
        let possibleIds = [id, "drone-\(id)", baseId, "drone-\(baseId)"]
        
        for possibleId in possibleIds {
            if let encounter = fetchEncounter(id: possibleId) {
                encounter.metadata["doNotTrack"] = "true"
            }
        }
        
        do {
            try modelContext?.save()
            logger.info("Marked as do not track: \(possibleIds)")
        } catch {
            logger.error("Failed to mark as do not track: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Export Operations
    
    func exportToCSV() -> String {
        let encounters = fetchAllEncounters()
        var csv = DroneEncounter.csvHeaders() + "\n"
        
        for encounter in encounters {
            let legacy = encounter.toLegacy()
            csv += legacy.toCSVRow() + "\n"
        }
        
        return csv
    }
    
    func shareCSV(from viewController: UIViewController? = nil) {
        let csvContent = exportToCSV()
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let filename = "drone_encounters_\(timestamp).csv"
        
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileURL = tempDirectory.appendingPathComponent(filename)
        
        do {
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            logger.error("Failed to write CSV: \(error.localizedDescription)")
            return
        }
        
        let csvDataItem = DroneStorageManager.CSVDataItem(fileURL: fileURL, filename: filename)
        let activityVC = UIActivityViewController(activityItems: [csvDataItem], applicationActivities: nil)
        
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
            }
            
            DispatchQueue.main.async {
                window.rootViewController?.present(activityVC, animated: true)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func findEncounterByMAC(_ mac: String, context: ModelContext) -> StoredDroneEncounter? {
        let descriptor = FetchDescriptor<StoredDroneEncounter>()
        
        do {
            let all = try context.fetch(descriptor)
            return all.first { $0.macAddresses.contains(mac) }
        } catch {
            return nil
        }
    }
    
    private func findEncounterByCAA(_ caaReg: String, context: ModelContext) -> StoredDroneEncounter? {
        let descriptor = FetchDescriptor<StoredDroneEncounter>()
        
        do {
            let all = try context.fetch(descriptor)
            return all.first { $0.metadata["caaRegistration"] == caaReg }
        } catch {
            return nil
        }
    }
    
    private func fetchOrCreateEncounter(id: String, message: CoTViewModel.CoTMessage, context: ModelContext) -> StoredDroneEncounter {
        if let existing = fetchEncounter(id: id) {
            return existing
        }
        
        let new = StoredDroneEncounter(
            id: id,
            firstSeen: Date(),
            lastSeen: Date(),
            customName: "",
            trustStatusRaw: "unknown",
            metadata: [:],
            macAddresses: []
        )
        context.insert(new)
        return new
    }
    
    private func updateMetadata(encounter: StoredDroneEncounter, message: CoTViewModel.CoTMessage) {
        var metadata = encounter.metadata
        
        if let mac = message.mac {
            metadata["mac"] = mac
        }
        if let caaReg = message.caaRegistration {
            metadata["caaRegistration"] = caaReg
        }
        if let manufacturer = message.manufacturer {
            metadata["manufacturer"] = manufacturer
        }
        metadata["idType"] = message.idType
        
        // Update pilot location
        if let pilotLat = Double(message.pilotLat), let pilotLon = Double(message.pilotLon),
           pilotLat != 0 && pilotLon != 0 {
            let newCoordKey = "\(pilotLat),\(pilotLon)"
            let currentCoordKey = metadata["pilotLat"].flatMap { lat in
                metadata["pilotLon"].map { lon in "\(lat),\(lon)" }
            }
            
            if currentCoordKey != newCoordKey {
                metadata["pilotLat"] = message.pilotLat
                metadata["pilotLon"] = message.pilotLon
                
                let timestamp = Date().timeIntervalSince1970
                let pilotEntry = "\(timestamp):\(pilotLat),\(pilotLon)"
                
                if let existingHistory = metadata["pilotHistory"] {
                    let existingEntries = Set(existingHistory.components(separatedBy: ";"))
                    if !existingEntries.contains(where: { $0.hasSuffix(":\(pilotLat),\(pilotLon)") }) {
                        metadata["pilotHistory"] = existingHistory + ";" + pilotEntry
                    }
                } else {
                    metadata["pilotHistory"] = pilotEntry
                }
            }
        }
        
        // Update home location
        if let homeLat = Double(message.homeLat), let homeLon = Double(message.homeLon),
           homeLat != 0 && homeLon != 0 {
            let newCoordKey = "\(homeLat),\(homeLon)"
            let currentCoordKey = metadata["homeLat"].flatMap { lat in
                metadata["homeLon"].map { lon in "\(lat),\(lon)" }
            }
            
            if currentCoordKey != newCoordKey {
                metadata["homeLat"] = message.homeLat
                metadata["homeLon"] = message.homeLon
                
                let timestamp = Date().timeIntervalSince1970
                let homeEntry = "\(timestamp):\(homeLat),\(homeLon)"
                
                if let existingHistory = metadata["homeHistory"] {
                    let existingEntries = Set(existingHistory.components(separatedBy: ";"))
                    if !existingEntries.contains(where: { $0.hasSuffix(":\(homeLat),\(homeLon)") }) {
                        metadata["homeHistory"] = existingHistory + ";" + homeEntry
                    }
                } else {
                    metadata["homeHistory"] = homeEntry
                }
            }
        }
        
        encounter.metadata = metadata
    }
    
    private func calculateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let location1 = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let location2 = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return location1.distance(from: location2)
    }
    
    private func updateInMemoryCache() {
        // Update the in-memory encounters dictionary for backward compatibility
        let stored = fetchAllEncounters()
        encounters = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.toLegacy()) })
    }
}
