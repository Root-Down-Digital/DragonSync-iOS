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

    func start() {
        guard !started else { return }
        started = true

        configureSession()
        configureEngine()
        startEngine()
        registerObservers()
    }
    
    func stop() {
        guard started else { return }
        started = false
        
        engine.stop()
        
        if let sourceNode = sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            os_log("Failed to deactivate audio session: %{public}@", log: log, type: .error,
                   String(describing: error))
        }
    }

    private func configureSession() {
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
        // First, detach any existing nodes
        if let sourceNode = sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
        
        // Create a proper audio format with mono channel at 8kHz
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1) else {
            os_log("Failed to create audio format", log: log, type: .error)
            return
        }
        
        let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in ablPointer {
                if let data = buffer.mData {
                    // Fill with silence (zeros)
                    memset(data, 0, Int(buffer.mDataByteSize))
                }
            }
            return noErr
        }
        
        self.sourceNode = sourceNode
        engine.attach(sourceNode)
        
        // Connect with explicit format
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        
        os_log("Audio engine configured with format: %{public}@", log: log, type: .info, 
               format.description)
    }

    private func startEngine() {
        guard !engine.isRunning else {
            os_log("Engine already running", log: log, type: .debug)
            return
        }
        
        do {
            try engine.start()
            os_log("Keep-alive engine running", log: log, type: .info)
        } catch {
            os_log("Engine start failed: %{public}@", log: log, type: .error, String(describing: error))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.reconfigureAndRestart()
            }
        }
    }
    
    private func reconfigureAndRestart() {
        os_log("Reconfiguring audio engine", log: log, type: .info)
        
        engine.stop()
        
        // Detach old source node if it exists
        if let sourceNode = sourceNode {
            engine.detach(sourceNode)
            self.sourceNode = nil
        }
        
        engine.reset()
        
        configureSession()
        configureEngine()
        startEngine()
    }

    private func registerObservers() {
        let nc = NotificationCenter.default

        nc.addObserver(forName: .AVAudioEngineConfigurationChange,
                       object: engine, queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        nc.addObserver(forName: AVAudioSession.interruptionNotification,
                       object: nil, queue: .main) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification,
                       object: nil, queue: .main) { [weak self] _ in
            self?.handleMediaServicesReset()
        }
    }
    
    private func handleConfigurationChange() {
        os_log("Audio configuration changed, restarting engine", log: log, type: .info)
        startEngine()
    }
    
    private func handleInterruption(_ notification: Notification) {
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
                if options.contains(.shouldResume) {
                    os_log("Audio interruption ended, resuming", log: log, type: .info)
                    startEngine()
                }
            }
        @unknown default:
            break
        }
    }
    
    private func handleMediaServicesReset() {
        os_log("Media services reset, reconfiguring audio", log: log, type: .info)
        configureSession()
        configureEngine()
        startEngine()
    }
}
