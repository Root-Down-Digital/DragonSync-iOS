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
    private let maxTaskDuration: TimeInterval = 25
    
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
            bgRefreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
                guard let self else { return }
                if UIApplication.shared.backgroundTimeRemaining < 10 {
                    self.endDrainTask()
                    self.beginDrainTask()
                }
            }
        }

        queue.async { [weak self] in
            guard let self else { return }
            MulticastDrain.connect(&self.group, lock: self.groupLock)
            ZMQHandler.shared.connectIfNeeded()

            while self.isRunningAndBackgroundOK(useBackgroundTask: useBackgroundTask) {
                autoreleasepool {
                    if ZMQHandler.shared.isConnected {
                        ZMQHandler.shared.drainOnce()
                    }
                    Thread.sleep(forTimeInterval: 0.05)
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

        // Only disconnect ZMQ if it was being used
        if Settings.shared.connectionMode == .zmq {
            ZMQHandler.shared.disconnect()
        }
        
        // Only disconnect multicast if it was being used
        if Settings.shared.connectionMode == .multicast {
            MulticastDrain.disconnect(&group, lock: groupLock)
        }

        bgRefreshTimer?.invalidate()
        bgRefreshTimer = nil
        endDrainTask()
    }

    private func isRunningAndBackgroundOK(useBackgroundTask: Bool) -> Bool {
        groupLock.lock()
        let run = running
        groupLock.unlock()
        return run && (useBackgroundTask ? UIApplication.shared.backgroundTimeRemaining > 1 : true)
    }

    private func checkAndRefreshBackgroundTask() {
        guard bgTaskID != .invalid else { return }
        
        let currentTime = Date()
        let timeRemaining = UIApplication.shared.backgroundTimeRemaining
        
        if let startTime = taskStartTime,
           currentTime.timeIntervalSince(startTime) >= maxTaskDuration || timeRemaining < 10 {
            endDrainTask()
            beginDrainTask()
        }
    }

    private func beginDrainTask() {
        endDrainTask()
        
        taskStartTime = Date()
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "Drain") { [weak self] in
            self?.endDrainTask()
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
