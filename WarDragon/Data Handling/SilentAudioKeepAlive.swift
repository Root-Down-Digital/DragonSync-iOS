//
//  SilentAudioKeepAlive.swift
//  WarDragon
//
//  Created by Luke on 7/13/25.
//

import AVFAudio

final class SilentAudioKeepAlive {
    static let shared = SilentAudioKeepAlive()

    private let engine = AVAudioEngine()
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        try? AVAudioSession.sharedInstance()
             .setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        
        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in abl {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: nil)
        try? engine.start()
    }
}
