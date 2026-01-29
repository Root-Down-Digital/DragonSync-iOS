//
//  WarDragonApp.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
import SwiftData
import BackgroundTasks
import UserNotifications

extension Font {
    static let appDefault    = Font.system(.body,       design: .monospaced)
    static let appHeadline   = Font.system(.headline,   design: .monospaced)
    static let appSubheadline = Font.system(.subheadline, design: .monospaced)
    static let appCaption    = Font.system(.caption,    design: .monospaced)
}

@main
struct WarDragonApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    // SwiftData model container with recovery
    let modelContainer: ModelContainer = {
        let schema = Schema([
            StoredDroneEncounter.self,
            StoredFlightPoint.self,
            StoredSignature.self,
            StoredADSBEncounter.self,
            OpenSkySettings.self,
            CachedAircraft.self
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        
        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("SwiftData initialization failed: \(error.localizedDescription)")
            print("   Attempting recovery by resetting SwiftData store...")
            
            // Try to delete corrupted store and recreate
            do {
                let fileManager = FileManager.default
                let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let storeURL = appSupportURL.appendingPathComponent("default.store")
                
                // Remove corrupted store files
                if fileManager.fileExists(atPath: storeURL.path) {
                    try fileManager.removeItem(at: storeURL)
                    print("   Removed corrupted store file")
                }
                
                // Also remove WAL and SHM files if they exist
                let walURL = appSupportURL.appendingPathComponent("default.store-wal")
                let shmURL = appSupportURL.appendingPathComponent("default.store-shm")
                try? fileManager.removeItem(at: walURL)
                try? fileManager.removeItem(at: shmURL)
                
                // Try creating container again
                let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                print("Successfully recovered SwiftData store")
                
                // Reset migration flag so data gets re-migrated
                UserDefaults.standard.set(false, forKey: "DataMigration_UserDefaultsToSwiftData_Completed")
                UserDefaults.standard.set(0, forKey: "DataMigration_Version")
                print("   Migration will run on next launch to restore your data")
                
                return container
            } catch {
                print("Recovery failed: \(error.localizedDescription)")
                fatalError("Could not create or recover ModelContainer. This should never happen. Error: \(error)")
            }
        }
    }()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .task {
                    // Configure OpenSky service with model context
                    await configureOpenSkyService()
                    // Perform migration after view appears
                    await performMigrationIfNeeded()
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background:
                print("App moved to background")
            case .inactive:
                print("App became inactive")
                if oldPhase == .background {
                    print("App terminating - triggering cleanup via scene phase")
                    BackgroundManager.shared.endAllBackgroundTasks()
                }
            case .active:
                print("App became active")
            @unknown default:
                break
            }
        }
    }
    
    @MainActor
    private func configureOpenSkyService() async {
        let context = modelContainer.mainContext
        OpenSkyService.shared.configure(with: context)
    }
    
    @MainActor
    private func performMigrationIfNeeded() async {
        let context = modelContainer.mainContext
        let migrationManager = DataMigrationManager.shared
        print("Migration Status: \(migrationManager.migrationStatus)")
        
        guard migrationManager.needsMigration else {
            print("No migration needed - data already in SwiftData")
            DroneStorageManager.shared.loadFromStorage()
            return
        }
        
        print("🔄 Starting data migration (first run)...")
        print("   This is a one-time process to migrate your data to the new storage system")
        
        do {
            // Only create backup if one doesn't already exist
            let existingBackups = (try? migrationManager.listBackupFiles()) ?? []
            let hasLegacyBackup = existingBackups.contains { $0.lastPathComponent.hasPrefix("wardragon_backup_") }
            
            if !hasLegacyBackup {
                do {
                    let backupURL = try migrationManager.createBackup()
                    print("Backup created at: \(backupURL.path)")
                } catch {
                    print("Warning: Backup creation failed (non-fatal): \(error.localizedDescription)")
                    print("   Migration will continue, but you may want to manually backup your data")
                }
            } else {
                print("Backup already exists, skipping duplicate backup creation")
            }
            
            // Perform migration with retry logic
            var migrationSucceeded = false
            var lastError: Error?
            
            for attempt in 1...3 {
                do {
                    if attempt > 1 {
                        print("Migration attempt \(attempt)/3...")
                        try await Task.sleep(nanoseconds: 500_000_000)
                    }
                    
                    try await migrationManager.migrate(modelContext: context)
                    migrationSucceeded = true
                    break
                } catch {
                    lastError = error
                    print("Migration attempt \(attempt) failed: \(error.localizedDescription)")
                    
                    if attempt < 3 {
                        print("   Will retry...")
                    }
                }
            }
            
            if migrationSucceeded {
                print("Migration completed successfully!")
                print("   Your data has been migrated to the new storage system")
                print("   New Migration Status: \(migrationManager.migrationStatus)")
                
                // Verify migration by checking data count
                let descriptor = FetchDescriptor<StoredDroneEncounter>()
                let count = try context.fetchCount(descriptor)
                print("Verification: \(count) encounters now stored in SwiftData")
                
                // Force DroneStorageManager to reload from SwiftData
                DroneStorageManager.shared.loadFromStorage()
                
                // CRITICAL: Update cached stats for all existing encounters
                print("🔄 Updating cached stats for all encounters...")
                let allEncounters = try context.fetch(FetchDescriptor<StoredDroneEncounter>())
                var updatedCount = 0
                for encounter in allEncounters {
                    // Only update if caches are empty (old data)
                    if encounter.cachedFlightPointCount == 0 || encounter.cachedMaxAltitude == 0 {
                        encounter.updateCachedStats()
                        updatedCount += 1
                    }
                }
                if updatedCount > 0 {
                    try context.save()
                    print(" Updated cached stats for \(updatedCount) encounters")
                }
                
                print("🎉 Migration complete - app is now using the new storage system")
            } else {
                throw lastError ?? NSError(domain: "Migration", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown migration error"])
            }
            
        } catch {
            print("Migration failed after all attempts: \(error.localizedDescription)")
            print("   Don't worry - your data is safe!")
            print("   • App will continue using UserDefaults as fallback")
            print("   • Migration will be retried automatically on next launch")
            print("   • Your original data has been preserved")
            
            // Load from UserDefaults fallback
            DroneStorageManager.shared.loadFromStorage()
            
            // Log additional debugging info
            if let nsError = error as NSError? {
                print("   Debug info: domain=\(nsError.domain), code=\(nsError.code)")
                if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                    print("   Underlying: \(underlyingError.localizedDescription)")
                }
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let bgIDs = [
        "com.wardragon.processMessages",
        "com.wardragon.updateStatus",
        "com.wardragon.refreshConnections"
    ]

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        // Always start with a clean state - not listening
        Task { @MainActor in
            Settings.shared.isListening = false
        }

        UNUserNotificationCenter.current().delegate = self
        setupAppLifecycleObservers()
        registerBGTasks()
        scheduleAllBGTasks()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.windows.first?.frame = scene.windows.first?.frame ?? .zero
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                     fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {

        if let trigger = (userInfo["dragon"] as? [String : String])?["trigger"],
           trigger == "processMessages" {
            scheduleBGTask(id: "com.wardragon.processMessages", delay: 0)
        }
        completion(.newData)
    }

    private func setupAppLifecycleObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appMovingToBackground),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appMovingToForeground),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }

    @objc private func appMovingToBackground() {
        // Force save all pending data before backgrounding
        Task { @MainActor in
            DroneStorageManager.shared.forceSave()
            SwiftDataStorageManager.shared.forceSave()
        }
        
        if Settings.shared.isListening && Settings.shared.enableBackgroundDetection {
            BackgroundManager.shared.startBackgroundProcessing()
        }
    }

    @objc private func appMovingToForeground() { }

    private func registerBGTasks() {
        bgIDs.forEach { id in
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
                self.handleBGTask(task as! BGProcessingTask)
            }
        }
    }

    private func scheduleAllBGTasks() {
        bgIDs.forEach { id in scheduleBGTask(id: id, delay: 15*60) }
    }

    private func scheduleBGTask(id: String, delay: TimeInterval) {
        let req = BGProcessingTaskRequest(identifier: id)
        req.requiresNetworkConnectivity = true
        req.earliestBeginDate = Date(timeIntervalSinceNow: delay)
        try? BGTaskScheduler.shared.submit(req)
    }

    private func handleBGTask(_ task: BGProcessingTask) {
        task.expirationHandler = { BackgroundManager.shared.stopBackgroundProcessing() }
        BackgroundManager.shared.startBackgroundProcessing(useBackgroundTask: false)
        task.setTaskCompleted(success: true)
        scheduleBGTask(id: task.identifier, delay: 15*60)
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        // Clean stop - ensure listening is disabled
        Task { @MainActor in
            Settings.shared.isListening = false
        }
        ZMQHandler.shared.disconnect()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
