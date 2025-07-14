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
    private var running = false
    private var bgTaskID: UIBackgroundTaskIdentifier = .invalid
    private var bgRefreshTimer: Timer?
    private let monitor = NWPathMonitor()
    private var hasConnection = true
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
        guard !running else { return }
        running = true
        
        SilentAudioKeepAlive.shared.start()
        
        if useBackgroundTask {
            beginDrainTask()
            // Refresh 20 s in; we’ll always end/start before the 30 s warning.
            bgRefreshTimer = Timer.scheduledTimer(withTimeInterval: 20,
                                                  repeats: true) { [weak self] _ in
                guard let self else { return }
                if UIApplication.shared.backgroundTimeRemaining < 10 {
                    self.endDrainTask()
                    self.beginDrainTask()
                }
            }
        }
        
        queue.async {
            MulticastDrain.connect(&self.group)
            ZMQHandler.shared.connectIfNeeded()
            
            while self.running &&
                    (useBackgroundTask ? UIApplication.shared.backgroundTimeRemaining > 1 : true) {
                _ = ZMQHandler.shared.drainOnce()
                Thread.sleep(forTimeInterval: 0.05)
            }
            
            self.stopBackgroundProcessing()
        }
    }

    func stopBackgroundProcessing() {
        running = false
        ZMQHandler.shared.disconnect()
        MulticastDrain.disconnect(&group)

        bgRefreshTimer?.invalidate()
        bgRefreshTimer = nil
        endDrainTask()
    }
    
    private func beginDrainTask() {
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "Drain") { [weak self] in
            self?.endDrainTask()
            self?.beginDrainTask()
        }
    }

    private func endDrainTask() {
        if bgTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }
    }
}

enum MulticastDrain {
    static func connect(_ grp: inout NWConnectionGroup?) {
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

    static func disconnect(_ grp: inout NWConnectionGroup?) {
        grp?.cancel()
        grp = nil
    }
}
