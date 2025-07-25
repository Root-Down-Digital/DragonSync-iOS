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

    private let queue = DispatchQueue(label: "BackgroundWork", qos: .utility)
    private let groupLock = NSLock()
    private var group: NWConnectionGroup?
    private var running = false
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var bgRefreshTimer: Timer?
    private let monitor = NWPathMonitor()
    private var hasConnection = true
    private var taskStartTime: Date?
    private let maxTaskDuration: TimeInterval = 20
    private var terminationRequested = false
    private var allBackgroundTasks: [UIBackgroundTaskIdentifier] = []
    
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.hasConnection = (path.status == .satisfied)
        }
        monitor.start(queue: .global(qos: .background))
    }

    private weak var cotViewModel: CoTViewModel?
    func configure(with viewModel: CoTViewModel) { cotViewModel = viewModel }

    var isBackgroundModeActive: Bool {
        groupLock.lock()
        defer { groupLock.unlock() }
        return running
    }
    
    func isNetworkAvailable() -> Bool { hasConnection }

    func startBackgroundProcessing(useBackgroundTask: Bool = true) {
        if terminationRequested { return }
        
        groupLock.lock()
        if running {
            groupLock.unlock()
            return
        }
        running = true
        groupLock.unlock()

        SilentAudioKeepAlive.shared.start()

        if useBackgroundTask {
            beginDrainTask()
            bgRefreshTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
                guard let self = self, !self.terminationRequested else { return }
                self.checkAndRefreshBackgroundTask()
            }
        }

        queue.async { [weak self] in
            guard let self = self, !self.terminationRequested else { return }
            
            switch Settings.shared.connectionMode {
            case .multicast:
                MulticastDrain.connect(&self.group, lock: self.groupLock)
            case .zmq:
                ZMQHandler.shared.connectIfNeeded()
            }

            while self.isRunningAndBackgroundOK(useBackgroundTask: useBackgroundTask) && !self.terminationRequested {
                autoreleasepool {
                    switch Settings.shared.connectionMode {
                    case .multicast:
                        break
                    case .zmq:
                        if ZMQHandler.shared.isConnected && !self.terminationRequested {
                            ZMQHandler.shared.drainOnce()
                        }
                    }
                    if !self.terminationRequested {
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                }
            }

            self.stopBackgroundProcessing()
        }
    }
    

    func stopBackgroundProcessing() {
        groupLock.lock()
        let wasRunning = running
        running = false
        groupLock.unlock()
        guard wasRunning else { return }

        switch Settings.shared.connectionMode {
        case .zmq:
            ZMQHandler.shared.disconnect()
        case .multicast:
            MulticastDrain.disconnect(&group, lock: groupLock)
        }

        bgRefreshTimer?.invalidate()
        bgRefreshTimer = nil
        endDrainTask()
        SilentAudioKeepAlive.shared.stop()
    }

    private func isRunningAndBackgroundOK(useBackgroundTask: Bool) -> Bool {
        if terminationRequested { return false }
        
        groupLock.lock()
        let run = running
        groupLock.unlock()
        return run && (useBackgroundTask ? UIApplication.shared.backgroundTimeRemaining > 5 : true)
    }

    private func checkAndRefreshBackgroundTask() {
        guard bgTaskID != .invalid, !terminationRequested else { return }
        
        let currentTime = Date()
        let timeRemaining = UIApplication.shared.backgroundTimeRemaining
        
        if let startTime = taskStartTime,
           currentTime.timeIntervalSince(startTime) >= maxTaskDuration || timeRemaining < 15 {
            endDrainTask()
            beginDrainTask()
        }
    }

    private func beginDrainTask() {
        if terminationRequested { return }
        
        endDrainTask()
        
        taskStartTime = Date()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "Drain") { [weak self] in
            guard let self = self, !self.terminationRequested else { return }
            NotificationCenter.default.post(name: NSNotification.Name("BackgroundTaskExpiring"), object: nil)
            self.endDrainTask()
        }
        
        guard bgTaskID != .invalid else {
            print("Failed to begin background task")
            return
        }
        
        allBackgroundTasks.append(bgTaskID)
    }

    private func endDrainTask() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            allBackgroundTasks.removeAll { $0 == bgTaskID }
            bgTaskID = .invalid
            taskStartTime = nil
        }
    }
    
    func forceStopAllBackgroundTasks() {
        print("BackgroundManager: Force stopping all background tasks")
        
        groupLock.lock()
        let wasRunning = running
        running = false
        groupLock.unlock()
        
        guard wasRunning else {
            print("BackgroundManager: Already stopped")
            return
        }
        
        bgRefreshTimer?.invalidate()
        bgRefreshTimer = nil
        
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
            taskStartTime = nil
        }
        
        switch Settings.shared.connectionMode {
        case .zmq:
            ZMQHandler.shared.disconnect()
        case .multicast:
            MulticastDrain.disconnect(&group, lock: groupLock)
        }
        
        SilentAudioKeepAlive.shared.stop()
        
        print("BackgroundManager: All background tasks force stopped")
    }
}

enum MulticastDrain {
    static func connect(_ grp: inout NWConnectionGroup?, lock: NSLock) {
        lock.lock()
        defer { lock.unlock() }
        guard grp == nil else { return }
        do {
            let host = NWEndpoint.Host(Settings.shared.multicastHost)
            let port = NWEndpoint.Port(integerLiteral: UInt16(Settings.shared.multicastPort))
            let desc = try NWMulticastGroup(for: [.hostPort(host: host, port: port)])
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true

            let g = NWConnectionGroup(with: desc, using: params)
            g.setReceiveHandler(maximumMessageSize: 65_535) { _, data, _ in
                if let d = data {
                    NotificationCenter.default.post(name: .init("BackgroundMulticastData"), object: d)
                }
            }
            g.start(queue: .global(qos: .utility))
            grp = g
        } catch { }
    }

    static func disconnect(_ grp: inout NWConnectionGroup?, lock: NSLock) {
        lock.lock()
        defer { lock.unlock() }
        grp?.cancel()
        grp = nil
    }
}
