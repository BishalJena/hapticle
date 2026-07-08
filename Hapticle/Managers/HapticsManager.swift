import SwiftUI
import CoreHaptics

class HapticsManager {
    static let shared = HapticsManager()
    
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var isEngineSupported: Bool = false
    private var isEngineRunning: Bool = false
    
    // Throttling for transient clicks (prevent CoreHaptics 32Hz rate-limit warnings)
    private var lastClickTime: TimeInterval = 0
    private let minClickInterval: TimeInterval = 0.030 // 30ms gap (approx 33Hz max)
    
    // Fallback generators for Simulators and non-CoreHaptics hardware
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    init() {
        prepareEngine()
        impactLight.prepare()
        impactMedium.prepare()
        impactHeavy.prepare()
        selectionFeedback.prepare()
    }
    
    private func prepareEngine() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            isEngineSupported = false
            return
        }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            isEngineRunning = true
            isEngineSupported = true
            
            // Automatically restart the engine if it stops asynchronously
            engine?.stoppedHandler = { [weak self] reason in
                print("Haptic Engine Stopped: \(reason)")
                self?.isEngineRunning = false
            }
            engine?.resetHandler = { [weak self] in
                print("Haptic Engine Reset")
                try? self?.engine?.start()
                self?.isEngineRunning = true
            }
        } catch {
            print("Failed to initialize Haptic Engine: \(error)")
            isEngineSupported = false
            isEngineRunning = false
        }
    }
    
    func playClick(intensity: Double, sharpness: Double) {
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastClickTime >= minClickInterval else {
            // Drop clicks exceeding rate-limit to prevent CHHaptic system drops
            return
        }
        
        if isEngineSupported, let engine = engine {
            // Ensure engine is running before starting the player (fixes error -4805)
            if !isEngineRunning {
                do {
                    try engine.start()
                    isEngineRunning = true
                } catch {
                    print("Failed to restart Haptic Engine: \(error)")
                    playFallbackClick(intensity: intensity)
                    return
                }
            }
            
            lastClickTime = currentTime
            do {
                let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity))
                let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
                
                let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensityParam, sharpnessParam], relativeTime: 0)
                let pattern = try CHHapticPattern(events: [event], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
            } catch {
                playFallbackClick(intensity: intensity)
            }
        } else {
            lastClickTime = currentTime
            playFallbackClick(intensity: intensity)
        }
    }
    
    private func playFallbackClick(intensity: Double) {
        if intensity > 0.7 {
            impactHeavy.impactOccurred()
        } else if intensity > 0.4 {
            impactMedium.impactOccurred()
        } else {
            selectionFeedback.selectionChanged()
        }
    }
    
    func startContinuousFeedback(intensity: Double, sharpness: Double) {
        guard isEngineSupported, let engine = engine else { return }
        
        // Ensure engine is running before starting continuous feedback
        if !isEngineRunning {
            do {
                try engine.start()
                isEngineRunning = true
            } catch {
                print("Failed to restart Haptic Engine for continuous feedback: \(error)")
                return
            }
        }
        
        do {
            if continuousPlayer != nil {
                updateContinuousFeedback(intensity: intensity, sharpness: sharpness)
                return
            }
            
            let intensityParam = CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity))
            let sharpnessParam = CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
            
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [intensityParam, sharpnessParam], relativeTime: 0, duration: 100)
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            continuousPlayer = try engine.makeAdvancedPlayer(with: pattern)
            try continuousPlayer?.start(atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to start continuous feedback: \(error)")
        }
    }
    
    func updateContinuousFeedback(intensity: Double, sharpness: Double) {
        guard isEngineSupported, let player = continuousPlayer else { return }
        
        do {
            let intensityParam = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(intensity), relativeTime: 0)
            let sharpnessParam = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: Float(sharpness), relativeTime: 0)
            try player.sendParameters([intensityParam, sharpnessParam], atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to update continuous haptics, invalidating player: \(error)")
            continuousPlayer = nil // Invalidate player so it is recreated on the next frame
        }
    }
    
    func stopContinuousFeedback() {
        guard isEngineSupported else { return }
        try? continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        continuousPlayer = nil
    }
}
