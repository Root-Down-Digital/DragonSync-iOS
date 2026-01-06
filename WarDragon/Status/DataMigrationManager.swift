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
    
    /// Helper to convert date decoding strategy to readable string
    private func strategyName(_ strategy: JSONDecoder.DateDecodingStrategy) -> String {
        switch strategy {
        case .iso8601:
            return "ISO8601"
        case .secondsSince1970:
            return "secondsSince1970"
        case .millisecondsSince1970:
            return "millisecondsSince1970"
        default:
            return "unknown"
        }
    }
    
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
            if let existingBackup = try findRecentValidBackup() {
                logger.info("✅ Using existing recent backup: \(existingBackup.lastPathComponent)")
                return existingBackup
            }
        }
        
        // Load UserDefaults data
        guard let encountersData = UserDefaults.standard.data(forKey: "DroneEncounters") else {
            logger.info("No drone encounters data found to backup - creating empty backup marker")
            return try createEmptyBackupMarker()
        }
        
        // Validate the data can be decoded before creating backup
        logger.info("Validating UserDefaults data before backup...")
        let isValid = validateUserDefaultsData(encountersData)
        if !isValid {
            logger.warning("⚠️ UserDefaults data appears corrupted - creating backup anyway for forensics")
        }
        
        // Create backup with validated format
        var backupData: [String: Any] = [
            "version": "1.0",
            "timestamp": Date().timeIntervalSince1970,
            "migrationVersion": currentMigrationVersion,
            "dataValid": isValid
        ]
        
        // Convert data to base64 string for safe JSON serialization
        let base64String = encountersData.base64EncodedString()
        backupData["droneEncounters"] = base64String
        backupData["droneEncountersSize"] = encountersData.count
        
        // Serialize to JSON
        let jsonData = try JSONSerialization.data(withJSONObject: backupData, options: .prettyPrinted)
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsPath.appendingPathComponent("wardragon_backup_\(Int(Date().timeIntervalSince1970)).json")
        
        // Write to file
        try jsonData.write(to: backupURL)
        
        // Immediately verify the backup can be read back
        do {
            try validateBackupFile(backupURL)
            logger.info("✅ Backup created and verified at: \(backupURL.lastPathComponent)")
        } catch {
            logger.error("❌ Backup verification failed: \(error.localizedDescription)")
            // Delete the bad backup
            try? FileManager.default.removeItem(at: backupURL)
            throw MigrationError.backupFailed(NSError(
                domain: "com.wardragon.migration",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Backup file verification failed: \(error.localizedDescription)"]
            ))
        }
        
        return backupURL
    }
    
    /// Find a recent valid backup (within last hour)
    private func findRecentValidBackup() throws -> URL? {
        let backupFiles = try? listBackupFiles()
        let recentBackups = backupFiles?.filter { url in
            url.lastPathComponent.hasPrefix("wardragon_backup_") &&
            (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate?
                .timeIntervalSinceNow ?? -Double.infinity > -3600 // Within last hour
        } ?? []
        
        // Find first valid backup
        for backup in recentBackups {
            do {
                try validateBackupFile(backup)
                logger.info("Found valid recent backup: \(backup.lastPathComponent)")
                return backup
            } catch {
                logger.warning("Recent backup \(backup.lastPathComponent) is invalid: \(error.localizedDescription)")
                continue
            }
        }
        
        return nil
    }
    
    /// Validate UserDefaults data can be decoded
    private func validateUserDefaultsData(_ data: Data) -> Bool {
        // Try to decode with multiple strategies
        let strategies: [JSONDecoder.DateDecodingStrategy] = [
            .iso8601,
            .secondsSince1970,
            .millisecondsSince1970
        ]
        
        for strategy in strategies {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = strategy
                let encounters = try decoder.decode([String: DroneEncounter].self, from: data)
                logger.info("✅ Data is valid - contains \(encounters.count) encounters (decoded with \(self.strategyName(strategy)))")
                return true
            } catch {
                continue
            }
        }
        
        logger.error("❌ Data validation failed - could not decode with any strategy")
        return false
    }
    
    /// Validate a backup file can be read and contains expected structure
    private func validateBackupFile(_ url: URL) throws {
        // Check file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MigrationError.decodingFailed("Backup file does not exist")
        }
        
        // Read file data
        let jsonData = try Data(contentsOf: url)
        guard jsonData.count > 0 else {
            throw MigrationError.decodingFailed("Backup file is empty (0 bytes)")
        }
        
        // Try to parse as JSON object
        guard let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) else {
            throw MigrationError.decodingFailed("Backup file is not valid JSON")
        }
        
        // Check if this is a wrapped backup (legacy format with timestamp)
        if let backupDict = jsonObject as? [String: Any] {
            // Check if it has timestamp (legacy UserDefaults backup format)
            if backupDict["timestamp"] != nil {
                logger.info("Validating legacy backup format (with timestamp wrapper)")
                
                // Check for encounters data
                if let encountersBase64 = backupDict["droneEncounters"] as? String {
                    // Verify base64 can be decoded
                    guard let encountersData = Data(base64Encoded: encountersBase64) else {
                        throw MigrationError.decodingFailed("Backup 'droneEncounters' field is not valid base64")
                    }
                    
                    // Verify encounters data is valid JSON
                    let strategies: [JSONDecoder.DateDecodingStrategy] = [.iso8601, .secondsSince1970, .millisecondsSince1970]
                    var decodedSuccessfully = false
                    
                    for strategy in strategies {
                        do {
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = strategy
                            _ = try decoder.decode([String: DroneEncounter].self, from: encountersData)
                            decodedSuccessfully = true
                            break
                        } catch {
                            continue
                        }
                    }
                    
                    if !decodedSuccessfully {
                        throw MigrationError.decodingFailed("Backup 'droneEncounters' data cannot be decoded")
                    }
                } else if backupDict["droneEncounters"] is NSNull {
                    // Empty backup is valid
                    logger.info("Backup file contains no encounters (NSNull) - this is valid")
                } else {
                    throw MigrationError.decodingFailed("Backup file missing 'droneEncounters' field or wrong type")
                }
                
                logger.info("✅ Legacy backup file validation passed")
                return
            }
            
            // If no timestamp, try as direct SwiftData export format (dictionary of encounters)
            logger.info("Validating SwiftData export format (direct encounter dictionary)")
            
            let strategies: [JSONDecoder.DateDecodingStrategy] = [.iso8601, .secondsSince1970, .millisecondsSince1970]
            var decodedSuccessfully = false
            
            for strategy in strategies {
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = strategy
                    _ = try decoder.decode([String: DroneEncounter].self, from: jsonData)
                    decodedSuccessfully = true
                    logger.info("✅ SwiftData export validation passed (strategy: \(self.strategyName(strategy)))")
                    return
                } catch {
                    continue
                }
            }
            
            if !decodedSuccessfully {
                throw MigrationError.decodingFailed("Backup file is not a valid encounter dictionary")
            }
        } else {
            throw MigrationError.decodingFailed("Backup file is not a valid JSON dictionary")
        }
    }
    
    /// Create an empty backup marker when there's no data to backup
    private func createEmptyBackupMarker() throws -> URL {
        let backupData: [String: Any] = [
            "version": "1.0",
            "timestamp": Date().timeIntervalSince1970,
            "migrationVersion": currentMigrationVersion,
            "droneEncounters": NSNull(),
            "note": "Empty backup - no data in UserDefaults"
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: backupData, options: .prettyPrinted)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsPath.appendingPathComponent("wardragon_backup_empty_\(Int(Date().timeIntervalSince1970)).json")
        
        try jsonData.write(to: backupURL)
        logger.info("✅ Empty backup marker created at: \(backupURL.lastPathComponent)")
        
        return backupURL
    }
    
    /// Export current SwiftData database to JSON backup
    func exportSwiftDataBackup(modelContext: ModelContext) throws -> URL {
        logger.info("Exporting SwiftData backup...")
        
        let descriptor = FetchDescriptor<StoredDroneEncounter>(
            sortBy: [SortDescriptor(\.firstSeen, order: .reverse)]
        )
        let encounters = try modelContext.fetch(descriptor)
        
        // Check if there's any data to backup
        if encounters.isEmpty {
            logger.warning("⚠️ No encounters found to export")
            throw MigrationError.backupFailed(NSError(
                domain: "com.wardragon.migration",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "No encounters to export. Database is empty."]
            ))
        }
        
        // Convert to legacy format for JSON serialization
        logger.info("Converting \(encounters.count) encounters to legacy format...")
        let legacyEncounters = encounters.map { $0.toLegacy() }
        let encountersDict = Dictionary(uniqueKeysWithValues: legacyEncounters.map { ($0.id, $0) })
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(encountersDict)
        
        // Validate the encoded data can be decoded back
        logger.info("Validating encoded data...")
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let validated = try decoder.decode([String: DroneEncounter].self, from: jsonData)
            logger.info("✅ Validation passed - \(validated.count) encounters can be decoded")
        } catch {
            logger.error("❌ Validation failed: \(error.localizedDescription)")
            throw MigrationError.backupFailed(NSError(
                domain: "com.wardragon.migration",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Backup validation failed: \(error.localizedDescription)"]
            ))
        }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupURL = documentsPath.appendingPathComponent("wardragon_swiftdata_export_\(Int(Date().timeIntervalSince1970)).json")
        
        try jsonData.write(to: backupURL)
        logger.info("✅ SwiftData export created and validated at: \(backupURL.lastPathComponent) (\(encounters.count) encounters)")
        
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
    
    /// Clean up old or duplicate backups, keeping only the most recent valid ones
    /// - Parameter keepCount: Number of recent backups to keep (default 3)
    func cleanupOldBackups(keepCount: Int = 3) throws {
        logger.info("Cleaning up old backups (keeping \(keepCount) most recent)...")
        
        let backupFiles = try listBackupFiles()
        
        // Separate by type
        let legacyBackups = backupFiles.filter { $0.lastPathComponent.hasPrefix("wardragon_backup_") }
        let swiftDataExports = backupFiles.filter { $0.lastPathComponent.hasPrefix("wardragon_swiftdata_export_") }
        
        // Clean each type separately
        try cleanupBackupList(legacyBackups, keepCount: keepCount, type: "legacy UserDefaults")
        try cleanupBackupList(swiftDataExports, keepCount: keepCount, type: "SwiftData export")
    }
    
    /// Helper to clean up a list of backups
    private func cleanupBackupList(_ backups: [URL], keepCount: Int, type: String) throws {
        guard backups.count > keepCount else {
            logger.info("No cleanup needed for \(type) backups (\(backups.count) files)")
            return
        }
        
        // Sort by date (newest first) - already done in listBackupFiles
        let toDelete = backups.dropFirst(keepCount)
        
        logger.info("Deleting \(toDelete.count) old \(type) backup(s)...")
        
        for backup in toDelete {
            do {
                try deleteBackup(at: backup)
                logger.info("  Deleted: \(backup.lastPathComponent)")
            } catch {
                logger.warning("  Failed to delete \(backup.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }
    
    /// Verify all existing backups and report status
    func verifyAllBackups() -> [BackupVerificationResult] {
        logger.info("Verifying all backup files...")
        
        guard let backupFiles = try? listBackupFiles() else {
            logger.error("Failed to list backup files")
            return []
        }
        
        var results: [BackupVerificationResult] = []
        
        for backupURL in backupFiles {
            let result = verifyBackup(backupURL)
            results.append(result)
            
            switch result.status {
            case .valid:
                logger.info("✅ \(backupURL.lastPathComponent): Valid (\(result.encounterCount) encounters)")
            case .empty:
                logger.info("⚠️  \(backupURL.lastPathComponent): Empty (no encounters)")
            case .corrupted:
                logger.error("❌ \(backupURL.lastPathComponent): Corrupted - \(result.error ?? "Unknown error")")
            }
        }
        
        return results
    }
    
    /// Verify a single backup file
    private func verifyBackup(_ url: URL) -> BackupVerificationResult {
        do {
            try validateBackupFile(url)
            
            // Count encounters if possible
            let jsonData = try Data(contentsOf: url)
            guard let backupDict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                logger.error("Failed to parse JSON dictionary for \(url.lastPathComponent)")
                return BackupVerificationResult(url: url, status: .corrupted, error: "Not a valid JSON dictionary")
            }
            
            var encounterCount = 0
            
            // Check if this is legacy format (with timestamp wrapper)
            if backupDict["timestamp"] != nil {
                logger.info("Verifying legacy format backup: \(url.lastPathComponent)")
                // Legacy UserDefaults backup format
                if let encountersBase64 = backupDict["droneEncounters"] as? String,
                   let encountersData = Data(base64Encoded: encountersBase64) {
                    // Try to count encounters from base64
                    for strategy in [JSONDecoder.DateDecodingStrategy.iso8601, .secondsSince1970, .millisecondsSince1970] {
                        do {
                            let decoder = JSONDecoder()
                            decoder.dateDecodingStrategy = strategy
                            let encounters = try decoder.decode([String: DroneEncounter].self, from: encountersData)
                            encounterCount = encounters.count
                            logger.info("Successfully decoded \(encounterCount) encounters from legacy backup")
                            break
                        } catch {
                            continue
                        }
                    }
                } else if backupDict["droneEncounters"] is NSNull {
                    encounterCount = 0
                    logger.info("Legacy backup is empty (NSNull)")
                }
            } else {
                logger.info("Verifying SwiftData export format: \(url.lastPathComponent)")
                // SwiftData export format (direct encounter dictionary)
                // Try to decode the entire JSON as encounters
                for strategy in [JSONDecoder.DateDecodingStrategy.iso8601, .secondsSince1970, .millisecondsSince1970] {
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = strategy
                        let encounters = try decoder.decode([String: DroneEncounter].self, from: jsonData)
                        encounterCount = encounters.count
                        logger.info("Successfully decoded \(encounterCount) encounters from SwiftData export using \(self.strategyName(strategy))")
                        break
                    } catch {
                        logger.debug("Failed to decode with \(self.strategyName(strategy)): \(error.localizedDescription)")
                        continue
                    }
                }
            }
            
            if encounterCount == 0 {
                logger.warning("Backup \(url.lastPathComponent) contains no encounters")
                return BackupVerificationResult(url: url, status: .empty, encounterCount: 0)
            } else {
                logger.info("Backup \(url.lastPathComponent) is valid with \(encounterCount) encounters")
                return BackupVerificationResult(url: url, status: .valid, encounterCount: encounterCount)
            }
            
        } catch {
            logger.error("Backup verification failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return BackupVerificationResult(url: url, status: .corrupted, error: error.localizedDescription)
        }
    }
    
    /// Restore from a backup file (imports into SwiftData)
    func restoreFromBackup(backupURL: URL, modelContext: ModelContext) throws {
        logger.info("Restoring from backup: \(backupURL.lastPathComponent)")
        
        // First validate the backup file
        do {
            try validateBackupFile(backupURL)
        } catch {
            logger.error("❌ Backup validation failed: \(error.localizedDescription)")
            throw MigrationError.decodingFailed("Invalid backup format or backup may be corrupted: \(error.localizedDescription)")
        }
        
        let jsonData = try Data(contentsOf: backupURL)
        logger.info("Read \(jsonData.count) bytes from backup file")
        
        // Try to decode as direct encounter dictionary first (SwiftData export format)
        logger.info("Attempting to decode as SwiftData export format...")
        
        for strategy in [JSONDecoder.DateDecodingStrategy.iso8601, 
                         .secondsSince1970, 
                         .millisecondsSince1970] {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = strategy
                let encounters = try decoder.decode([String: DroneEncounter].self, from: jsonData)
                
                logger.info("✅ Successfully decoded \(encounters.count) encounters using \(self.strategyName(strategy))")
                
                // Check if backup is empty
                if encounters.isEmpty {
                    logger.warning("⚠️ Backup file contains no encounters")
                    throw MigrationError.decodingFailed("Backup file is empty - no encounters to restore")
                }
                
                // Import each encounter
                var importedCount = 0
                for (_, encounter) in encounters {
                    let stored = StoredDroneEncounter.from(legacy: encounter, context: modelContext)
                    modelContext.insert(stored)
                    importedCount += 1
                }
                
                try modelContext.save()
                logger.info("✅ Successfully restored \(importedCount) encounters from backup")
                return
                
            } catch let decodeError as DecodingError {
                logger.info("Failed with \(self.strategyName(strategy)): \(decodeError.localizedDescription)")
                continue
            } catch let migrationError as MigrationError {
                // Re-throw migration errors (like empty backup)
                throw migrationError
            } catch {
                logger.info("Failed with \(self.strategyName(strategy)): \(error.localizedDescription)")
                continue
            }
        }
        
        // If direct decode failed, try legacy backup format
        logger.info("Direct decode failed, attempting legacy backup format...")
        
        do {
            guard let backupDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                logger.error("Failed to parse JSON as dictionary")
                throw MigrationError.decodingFailed("JSON is not a dictionary")
            }
            
            logger.info("Parsed JSON dictionary with keys: \(backupDict.keys.joined(separator: ", "))")
            
            // Check if this is the legacy format with base64-encoded data
            if let encountersBase64 = backupDict["droneEncounters"] as? String {
                logger.info("Found base64-encoded encounters data")
                
                guard let encountersData = Data(base64Encoded: encountersBase64) else {
                    logger.error("Failed to decode base64 string")
                    throw MigrationError.decodingFailed("Invalid base64 encoding")
                }
                
                logger.info("Decoded base64 data: \(encountersData.count) bytes")
                
                // Try multiple date decoding strategies
                for strategy in [JSONDecoder.DateDecodingStrategy.iso8601, 
                                 .secondsSince1970, 
                                 .millisecondsSince1970] {
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = strategy
                        let encounters = try decoder.decode([String: DroneEncounter].self, from: encountersData)
                        
                        logger.info("✅ Successfully decoded \(encounters.count) encounters from base64 using \(self.strategyName(strategy))")
                        
                        if encounters.isEmpty {
                            logger.warning("⚠️ Backup file contains no encounters")
                            throw MigrationError.decodingFailed("Backup file is empty - no encounters to restore")
                        }
                        
                        var importedCount = 0
                        for (_, encounter) in encounters {
                            let stored = StoredDroneEncounter.from(legacy: encounter, context: modelContext)
                            modelContext.insert(stored)
                            importedCount += 1
                        }
                        
                        try modelContext.save()
                        logger.info("✅ Successfully restored \(importedCount) encounters from legacy backup")
                        return
                    } catch let migrationError as MigrationError {
                        throw migrationError
                    } catch {
                        logger.info("Failed base64 decode with \(self.strategyName(strategy)): \(error.localizedDescription)")
                        continue
                    }
                }
            }
            // Handle NSNull case (empty UserDefaults backup)
            else if backupDict["droneEncounters"] is NSNull {
                logger.warning("⚠️ Backup contains NSNull for droneEncounters (empty UserDefaults backup)")
                throw MigrationError.decodingFailed("Backup file is empty - no encounters to restore")
            }
            // Check if encounters is directly in the dictionary (not base64)
            else if let encountersDict = backupDict["droneEncounters"] {
                logger.info("Found encounters dictionary directly (not base64)")
                
                let encountersJSON = try JSONSerialization.data(withJSONObject: encountersDict)
                logger.info("Serialized encounters dictionary: \(encountersJSON.count) bytes")
                
                for strategy in [JSONDecoder.DateDecodingStrategy.iso8601, 
                                 .secondsSince1970, 
                                 .millisecondsSince1970] {
                    do {
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = strategy
                        let encounters = try decoder.decode([String: DroneEncounter].self, from: encountersJSON)
                        
                        logger.info("✅ Successfully decoded \(encounters.count) encounters from dictionary using \(self.strategyName(strategy))")
                        
                        if encounters.isEmpty {
                            logger.warning("⚠️ Backup file contains no encounters")
                            throw MigrationError.decodingFailed("Backup file is empty - no encounters to restore")
                        }
                        
                        var importedCount = 0
                        for (_, encounter) in encounters {
                            let stored = StoredDroneEncounter.from(legacy: encounter, context: modelContext)
                            modelContext.insert(stored)
                            importedCount += 1
                        }
                        
                        try modelContext.save()
                        logger.info("✅ Successfully restored \(importedCount) encounters from legacy backup")
                        return
                    } catch let migrationError as MigrationError {
                        throw migrationError
                    } catch {
                        logger.info("Failed dictionary decode with \(self.strategyName(strategy)): \(error.localizedDescription)")
                        continue
                    }
                }
            } else {
                logger.error("No 'droneEncounters' key found in backup dictionary")
                throw MigrationError.decodingFailed("Backup file missing 'droneEncounters' key")
            }
            
        } catch let jsonError as MigrationError {
            throw jsonError
        } catch {
            logger.error("Failed to parse legacy format: \(error.localizedDescription)")
            throw MigrationError.decodingFailed("Legacy format parsing failed: \(error.localizedDescription)")
        }
        
        logger.error("All restore attempts failed")
        throw MigrationError.invalidData
    }
    
    /// Get database statistics
    func getDatabaseStats(modelContext: ModelContext) throws -> DatabaseStats {
        let encounterDescriptor = FetchDescriptor<StoredDroneEncounter>()
        let encounterCount = try modelContext.fetchCount(encounterDescriptor)
        
        let pointDescriptor = FetchDescriptor<StoredFlightPoint>()
        let pointCount = try modelContext.fetchCount(pointDescriptor)
        
        let signatureDescriptor = FetchDescriptor<StoredSignature>()
        let signatureCount = try modelContext.fetchCount(signatureDescriptor)
        
        let aircraftDescriptor = FetchDescriptor<StoredADSBEncounter>()
        let aircraftCount = try modelContext.fetchCount(aircraftDescriptor)
        
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
            aircraftCount: aircraftCount,
            databaseSizeBytes: databaseSize
        )
    }
    
    /// Delete all SwiftData (for complete reset)
    func deleteAllSwiftData(modelContext: ModelContext) throws {
        logger.warning("Deleting all SwiftData...")
        
        // Delete all drone encounters (cascade will handle relationships)
        let droneDescriptor = FetchDescriptor<StoredDroneEncounter>()
        let encounters = try modelContext.fetch(droneDescriptor)
        
        for encounter in encounters {
            modelContext.delete(encounter)
        }
        
        // Delete all aircraft encounters
        let aircraftDescriptor = FetchDescriptor<StoredADSBEncounter>()
        let aircraft = try modelContext.fetch(aircraftDescriptor)
        
        for aircraftEncounter in aircraft {
            modelContext.delete(aircraftEncounter)
        }
        
        try modelContext.save()
        logger.info("✅ Deleted \(encounters.count) drone encounters and \(aircraft.count) aircraft from SwiftData")
    }
}

struct DatabaseStats {
    let encounterCount: Int
    let flightPointCount: Int
    let signatureCount: Int
    let aircraftCount: Int
    let databaseSizeBytes: Int64
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: databaseSizeBytes)
    }
}

struct BackupVerificationResult {
    let url: URL
    let status: BackupStatus
    var encounterCount: Int = 0
    var error: String?
    
    enum BackupStatus {
        case valid
        case empty
        case corrupted
    }
    
    var statusEmoji: String {
        switch status {
        case .valid: return "✅"
        case .empty: return "⚠️"
        case .corrupted: return "❌"
        }
    }
}

enum MigrationError: LocalizedError {
    case migrationFailed(Error)
    case backupFailed(Error)
    case invalidData
    case decodingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .migrationFailed(let error):
            return "Migration failed: \(error.localizedDescription)"
        case .backupFailed(let error):
            return "Backup failed: \(error.localizedDescription)"
        case .invalidData:
            return "Invalid backup file format. The file may be corrupted or in an unsupported format."
        case .decodingFailed(let details):
            return "Failed to decode backup data: \(details)"
        }
    }
}
