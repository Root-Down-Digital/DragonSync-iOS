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
    private let groupLock = NSLock()
    private var group: NWConnectionGroup?
    private var running = false
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
            // Reduced refresh interval for better RID message capture
            bgRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.checkAndRefreshBackgroundTask()
            }
        }

        queue.async { [weak self] in
            guard let self else { return }
            
            switch Settings.shared.connectionMode {
            case .multicast:
                MulticastDrain.connect(&self.group, lock: self.groupLock)
            case .zmq:
                ZMQHandler.shared.connectIfNeeded()
            }

            while self.isRunningAndBackgroundOK(useBackgroundTask: useBackgroundTask) {
                autoreleasepool {
                    switch Settings.shared.connectionMode {
                    case .multicast:
                        break
                    case .zmq:
                        if ZMQHandler.shared.isConnected {
                            ZMQHandler.shared.drainOnce()
                        }
                    }
                    // Reduced sleep time for faster message processing
                    Thread.sleep(forTimeInterval: 0.02)
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
        groupLock.lock()
        let run = running
        groupLock.unlock()
        
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
