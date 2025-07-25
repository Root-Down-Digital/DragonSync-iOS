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
    private var sourceNode: AVAudioSourceNode?
    private var terminationRequested = false
    private var observersRegistered = false

    func start() {
        guard !started, !terminationRequested else { return }
        started = true

        configureSession()
        configureEngine()
        startEngine()
        registerObservers()
    }
    
    func stop() {
        guard started else { return }
        started = false
        terminationRequested = true
        
        removeObservers()
        
        engine.stop()
        
        if let sourceNode = sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            os_log("Failed to deactivate audio session: %{public}@", log: log, type: .error,
                   String(describing: error))
        }
    }

    private func configureSession() {
        guard !terminationRequested else { return }
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setPreferredSampleRate(8000)
            try session.setPreferredIOBufferDuration(0.5)
            try session.setActive(true)
            os_log("Audio session configured successfully", log: log, type: .info)
        } catch {
            os_log("Session activate failed: %{public}@", log: log, type: .error, String(describing: error))
        }
    }

    private func configureEngine() {
        guard !terminationRequested else { return }
        
        let sourceNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            guard !self.terminationRequested else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in ablPointer {
                if let data = buffer.mData {
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return noErr
        }
        
        self.sourceNode = sourceNode
        engine.attach(sourceNode)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        
        os_log("Audio engine configured", log: log, type: .info)
    }

    private func startEngine() {
        guard !terminationRequested else { return }
        
        guard !engine.isRunning else {
            os_log("Engine already running", log: log, type: .debug)
            return
        }
        
        do {
            try engine.start()
            os_log("Keep-alive engine running", log: log, type: .info)
        } catch {
            os_log("Engine start failed: %{public}@", log: log, type: .error, String(describing: error))
            
            if !terminationRequested {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self = self, !self.terminationRequested else { return }
                    self.reconfigureAndRestart()
                }
            }
        }
    }
    
    private func reconfigureAndRestart() {
        guard !terminationRequested else { return }
        
        engine.stop()
        engine.reset()
        configureSession()
        configureEngine()
        startEngine()
    }

    private func registerObservers() {
        guard !terminationRequested, !observersRegistered else { return }
        observersRegistered = true
        
        let nc = NotificationCenter.default

        nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                       object: engine, queue: .main) { [weak self] _ in
            guard let self = self, !self.terminationRequested else { return }
            self.handleConfigurationChange()
        }

        nc.addObserver(forName: AVAudioSession.interruptionNotification,
                       object: nil, queue: .main) { [weak self] notification in
            guard let self = self, !self.terminationRequested else { return }
            self.handleInterruption(notification)
        }

        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                       object: nil, queue: .main) { [weak self] _ in
            guard let self = self, !self.terminationRequested else { return }
            self.handleMediaServicesReset()
        }
    }
    
    private func removeObservers() {
        guard observersRegistered else { return }
        observersRegistered = false
        
        let nc = NotificationCenter.default
        nc.removeObserver(self, name: .AVAudioEngineConfigurationChange, object: engine)
        nc.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        nc.removeObserver(self, name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }
    
    private func handleConfigurationChange() {
        guard !terminationRequested else { return }
        os_log("Audio configuration changed, restarting engine", log: log, type: .info)
        startEngine()
    }
    
    private func handleInterruption(_ notification: Notification) {
        guard !terminationRequested else { return }
        
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            os_log("Audio interruption began", log: log, type: .info)
        case .ended:
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) && !terminationRequested {
                    os_log("Audio interruption ended, resuming", log: log, type: .info)
                    startEngine()
                }
            }
        @unknown default:
            break
        }
    }
    
    private func handleMediaServicesReset() {
        guard !terminationRequested else { return }
        os_log("Media services reset, reconfiguring audio", log: log, type: .info)
        configureSession()
        configureEngine()
        startEngine()
    }
}
