//
//  MagnetModel.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI
import Combine

/// Real-time physics simulator for the Magnet fidget.
///
/// The knob is a loose "magnet" riding a MagSafe-style attractive ring band.
/// While `attached` it slides pole-to-pole around the band (the same finger
/// spring + sinusoidal detent-well math as `DialModel`, applied tangentially)
/// and resists being peeled off radially until a breakaway threshold lets it
/// go. Once `free` it roams with plain inertia until it drifts back within
/// the ring's capture annulus, where an inverse-square pull grabs it back.
/// The four screen bezels carry the opposite polarity and always repel the
/// knob, growing sharply the closer it gets — containment falls out of that
/// force rather than a hard bounce.
class MagnetModel: ObservableObject {

    enum CouplingState {
        case attached   // riding the ring band
        case capturing  // free, but inside the ring's capture annulus — being pulled in
        case free       // loose, inertia only
    }

    // MARK: - Published Visual/Interaction State

    @Published var position: CGPoint = .zero      // knob center, relative to ring center
    @Published var couplingState: CouplingState = .attached
    @Published var couplingStrength: Double = 1.0 // 0 (loose) → 1 (locked); drives visual/haptic crossfades
    @Published var isDragging: Bool = false
    @Published var isPressed: Bool = false

    // MARK: - Tunable Physics Parameters (starting points; tune by feel)

    @Published var mass: Double = 0.25
    @Published var damping: Double = 3.5

    @Published var fingerSpringConstant: Double = 420.0     // radial finger coupling while attached
    @Published var tangentialFingerSpring: Double = 3200.0  // angular finger coupling while attached
    @Published var freeFollowStiffness: Double = 1400.0     // how tightly a free/capturing knob tracks the finger

    @Published var ringRadius: Double = 140.0
    @Published var poleCount: Int = 24
    @Published var detentForceStrength: Double = 26.0

    @Published var radialSpringConstant: Double = 55.0
    @Published var radialSpringCubic: Double = 0.018
    @Published var breakawayOutward: Double = 46.0
    @Published var breakawayInward: Double = 50.0

    @Published var captureAnnulusWidth: Double = 46.0
    @Published var captureGain: Double = 6000.0
    @Published var snapRadius: Double = 14.0

    @Published var bezelRepelDistance: Double = 32.0
    @Published var bezelRepelGain: Double = 900.0

    @Published var baseHapticIntensity: Double = 0.6
    @Published var baseHapticSharpness: Double = 0.5

    // MARK: - Motion State Variables

    var velocity: CGVector = .zero
    var fingerPosition: CGPoint = .zero   // absolute canvas coordinates

    private var ringCenter: CGPoint = .zero
    private var canvasSize: CGSize = .zero

    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var lastTriggeredPoleIndex: Int = 0

    init() {
        position = CGPoint(x: ringRadius, y: 0)
        lastTriggeredPoleIndex = poleIndex(for: 0)
    }

    // MARK: - Setup

    /// Tell the model where the ring lives in the view's coordinate space.
    func configure(canvasSize: CGSize) {
        self.canvasSize = canvasSize
        ringCenter = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    }

    // MARK: - Public Gesture Handlers

    func handleDragStarted(at point: CGPoint) {
        isDragging = true
        isPressed = true
        fingerPosition = point
        startDisplayLink()
    }

    func handleDragUpdated(to point: CGPoint) {
        fingerPosition = point
    }

    func handleDragEnded() {
        isDragging = false
        isPressed = false
        // Let it run free. CADisplayLink continues until momentum/haptics settle.
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
        var dt = link.timestamp - lastFrameTimestamp
        if dt <= 0 || dt > 0.1 { dt = 1.0 / 60.0 }
        lastFrameTimestamp = link.timestamp

        let fingerVector = CGVector(dx: fingerPosition.x - ringCenter.x, dy: fingerPosition.y - ringCenter.y)

        var force: CGVector
        switch couplingState {
        case .attached:
            force = attachedCouplingForce(fingerVector: fingerVector)
        case .capturing:
            force = capturingCouplingForce() + freeCouplingForce(fingerVector: fingerVector)
        case .free:
            force = freeCouplingForce(fingerVector: fingerVector)
        }

        force += bezelRepulsionForce()
        force += CGVector(dx: -damping * velocity.dx, dy: -damping * velocity.dy)

        integrate(force: force, dt: dt)
        evaluateStateTransitions()
        updateContinuousHaptics()
        maybeSleep()
    }

    // MARK: - Per-State Forces

    /// Radial band-holding spring + sinusoidal per-pole detent wells, both
    /// stiffened by a competing finger-coupling spring while dragging.
    private func attachedCouplingForce(fingerVector: CGVector) -> CGVector {
        let r = max(hypot(position.x, position.y), 0.0001)
        let theta = atan2(position.y, position.x)
        let er = CGVector(dx: position.x / r, dy: position.y / r)
        let et = CGVector(dx: -er.dy, dy: er.dx)

        let stretch = r - ringRadius
        var radialMag = -radialSpringConstant * stretch - radialSpringCubic * pow(stretch, 3)
        var tangentialMag = -detentForceStrength * sin(Double(poleCount) * theta)

        if isDragging {
            let fingerR = hypot(fingerVector.dx, fingerVector.dy)
            radialMag += fingerSpringConstant * (fingerR - r)

            let fingerTheta = atan2(fingerVector.dy, fingerVector.dx)
            var diff = fingerTheta - theta
            while diff > .pi { diff -= 2.0 * .pi }
            while diff < -.pi { diff += 2.0 * .pi }
            tangentialMag += tangentialFingerSpring * diff
        }

        return CGVector(dx: er.dx * radialMag + et.dx * tangentialMag,
                         dy: er.dy * radialMag + et.dy * tangentialMag)
    }

    /// Inverse-square-ish pull toward the ring band, capped so it doesn't blow up at close range.
    private func capturingCouplingForce() -> CGVector {
        let r = max(hypot(position.x, position.y), 0.0001)
        let er = CGVector(dx: position.x / r, dy: position.y / r)
        let stretch = r - ringRadius
        let distance = max(abs(stretch), 3.0)
        let pullMag = min(captureGain / (distance * distance), captureGain / 9.0)
        let signedPull = stretch >= 0 ? -pullMag : pullMag
        return CGVector(dx: er.dx * signedPull, dy: er.dy * signedPull)
    }

    /// Spring-follow toward the finger; zero when not being dragged (pure inertia).
    private func freeCouplingForce(fingerVector: CGVector) -> CGVector {
        guard isDragging else { return .zero }
        return CGVector(dx: freeFollowStiffness * (fingerVector.dx - position.x),
                         dy: freeFollowStiffness * (fingerVector.dy - position.y))
    }

    /// The screen bezels carry the opposite polarity: always pushing back, harder the closer you get.
    private func bezelRepulsionForce() -> CGVector {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .zero }
        let absX = ringCenter.x + position.x
        let absY = ringCenter.y + position.y

        func repel(_ distance: Double) -> Double {
            guard distance < bezelRepelDistance, distance > 0 else { return 0 }
            return bezelRepelGain / (distance * distance)
        }

        let maxForce = bezelRepelGain / 16.0
        var fx = repel(absX) - repel(canvasSize.width - absX)
        var fy = repel(absY) - repel(canvasSize.height - absY)
        fx = max(-maxForce, min(maxForce, fx))
        fy = max(-maxForce, min(maxForce, fy))
        return CGVector(dx: fx, dy: fy)
    }

    // MARK: - Integration

    private func integrate(force: CGVector, dt: Double) {
        let m = max(mass, 0.01)
        velocity.dx += (force.dx / m) * dt
        velocity.dy += (force.dy / m) * dt
        position.x += velocity.dx * dt
        position.y += velocity.dy * dt
    }

    // MARK: - State Machine

    private func evaluateStateTransitions() {
        let r = hypot(position.x, position.y)
        let theta = atan2(position.y, position.x)

        switch couplingState {
        case .attached:
            couplingStrength = 1.0
            handlePoleCrossing(theta: theta)

            let stretch = r - ringRadius
            if stretch > breakawayOutward || stretch < -breakawayInward {
                breakAway()
            }

        case .capturing:
            let distanceFromBand = abs(r - ringRadius)
            couplingStrength = 1.0 - min(distanceFromBand / captureAnnulusWidth, 1.0)

            if distanceFromBand < snapRadius {
                snapToRing(theta: theta)
            } else if distanceFromBand > captureAnnulusWidth {
                couplingState = .free
                couplingStrength = 0
            }

        case .free:
            couplingStrength = 0
            if abs(r - ringRadius) < captureAnnulusWidth {
                couplingState = .capturing
            }
        }
    }

    private func breakAway() {
        couplingState = .free
        couplingStrength = 0
        HapticsManager.shared.playClick(intensity: 0.7, sharpness: 0.9)
        SoundManager.shared.playSystemClick()
    }

    private func snapToRing(theta: Double) {
        let step = 2.0 * Double.pi / Double(poleCount)
        let snappedTheta = round(theta / step) * step
        position = CGPoint(x: cos(snappedTheta) * ringRadius, y: sin(snappedTheta) * ringRadius)

        // Preserve tangential momentum; kill the radial component so it doesn't re-stretch instantly.
        let et = CGVector(dx: -sin(snappedTheta), dy: cos(snappedTheta))
        let tangentialSpeed = velocity.dx * et.dx + velocity.dy * et.dy
        velocity = CGVector(dx: et.dx * tangentialSpeed, dy: et.dy * tangentialSpeed)

        couplingState = .attached
        couplingStrength = 1.0
        lastTriggeredPoleIndex = poleIndex(for: snappedTheta)

        HapticsManager.shared.playClick(intensity: 0.9, sharpness: 0.55)
        SoundManager.shared.playSystemClick()
    }

    // MARK: - Detent (Pole) Crossing

    private func poleIndex(for theta: Double) -> Int {
        let step = 2.0 * Double.pi / Double(poleCount)
        return Int(round(theta / step))
    }

    private func handlePoleCrossing(theta: Double) {
        let index = poleIndex(for: theta)
        guard index != lastTriggeredPoleIndex else { return }
        lastTriggeredPoleIndex = index

        let alpha = tangentialCrossfadeAlpha()
        guard alpha < 1.0 else { return } // fully continuous already; the whirr covers it
        HapticsManager.shared.playClick(intensity: baseHapticIntensity * (1 - alpha), sharpness: baseHapticSharpness)
        SoundManager.shared.playSystemClick()
    }

    private func tangentialCrossfadeAlpha() -> Double {
        let speed = hypot(velocity.dx, velocity.dy)
        let angularSpeed = speed / max(ringRadius, 1)
        let repetitionHz = (angularSpeed * Double(poleCount)) / (2.0 * .pi)
        return min(max((repetitionHz - 10.0) / 10.0, 0.0), 1.0)
    }

    // MARK: - Continuous Haptics

    /// Only one continuous channel can play at a time, so pick whichever
    /// physical event is currently strongest and let it speak.
    private func updateContinuousHaptics() {
        var candidates: [(intensity: Double, sharpness: Double, frequency: Float)] = []

        switch couplingState {
        case .attached:
            let alpha = tangentialCrossfadeAlpha()
            let speed = hypot(velocity.dx, velocity.dy)
            if alpha > 0, speed > 3 {
                let intensity = min((speed / 500.0) * alpha, 1.0)
                let sharpness = baseHapticSharpness + 0.3 * alpha
                let repetitionHz = (speed / max(ringRadius, 1)) * Double(poleCount) / (2.0 * .pi)
                candidates.append((intensity, sharpness, Float(repetitionHz * 4)))
            }

            let r = hypot(position.x, position.y)
            let stretchFraction = min(abs(r - ringRadius) / max(breakawayOutward, 1), 1.0)
            if stretchFraction > 0.05 {
                let intensity = 0.1 + 0.5 * stretchFraction
                let sharpness = 0.3 + 0.45 * stretchFraction
                candidates.append((intensity, sharpness, Float(70 + stretchFraction * 60)))
            }

        case .capturing:
            let intensity = 0.05 + 0.3 * couplingStrength
            candidates.append((intensity, 0.2, Float(60 + couplingStrength * 40)))

        case .free:
            break
        }

        let edgeDistance = nearestEdgeDistance()
        if edgeDistance < bezelRepelDistance {
            let proximity = 1.0 - (edgeDistance / bezelRepelDistance)
            let intensity = 0.08 + 0.4 * proximity
            let sharpness = 0.25 + 0.2 * proximity
            candidates.append((intensity, sharpness, Float(50 + proximity * 30)))
        }

        guard let dominant = candidates.max(by: { $0.intensity < $1.intensity }) else {
            HapticsManager.shared.stopContinuousFeedback()
            SoundManager.shared.stopOscillator()
            return
        }

        let intensity = min(dominant.intensity, 1.0)
        let sharpness = min(dominant.sharpness, 1.0)
        HapticsManager.shared.startContinuousFeedback(intensity: intensity, sharpness: sharpness)
        SoundManager.shared.startOscillator(frequency: dominant.frequency, volume: Float(intensity * 0.05))
    }

    private func nearestEdgeDistance() -> Double {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .infinity }
        let absX = ringCenter.x + position.x
        let absY = ringCenter.y + position.y
        return min(absX, canvasSize.width - absX, absY, canvasSize.height - absY)
    }

    // MARK: - Deactivation

    private func maybeSleep() {
        guard !isDragging else { return }
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed < 0.5 else { return }

        switch couplingState {
        case .attached:
            let r = hypot(position.x, position.y)
            let theta = atan2(position.y, position.x)
            let step = 2.0 * Double.pi / Double(poleCount)
            let settledDelta = abs(theta.truncatingRemainder(dividingBy: step))
            let closeToBand = abs(r - ringRadius) < 0.5
            let closeToPole = settledDelta < 0.02 || settledDelta > (step - 0.02)
            guard closeToBand && closeToPole else { return }
        case .capturing:
            return // keep simulating until it snaps or drifts back out
        case .free:
            break
        }

        velocity = .zero
        HapticsManager.shared.stopContinuousFeedback()
        SoundManager.shared.stopOscillator()
        stopDisplayLink()
    }
}

private extension CGVector {
    static func + (lhs: CGVector, rhs: CGVector) -> CGVector {
        CGVector(dx: lhs.dx + rhs.dx, dy: lhs.dy + rhs.dy)
    }

    static func += (lhs: inout CGVector, rhs: CGVector) {
        lhs = lhs + rhs
    }
}
