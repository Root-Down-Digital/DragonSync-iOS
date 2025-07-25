//
//  WarDragonApp.swift
//  WarDragon
//
//  Created by Luke on 11/18/24.
//

import SwiftUI
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
    var body: some Scene { WindowGroup { ContentView() } }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    private let bgIDs = ["com.wardragon.processMessages", "com.wardragon.updateStatus", "com.wardragon.refreshConnections"]
    private var terminationInProgress = false

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        setupAppLifecycleObservers()
        registerBGTasks()
        scheduleAllBGTasks()
        return true
    }

    func application(_ application: UIApplication, performFetchWithCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
        if terminationInProgress {
            completion(.noData)
            return
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
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(appWillTerminate),
                                               name: UIApplication.willTerminateNotification,
                                               object: nil)
    }

    @objc private func appMovingToBackground() {
        if terminationInProgress { return }
        if Settings.shared.isListening && Settings.shared.enableBackgroundDetection {
            BackgroundManager.shared.startBackgroundProcessing()
        }
    }

    @objc private func appMovingToForeground() {
        if terminationInProgress { return }
    }
    
    @objc private func appWillTerminate() {
        terminationInProgress = true
        performGracefulTermination()
    }

    private func registerBGTasks() {
        bgIDs.forEach { id in
            BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
                if self.terminationInProgress {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.handleBGTask(task as! BGProcessingTask)
            }
        }
    }

    private func scheduleAllBGTasks() {
        if terminationInProgress { return }
        bgIDs.forEach { id in scheduleBGTask(id: id, delay: 15*60) }
    }

    private func scheduleBGTask(id: String, delay: TimeInterval) {
        if terminationInProgress { return }
        let req = BGProcessingTaskRequest(identifier: id)
        req.requiresNetworkConnectivity = true
        req.earliestBeginDate = Date(timeIntervalSinceNow: delay)
        try? BGTaskScheduler.shared.submit(req)
    }

    private func handleBGTask(_ task: BGProcessingTask) {
        if terminationInProgress {
            task.setTaskCompleted(success: false)
            return
        }
        
        task.expirationHandler = {
            BackgroundManager.shared.stopBackgroundProcessing()
            task.setTaskCompleted(success: true)
        }
        BackgroundManager.shared.startBackgroundProcessing(useBackgroundTask: false)
        task.setTaskCompleted(success: true)
        scheduleBGTask(id: task.identifier, delay: 15*60)
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        print("App terminating - force stopping background tasks")
        BackgroundManager.shared.forceStopAllBackgroundTasks()
        print("App termination cleanup complete")
    }
    
    private func performGracefulTermination() {
        let semaphore = DispatchSemaphore(value: 0)
        
        DispatchQueue.global(qos: .userInitiated).async {
            BackgroundManager.shared.forceStopAllBackgroundTasks()
            SilentAudioKeepAlive.shared.stop()
            ZMQHandler.shared.disconnect()
            semaphore.signal()
        }
        
        let result = semaphore.wait(timeout: .now() + 2.0)
        if result == .timedOut {
            print("Warning: Termination cleanup timed out")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
