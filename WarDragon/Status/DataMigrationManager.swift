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
                logger.warning("🔄 Data inconsistency detected - will attempt to re-migrate WITHOUT creating new backup")
                
                // Don't reset flag here - just continue with migration
                // This prevents creating duplicate backups on retry
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
        var skippedCount = 0
        var errorCount = 0
        
        for (_, encounter) in legacyEncounters {
            do {
                // Check if already exists
                let predicate = #Predicate<StoredDroneEncounter> { stored in
                    stored.id == encounter.id
                }
                let descriptor = FetchDescriptor(predicate: predicate)
                
                if try modelContext.fetch(descriptor).first != nil {
                    logger.info("Encounter \(encounter.id) already exists, skipping duplicate...")
                    skippedCount += 1
                    // Skip duplicates - the existing one is already in SwiftData
                    // If you need to update, delete and re-create instead of appending
                } else {
                    // Create new - this now safely builds arrays first
                    let stored = StoredDroneEncounter.from(legacy: encounter, context: modelContext)
                    modelContext.insert(stored)
                    migratedCount += 1
                }
                
                // Save periodically to avoid memory issues
                if (migratedCount + skippedCount) % 50 == 0 {
                    try modelContext.save()
                    logger.info("Saved batch: \(migratedCount) migrated, \(skippedCount) skipped (total \(migratedCount + skippedCount)/\(legacyEncounters.count))")
                }
            } catch {
                errorCount += 1
                logger.error("Failed to migrate encounter \(encounter.id): \(error.localizedDescription)")
                // Continue with other encounters rather than failing completely
                // This ensures partial migration succeeds
            }
        }
        
        // Final save
        do {
            try modelContext.save()
            logger.info("✅ Migration complete: \(migratedCount) migrated, \(skippedCount) skipped, \(errorCount) errors")
            
            if errorCount > 0 {
                logger.warning("⚠️ Some encounters failed to migrate, but others succeeded")
            }
        } catch {
            logger.error("❌ Final save failed: \(error.localizedDescription)")
            throw error
        }
        
        // Keep UserDefaults as backup for now (will clean up later after verification)
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
    /// Returns existing recent backup if one exists (within last hour), or creates new one
    func createBackup(forceNew: Bool = false) throws -> URL {
        logger.info("Creating data backup...")
        
        // Check for existing recent backup (within last hour) unless forced
        if !forceNew {
            let backupFiles = try? listBackupFiles()
            let recentBackups = backupFiles?.filter { url in
                url.lastPathComponent.hasPrefix("wardragon_backup_") &&
                (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate?
                    .timeIntervalSinceNow ?? -Double.infinity > -3600 // Within last hour
            } ?? []
            
            if let existingBackup = recentBackups.first {
                logger.info("Using existing recent backup: \(existingBackup.lastPathComponent)")
                return existingBackup
            }
        }
        
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
    
    /// Export current SwiftData database to JSON backup
    func exportSwiftDataBackup(modelContext: ModelContext) throws -> URL {
        logger.info("Exporting SwiftData backup...")
        
        let descriptor = FetchDescriptor<StoredDroneEncounter>(
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)]
        )
        let encounters = try modelContext.fetch(descriptor)
        
        // Convert to legacy format for JSON serialization
        let legacyEncounters = encounters.map { $0.toLegacy() }
        let encountersDict = Dictionary(uniqueKeysWithValues: legacyEncounters.map { ($0.id, $0) })
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(encountersDict)
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsPath.appendingPathComponent("wardragon_swiftdata_export_\(Int(Date().timeIntervalSince1970)).json")
        
        try jsonData.write(to: backupURL)
        logger.info("SwiftData export created at: \(backupURL.path) (\(encounters.count) encounters)")
        
        return backupURL
    }
    
    /// List all backup files in Documents directory
    func listBackupFiles() throws -> [URL] {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileManager = FileManager.default
        
        let files = try fileManager.contentsOfDirectory(
            at: documentsPath,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        
        // Filter for backup files
        let backupFiles = files.filter { url in
            url.lastPathComponent.hasPrefix("wardragon_backup_") ||
            url.lastPathComponent.hasPrefix("wardragon_swiftdata_export_")
        }
        
        // Sort by creation date (newest first)
        return backupFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
            return date1 > date2
        }
    }
    
    /// Delete a specific backup file
    func deleteBackup(at url: URL) throws {
        logger.info("Deleting backup: \(url.lastPathComponent)")
        try FileManager.default.removeItem(at: url)
    }
    
    /// Restore from a backup file (imports into SwiftData)
    func restoreFromBackup(backupURL: URL, modelContext: ModelContext) throws {
        logger.info("Restoring from backup: \(backupURL.lastPathComponent)")
        
        let jsonData = try Data(contentsOf: backupURL)
        
        // Try to decode as direct encounter dictionary first (SwiftData export format)
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let encounters = try decoder.decode([String: DroneEncounter].self, from: jsonData)
            
            logger.info("Found \(encounters.count) encounters in backup")
            
            // Import each encounter
            var importedCount = 0
            for (_, encounter) in encounters {
                let stored = StoredDroneEncounter.from(legacy: encounter, context: modelContext)
                modelContext.insert(stored)
                importedCount += 1
            }
            
            try modelContext.save()
            logger.info("✅ Successfully restored \(importedCount) encounters from backup")
            
        } catch {
            // Try legacy backup format with base64-encoded data
            logger.info("Trying legacy backup format...")
            
            let backupDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            guard let encountersBase64 = backupDict?["droneEncounters"] as? String,
                  let encountersData = Data(base64Encoded: encountersBase64) else {
                throw MigrationError.invalidData
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let encounters = try decoder.decode([String: DroneEncounter].self, from: encountersData)
            
            logger.info("Found \(encounters.count) encounters in legacy backup")
            
            var importedCount = 0
            for (_, encounter) in encounters {
                let stored = StoredDroneEncounter.from(legacy: encounter, context: modelContext)
                modelContext.insert(stored)
                importedCount += 1
            }
            
            try modelContext.save()
            logger.info("✅ Successfully restored \(importedCount) encounters from legacy backup")
        }
    }
    
    /// Get database statistics
    func getDatabaseStats(modelContext: ModelContext) throws -> DatabaseStats {
        let encounterDescriptor = FetchDescriptor<StoredDroneEncounter>()
        let encounterCount = try modelContext.fetchCount(encounterDescriptor)
        
        let pointDescriptor = FetchDescriptor<StoredFlightPoint>()
        let pointCount = try modelContext.fetchCount(pointDescriptor)
        
        let signatureDescriptor = FetchDescriptor<StoredSignature>()
        let signatureCount = try modelContext.fetchCount(signatureDescriptor)
        
        // Calculate database file size
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let storeURL = appSupportURL.appendingPathComponent("default.store")
        
        var databaseSize: Int64 = 0
        if fileManager.fileExists(atPath: storeURL.path) {
            let attributes = try? fileManager.attributesOfItem(atPath: storeURL.path)
            databaseSize = attributes?[.size] as? Int64 ?? 0
        }
        
        return DatabaseStats(
            encounterCount: encounterCount,
            flightPointCount: pointCount,
            signatureCount: signatureCount,
            databaseSizeBytes: databaseSize
        )
    }
    
    /// Delete all SwiftData (for complete reset)
    func deleteAllSwiftData(modelContext: ModelContext) throws {
        logger.warning("Deleting all SwiftData...")
        
        // Delete all encounters (cascade will handle relationships)
        let descriptor = FetchDescriptor<StoredDroneEncounter>()
        let encounters = try modelContext.fetch(descriptor)
        
        for encounter in encounters {
            modelContext.delete(encounter)
        }
        
        try modelContext.save()
        logger.info("✅ Deleted \(encounters.count) encounters from SwiftData")
    }
}

struct DatabaseStats {
    let encounterCount: Int
    let flightPointCount: Int
    let signatureCount: Int
    let databaseSizeBytes: Int64
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: databaseSizeBytes)
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
