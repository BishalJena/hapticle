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
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        audioEngine = engine
        sampleRate = engine.mainMixerNode.outputFormat(forBus: 0).sampleRate
        
        // 1. Create the procedural synthesizer node
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            
            let bufferPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let freq = self.currentFrequency
            let vol = self.currentVolume
            let step = (2.0 * Float.pi * freq) / Float(self.sampleRate)
            
            for frame in 0..<Int(frameCount) {
                // Generate a simple sine wave with exponential decay envelope if needed,
                // or continuously tracking the speed.
                let sample = sin(self.phase) * vol
                self.phase += step
                if self.phase >= 2.0 * Float.pi {
                    self.phase -= 2.0 * Float.pi
                }
                
                for buffer in bufferPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    if frame < buf.count {
                        buf[frame] = sample
                    }
                }
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
