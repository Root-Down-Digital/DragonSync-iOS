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
    
    @Published var encounters: [String: DroneEncounter] = [:]
    
    // Reference to model context (will be set from ContentView)
    var modelContext: ModelContext?
    
    // Cache for MAC to ID lookups to avoid repeated database queries
    private var macToIdCache: [String: String] = [:]
    private var caaToIdCache: [String: String] = [:]
    
    // Batch saving optimization
    private var needsSave = false
    private var saveTimer: Timer?
    private var cacheUpdateCounter = 0
    
    nonisolated private init() {
        // Setup auto-save timer - will be initialized when first accessed
    }
    
    nonisolated private static func startTimer() -> Timer {
        let timer = Timer(timeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                SwiftDataStorageManager.shared.saveIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
    
    private func ensureTimerStarted() {
        if saveTimer == nil {
            Task { @MainActor in
                self.saveTimer = Self.startTimer()
            }
        }
    }
    
    private func saveIfNeeded() {
        guard needsSave, let context = modelContext else { return }
        
        do {
            try context.save()
            needsSave = false
            
            cacheUpdateCounter += 1
            if cacheUpdateCounter >= 5 {
                updateInMemoryCache()
                cacheUpdateCounter = 0
            }
        } catch {
            logger.error("Auto-save failed: \(error.localizedDescription)")
        }
    }
    
    func forceSave() {
        guard let context = modelContext else { return }
        do {
            try context.save()
            needsSave = false
            logger.info("Force saved all changes")
        } catch {
            logger.error("Force save failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Save Operations
    
    /// Save an encounter directly from the legacy DroneEncounter format
    /// This is optimized to avoid re-parsing and re-fetching
    func saveEncounterDirect(_ encounter: DroneEncounter) {
        guard let context = modelContext else {
            logger.error("ModelContext not set")
            return
        }
        
        // Fetch or create SwiftData encounter
        let stored = fetchOrCreateEncounter(id: encounter.id, message: nil, context: context)
        
        // Update scalar fields
        stored.firstSeen = encounter.firstSeen
        stored.lastSeen = encounter.lastSeen
        stored.customName = encounter.customName
        stored.trustStatus = encounter.trustStatus
        stored.metadata = encounter.metadata
        stored.macAddresses = Array(encounter.macHistory)
        
        // Only update flight points if count changed (optimization)
        if stored.flightPoints.count != encounter.flightPath.count {
            stored.flightPoints.forEach { context.delete($0) }
            stored.flightPoints.removeAll()
            
            for point in encounter.flightPath {
                let storedPoint = StoredFlightPoint(
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
                stored.flightPoints.append(storedPoint)
            }
        }
        
        // Only update signatures if count changed (optimization)
        if stored.signatures.count != encounter.signatures.count {
            stored.signatures.forEach { context.delete($0) }
            stored.signatures.removeAll()
            
            for sig in encounter.signatures {
                let storedSig = StoredSignature(
                    timestamp: sig.timestamp,
                    rssi: sig.rssi,
                    speed: sig.speed,
                    height: sig.height,
                    mac: sig.mac
                )
                stored.signatures.append(storedSig)
            }
        }
        
        // PERFORMANCE: Update cached stats after modifications
        stored.updateCachedStats()
        
        // Mark that we need to save
        needsSave = true
    }
    
    func saveEncounter(_ message: CoTViewModel.CoTMessage, monitorStatus: StatusViewModel.StatusMessage? = nil) {
        guard let context = modelContext else {
            logger.error("ModelContext not set")
            return
        }
        
        // Ensure timer is running
        ensureTimerStarted()
        
        let lat = Double(message.lat) ?? 0
        let lon = Double(message.lon) ?? 0
        let droneId = message.uid
        
        var targetId: String = droneId
        
        // Check cache first for MAC lookup (fast path)
        if let mac = message.mac, !mac.isEmpty {
            if let cachedId = macToIdCache[mac] {
                targetId = cachedId
            } else if let existing = findEncounterByMAC(mac, context: context) {
                targetId = existing.id
                macToIdCache[mac] = existing.id
            }
        } else if message.idType.contains("CAA"), let caaReg = message.caaRegistration {
            if let cachedId = caaToIdCache[caaReg] {
                targetId = cachedId
            } else if let existing = findEncounterByCAA(caaReg, context: context) {
                targetId = existing.id
                caaToIdCache[caaReg] = existing.id
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
                    print("✈️ FLIGHT PATH: Added point #\(encounter.flightPoints.count) for \(droneId) - Distance: \(String(format: "%.2f", distance))m, TimeGap: \(String(format: "%.1f", timeGap))s")
                } else {
                    print("⏭️ FLIGHT PATH: Skipped point for \(droneId) - Distance: \(String(format: "%.2f", distance))m, TimeGap: \(String(format: "%.1f", timeGap))s (too close)")
                }
            } else {
                encounter.flightPoints.append(newPoint)
                didAddPoint = true
                print("✈️ FLIGHT PATH: Added FIRST point for \(droneId)")
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
        
        // Track MAC addresses (optimize with Set)
        if let mac = message.mac, !mac.isEmpty && !encounter.macAddresses.contains(mac) {
            encounter.macAddresses.append(mac)
            macToIdCache[mac] = encounter.id // Update cache
        }
        for source in message.signalSources {
            if !source.mac.isEmpty && !encounter.macAddresses.contains(source.mac) {
                encounter.macAddresses.append(source.mac)
                macToIdCache[source.mac] = encounter.id // Update cache
            }
        }
        
        // Add signature (only if RSSI changed significantly to reduce bloat)
        if let rssi = message.rssi, rssi != 0 {
            let shouldAdd: Bool
            if let lastSig = encounter.signatures.last {
                // Only add if RSSI changed by 3dBm or time gap > 5 seconds
                let rssiDelta = abs(Double(rssi) - lastSig.rssi)
                let timeGap = Date().timeIntervalSince1970 - lastSig.timestamp
                shouldAdd = rssiDelta > 3.0 || timeGap > 5.0
            } else {
                shouldAdd = true
            }
            
            if shouldAdd {
                let sig = StoredSignature(
                    timestamp: Date().timeIntervalSince1970,
                    rssi: Double(rssi),
                    speed: Double(message.speed) ?? 0.0,
                    height: Double(message.height ?? "0.0") ?? 0.0,
                    mac: message.mac
                )
                encounter.signatures.append(sig)
                
                // Limit signatures to prevent bloat (batch delete for performance)
                if encounter.signatures.count > 500 {
                    let toRemove = Array(encounter.signatures.prefix(100))
                    toRemove.forEach { context.delete($0) }
                    encounter.signatures.removeFirst(100)
                }
            }
        }
        
        // Updates
        updateMetadata(encounter: encounter, message: message)
        encounter.lastSeen = Date()
        
        // PERFORMANCE: Update cached stats after modifications
        encounter.updateCachedStats()
        
        needsSave = true
        updateInMemoryCacheForEncounterFast(encounter)
        
        // Also update DroneStorageManager's cache immediately if a flight point was added
        if didAddPoint {
            Task { @MainActor in
                if let legacyEncounter = self.encounters[encounter.id] {
                    DroneStorageManager.shared.updateEncounterInCache(legacyEncounter)
//                    print("🔄 Updated DroneStorageManager cache for \(encounter.id) - Flight path now has \(legacyEncounter.flightPath.count) points")
                }
            }
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
    
    /// Fetch full encounter with all data (use for detail views)
    func fetchFullEncounter(id: String) -> DroneEncounter? {
        guard let stored = fetchEncounter(id: id) else { return nil }
        return stored.toLegacy()
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
            
            // Clear caches
            macToIdCache.removeAll()
            caaToIdCache.removeAll()
            
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
    
    func clearDoNotTrack(id: String) {
        let baseId = id.replacingOccurrences(of: "drone-", with: "")
        let possibleIds = [id, "drone-\(id)", baseId, "drone-\(baseId)"]
        
        var cleared = false
        for possibleId in possibleIds {
            if let encounter = fetchEncounter(id: possibleId) {
                encounter.metadata.removeValue(forKey: "doNotTrack")
                cleared = true
                logger.info("✅ Cleared do not track for: \(possibleId)")
            }
        }
        
        if cleared {
            do {
                try modelContext?.save()
                updateInMemoryCache()
                logger.info("Successfully cleared do not track for: \(possibleIds)")
            } catch {
                logger.error("Failed to save after clearing do not track: \(error.localizedDescription)")
            }
        } else {
            logger.warning("No encounter found to clear do not track: \(possibleIds)")
        }
    }
    
    func clearAllDoNotTrack() {
        let allEncounters = fetchAllEncounters()
        var clearedCount = 0
        
        for encounter in allEncounters {
            if encounter.metadata["doNotTrack"] != nil {
                encounter.metadata.removeValue(forKey: "doNotTrack")
                clearedCount += 1
            }
        }
        
        if clearedCount > 0 {
            do {
                try modelContext?.save()
                updateInMemoryCache()
                logger.info("✅ Cleared do not track for \(clearedCount) encounters")
            } catch {
                logger.error("Failed to save after clearing all do not track: \(error.localizedDescription)")
            }
        } else {
            logger.info("No encounters had do not track set")
        }
    }
    
    // MARK: - Export Operations
    
    /// Repair cached stats for all encounters that have missing or zero cached values
    /// This should be called on app startup or as a maintenance operation
    func repairCachedStats() {
        guard let context = modelContext else { return }
        
        // Fetch ALL encounters with relationships prefetched
        var descriptor = FetchDescriptor<StoredDroneEncounter>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        // Prefetch relationships to avoid faulting
        descriptor.relationshipKeyPathsForPrefetching = [
            \.flightPoints,
            \.signatures
        ]
        
        let allEncounters: [StoredDroneEncounter]
        do {
            allEncounters = try context.fetch(descriptor)
        } catch {
            logger.error("❌ Failed to fetch encounters for repair: \(error.localizedDescription)")
            return
        }
        
        var repairedCount = 0
        
        logger.info("🔧 Checking \(allEncounters.count) encounters for missing cached stats...")
        
        for encounter in allEncounters {
            // Safe check - just look at cached counts first
            let needsRepair = encounter.cachedFlightPointCount == 0 || 
                             encounter.cachedSignatureCount == 0
            
            if needsRepair {
                // Now that relationships are prefetched, this is safe
                encounter.updateCachedStats()
                repairedCount += 1
                
                if repairedCount % 10 == 0 {
                    logger.info("Repaired \(repairedCount) encounters so far...")
                }
            }
        }
        
        if repairedCount > 0 {
            do {
                try context.save()
                logger.info("✅ Repaired cached stats for \(repairedCount) encounters")
            } catch {
                logger.error("❌ Failed to save repaired stats: \(error.localizedDescription)")
            }
        } else {
            logger.info("✅ All encounters have valid cached stats")
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
    
    private func fetchOrCreateEncounter(id: String, message: CoTViewModel.CoTMessage?, context: ModelContext) -> StoredDroneEncounter {
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
        let stored = fetchAllEncounters()
        encounters = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0.toLegacyLightweight()) })
    }
    
    private func updateInMemoryCacheForEncounter(_ encounter: StoredDroneEncounter) {
        encounters[encounter.id] = encounter.toLegacyLightweight()
    }
    
    private func updateInMemoryCacheForEncounterFast(_ encounter: StoredDroneEncounter) {
        // Always update the full encounter data to keep flight path in sync
        // This is critical for UI to show updated flight paths
        encounters[encounter.id] = encounter.toLegacyLightweight()
        
        // Notify DroneStorageManager to update its cache too
        Task { @MainActor in
            DroneStorageManager.shared.objectWillChange.send()
        }
    }
    
    // MARK: - Aircraft Storage Cleanup
    
    /// Cleanup old aircraft encounters to prevent database bloat
    func cleanupOldAircraftEncounters(maxAircraftCount: Int = 200) {
        guard let context = modelContext else { return }
        
        do {
            // Fetch all encounters
            let descriptor = FetchDescriptor<StoredDroneEncounter>()
            let allEncounters = try context.fetch(descriptor)
            
            // Filter to aircraft only (IDs starting with "aircraft-")
            let aircraftEncounters = allEncounters.filter { $0.id.hasPrefix("aircraft-") }
            
            guard aircraftEncounters.count > maxAircraftCount else {
                logger.info("Aircraft cleanup not needed: \(aircraftEncounters.count)/\(maxAircraftCount) stored")
                return
            }
            
            // Sort by last seen (oldest first)
            let sortedAircraft = aircraftEncounters.sorted { $0.lastSeen < $1.lastSeen }
            
            // Calculate how many to delete
            let deleteCount = aircraftEncounters.count - maxAircraftCount
            let toDelete = sortedAircraft.prefix(deleteCount)
            
            logger.info("🗑️ Cleaning up \(deleteCount) old aircraft encounters (keeping \(maxAircraftCount) newest)...")
            
            // Delete old aircraft
            for aircraft in toDelete {
                context.delete(aircraft)
            }
            
            // Save deletions
            try context.save()
            
            // Update cache
            updateInMemoryCache()
            
            logger.info("✅ Deleted \(deleteCount) old aircraft encounters")
            
        } catch {
            logger.error("❌ Aircraft cleanup failed: \(error.localizedDescription)")
        }
    }
    
    /// Delete all aircraft encounters (keeps drone encounters)
    /// Use this to clear aircraft history without affecting drone data
    func deleteAllAircraftEncounters() {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<StoredDroneEncounter>()
            let allEncounters = try context.fetch(descriptor)
            
            // Filter to aircraft only
            let aircraftEncounters = allEncounters.filter { $0.id.hasPrefix("aircraft-") }
            
            logger.info("🗑️ Deleting \(aircraftEncounters.count) aircraft encounters...")
            
            for aircraft in aircraftEncounters {
                context.delete(aircraft)
            }
            
            try context.save()
            updateInMemoryCache()
            
            logger.info("✅ Deleted all aircraft encounters (drones preserved)")
            
        } catch {
            logger.error("❌ Failed to delete aircraft encounters: \(error.localizedDescription)")
        }
    }
}
