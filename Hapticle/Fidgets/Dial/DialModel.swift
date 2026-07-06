import SwiftUI
import Combine

/// Real-time physics simulator for the Neumorphic dial.
/// Implements Newton's second rotational law, virtual spring touch coupling,
/// sinusoidal potential energy detent wells, and real-time Hz estimation for sensory cross-fades.
class DialModel: ObservableObject {
    // MARK: - Published Physics States
    @Published var rotationAngle: Double = 0.0
    @Published var isDragging: Bool = false
    @Published var isPressed: Bool = false
    
    // MARK: - Tunable Physics Parameters (Exposed to Debug View)
    @Published var mass: Double = 0.2                     // Dial Mass (controls inertia)
    @Published var damping: Double = 3.0                  // Damping Coefficient (friction)
    @Published var springConstant: Double = 350.0          // Touch spring coupling constant
    @Published var detentTorqueStrength: Double = 25.0     // Potential energy well depth
    @Published var detentCount: Int = 24                  // Number of teeth (ticks) on the gear
    
    @Published var baseHapticIntensity: Double = 0.6
    @Published var baseHapticSharpness: Double = 0.5
    
    // MARK: - Motion State Variables
    var angularVelocity: Double = 0.0
    var fingerAngle: Double = 0.0
    
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var lastTriggeredDetentIndex: Int = 0
    
    init() {
        // Initialize detent index based on start angle
        lastTriggeredDetentIndex = currentDetentIndex()
    }
    
    // MARK: - Public Gesture Handlers
    
    func handleDragStarted(at point: CGPoint, dialCenter: CGPoint) {
        isDragging = true
        isPressed = true
        fingerAngle = calculateAngle(from: point, relativeTo: dialCenter)
        
        // Start simulation loop if not already running
        startDisplayLink()
    }
    
    func handleDragUpdated(to point: CGPoint, dialCenter: CGPoint) {
        fingerAngle = calculateAngle(from: point, relativeTo: dialCenter)
    }
    
    func handleDragEnded(velocity: CGSize) {
        isDragging = false
        isPressed = false
        // Let it run free. CADisplayLink continues running until momentum decays.
    }
    
    func resetPhysics() {
        rotationAngle = 0.0
        angularVelocity = 0.0
        isDragging = false
        isPressed = false
        lastTriggeredDetentIndex = 0
        stopDisplayLink()
        
        HapticsManager.shared.stopContinuousFeedback()
        SoundManager.shared.stopOscillator()
    }
    
    // MARK: - CADisplayLink Physics Loop
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastFrameTimestamp = CACurrentMediaTime()
        
        let link = CADisplayLink(target: self, selector: #selector(stepPhysics))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = 0
    }
    
    @objc private func stepPhysics(link: CADisplayLink) {
        let currentTimestamp = link.timestamp
        var dt = currentTimestamp - lastFrameTimestamp
        
        // Safety bounds for dt (avoid explosions when transitioning scenes or dropping frames)
        if dt <= 0 || dt > 0.1 {
            dt = 1.0 / 60.0
        }
        lastFrameTimestamp = currentTimestamp
        
        // 1. Calculate Torques (Newton's 2nd Law for Rotation: τ = I * α)
        
        // Torsion coupling spring torque (pulls dial toward finger angle during drag)
        var touchTorque = 0.0
        if isDragging {
            var diff = fingerAngle - rotationAngle
            // Unwrapping/normalizing rotation angle difference to (-π, π) range
            while diff > .pi { diff -= 2.0 * .pi }
            while diff < -.pi { diff += 2.0 * .pi }
            touchTorque = springConstant * diff
        }
        
        // Detent restoring torque (sinusoidal potential energy wells pulling to ticks)
        let n = Double(detentCount)
        let detentTorque = -detentTorqueStrength * sin(n * rotationAngle)
        
        // Friction damping torque (opposes velocity)
        let frictionTorque = -damping * angularVelocity
        
        // Net torque
        let netTorque = touchTorque + detentTorque + frictionTorque
        
        // Moment of Inertia (disc shape: I = 0.5 * m * r^2. Let's assume normalized r=1)
        let inertia = max(0.5 * mass, 0.01)
        
        // Calculate angular acceleration: α = τ / I
        let angularAcceleration = netTorque / inertia
        
        // 2. Integrate motion (Euler-Cromer method)
        angularVelocity += angularAcceleration * dt
        rotationAngle += angularVelocity * dt
        
        // 3. Process Detent Crossings (Ticks)
        let currentIndex = currentDetentIndex()
        if currentIndex != lastTriggeredDetentIndex {
            lastTriggeredDetentIndex = currentIndex
            
            // Calculate instantaneous click frequency (Hz)
            let speed = abs(angularVelocity)
            let f_rep = (speed * Double(detentCount)) / (2.0 * .pi)
            
            // Apply transient-to-continuous cross-fade factor (alpha)
            // Discrete under 10Hz, morphs to continuous between 10Hz and 20Hz
            let alpha = min(max((f_rep - 10.0) / 10.0, 0.0), 1.0)
            
            if alpha < 1.0 {
                // Synthesize transient click
                let intensity = baseHapticIntensity * (1.0 - alpha)
                HapticsManager.shared.playClick(intensity: intensity, sharpness: baseHapticSharpness)
                SoundManager.shared.playSystemClick()
            }
        }
        
        // 4. Process Continuous Friction & Whirr modulation
        let speed = abs(angularVelocity)
        let f_rep = (speed * Double(detentCount)) / (2.0 * .pi)
        let alpha = min(max((f_rep - 10.0) / 10.0, 0.0), 1.0)
        
        if alpha > 0.0 && speed > 0.05 {
            // Modulate continuous haptic rumble
            let intensity = (speed / 15.0) * alpha * 0.4
            let sharpness = baseHapticSharpness + 0.3 * alpha
            HapticsManager.shared.startContinuousFeedback(intensity: min(intensity, 1.0), sharpness: min(sharpness, 1.0))
            
            // Modulate continuous audio pitch whirr (fundamental frequency maps to f_rep)
            // Multiple resonances simulated by shifting pitch by a multiplier
            let volume = Float(alpha * min(speed / 15.0, 1.0) * 0.05)
            SoundManager.shared.startOscillator(frequency: Float(f_rep * 4.0), volume: volume)
        } else {
            HapticsManager.shared.stopContinuousFeedback()
            SoundManager.shared.stopOscillator()
        }
        
        // 5. Deactivation Check (Stop display link when dial settles in a detent well)
        if !isDragging && abs(angularVelocity) < 0.01 {
            // Check if settled in the potential well (close to sine zero)
            let settledAngle = 2.0 * .pi / Double(detentCount)
            let diffFromWell = abs(rotationAngle.truncatingRemainder(dividingBy: settledAngle))
            if diffFromWell < 0.02 || diffFromWell > (settledAngle - 0.02) {
                angularVelocity = 0.0
                HapticsManager.shared.stopContinuousFeedback()
                SoundManager.shared.stopOscillator()
                stopDisplayLink()
            }
        }
    }
    
    // MARK: - Private Helper Math
    
    private func calculateAngle(from point: CGPoint, relativeTo center: CGPoint) -> Double {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return atan2(dy, dx)
    }
    
    private func currentDetentIndex() -> Int {
        let angleStep = 2.0 * .pi / Double(detentCount)
        return Int(round(rotationAngle / angleStep))
    }
}
