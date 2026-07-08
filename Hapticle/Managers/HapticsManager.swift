import SwiftUI
import CoreHaptics

class HapticsManager {
    static let shared = HapticsManager()
    
    private var engine: CHHapticEngine?
    private var continuousPlayer: CHHapticAdvancedPatternPlayer?
    private var isEngineSupported: Bool = false
    
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
            isEngineSupported = true
            
            // Automatically restart the engine if it stops asynchronously
            engine?.stoppedHandler = { reason in
                print("Haptic Engine Stopped: \(reason)")
            }
            engine?.resetHandler = { [weak self] in
                print("Haptic Engine Reset")
                try? self?.engine?.start()
            }
        } catch {
            print("Failed to initialize Haptic Engine: \(error)")
            isEngineSupported = false
        }
    }
    
    func playClick(intensity: Double, sharpness: Double) {
        let intensity = intensity.clampedToUnit
        let sharpness = sharpness.clampedToUnit
        if isEngineSupported, let engine = engine {
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
        let intensity = intensity.clampedToUnit
        let sharpness = sharpness.clampedToUnit
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
        let intensity = intensity.clampedToUnit
        let sharpness = sharpness.clampedToUnit
        do {
            let intensityParam = CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: Float(intensity), relativeTime: 0)
            let sharpnessParam = CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: Float(sharpness), relativeTime: 0)
            try player.sendParameters([intensityParam, sharpnessParam], atTime: CHHapticTimeImmediate)
        } catch {
            print("Failed to update continuous haptics: \(error)")
        }
    }
    
    func stopContinuousFeedback() {
        guard isEngineSupported else { return }
        try? continuousPlayer?.stop(atTime: CHHapticTimeImmediate)
        continuousPlayer = nil
    }
}

private extension Double {
    /// Core Haptics intensity/sharpness must be within 0…1; clamp defensively
    /// so an out-of-range tuning value degrades gracefully instead of failing.
    var clampedToUnit: Double { Swift.max(0, Swift.min(1, self)) }
}
