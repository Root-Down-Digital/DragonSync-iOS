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
    var encounters: [String: DroneEncounter] = [:]
    var modelContext: ModelContext?
    private var macToIdCache: [String: String] = [:]
    private var caaToIdCache: [String: String] = [:]
    
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
                if point.latitude == 0 && point.longitude == 0 && !point.isProximityPoint {
                    logger.warning("Skipping invalid 0/0 flight point during saveEncounterDirect for \(encounter.id)")
                    continue
                }
                
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
        
        stored.updateCachedStats()
        
        needsSave = true
    }
    
    func saveEncounter(_ message: CoTViewModel.CoTMessage, monitorStatus: StatusViewModel.StatusMessage? = nil) {
        guard let context = modelContext else {
            logger.error("ModelContext not set")
            return
        }
        
        ensureTimerStarted()
        
        let lat = Double(message.lat) ?? 0
        let lon = Double(message.lon) ?? 0
        let droneId = message.uid
        
        var targetId: String = droneId
        
        logger.info("saveEncounter: Processing \(droneId), idType: \(message.idType), MAC: \(message.mac ?? "none")")
        
        if message.idType.contains("Serial Number") {
            logger.info("Serial Number detected - use serial \(droneId) as unique ID")
            targetId = droneId
        
            if let mac = message.mac, !mac.isEmpty {
                if let existingIdForMac = macToIdCache[mac], existingIdForMac != droneId {
                    logger.warning("MAC \(mac) was previously seen with serial \(existingIdForMac), now seen with \(droneId)")
                } else {
                    macToIdCache[mac] = droneId
                    logger.info("Cached MAC for serial: \(mac) -> \(droneId)")
                }
            }
        } else if message.idType.contains("CAA"), let caaReg = message.caaRegistration {
            if let cachedId = caaToIdCache[caaReg] {
                logger.info("Found CAA in cache: \(caaReg) -> \(cachedId)")
                targetId = cachedId
            } else if let existing = findEncounterByCAA(caaReg, context: context) {
                logger.info("Found CAA in database: \(caaReg) -> \(existing.id)")
                targetId = existing.id
                caaToIdCache[caaReg] = existing.id
            }
            
            if let mac = message.mac, !mac.isEmpty {
                macToIdCache[mac] = targetId
            }
        } else if let mac = message.mac, !mac.isEmpty {
            if let cachedId = macToIdCache[mac] {
                let existingEncounter = fetchEncounter(id: cachedId)
                let droneEncounter = fetchEncounter(id: droneId)
                
                if droneEncounter == nil {
                    logger.info("Using MAC from cache: \(mac) -> \(cachedId) (no existing encounter for \(droneId))")
                    targetId = cachedId
                } else if existingEncounter != nil, cachedId == droneId {
                    logger.info("MAC maps to same drone: \(mac) -> \(droneId)")
                    targetId = droneId
                } else {
                    logger.info("MAC conflict: \(mac) cached to \(cachedId) but drone \(droneId) exists - treating as separate drones")
                    targetId = droneId
                }
            } else if let existing = findEncounterByMAC(mac, context: context) {
                if existing.id == droneId {
                    logger.info("Found MAC in database: \(mac) -> \(existing.id)")
                    targetId = existing.id
                    macToIdCache[mac] = existing.id
                } else {
                    logger.info("MAC conflict: \(mac) exists for \(existing.id) but processing \(droneId) - treating as separate drones")
                    targetId = droneId
                }
            } else {
                macToIdCache[mac] = droneId
                logger.info("New MAC cached: \(mac) -> \(droneId)")
            }
        }
        
        if targetId != droneId {
            logger.info("Consolidating \(droneId) -> \(targetId)")
        }
        
        let encounter = fetchOrCreateEncounter(id: targetId, message: message, context: context)
        
        let now = Date()
        let sessionKey = createSessionKey(for: now)
        var sessionHistory = encounter.metadata["sessionHistory"] ?? ""
        let existingSessions = Set(sessionHistory.components(separatedBy: ";").filter { !$0.isEmpty })
        if !existingSessions.contains(sessionKey) {
            if sessionHistory.isEmpty {
                sessionHistory = sessionKey
            } else {
                sessionHistory += ";\(sessionKey)"
            }
            encounter.metadata["sessionHistory"] = sessionHistory
            logger.info("Added session \(sessionKey) to drone \(targetId)")
        }
        
        logDroneActivity(encounter: encounter, timestamp: now)

        var didAddPoint = false
        
        if lat == 0 && lon == 0 {
            logger.info("Skipping flight point for \(droneId): coordinates are 0/0, isFPV=\(message.isFPVDetection)")
        } else if message.isFPVDetection {
            logger.info("Skipping flight point for \(droneId): message is FPV detection")
        }
        
        if !(lat == 0 && lon == 0) && !message.isFPVDetection {
            logger.info("Adding regular flight point for \(droneId): lat=\(lat), lon=\(lon), isFPV=\(message.isFPVDetection)")
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
            
            let lastValidPoint = encounter.flightPoints.last(where: { 
                !($0.latitude == 0 && $0.longitude == 0) && !$0.isProximityPoint 
            })
            
            if let lastPoint = lastValidPoint {
                let distance = calculateDistance(
                    from: CLLocationCoordinate2D(latitude: lastPoint.latitude, longitude: lastPoint.longitude),
                    to: CLLocationCoordinate2D(latitude: lat, longitude: lon)
                )
                let timeGap = newPoint.timestamp - lastPoint.timestamp
                
                if distance > 0.1 || timeGap > 2 {
                    encounter.flightPoints.append(newPoint)
                    didAddPoint = true
                } else {
                    
                }
            } else {
                encounter.flightPoints.append(newPoint)
                didAddPoint = true
            }
        }
        
        // Add proximity point if no flight point added
        if !didAddPoint && message.rssi != nil && message.rssi != 0 {
            if let monitorStatus = monitorStatus {
                let monitorLat = monitorStatus.gpsData.latitude
                let monitorLon = monitorStatus.gpsData.longitude
                
                guard !(monitorLat == 0 && monitorLon == 0) else {
                    logger.warning("Skipping proximity point for \(droneId) - monitor has no GPS location (0/0)")
                    return
                }
                
                let currentCount = Int(encounter.metadata["totalDetections"] ?? "0") ?? 0
                encounter.metadata["totalDetections"] = "\(currentCount + 1)"
                
                let proximityPoint = StoredFlightPoint(
                    latitude: monitorLat,
                    longitude: monitorLon,
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
        
        if let mac = message.mac, !mac.isEmpty && !encounter.macAddresses.contains(mac) {
            encounter.macAddresses.append(mac)
            macToIdCache[mac] = encounter.id
        }
        for source in message.signalSources {
            if !source.mac.isEmpty && !encounter.macAddresses.contains(source.mac) {
                encounter.macAddresses.append(source.mac)
                macToIdCache[source.mac] = encounter.id
            }
        }
        
        if let rssi = message.rssi, rssi != 0 {
            let shouldAdd: Bool
            if let lastSig = encounter.signatures.last {
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
                
                if encounter.signatures.count > 500 {
                    let toRemove = Array(encounter.signatures.prefix(100))
                    toRemove.forEach { context.delete($0) }
                    encounter.signatures.removeFirst(100)
                }
            }
        }
        
        updateMetadata(encounter: encounter, message: message)
        encounter.lastSeen = Date()
        
        encounter.updateCachedStats()
        
        needsSave = true
        
        let shouldUpdateCache = didAddPoint || 
                               encounter.signatures.count > 0 || 
                               !message.isFPVDetection
        
        if shouldUpdateCache {
            let shouldNotify = didAddPoint || !message.isFPVDetection
            updateInMemoryCacheForEncounterFast(encounter, sendChangeNotification: shouldNotify)
        }
        
        if didAddPoint {
            Task { @MainActor in
                if let legacyEncounter = self.encounters[encounter.id] {
                    DroneStorageManager.shared.updateEncounterInCache(legacyEncounter)
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
            
            for encounter in encounters {
                context.delete(encounter)
            }
            
            try context.save()
            
            macToIdCache.removeAll()
            caaToIdCache.removeAll()
            
            self.encounters.removeAll()
            
            logger.info("Successfully deleted all encounters")
            
        } catch {
            logger.error("Failed to delete all encounters: \(error.localizedDescription)")
            
            do {
                let descriptor = FetchDescriptor<StoredDroneEncounter>()
                let remaining = try context.fetch(descriptor)
                
                var convertedEncounters: [String: DroneEncounter] = [:]
                for encounter in remaining {
                    guard encounter.modelContext != nil else {
                        continue
                    }
                    convertedEncounters[encounter.id] = encounter.toLegacyLightweight()
                }
                
                self.encounters = convertedEncounters
            } catch {
                self.encounters.removeAll()
                logger.error("Failed to update cache after deletion error, cleared cache")
            }
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
                logger.info(" Cleared do not track for: \(possibleId)")
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
                logger.info(" Cleared do not track for \(clearedCount) encounters")
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
        
        var descriptor = FetchDescriptor<StoredDroneEncounter>(
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        descriptor.relationshipKeyPathsForPrefetching = [
            \.flightPoints,
            \.signatures
        ]
        
        let allEncounters: [StoredDroneEncounter]
        do {
            allEncounters = try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch encounters for repair: \(error.localizedDescription)")
            return
        }
        
        var repairedCount = 0
        
        for encounter in allEncounters {
            let needsRepair = encounter.cachedFlightPointCount == 0 || 
                             encounter.cachedSignatureCount == 0
            
            if needsRepair {
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
                logger.info(" Repaired cached stats for \(repairedCount) encounters")
            } catch {
                logger.error("Failed to save repaired stats: \(error.localizedDescription)")
            }
        } else {
            logger.info(" All encounters have valid cached stats")
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
    
    private func createSessionKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH"
        return formatter.string(from: date)
    }
    
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
            logger.info("Found existing encounter for ID: \(id)")
            return existing
        }
        
        // Check if there's an in-memory encounter we should preserve data from
        let existingCustomName = encounters[id]?.customName ?? ""
        let existingTrustStatus = encounters[id]?.trustStatus ?? .unknown
        
        logger.info("Creating NEW encounter for ID: \(id), preserving customName: '\(existingCustomName)', trustStatus: \(existingTrustStatus.rawValue)")
        let new = StoredDroneEncounter(
            id: id,
            firstSeen: Date(),
            lastSeen: Date(),
            customName: existingCustomName,
            trustStatusRaw: existingTrustStatus.rawValue,
            metadata: [:],
            macAddresses: []
        )
        context.insert(new)
        logger.info("Successfully created and inserted new encounter: \(id)")
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
    
    /// Log when drone was actively transmitting data
    private func logDroneActivity(encounter: StoredDroneEncounter, timestamp: Date) {
        var logs = encounter.activityLog
        
        if let lastIndex = logs.indices.last, timestamp.timeIntervalSince(logs[lastIndex].endTime) < 120 {
            logs[lastIndex].endTime = timestamp
            logger.info("Extended activity log for \(encounter.id) to \(timestamp)")
        } else {
            let entry = ActivityLogEntry(startTime: timestamp, endTime: timestamp)
            logs.append(entry)
            logger.info("Added new activity log entry for \(encounter.id) at \(timestamp)")
        }
        
        encounter.activityLog = logs
    }
    
    private func updateInMemoryCache() {
        let stored = fetchAllEncounters()
        
        var convertedEncounters: [String: DroneEncounter] = [:]
        for encounter in stored {
            guard encounter.modelContext != nil else {
                logger.warning("Skipping deleted/detached encounter \(encounter.id) during cache update")
                continue
            }
            
            convertedEncounters[encounter.id] = encounter.toLegacyLightweight()
        }
        
        self.encounters = convertedEncounters
        
        // Manually notify observers since encounters is not @Published
        Task { @MainActor in
            self.objectWillChange.send()
            DroneStorageManager.shared.objectWillChange.send()
        }
    }
    
    private func updateInMemoryCacheForEncounter(_ encounter: StoredDroneEncounter) {
        guard encounter.modelContext != nil else {
            logger.warning("Skipping deleted/detached encounter \(encounter.id) in updateInMemoryCacheForEncounter")
            return
        }
        encounters[encounter.id] = encounter.toLegacyLightweight()
        
        // Manually notify observers since encounters is not @Published
        Task { @MainActor in
            self.objectWillChange.send()
            DroneStorageManager.shared.objectWillChange.send()
        }
    }
    
    private func updateInMemoryCacheForEncounterFast(_ encounter: StoredDroneEncounter, sendChangeNotification: Bool = true) {
        guard encounter.modelContext != nil else {
            logger.warning("Skipping deleted/detached encounter \(encounter.id) in updateInMemoryCacheForEncounterFast")
            return
        }
        
        // Always update the dictionary (no longer @Published, so no auto-notification)
        encounters[encounter.id] = encounter.toLegacyLightweight()
        
        // Only manually notify observers when requested
        if sendChangeNotification {
            Task { @MainActor in
                // Notify both storage managers
                self.objectWillChange.send()
                DroneStorageManager.shared.objectWillChange.send()
            }
        }
    }
    
    // MARK: - Aircraft Storage Cleanup
    
    /// Cleanup old aircraft encounters to prevent database bloat
    func cleanupOldAircraftEncounters(maxAircraftCount: Int = 200) {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<StoredDroneEncounter>()
            let allEncounters = try context.fetch(descriptor)
            
            let aircraftEncounters = allEncounters.filter { $0.id.hasPrefix("aircraft-") }
            
            guard aircraftEncounters.count > maxAircraftCount else {
                logger.info("Aircraft cleanup not needed: \(aircraftEncounters.count)/\(maxAircraftCount) stored")
                return
            }
            
            let sortedAircraft = aircraftEncounters.sorted { $0.lastSeen < $1.lastSeen }
            
            let deleteCount = aircraftEncounters.count - maxAircraftCount
            let toDelete = sortedAircraft.prefix(deleteCount)
            
            logger.info("🗑️ Cleaning up \(deleteCount) old aircraft encounters (keeping \(maxAircraftCount) newest)...")
            
            for aircraft in toDelete {
                context.delete(aircraft)
            }
            
            try context.save()
            
            updateInMemoryCache()
            
            logger.info(" Deleted \(deleteCount) old aircraft encounters")
            
        } catch {
            logger.error("Aircraft cleanup failed: \(error.localizedDescription)")
        }
    }
    
    /// Delete all aircraft encounters (keeps drone encounters)
    /// Use this to clear aircraft history without affecting drone data
    func deleteAllAircraftEncounters() {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<StoredDroneEncounter>()
            let allEncounters = try context.fetch(descriptor)
            
            let aircraftEncounters = allEncounters.filter { $0.id.hasPrefix("aircraft-") }
            
            logger.info("🗑️ Deleting \(aircraftEncounters.count) aircraft encounters...")
            
            for aircraft in aircraftEncounters {
                context.delete(aircraft)
            }
            
            try context.save()
            updateInMemoryCache()
            
            logger.info(" Deleted all aircraft encounters (drones preserved)")
            
        } catch {
            logger.error("Failed to delete aircraft encounters: \(error.localizedDescription)")
        }
    }
    
    func backfillActivityLogsForAllEncounters() {
        guard UserDefaults.standard.bool(forKey: "activityLogBackfillCompleted") == false else {
            return
        }
        
        guard let context = modelContext else { return }
        
        do {
            var descriptor = FetchDescriptor<StoredDroneEncounter>()
            descriptor.relationshipKeyPathsForPrefetching = [\.flightPoints, \.signatures]
            
            let allEncounters = try context.fetch(descriptor)
            
            let encountersNeedingBackfill = allEncounters.filter { encounter in
                encounter.metadata["activityLog"] == nil || encounter.metadata["activityLog"]?.isEmpty == true
            }
            
            guard !encountersNeedingBackfill.isEmpty else {
                logger.info("No encounters need activity log backfill")
                UserDefaults.standard.set(true, forKey: "activityLogBackfillCompleted")
                return
            }
            
            logger.info("Backfilling activity logs for \(encountersNeedingBackfill.count) encounters...")
            
            for encounter in encountersNeedingBackfill {
                encounter.backfillActivityLog()
            }
            
            try context.save()
            UserDefaults.standard.set(true, forKey: "activityLogBackfillCompleted")
            logger.info("Successfully backfilled activity logs for \(encountersNeedingBackfill.count) encounters")
            
        } catch {
            logger.error("Failed to backfill activity logs: \(error.localizedDescription)")
        }
    }
    
    /// Remove any flight points with 0/0 coordinates from all encounters
    /// This cleans up invalid data that may have been saved before validation was added
    func cleanupInvalidFlightPoints() {
        guard UserDefaults.standard.bool(forKey: "invalidFlightPointsCleanupCompleted") == false else {
            logger.info("Invalid flight points cleanup already completed")
            return
        }
        
        guard let context = modelContext else { return }
        
        do {
            var descriptor = FetchDescriptor<StoredDroneEncounter>()
            descriptor.relationshipKeyPathsForPrefetching = [\.flightPoints]
            
            let allEncounters = try context.fetch(descriptor)
            
            var totalPointsRemoved = 0
            var encountersAffected = 0
            
            logger.info("🧹 Checking \(allEncounters.count) encounters for invalid 0/0 flight points...")
            
            for encounter in allEncounters {
                let invalidPoints = encounter.flightPoints.filter { point in
                    point.latitude == 0 && point.longitude == 0 && !point.isProximityPoint
                }
                
                if !invalidPoints.isEmpty {
                    logger.info("Removing \(invalidPoints.count) invalid points from encounter \(encounter.id)")
                    
                    for point in invalidPoints {
                        context.delete(point)
                        encounter.flightPoints.removeAll { $0.persistentModelID == point.persistentModelID }
                    }
                    
                    totalPointsRemoved += invalidPoints.count
                    encountersAffected += 1
                    
                    encounter.updateCachedStats()
                }
            }
            
            if totalPointsRemoved > 0 {
                try context.save()
                logger.info("✅ Removed \(totalPointsRemoved) invalid flight points from \(encountersAffected) encounters")
            } else {
                logger.info("✅ No invalid flight points found")
            }
            
            UserDefaults.standard.set(true, forKey: "invalidFlightPointsCleanupCompleted")
            
            updateInMemoryCache()
            
        } catch {
            logger.error("Failed to cleanup invalid flight points: \(error.localizedDescription)")
        }
    }
}
