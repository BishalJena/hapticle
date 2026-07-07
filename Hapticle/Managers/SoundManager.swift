import Foundation
import AVFoundation
import AudioToolbox

class SoundManager {
    static let shared = SoundManager()
    
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    
    private var currentFrequency: Float = 100.0
    private var currentVolume: Float = 0.0
    private var sampleRate: Double = 44100.0
    private var isOscillatorRunning = false
    private var phase: Float = 0.0
    
    init() {
        configureAudioSession()
        setupAudioEngine()
    }
    
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Set the audio session category to .playback with .mixWithOthers option.
            // This prevents iOS from ducking system sounds (like the Digital Crown tick)
            // when the AVAudioEngine is active.
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        audioEngine = engine
        sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        
        // 1. Create the procedural synthesizer node with correct channel-first loop nesting
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let freq = self.currentFrequency
            let vol = self.currentVolume
            let step = (2.0 * Float.pi * freq) / Float(self.sampleRate)
            
            // Loop over channels first to handle multi-channel layouts correctly
            for channel in 0..<ablPointer.count {
                let buffer = ablPointer[channel]
                guard let buf = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                
                // Track channel-specific phase to keep channels in sync
                var channelPhase = self.phase
                for frame in 0..<Int(frameCount) {
                    buf[frame] = sin(channelPhase) * vol
                    channelPhase += step
                    if channelPhase >= 2.0 * Float.pi {
                        channelPhase -= 2.0 * Float.pi
                    }
                }
            }
            
            // Update master phase once after processing all channels
            self.phase += step * Float(frameCount)
            while self.phase >= 2.0 * Float.pi {
                self.phase -= 2.0 * Float.pi
            }
            
            return noErr
        }
        
        guard let sourceNode = sourceNode else { return }
        engine.attach(sourceNode)
        
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        
        do {
            try engine.start()
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    /// Play a short, crisp transient click sample using the low-latency system sound services.
    func playSystemClick() {
        // SystemSoundID 1104 is the native iOS Digital Crown / selector tick click
        AudioServicesPlaySystemSound(1104)
    }
    
    /// Start the continuous whirr oscillator.
    func startOscillator(frequency: Float, volume: Float) {
        currentFrequency = frequency
        currentVolume = volume
        
        if !isOscillatorRunning {
            isOscillatorRunning = true
            // If engine is not running, attempt restart
            if let engine = audioEngine, !engine.isRunning {
                try? engine.start()
            }
        }
    }
    
    /// Update the continuous oscillator pitch and volume.
    func updateOscillator(frequency: Float, volume: Float) {
        currentFrequency = frequency
        currentVolume = volume
    }
    
    /// Stop/mute the oscillator.
    func stopOscillator() {
        currentVolume = 0.0
        isOscillatorRunning = false
    }
}
