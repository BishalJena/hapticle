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
/// The whole screen is one continuous magnetic field. The ring band is a
/// uniformly magnetized attractor whose pull is felt everywhere — inverse
/// square with distance from the band, overwhelming at contact, a gentle
/// tug from across the screen — so a released magnet always glides home
/// and clacks onto the band. The four screen bezels carry the opposite
/// polarity and repel the magnet as it nears an edge. Sticking, strain,
/// breakaway, and recapture are not scripted states; they emerge from the
/// tug-of-war between the finger spring and the field. Haptics render the
/// field itself: rumble intensity tracks local field strength (the "haptic
/// map"), with discrete transients only for the physical clack of seating
/// and the pop of breaking free.
class MagnetModel: ObservableObject {

    // MARK: - Published Visual/Interaction State

    @Published var position: CGPoint = .zero   // knob center, relative to ring center
    @Published var isOnRing: Bool = true       // seated on the band (hysteresis; drives haptic transients + shadow)
    @Published var isDragging: Bool = false
    @Published var isPressed: Bool = false

    // MARK: - Tunable Physics Parameters (starting points; tune by feel)

    @Published var mass: Double = 0.25
    @Published var damping: Double = 1.8            // low friction so flicked orbits persist

    @Published var fingerSpring: Double = 1400.0    // spring pulling the knob toward the finger while dragging
    /// Damping while dragging, tuned near-critical for the finger spring
    /// (c_crit = 2·√(k·m) ≈ 37) so the knob trails the finger with a smooth,
    /// weighty lag instead of ringing around it.
    @Published var dragDamping: Double = 30.0

    @Published var ringRadius: Double = 140.0

    /// Ring field: F = fieldGain / (d² + softening²), toward the band, where
    /// d is the signed distance from the band. Clamped to [fieldFloor, fieldMax]:
    /// the cap keeps contact forces finite; the floor is a gameplay concession —
    /// a real far field decays toward zero, but the toy should always bring the
    /// magnet home in a second or two rather than strand it mid-glide.
    @Published var fieldGain: Double = 2_200_000.0
    @Published var fieldSoftening: Double = 8.0
    @Published var fieldFloor: Double = 450.0
    @Published var fieldMax: Double = 35_000.0

    /// Radius around the ring's exact center where the field fades to zero —
    /// the direction is undefined there. Physically this is the symmetry null
    /// of a ring magnet: an unstable equilibrium where the magnet can balance.
    @Published var centerNullRadius: Double = 30.0

    /// Seat/release hysteresis on |d| so contact transients don't chatter.
    @Published var contactDistance: Double = 10.0
    /// How far the finger must stretch from the band before a seated knob
    /// breaks free — a deliberate pull, so nothing unseats by accident.
    @Published var releaseDistance: Double = 48.0

    @Published var bezelRepelDistance: Double = 32.0
    @Published var bezelRepelGain: Double = 900.0

    /// Half of `MagnetView.knobDiameter`; the hard on-screen containment margin.
    let knobRadius: Double = 28.0

    // MARK: - Motion State Variables

    var velocity: CGVector = .zero
    var fingerPosition: CGPoint = .zero   // absolute canvas coordinates

    private var ringCenter: CGPoint = .zero
    private var canvasSize: CGSize = .zero

    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var slideDistanceSinceTick: Double = 0

    /// The near-band field is stiff (dF/dd is huge at contact), so a single
    /// 60 Hz Euler step can overshoot and jitter. Sub-stepping keeps the
    /// integration stable without softening the field.
    private let substeps = 4
    private let maxSpeed: Double = 5000.0

    init() {
        position = CGPoint(x: ringRadius, y: 0)
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
        // Momentum carries; the field takes over and brings it home.
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
        var frameDt = link.timestamp - lastFrameTimestamp
        if frameDt <= 0 || frameDt > 0.1 { frameDt = 1.0 / 60.0 }
        lastFrameTimestamp = link.timestamp

        let dt = frameDt / Double(substeps)
        for _ in 0..<substeps {
            var force = ringFieldForce() + bezelRepulsionForce()
            if isDragging {
                let fingerLocal = CGPoint(x: fingerPosition.x - ringCenter.x,
                                          y: fingerPosition.y - ringCenter.y)
                force += CGVector(dx: fingerSpring * (fingerLocal.x - position.x),
                                   dy: fingerSpring * (fingerLocal.y - position.y))
            }
            let friction = isDragging ? dragDamping : damping
            force += CGVector(dx: -friction * velocity.dx, dy: -friction * velocity.dy)
            if !isOnRing { force += approachRadialDamping() }
            integrate(force: force, dt: dt)
            clampToScreen()
            // Seated = bead on a wire: the band holds the knob exactly, so
            // orbits are perfect circles and there is nothing left to vibrate.
            if isOnRing { seatOnBand() }
        }

        updateSeatState()
        driveHaptics(dt: frameDt)
        maybeSleep()
    }

    // MARK: - The Field

    /// Attraction toward the nearest point of the ring band, felt everywhere.
    private func ringFieldForce() -> CGVector {
        let r = hypot(position.x, position.y)
        guard r > 0.001 else { return .zero } // exact center: symmetry null

        let d = r - ringRadius
        var magnitude = fieldGain / (d * d + fieldSoftening * fieldSoftening)
        magnitude = min(max(magnitude, fieldFloor), fieldMax)

        // Fade out approaching the center null so the force direction never flips abruptly.
        if r < centerNullRadius {
            let t = r / centerNullRadius
            magnitude *= t * t * (3 - 2 * t) // smoothstep
        }

        let er = CGVector(dx: position.x / r, dy: position.y / r)
        let towardBand: Double = d >= 0 ? -1 : 1
        return CGVector(dx: er.dx * magnitude * towardBand,
                         dy: er.dy * magnitude * towardBand)
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

    /// Near-critical damping of the radial velocity component as the knob
    /// nears the band. The inverse-square field is a very stiff spring there;
    /// without this the arrival rings at ~30 Hz instead of clacking once.
    private func approachRadialDamping() -> CGVector {
        let r = hypot(position.x, position.y)
        guard r > 0.001 else { return .zero }
        let d = abs(r - ringRadius)
        guard d < 48 else { return .zero }

        let kLocal = 2 * fieldGain / max(d * d * d, pow(fieldSoftening, 3))
        let cR = min(2 * (mass * kLocal).squareRoot(), 60)
        let er = CGVector(dx: position.x / r, dy: position.y / r)
        let radialSpeed = velocity.dx * er.dx + velocity.dy * er.dy
        return CGVector(dx: -cR * radialSpeed * er.dx, dy: -cR * radialSpeed * er.dy)
    }

    /// Hard constraint while seated: project onto the band and strip the
    /// radial velocity, keeping the tangential component for orbits.
    private func seatOnBand() {
        let r = hypot(position.x, position.y)
        guard r > 0.001 else { return }
        let er = CGVector(dx: position.x / r, dy: position.y / r)
        position = CGPoint(x: er.dx * ringRadius, y: er.dy * ringRadius)
        let radialSpeed = velocity.dx * er.dx + velocity.dy * er.dy
        velocity.dx -= er.dx * radialSpeed
        velocity.dy -= er.dy * radialSpeed
    }

    /// Signed distance of the *finger* from the band — the escape gauge while seated.
    private func fingerBandStretch() -> Double {
        let fx = fingerPosition.x - ringCenter.x
        let fy = fingerPosition.y - ringCenter.y
        return hypot(fx, fy) - ringRadius
    }

    // MARK: - Integration & Containment

    private func integrate(force: CGVector, dt: Double) {
        let m = max(mass, 0.01)
        velocity.dx += (force.dx / m) * dt
        velocity.dy += (force.dy / m) * dt

        let speed = hypot(velocity.dx, velocity.dy)
        if speed > maxSpeed {
            velocity.dx *= maxSpeed / speed
            velocity.dy *= maxSpeed / speed
        }

        position.x += velocity.dx * dt
        position.y += velocity.dy * dt
    }

    /// Hard backstop under the repulsion field: the knob can never actually leave the
    /// screen, even from a hard flick that outruns the soft field above.
    private func clampToScreen() {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let minX = knobRadius - ringCenter.x
        let maxX = canvasSize.width - knobRadius - ringCenter.x
        let minY = knobRadius - ringCenter.y
        let maxY = canvasSize.height - knobRadius - ringCenter.y

        var impact: Double = 0

        if position.x < minX {
            position.x = minX
            if velocity.dx < 0 {
                impact = max(impact, -velocity.dx)
                velocity.dx = isDragging ? 0 : -velocity.dx * 0.3
            }
        } else if position.x > maxX {
            position.x = maxX
            if velocity.dx > 0 {
                impact = max(impact, velocity.dx)
                velocity.dx = isDragging ? 0 : -velocity.dx * 0.3
            }
        }

        if position.y < minY {
            position.y = minY
            if velocity.dy < 0 {
                impact = max(impact, -velocity.dy)
                velocity.dy = isDragging ? 0 : -velocity.dy * 0.3
            }
        } else if position.y > maxY {
            position.y = maxY
            if velocity.dy > 0 {
                impact = max(impact, velocity.dy)
                velocity.dy = isDragging ? 0 : -velocity.dy * 0.3
            }
        }

        if !isDragging, impact > 250 {
            HapticsManager.shared.playClick(intensity: min(impact / 800, 1.0), sharpness: 0.85)
            SoundManager.shared.playSystemClick()
        }
    }

    // MARK: - Seat / Release Transients

    private func updateSeatState() {
        if isOnRing {
            // Seated is stable: only a deliberate drag past the escape
            // stretch unseats it — nothing bounces off on its own.
            guard isDragging, abs(fingerBandStretch()) > releaseDistance else { return }
            isOnRing = false
            HapticsManager.shared.playClick(intensity: 0.85, sharpness: 1.0)
            SoundManager.shared.playSystemClick()
        } else {
            let d = abs(hypot(position.x, position.y) - ringRadius)
            guard d < contactDistance else { return }
            // Don't re-latch while the finger is still holding it past the
            // escape stretch (i.e. the instant after a breakaway).
            if isDragging, abs(fingerBandStretch()) > releaseDistance { return }

            isOnRing = true
            seatOnBand() // inelastic capture: the clack absorbs the radial energy
            // Double-tap clack: full thunk plus a crisp little rebound.
            HapticsManager.shared.playClick(intensity: 1.0, sharpness: 0.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.045) {
                HapticsManager.shared.playClick(intensity: 0.35, sharpness: 0.85)
            }
            SoundManager.shared.playSystemClick()
        }
    }

    // MARK: - Continuous Haptics (the field map)

    /// The Taptic Engine speaks clearest in transients, so every physical
    /// quantity is voiced primarily as a tick train — slide ripple on the band,
    /// Geiger-style crackle whose *rate* encodes field strength off it, and a
    /// creak ramp before breakaway — with the continuous rumble demoted to a
    /// supporting layer underneath.
    private func driveHaptics(dt: Double) {
        let speed = hypot(velocity.dx, velocity.dy)

        if isOnRing {
            // Polarity-ripple ticks: one per ~14pt of arc, blurring into a
            // buzz at fast orbits.
            slideDistanceSinceTick += speed * dt
            if speed > 8, slideDistanceSinceTick >= 14 {
                slideDistanceSinceTick = 0
                HapticsManager.shared.playClick(intensity: min(0.12 + speed / 1500, 0.4),
                                                sharpness: 0.7)
            }

            let slideIntensity = speed > 8 ? min(speed / 700.0, 1.0) * 0.5 : 0

            // Peel-off strain: the knob is pinned to the band, so the tension
            // you feel is how far the *finger* has stretched from it.
            var strainIntensity = 0.0
            var strainSharpness = 0.0
            if isDragging {
                let stretch = min(abs(fingerBandStretch()) / max(releaseDistance, 1), 1.0)
                if stretch > 0.12 {
                    strainIntensity = 0.1 + 0.5 * stretch
                    strainSharpness = 0.3 + 0.45 * stretch
                    // Creak: tearing ticks accelerating toward the escape threshold.
                    if Double.random(in: 0...1) < 25 * stretch * stretch * dt {
                        HapticsManager.shared.playClick(intensity: 0.2 + 0.3 * stretch,
                                                        sharpness: 0.85)
                    }
                }
            }

            guard slideIntensity > 0 || strainIntensity > 0 else {
                HapticsManager.shared.stopContinuousFeedback()
                SoundManager.shared.stopOscillator()
                return
            }
            if strainIntensity >= slideIntensity {
                HapticsManager.shared.startContinuousFeedback(intensity: strainIntensity,
                                                              sharpness: strainSharpness)
                SoundManager.shared.startOscillator(frequency: Float(70 + strainIntensity * 100),
                                                    volume: Float(strainIntensity * 0.04))
            } else {
                HapticsManager.shared.startContinuousFeedback(intensity: slideIntensity, sharpness: 0.5)
                SoundManager.shared.startOscillator(frequency: Float(40 + speed * 0.12),
                                                    volume: Float(slideIntensity * 0.05))
            }
            return
        }

        guard isDragging || speed > 8 else {
            HapticsManager.shared.stopContinuousFeedback()
            SoundManager.shared.stopOscillator()
            return
        }

        let field = ringFieldForce() + bezelRepulsionForce()
        let strength = min(hypot(field.dx, field.dy) / fieldMax, 1.0)
        let perceived = pow(strength, 0.4) // perceptual curve: keep the faint far field feelable

        // Geiger-counter crackle: tick *rate* encodes field strength — countable
        // and far more legible than rumble amplitude.
        let crackleRate = 2.0 + 33.0 * pow(perceived, 0.6)
        if Double.random(in: 0...1) < crackleRate * dt {
            HapticsManager.shared.playClick(intensity: 0.1 + 0.3 * perceived,
                                            sharpness: 0.5 + 0.4 * perceived)
        }

        let intensity = 0.1 + 0.7 * perceived
        let sharpness = 0.25 + 0.45 * perceived
        HapticsManager.shared.startContinuousFeedback(intensity: intensity, sharpness: sharpness)
        SoundManager.shared.startOscillator(frequency: Float(55 + perceived * 90),
                                            volume: Float(intensity * 0.04))
    }

    // MARK: - Deactivation

    private func maybeSleep() {
        guard !isDragging else { return }
        let speed = hypot(velocity.dx, velocity.dy)
        guard speed < 2 else { return }

        let r = hypot(position.x, position.y)
        let d = abs(r - ringRadius)

        if isOnRing, d < 1.0 {
            // Seat exactly on the band.
            if r > 0.001 {
                let scale = ringRadius / r
                position = CGPoint(x: position.x * scale, y: position.y * scale)
            }
        } else if r < 2.0 {
            // Balanced on the center null — an equilibrium too; let it rest.
        } else {
            return // still gliding home; keep simulating
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
