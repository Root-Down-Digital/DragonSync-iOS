//
//  SilentAudioKeepAlive.swift
//  WarDragon
//
//  Created by Luke on 7/13/25.
//

import AVFAudio
import os.log

final class SilentAudioKeepAlive {
    static let shared = SilentAudioKeepAlive()

    private let engine = AVAudioEngine()
    private var started = false
    private let log = OSLog(subsystem: "com.wardragon", category: "AudioKeepAlive")

    func start() {
        guard !started else { return }
        started = true

        configureSession()
        configureEngine()
        startEngine()
        registerObservers()
    }

    // MARK: - helpers

    private func configureSession() {
        let s = AVAudioSession.sharedInstance()
        do {
            try s.setCategory(.playback, options: [.mixWithOthers])
            try s.setActive(true)
        } catch {
            os_log("Session activate failed: %{public}@", log: log, type: .error,
                   String(describing: error))
        }
    }

    private func configureEngine() {
        let src = AVAudioSourceNode { _, _, _, abl -> OSStatus in
            for b in UnsafeMutableAudioBufferListPointer(abl) {
                if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) }
            }
            return noErr
        }
        engine.attach(src)
        engine.connect(src, to: engine.mainMixerNode, format: nil)
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            try engine.start()
            os_log("Keep-alive engine running", log: log, type: .info)
        } catch {
            os_log("Engine start failed: %{public}@", log: log, type: .error,
                   String(describing: error))
        }
    }

    private func registerObservers() {
        let nc = NotificationCenter.default

        // 🔑 compile-safe constant here:
        nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                       object: engine, queue: .main) { [weak self] _ in
            self?.startEngine()
        }

        nc.addObserver(forName: AVAudioSession.interruptionNotification,
                       object: nil, queue: .main) { [weak self] n in
            guard
                let self,
                let u = n.userInfo,
                (u[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
            else { return }
            self.startEngine()
        }

        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.configureSession()
            self?.configureEngine()
            self?.startEngine()
        }
    }
}
