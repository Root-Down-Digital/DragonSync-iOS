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

final class BackgroundManager: @unchecked Sendable {

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
    private let maxTaskDuration: TimeInterval = 150
    private var memoryCheckCounter = 0
    private let memoryCheckInterval = 50  // Check memory every 50 iterations (~5 seconds)
    
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
        
        Task { @MainActor in
            let isListening = Settings.shared.isListening
            let enableBg = Settings.shared.enableBackgroundDetection
            print("BackgroundManager: isListening=\(isListening), enableBackgroundDetection=\(enableBg)")
            
            guard isListening && enableBg else {
                print("BackgroundManager: NOT starting - user not listening or background detection disabled")
                return
            }
            
            await self._internalStartBackgroundProcessing(useBackgroundTask: useBackgroundTask)
        }
    }
    
    private func _internalStartBackgroundProcessing(useBackgroundTask: Bool) async {
        running = true

        SilentAudioKeepAlive.shared.start()

        if useBackgroundTask {
            await MainActor.run {
                beginDrainTask()
                bgRefreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.checkAndRefreshBackgroundTask()
                    }
                }
                if let timer = bgRefreshTimer {
                    RunLoop.main.add(timer, forMode: .default)
                }
            }
        }

        let connectionMode = await MainActor.run {
            Settings.shared.connectionMode
        }
        
        Task.detached { [weak self] in
            guard let self else { return }
            
            switch connectionMode {
            case .multicast:
                await self.connectMulticast()
            case .zmq:
                ZMQHandler.shared.connectIfNeeded()
            }

            while await self.isRunningAndBackgroundOK(useBackgroundTask: useBackgroundTask) {
                // Check memory periodically
                self.memoryCheckCounter += 1
                if self.memoryCheckCounter >= self.memoryCheckInterval {
                    self.memoryCheckCounter = 0
                    
                    let isInBackground = await MainActor.run {
                        UIApplication.shared.applicationState == .background
                    }
                    
                    if isInBackground {
                        autoreleasepool {
                            self.checkMemoryUsage()
                        }
                    }
                }
                
                let currentMode = await MainActor.run {
                    Settings.shared.connectionMode
                }
                
                autoreleasepool {
                    switch currentMode {
                    case .multicast:
                        break
                    case .zmq:
                        if ZMQHandler.shared.isConnected {
                            ZMQHandler.shared.drainOnce()
                        }
                    }
                }
                
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }

            self._internalStopBackgroundProcessing()
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
        self._internalStopBackgroundProcessing()
    }

    func stopBackgroundProcessing() {
        _internalStopBackgroundProcessing()
    }
    
    private func _internalStopBackgroundProcessing() {
        let wasRunning = running
        running = false
        guard wasRunning else { return }

        ZMQHandler.shared.disconnect()
        disconnectMulticast()

        DispatchQueue.main.async { [weak self] in
            self?.bgRefreshTimer?.invalidate()
            self?.bgRefreshTimer = nil
            self?.endDrainTask()
        }
        SilentAudioKeepAlive.shared.stop()
    }

    private func isRunningAndBackgroundOK(useBackgroundTask: Bool) async -> Bool {
        let run = running
        
        let backgroundTimeOK: Bool
        if useBackgroundTask {
            backgroundTimeOK = await MainActor.run {
                UIApplication.shared.backgroundTimeRemaining > 5
            }
        } else {
            backgroundTimeOK = true
        }
            
        return run && backgroundTimeOK
    }

    @MainActor
    private func checkAndRefreshBackgroundTask() {
        guard bgTaskID != .invalid else { return }
        
        let currentTime = Date()
        let timeRemaining = UIApplication.shared.backgroundTimeRemaining
        
        if let startTime = taskStartTime,
           currentTime.timeIntervalSince(startTime) >= 20 || timeRemaining < 30 {
            let age = Int(currentTime.timeIntervalSince(startTime))
            let remainingString: String
            if timeRemaining == .greatestFiniteMagnitude || timeRemaining > Double(Int.max) {
                remainingString = "unlimited"
            } else {
                remainingString = "\(Int(timeRemaining))s"
            }
            print("Refreshing background task (age: \(age)s, remaining: \(remainingString))")
            endDrainTask()
            beginDrainTask()
        }
    }

    @MainActor
    private func beginDrainTask() {
        endDrainTask()
        
        taskStartTime = Date()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "Drain") {
            print("⚠️ Background task about to expire - refreshing...")
            NotificationCenter.default.post(name: NSNotification.Name("BackgroundTaskExpiring"), object: nil)
        }
        
        guard bgTaskID != .invalid else {
            print("❌ Failed to begin background task - iOS may have denied it")
            return
        }
        
        let timeRemaining = UIApplication.shared.backgroundTimeRemaining
        let timeString: String
        if timeRemaining == .greatestFiniteMagnitude {
            timeString = "unlimited"
        } else if timeRemaining > Double(Int.max) {
            timeString = "unlimited"
        } else {
            timeString = "\(Int(timeRemaining))s"
        }
        print("Background task started - ID: \(bgTaskID.rawValue), time remaining: \(timeString)")
    }

    @MainActor
    private func endDrainTask() {
        if bgTaskID != .invalid {
            print("Ending background task - ID: \(bgTaskID.rawValue)")
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
            taskStartTime = nil
        }
    }
    
    /// Force end all background tasks (for app termination)
    func endAllBackgroundTasks() {
        print("BackgroundManager: Ending all background tasks")
        _internalStopBackgroundProcessing()
        print(" BackgroundManager: All tasks ended")
    }
    
    private func disconnectMulticast() {
        group?.cancel()
        group = nil
    }
    
    private func checkMemoryUsage() {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            let memoryMB = Double(taskInfo.resident_size) / 1024.0 / 1024.0

            // iOS jetsam threshold in background is ~50MB on many devices.
            // React EARLY, not after we've already crossed the kill line.
            if memoryMB > 40 {
                print("⚠️ Memory: \(String(format: "%.1f", memoryMB))MB - early-release to stay below jetsam")

                ZMQHandler.shared.clearCaches()
                URLCache.shared.removeAllCachedResponses()

                Task { @MainActor in
                    SwiftDataStorageManager.shared.releaseBackgroundMemory()
                    DroneStorageManager.shared.forceSave()
                    // Cap unbounded UI buffers that grow under BG ingest.
                    self.cotViewModel?.trimDetectionBuffersForBackground()
                }

                if memoryMB > 60 {
                    print("❌ CRITICAL MEMORY (\(String(format: "%.1f", memoryMB))MB) - Pausing to avoid termination")
                    _internalStopBackgroundProcessing()
                }
            }
        }
    }
}
