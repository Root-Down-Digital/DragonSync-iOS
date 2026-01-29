//
//  BackgroundManager.swift
//  WarDragon
//
//  Created by Luke on 4/16/25.
//

import Foundation
import Network
import UIKit
import AVFAudio

final class BackgroundManager {

    static let shared = BackgroundManager()

    private let queue = DispatchQueue(label: "BackgroundWork")
    private var group: NWConnectionGroup?
    private let runningQueue = DispatchQueue(label: "BackgroundManager.running")
    private var _running = false
    private var running: Bool {
        get { runningQueue.sync { _running } }
        set { runningQueue.sync { _running = newValue } }
    }
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var bgRefreshTimer: Timer?
    private let monitor = NWPathMonitor()
    private var hasConnection = true
    private var taskStartTime: Date?
    private let maxTaskDuration: TimeInterval = 20
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.hasConnection = (path.status == .satisfied)
        }
        monitor.start(queue: .global(qos: .background))
    }

    private weak var cotViewModel: CoTViewModel?
    func configure(with viewModel: CoTViewModel) { cotViewModel = viewModel }

    var isBackgroundModeActive: Bool { running }
    func isNetworkAvailable() -> Bool { hasConnection }

    func startBackgroundProcessing(useBackgroundTask: Bool = true) {
        if running {
            return
        }
        running = true

        SilentAudioKeepAlive.shared.start()

        if useBackgroundTask {
            beginDrainTask()
            // Reduced refresh interval for better RID message capture
            bgRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.checkAndRefreshBackgroundTask()
            }
        }

        Task.detached { [weak self] in
            guard let self else { return }
            
            // Get connection mode on main actor
            let connectionMode = await MainActor.run {
                Settings.shared.connectionMode
            }
            
            switch connectionMode {
            case .multicast:
                await self.connectMulticast()
            case .zmq:
                ZMQHandler.shared.connectIfNeeded()
            }

            while self.isRunningAndBackgroundOK(useBackgroundTask: useBackgroundTask) {
                autoreleasepool {
                    // Check connection mode each iteration in case it changed
                    Task {
                        let currentMode = await MainActor.run {
                            Settings.shared.connectionMode
                        }
                        
                        switch currentMode {
                        case .multicast:
                            break
                        case .zmq:
                            if ZMQHandler.shared.isConnected {
                                ZMQHandler.shared.drainOnce()
                            }
                        }
                    }
                    // Reduced sleep time for faster message processing
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }

            await self.cleanup()
        }
    }
    
    private func connectMulticast() async {
        guard group == nil else { return }
        
        let host = await MainActor.run { Settings.shared.multicastHost }
        let port = await MainActor.run { Settings.shared.multicastPort }
        
        do {
            let hostEndpoint = NWEndpoint.Host(host)
            let portEndpoint = NWEndpoint.Port(integerLiteral: UInt16(port))
            let desc = try NWMulticastGroup(for: [.hostPort(host: hostEndpoint, port: portEndpoint)])
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true

            let g = NWConnectionGroup(with: desc, using: params)
            g.setReceiveHandler(maximumMessageSize: 65_535) { _, data, _ in
                if let d = data {
                    NotificationCenter.default.post(name: .init("BackgroundMulticastData"), object: d)
                }
            }
            g.start(queue: DispatchQueue.global(qos: .utility))
            
            group = g
        } catch {
            print("Failed to connect multicast: \(error)")
        }
    }
    
    private func cleanup() async {
        self.stopBackgroundProcessing()
    }

    func stopBackgroundProcessing() {
        let wasRunning = running
        running = false
        guard wasRunning else { return }

        // Fix for crash report: Don't access Settings.shared during stop - disconnect both safely
        ZMQHandler.shared.disconnect()
        disconnectMulticast()

        bgRefreshTimer?.invalidate()
        bgRefreshTimer = nil
        endDrainTask()
        SilentAudioKeepAlive.shared.stop()
    }

    private func isRunningAndBackgroundOK(useBackgroundTask: Bool) -> Bool {
        let run = running
        
        let backgroundTimeOK = useBackgroundTask ?
            UIApplication.shared.backgroundTimeRemaining > 10 : true
            
        return run && backgroundTimeOK
    }

    private func checkAndRefreshBackgroundTask() {
        guard bgTaskID != .invalid else { return }
        
        let currentTime = Date()
        let timeRemaining = UIApplication.shared.backgroundTimeRemaining
        
        if let startTime = taskStartTime,
           currentTime.timeIntervalSince(startTime) >= maxTaskDuration || timeRemaining < 15 {
            endDrainTask()
            beginDrainTask()
        }
    }

    private func beginDrainTask() {
        endDrainTask()
        
        taskStartTime = Date()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "Drain") { [weak self] in
            NotificationCenter.default.post(name: NSNotification.Name("BackgroundTaskExpiring"), object: nil)
            self?.endDrainTask()
        }
        
        guard bgTaskID != .invalid else {
            print("Failed to begin background task")
            return
        }
    }

    private func endDrainTask() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
            taskStartTime = nil
        }
    }
    
    /// Force end all background tasks (for app termination)
    func endAllBackgroundTasks() {
        print("BackgroundManager: Ending all background tasks")
        
        // Stop the entire background processing system
        stopBackgroundProcessing()
        
        // Ensure the task is ended
        endDrainTask()
        
        // Cancel the timer
        bgRefreshTimer?.invalidate()
        bgRefreshTimer = nil
        
        print(" BackgroundManager: All tasks ended")
    }
    
    private func disconnectMulticast() {
        group?.cancel()
        group = nil
    }
}
