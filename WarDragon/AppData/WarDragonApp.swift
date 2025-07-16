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

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    private let bgIDs = [
        "com.wardragon.processMessages",
        "com.wardragon.updateStatus",
        "com.wardragon.refreshConnections"
    ]

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

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
        ZMQHandler.shared.disconnect()
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}
