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
    @Published var mass: Double = 2.0                     // Dial Mass (controls inertia)
    @Published var damping: Double = 1.5                 // Damping Coefficient (friction)
    @Published var detentDamping: Double = 6.0           // Detent localized oscillation damping
    @Published var springConstant: Double = 350.0          // Touch spring coupling constant
    @Published var detentTorqueStrength: Double = 25.0     // Potential energy well depth
    @Published var detentCount: Int = 24                  // Number of teeth (ticks) on the gear
    
    @Published var baseHapticIntensity: Double = 0.6
    @Published var baseHapticSharpness: Double = 0.5
    
    // MARK: - Motion State Variables
    var angularVelocity: Double = 0.0
    var fingerAngle: Double = 0.0
    var touchRadius: Double = 0.0
    
    private var startingFingerAngle: Double = 0.0
    private var startingRotationAngle: Double = 0.0
    private var wasCoupled: Bool = false
    
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
        
        let rx = point.x - dialCenter.x
        let ry = point.y - dialCenter.y
        touchRadius = Double(hypot(rx, ry))
        
        let currentAngle = calculateAngle(from: point, relativeTo: dialCenter)
        let rInner = 40.0
        if touchRadius >= rInner {
            startingFingerAngle = currentAngle
            startingRotationAngle = rotationAngle
            fingerAngle = startingFingerAngle
            wasCoupled = true
        } else {
            wasCoupled = false
        }
        
        // Start simulation loop if not already running
        startDisplayLink()
    }
    
    func handleDragUpdated(to point: CGPoint, dialCenter: CGPoint) {
        let rx = point.x - dialCenter.x
        let ry = point.y - dialCenter.y
        touchRadius = Double(hypot(rx, ry))
        
        let currentFinger = calculateAngle(from: point, relativeTo: dialCenter)
        let rInner = 40.0
        
        if touchRadius >= rInner {
            if !wasCoupled {
                // Re-anchor when exiting the deadzone to prevent snapping
                startingFingerAngle = currentFinger
                startingRotationAngle = rotationAngle
                fingerAngle = startingFingerAngle
                wasCoupled = true
            } else {
                var diff = currentFinger - startingFingerAngle
                while diff > .pi { diff -= 2.0 * .pi }
                while diff < -.pi { diff += 2.0 * .pi }
                
                fingerAngle = startingRotationAngle + diff
            }
        } else {
            wasCoupled = false
        }
    }
    
    func handleDragEnded(velocity: CGSize, touchPoint: CGPoint, dialCenter: CGPoint) {
        isDragging = false
        isPressed = false
        wasCoupled = false
        
        let rx = touchPoint.x - dialCenter.x
        let ry = touchPoint.y - dialCenter.y
        let r = Double(hypot(rx, ry))
        let r2 = max(rx * rx + ry * ry, 100.0) // prevent division by zero
        
        let vx = Double(velocity.width)
        let vy = Double(velocity.height)
        
        // Angular velocity: ω = (rx * vy - ry * vx) / r^2
        var computedAngularVelocity = (Double(rx) * vy - Double(ry) * vx) / Double(r2)
        
        // Scale down the initial velocity if released inside or near the deadzone
        let rInner = 40.0
        let rOuter = 80.0
        var velocityMultiplier = 1.0
        if r < rInner {
            velocityMultiplier = 0.0
        } else if r < rOuter {
            velocityMultiplier = (r - rInner) / (rOuter - rInner)
        }
        computedAngularVelocity *= velocityMultiplier
        
        // Cap the maximum initial angular velocity to prevent extreme spinning
        let maxVelocity = 40.0 // rad/s (~6.3 rev/s)
        self.angularVelocity = min(max(computedAngularVelocity, -maxVelocity), maxVelocity)
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
        
        let rInner = 40.0
        let n = Double(detentCount)
        var touchTorque = 0.0
        
        // Detent-specific localized damping window (maximized at the bottom of the potential wells)
        let detentWindow = (1.0 + cos(n * rotationAngle)) / 2.0
        var activeDamping = damping + detentDamping * detentWindow
        
        if isDragging {
            if touchRadius >= rInner {
                var diff = fingerAngle - rotationAngle
                while diff > .pi { diff -= 2.0 * .pi }
                while diff < -.pi { diff += 2.0 * .pi }
                touchTorque = springConstant * diff
            } else {
                // In Deadzone: Temporarily act as finger-up (no spring torque)
                // and apply heavy damping (braking) to rotation
                activeDamping = (damping + detentDamping * detentWindow) * 4.0
            }
        }
        
        // Detent restoring torque (sinusoidal potential energy wells pulling to ticks)
        let n = Double(detentCount)
        let detentTorque = -detentTorqueStrength * sin(n * rotationAngle)
        
        // Friction damping torque (opposes velocity)
        let frictionTorque = -activeDamping * angularVelocity
        
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
            // Discrete under 16Hz, morphs to continuous between 16Hz and 28Hz
            let alpha = min(max((f_rep - 16.0) / 12.0, 0.0), 1.0)
            
            if alpha < 1.0 {
                // Synthesize transient click with a gentler quadratic fade-out
                let intensity = baseHapticIntensity * (1.0 - alpha * alpha)
                HapticsManager.shared.playClick(intensity: intensity, sharpness: baseHapticSharpness)
                SoundManager.shared.playSystemClick()
            }
        }
        
        // 4. Process Continuous Friction & Whirr modulation
        let speed = abs(angularVelocity)
        let f_rep = (speed * Double(detentCount)) / (2.0 * .pi)
        let alpha = min(max((f_rep - 16.0) / 12.0, 0.0), 1.0)
        
        if speed > 0.05 {
            // Modulate continuous haptic rumble (surface friction + whirr intensity)
            // Even at slow speeds, we want a base surface friction rumble (intensity ~0.15)
            let frictionIntensity = min((speed / 15.0) * 0.2 + 0.15, 0.4)
            // Use sqrt(alpha) for a rapid, early fade-in of the whirr to bridge the transition zone
            let intensity = frictionIntensity + (speed / 10.0) * sqrt(alpha) * 0.6
            let sharpness = baseHapticSharpness + 0.4 * alpha
            HapticsManager.shared.startContinuousFeedback(intensity: min(intensity, 1.0), sharpness: min(sharpness, 1.0))
            
            if alpha > 0.0 {
                // Modulate continuous audio pitch whirr
                let volume = Float(alpha * min(speed / 15.0, 1.0) * 0.18)
                SoundManager.shared.startOscillator(frequency: Float(f_rep), volume: volume)
            } else {
                SoundManager.shared.stopOscillator()
            }
        } else {
            // Mute continuous rumble instead of destroying the player immediately
            HapticsManager.shared.startContinuousFeedback(intensity: 0.0, sharpness: 0.0)
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
