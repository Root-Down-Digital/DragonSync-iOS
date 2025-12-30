//
//  DataMigrationManager.swift
//  WarDragon
//
//  Handles migration from UserDefaults to SwiftData
//

import Foundation
import SwiftData
import OSLog

@MainActor
class DataMigrationManager {
    static let shared = DataMigrationManager()
    
    private let logger = Logger(subsystem: "com.wardragon", category: "Migration")
    private let migrationCompletedKey = "DataMigration_UserDefaultsToSwiftData_Completed"
    private let migrationVersionKey = "DataMigration_Version"
    private let currentMigrationVersion = 1
    
    private init() {}
    
    /// Check if migration is needed
    var needsMigration: Bool {
        let completed = UserDefaults.standard.bool(forKey: migrationCompletedKey)
        let version = UserDefaults.standard.integer(forKey: migrationVersionKey)
        let needed = !completed || version < currentMigrationVersion
        
        if needed {
            logger.info("Migration needed: completed=\(completed), version=\(version), current=\(self.currentMigrationVersion)")
        } else {
            logger.debug("Migration already completed: version=\(version)")
        }
        
        return needed
    }
    
    /// Get current migration status (for debugging/settings)
    var migrationStatus: String {
        let completed = UserDefaults.standard.bool(forKey: migrationCompletedKey)
        let version = UserDefaults.standard.integer(forKey: migrationVersionKey)
        
        if !completed {
            return "Not migrated"
        } else if version < currentMigrationVersion {
            return "Needs update (v\(version) → v\(currentMigrationVersion))"
        } else {
            return "Completed (v\(version))"
        }
    }
    
    /// Perform full migration from UserDefaults to SwiftData
    func migrate(modelContext: ModelContext) async throws {
        // Check if migration flag is set
        if !needsMigration {
            logger.info("Migration flag indicates completion - verifying data...")
            
            // Verify SwiftData actually has data
            let descriptor = FetchDescriptor<StoredDroneEncounter>()
            let count = try modelContext.fetchCount(descriptor)
            
            // Check if UserDefaults has data that SwiftData doesn't
            if let data = UserDefaults.standard.data(forKey: "DroneEncounters"),
               let legacyEncounters = try? JSONDecoder().decode([String: DroneEncounter].self, from: data),
               !legacyEncounters.isEmpty && count == 0 {
                logger.warning("⚠️ Migration marked complete but SwiftData is empty while UserDefaults has \(legacyEncounters.count) encounters")
                logger.warning("🔄 Re-running migration to fix data inconsistency...")
                
                // Reset migration flag to force re-migration
                UserDefaults.standard.set(false, forKey: migrationCompletedKey)
                UserDefaults.standard.synchronize()
            } else {
                if count > 0 {
                    logger.info("✅ Data verification passed - SwiftData has \(count) encounters")
                } else {
                    logger.info("✅ Data verification passed - both SwiftData and UserDefaults are empty (clean state)")
                }
                return
            }
        }
        
        logger.info("Starting data migration (version \(self.currentMigrationVersion))...")
        
        do {
            // Migrate drone encounters
            try await migrateDroneEncounters(modelContext: modelContext)
            
            // Migrate ADS-B encounters
            try await migrateADSBEncounters(modelContext: modelContext)
            
            // CRITICAL: Mark migration as complete BEFORE returning
            // This ensures we don't re-run migration even if there was no data
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
            UserDefaults.standard.synchronize() // Force immediate save
            
            logger.info("✅ Migration completed successfully - will not run again")
        } catch {
            logger.error("❌ Migration failed: \(error.localizedDescription)")
            // Don't mark as complete if migration failed - will retry next launch
            throw MigrationError.migrationFailed(error)
        }
    }
    
    /// Migrate drone encounters from UserDefaults to SwiftData
    private func migrateDroneEncounters(modelContext: ModelContext) async throws {
        logger.info("Migrating drone encounters...")
        
        // Load from UserDefaults
        guard let data = UserDefaults.standard.data(forKey: "DroneEncounters"),
              let legacyEncounters = try? JSONDecoder().decode([String: DroneEncounter].self, from: data) else {
            logger.info("No drone encounters to migrate")
            return
        }
        
        logger.info("Found \(legacyEncounters.count) encounters to migrate")
        
        var migratedCount = 0
        for (_, encounter) in legacyEncounters {
            // Check if already exists
            let predicate = #Predicate<StoredDroneEncounter> { stored in
                stored.id == encounter.id
            }
            let descriptor = FetchDescriptor(predicate: predicate)
            
            if let existing = try modelContext.fetch(descriptor).first {
                logger.info("Encounter \(encounter.id) already exists, updating...")
                // Update existing
                existing.lastSeen = encounter.lastSeen
                existing.customName = encounter.customName
                existing.trustStatusRaw = encounter.trustStatus.rawValue
                existing.metadata = encounter.metadata
                existing.macAddresses = Array(encounter.macHistory)
                
                // Clear old relationships
                existing.flightPoints.removeAll()
                existing.signatures.removeAll()
                
                // Add new data
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
                    existing.flightPoints.append(storedPoint)
                }
                
                for sig in encounter.signatures {
                    let storedSig = StoredSignature(
                        timestamp: sig.timestamp,
                        rssi: sig.rssi,
                        speed: sig.speed,
                        height: sig.height,
                        mac: sig.mac
                    )
                    existing.signatures.append(storedSig)
                }
            } else {
                // Create new
                let stored = StoredDroneEncounter.from(legacy: encounter, context: modelContext)
                modelContext.insert(stored)
            }
            
            migratedCount += 1
            
            // Save periodically to avoid memory issues
            if migratedCount % 50 == 0 {
                try modelContext.save()
                logger.info("Saved batch of encounters (\(migratedCount)/\(legacyEncounters.count))")
            }
        }
        
        // Final save
        try modelContext.save()
        logger.info("Successfully migrated \(migratedCount) drone encounters")
        
        // Keep UserDefaults as backup for now (will clean up later)
        // UserDefaults.standard.removeObject(forKey: "DroneEncounters")
    }
    
    /// Migrate ADS-B encounters
    private func migrateADSBEncounters(modelContext: ModelContext) async throws {
        logger.info("Migrating ADS-B encounters...")
        
        // Note: ADS-B encounters are currently in-memory only in StatusViewModel
        // This is a placeholder for when we add persistent storage for them
        
        // For now, we'll just log that there's nothing to migrate from UserDefaults
        logger.info("ADS-B encounters are in-memory only, no migration needed")
    }
    
    /// Clean up old UserDefaults data (call this after verifying migration)
    func cleanupLegacyData() {
        logger.info("Cleaning up legacy UserDefaults data...")
        
        UserDefaults.standard.removeObject(forKey: "DroneEncounters")
        
        logger.info("Legacy data cleanup complete")
    }
    
    /// Rollback migration (for testing/debugging)
    func rollback() {
        logger.warning("Rolling back migration...")
        UserDefaults.standard.set(false, forKey: migrationCompletedKey)
        UserDefaults.standard.set(0, forKey: migrationVersionKey)
        UserDefaults.standard.synchronize()
        logger.info("Migration rolled back - will run again on next launch")
    }
    
    /// Force mark migration as complete (for troubleshooting)
    func forceComplete() {
        logger.warning("Force marking migration as complete...")
        UserDefaults.standard.set(true, forKey: migrationCompletedKey)
        UserDefaults.standard.set(currentMigrationVersion, forKey: migrationVersionKey)
        UserDefaults.standard.synchronize()
        logger.info("Migration marked complete")
    }
    
    /// Export all data as JSON backup before migration
    func createBackup() throws -> URL {
        logger.info("Creating data backup...")
        
        var backupData: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970,
            "migrationVersion": currentMigrationVersion
        ]
        
        // Safely handle potentially nil data
        if let encountersData = UserDefaults.standard.data(forKey: "DroneEncounters") {
            // Convert data to base64 string for safe JSON serialization
            backupData["droneEncounters"] = encountersData.base64EncodedString()
        } else {
            backupData["droneEncounters"] = NSNull()
            logger.info("No drone encounters data found to backup")
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: backupData, options: .prettyPrinted)
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsPath.appendingPathComponent("wardragon_backup_\(Int(Date().timeIntervalSince1970)).json")
        
        try jsonData.write(to: backupURL)
        logger.info("Backup created at: \(backupURL.path)")
        
        return backupURL
    }
}

enum MigrationError: LocalizedError {
    case migrationFailed(Error)
    case backupFailed(Error)
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .migrationFailed(let error):
            return "Migration failed: \(error.localizedDescription)"
        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"
        case .invalidData:
            return "Invalid data format in UserDefaults"
        }
    }
}
