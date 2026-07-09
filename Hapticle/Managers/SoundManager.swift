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
    private var carrierPhase: Float = 0.0
    private var shaftPhase: Float = 0.0
    
    // MARK: - Tearing Synth (Ticket fidget: perforation noise-burst texture)
    
    private var tearSourceNode: AVAudioSourceNode?
    private var currentTearRate: Float = 0.0       // perforation crossings per second
    private var currentTearVolume: Float = 0.0
    private var tearPhase: Float = 0.0
    private var tearLP1: Float = 0.0               // wider lowpass (bandpass upper corner)
    private var tearLP2: Float = 0.0               // narrower lowpass (bandpass lower corner)
    private var isTearingActive = false
    
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
        
        // 1. Create the procedural synthesizer node to simulate physical mechanical clicks (casing resonance)
        sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let freq = self.currentFrequency // repetition frequency of detent crossings
            let vol = self.currentVolume
            
            // Detent crossing phase step
            let step = (2.0 * Float.pi * freq) / Float(self.sampleRate)
            
            // Mechanical casing resonance frequency (e.g. 1600 Hz)
            let carrierFreq: Float = 1600.0
            let carrierStep = (2.0 * Float.pi * carrierFreq) / Float(self.sampleRate)
            
            // Shaft rotation rate LFO frequency (repetition rate divided by detent count of 24)
            let shaftFreq = freq / 24.0
            let shaftStep = (2.0 * Float.pi * shaftFreq) / Float(self.sampleRate)
            
            // Loop over channels first to handle multi-channel layouts correctly
            for channel in 0..<ablPointer.count {
                let buffer = ablPointer[channel]
                guard let buf = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                
                var channelPhase = self.phase
                var channelCarrierPhase = self.carrierPhase
                var channelShaftPhase = self.shaftPhase
                
                for frame in 0..<Int(frameCount) {
                    // Exponential decay envelope from 1.0 to near 0.0 inside the detent cycle [0, 2pi]
                    let progress = channelPhase / (2.0 * Float.pi)
                    let envelope = exp(-12.0 * progress)
                    
                    // LFO representing shaft rotation eccentricity (subtle 30% amplitude modulation)
                    let lfo = 1.0 + 0.30 * sin(channelShaftPhase)
                    
                    // Add random micro-friction grit to mimic plastic/metallic teeth roughness
                    let grit = Float.random(in: -0.15...0.15)
                    let signal = sin(channelCarrierPhase) + grit
                    
                    // Synthesize final mechanical casing impact with LFO and texture grit
                    buf[frame] = signal * envelope * lfo * vol
                    
                    channelPhase += step
                    if channelPhase >= 2.0 * Float.pi {
                        channelPhase -= 2.0 * Float.pi
                    }
                    
                    channelCarrierPhase += carrierStep
                    if channelCarrierPhase >= 2.0 * Float.pi {
                        channelCarrierPhase -= 2.0 * Float.pi
                    }
                    
                    channelShaftPhase += shaftStep
                    if channelShaftPhase >= 2.0 * Float.pi {
                        channelShaftPhase -= 2.0 * Float.pi
                    }
                }
            }
            
            // Update master phases once after processing all channels
            self.phase += step * Float(frameCount)
            while self.phase >= 2.0 * Float.pi {
                self.phase -= 2.0 * Float.pi
            }
            
            self.carrierPhase += carrierStep * Float(frameCount)
            while self.carrierPhase >= 2.0 * Float.pi {
                self.carrierPhase -= 2.0 * Float.pi
            }
            
            self.shaftPhase += shaftStep * Float(frameCount)
            while self.shaftPhase >= 2.0 * Float.pi {
                self.shaftPhase -= 2.0 * Float.pi
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
    
    private func setupTearNode() {
        guard let engine = audioEngine, tearSourceNode == nil else { return }
        
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            let rate = max(self.currentTearRate, 0.001)
            let vol = self.currentTearVolume
            let step = (2.0 * Float.pi * rate) / Float(self.sampleRate)
            
            for channel in 0..<ablPointer.count {
                let buffer = ablPointer[channel]
                guard let buf = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                
                var phase = self.tearPhase
                var lp1 = self.tearLP1
                var lp2 = self.tearLP2
                
                for frame in 0..<Int(frameCount) {
                    // Sharp decaying envelope per "perforation snap" — snappier than the
                    // dial's resonance decay since a fiber snap is nearly instantaneous.
                    let progress = phase / (2.0 * Float.pi)
                    let envelope = exp(-12 * progress)
                    
                    // Raw broadband noise = the actual "tearing" source material
                    let whiteNoise = Float.random(in: -1...1)
                    
                    // Cascaded leaky-integrator lowpasses -> difference = crude bandpass,
                    // shaped to sit in the papery/crinkly mid-high range rather than full hiss.
                    lp1 += 0.5 * (whiteNoise - lp1)
                    lp2 += 0.02 * (whiteNoise - lp2)
                    let bandpassed = (lp1 - lp2) * 2.2
                    
                    // Sparse sharp impulses = individual fiber strands snapping ("crackle")
                    var crackle: Float = 0
                    if Float.random(in: 0...1) < 0.015 {
                        crackle = Float.random(in: -1...1) * 0.7
                    }
                    
                    buf[frame] = (bandpassed + crackle) * envelope * vol
                    
                    phase += step
                    if phase >= 2.0 * Float.pi { phase -= 2.0 * Float.pi }
                }
                
                self.tearPhase = phase
                self.tearLP1 = lp1
                self.tearLP2 = lp2
            }
            
            return noErr
        }
        
        engine.attach(node)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(node, to: engine.mainMixerNode, format: format)
        tearSourceNode = node
    }
    
    /// Start/refresh the continuous tearing texture.
    /// `rate` = perforation crossings per second (higher = faster "BRRRT").
    func startTearing(rate: Float, volume: Float) {
        setupTearNode()
        currentTearRate = rate
        currentTearVolume = volume
        if !isTearingActive {
            isTearingActive = true
            if let engine = audioEngine, !engine.isRunning { try? engine.start() }
        }
    }
    
    func updateTearing(rate: Float, volume: Float) {
        currentTearRate = rate
        currentTearVolume = volume
    }
    
    func stopTearing() {
        currentTearVolume = 0.0
        isTearingActive = false
    }
    
    /// Play a heavy, resonant pop for the final ticket severance.
    func playTearSnap() {
        AudioServicesPlaySystemSound(1520)
    }
}
