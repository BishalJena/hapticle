import SwiftUI
import Combine

// MARK: - Blob Entity

/// A single blob instance — a soft body that lives on the canvas.
///
/// Its shape is a ring of `ringCount` particles stored as **offsets from
/// `center`** (so center-based motion moves the whole blob for free). Each
/// particle is a Verlet point: current offset + previous offset, with implicit
/// velocity (`offset - offsetPrev`). That implicit velocity gives the jelly
/// real inertia — it lags, overshoots, and settles instead of snapping.
struct BlobEntity: Identifiable {
    static let ringCount = 32

    var id: UUID = UUID()
    var center: CGPoint
    var radius: CGFloat = 33
    var velocityX: CGFloat = 0        // free-motion / recoil velocity (pt/s)
    var velocityY: CGFloat = 0

    /// Perimeter particle offsets from `center` (current + previous frame).
    var ring: [CGVector] = []
    var ringPrev: [CGVector] = []

    init(center: CGPoint, radius: CGFloat = 33) {
        self.center = center
        self.radius = radius
        let rest = BlobEntity.restRing(radius: radius, count: BlobEntity.ringCount)
        self.ring = rest
        self.ringPrev = rest
    }

    /// Mass ∝ area. Used so big blobs feel heavy and small ones feel snappy.
    var mass: CGFloat { .pi * radius * radius }

    /// The undeformed circular ring — also the target every particle springs
    /// back toward, giving the blob "memory" of being round.
    static func restRing(radius: CGFloat, count: Int) -> [CGVector] {
        (0..<count).map { i in
            let a = CGFloat(i) / CGFloat(count) * 2 * .pi
            return CGVector(dx: cos(a) * radius, dy: sin(a) * radius)
        }
    }

    /// Perimeter points in absolute view coordinates, for rendering.
    var ringPoints: [CGPoint] {
        ring.map { CGPoint(x: center.x + $0.dx, y: center.y + $0.dy) }
    }

    /// Rescale the ring (keeping its current deformation) to a new radius.
    mutating func rescaleRing(to newRadius: CGFloat) {
        guard radius > 0 else { return }
        let k = newRadius / radius
        for i in ring.indices {
            ring[i] = CGVector(dx: ring[i].dx * k, dy: ring[i].dy * k)
            ringPrev[i] = CGVector(dx: ringPrev[i].dx * k, dy: ringPrev[i].dy * k)
        }
        radius = newRadius
    }
}

// MARK: - BlobModel

/// Physics + haptics model for the Blob fidget game.
///
/// The core interaction is an **elastic tether**: the grabbed blob's center
/// springs toward the finger, stiffness scaled by 1/mass. Drag slowly and the
/// blob follows (so you can push blobs together to merge); whip fast and the
/// tether stretches thin until the blob **sheds a droplet** off its tail.
/// Size is the master modulator of the whole haptic palette — big blobs feel
/// deep/dull/heavy, droplets feel crisp/light/quick.
class BlobModel: ObservableObject {

    // MARK: - Published State

    @Published var blobs: [BlobEntity] = []
    @Published var isDragging: Bool = false
    @Published var dragBlobID: UUID? = nil
    @Published var fingerPosition: CGPoint = .zero

    // MARK: - Tunable Parameters — Size & Mass

    /// Smallest a blob can get; it won't shed below this.
    private let rMin: CGFloat = 16
    /// Largest a blob can merge to.
    private let rMax: CGFloat = 110
    /// Starting blob radius — deliberately big so the first thing you do is break it.
    private let startRadius: CGFloat = 78
    /// Cap on blob count (bounds perf + the O(n²) merge scan).
    private let maxCount: Int = 14
    /// Reference radius for mass scaling (the "neutral weight" blob).
    private let refRadius: CGFloat = 45

    // MARK: - Tunable Parameters — Tether (grab-to-move)

    /// Spring constant pulling a grabbed blob's center toward the finger.
    private let tetherStiffness: CGFloat = 55
    /// Per-60fps velocity retention of the tether (viscous follow).
    private let tetherDamping: CGFloat = 0.72
    /// Free-motion (recoil/droplet) velocity decay per 60fps frame.
    private let dampingFactor: CGFloat = 0.86

    // MARK: - Tunable Parameters — Shedding

    /// Recoil speed of a shed droplet (scaled up for smaller droplets). Kept
    /// gentle so droplets settle near the drag path — a breadcrumb trail —
    /// rather than scattering across the screen.
    private let baseFlingSpeed: CGFloat = 80
    /// Minimum seconds between two sheds within one drag (trail spacing).
    private let shedCooldownDuration: CFTimeInterval = 0.16

    // MARK: - Tunable Parameters — Walls

    /// Fraction of speed retained when a blob bounces off a screen edge.
    private let wallRestitution: CGFloat = 0.6
    /// Minimum impact speed (pt/s) for a wall bounce to fire a haptic tick.
    private let wallTickMinSpeed: CGFloat = 140

    // MARK: - Tunable Parameters — Collecting

    /// Above this finger speed the dragged blob is "whipping" (it sheds); below
    /// it, moving slowly, it collects/absorbs droplets it rolls over.
    private let collectMaxSpeed: CGFloat = 900

    /// Tension (finger↔center lag, pt) needed to shed, scaled by size:
    /// a big blob resists; a small one lets go easily. Low enough that a
    /// brisk drag sheds a trail without needing a violent whip.
    private func shedThreshold(_ r: CGFloat) -> CGFloat { max(r * 1.3, 44) }

    // MARK: - Tunable Parameters — Soft Body

    private let shapeStiffness: CGFloat = 0.07
    private let smoothStiffness: CGFloat = 0.2
    private let vertexDamping: CGFloat = 0.93
    private let grabStiffness: CGFloat = 0.5
    private let grabFocus: CGFloat = 1.6
    private let constraintIterations: Int = 2
    private let idleAmplitude: CGFloat = 0.64
    /// How much of the center's per-frame motion the ring lags behind — this is
    /// what makes a moving blob deform (teardrop trails, wall-bounce squash)
    /// instead of translating as a rigid circle.
    private let inertiaLag: CGFloat = 0.36
    /// Cap on the per-frame center displacement fed into the ring, so a whip
    /// crossing the screen can't fling the soft body inside-out.
    private let inertiaLagMaxStep: CGFloat = 20

    // MARK: - Tunable Parameters — Haptics

    /// Crackle micro-transient probability scaling (per frame at full stretch/speed).
    private let crackleRate: CGFloat = 1.1

    // MARK: - Private

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var isActive: Bool = false
    private var canvasSize: CGSize = .zero

    private var prevFinger: CGPoint = .zero      // for frame-based finger speed
    private var fingerSpeed: CGFloat = 0
    private var shedCooldownUntil: CFTimeInterval = 0
    private var settleEnergy: CGFloat = 0         // decaying "boing" envelope after release

    // MARK: - Size → Haptic Character

    /// 0 for the smallest blob, 1 for the biggest — the "bigness" axis.
    private func bigness(_ r: CGFloat) -> Double {
        Double(min(max((r - rMin) / (rMax - rMin), 0), 1))
    }
    /// Crispness: small blobs feel sharp/high, big blobs feel dull/low.
    private func sharpBias(_ r: CGFloat) -> Double {
        0.7 - 0.55 * bigness(r)          // 0.7 (crisp) … 0.15 (dull)
    }

    // MARK: - View Lifecycle

    func activate(in size: CGSize) {
        isActive = true
        canvasSize = size
        if blobs.isEmpty {
            blobs = [BlobEntity(center: CGPoint(x: size.width / 2, y: size.height / 2),
                                radius: startRadius)]
        }
        startDisplayLink()
    }

    func deactivate() {
        isActive = false
        isDragging = false
        dragBlobID = nil
        settleEnergy = 0
        stopDisplayLink()
        HapticsManager.shared.stopContinuousFeedback()
        SoundManager.shared.stopOscillator()
    }

    // MARK: - Gesture Entry Points

    func handleDragStart(at location: CGPoint) {
        guard let blob = nearestBlob(to: location, maxDistance: 66) else { return }
        dragBlobID = blob.id
        fingerPosition = location
        prevFinger = location
        fingerSpeed = 0
        isDragging = true
        settleEnergy = 0
        startDisplayLink()

        // Contact tick: soft, dull, size-aware "I've got it".
        HapticsManager.shared.playClick(intensity: 0.3 + 0.25 * bigness(blob.radius),
                                        sharpness: 0.6 * sharpBias(blob.radius))
        // Start the continuous viscous rumble + audio (updated smoothly per frame).
        HapticsManager.shared.startContinuousFeedback(intensity: 0.05, sharpness: 0.2)
        SoundManager.shared.startOscillator(frequency: 80, volume: 0)
    }

    /// The gesture only reports the finger position; all physics + haptics are
    /// driven from the display link so they run at a steady 60/120 Hz.
    func handleDragChanged(to location: CGPoint) {
        fingerPosition = location
    }

    func handleDragEnd() {
        isDragging = false
        dragBlobID = nil
        fingerSpeed = 0
        SoundManager.shared.stopOscillator()
        // Hand off to the settle "boing" — the continuous rumble decays with the
        // blob's visible wobble rather than cutting out abruptly.
        settleEnergy = 0.7
    }

    // MARK: - Shedding (mass-conserving break)

    /// Break a small droplet off the tail of the dragged blob, conserving area:
    /// `rParent' = sqrt(r² − rDrop²)`. The parent stays grabbed so you can keep
    /// shedding until it hits `rMin`.
    @discardableResult
    private func shedDroplet(at idx: Int, now: CFTimeInterval) -> Bool {
        guard blobs.count < maxCount else { return false }
        var parent = blobs[idx]

        let ux: CGFloat, uy: CGFloat
        let dx = fingerPosition.x - parent.center.x
        let dy = fingerPosition.y - parent.center.y
        let d = hypot(dx, dy)
        guard d > 0.5 else { return false }
        ux = dx / d; uy = dy / d

        // Droplet takes ~30% of the parent's radius — small enough that a drag
        // leaves a trail of several before the parent runs dry.
        let dropletR = min(max(parent.radius * 0.3, rMin), parent.radius * 0.85)
        let newParentR = sqrt(max(parent.radius * parent.radius - dropletR * dropletR, 0))
        guard dropletR >= rMin, newParentR >= rMin else { return false }

        let parentBigness = bigness(parent.radius)

        // Shrink the parent (keeping its current deformation) and reset its lag so
        // you must whip again to shed the next one.
        parent.rescaleRing(to: newParentR)
        parent.center = CGPoint(x: fingerPosition.x - ux * newParentR,
                                y: fingerPosition.y - uy * newParentR)
        parent.velocityX = 0
        parent.velocityY = 0
        blobs[idx] = parent

        // Spawn the droplet behind the parent, flung backward. Smaller = faster.
        let flingSpeed = baseFlingSpeed * min(sqrt(refRadius / dropletR), 2.2)
        let dropCenter = CGPoint(x: parent.center.x - ux * (newParentR + dropletR + 2),
                                 y: parent.center.y - uy * (newParentR + dropletR + 2))
        var droplet = BlobEntity(center: dropCenter, radius: dropletR)
        droplet.velocityX = -ux * flingSpeed
        droplet.velocityY = -uy * flingSpeed
        stretchChild(&droplet, along: (-ux, -uy))
        blobs.append(droplet)

        shedCooldownUntil = now + shedCooldownDuration

        // Snap/shed pop: deep dull suction release (deeper for a bigger parent),
        // chased ~30ms later by a crisp little recoil tick. Punctuate by dropping
        // the continuous rumble to near-silence for the moment.
        HapticsManager.shared.updateContinuousFeedback(intensity: 0.02, sharpness: 0.1)
        HapticsManager.shared.playClick(intensity: 0.6 + 0.35 * parentBigness, sharpness: 0.12)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            HapticsManager.shared.playClick(intensity: 0.4,
                                            sharpness: 0.6 * self.sharpBias(dropletR))
        }
        SoundManager.shared.playSystemClick()
        return true
    }

    /// Elongate a fresh droplet along its fling axis so its ring springs back
    /// and jiggles instead of appearing as a rigid circle.
    private func stretchChild(_ blob: inout BlobEntity, along dir: (CGFloat, CGFloat)) {
        for i in blob.ring.indices {
            let o = blob.ring[i]
            let mag = hypot(o.dx, o.dy)
            guard mag > 0 else { continue }
            let dot = (o.dx / mag) * dir.0 + (o.dy / mag) * dir.1
            let scale = 1 + 0.35 * dot
            blob.ring[i] = CGVector(dx: o.dx * scale, dy: o.dy * scale)
        }
        blob.ringPrev = blob.ring
    }

    // MARK: - Collecting (slow-drag absorb)

    /// While dragging slowly, the held blob rolls over droplets on its path and
    /// absorbs them, conserving area (`r = sqrt(r² + rOther²)`). Grabbed blob
    /// keeps its id and stays under the finger, just growing heavier.
    private func absorbOverlaps() {
        guard let id = dragBlobID else { return }
        while true {
            guard let d = blobs.firstIndex(where: { $0.id == id }),
                  blobs[d].radius < rMax else { return }
            let dragged = blobs[d]

            var target: Int? = nil
            for j in blobs.indices where blobs[j].id != id {
                // Don't vacuum up a droplet that's still flying away from a fresh
                // shed — only settled puddles get collected.
                if hypot(blobs[j].velocityX, blobs[j].velocityY) > 200 { continue }
                let dist = hypot(blobs[j].center.x - dragged.center.x,
                                 blobs[j].center.y - dragged.center.y)
                if dist < (dragged.radius + blobs[j].radius) * 0.85 { target = j; break }
            }
            guard let j = target else { return }

            let other = blobs[j]
            let newR = min(sqrt(dragged.radius * dragged.radius + other.radius * other.radius), rMax)
            var grown = dragged
            grown.rescaleRing(to: newR)
            blobs[d] = grown
            blobs.remove(at: j)

            // Absorb gloop: a soft, wet swallow — deeper as the blob grows.
            HapticsManager.shared.playClick(intensity: 0.4 + 0.4 * bigness(newR), sharpness: 0.14)
            SoundManager.shared.playSystemClick()
        }
    }

    // MARK: - Merge Detection (area-conserving)

    private func checkMerge() {
        guard blobs.count > 1 else { return }

        var i = 0
        while i < blobs.count {
            if blobs[i].id == dragBlobID { i += 1; continue }

            var j = i + 1
            while j < blobs.count {
                if blobs[j].id == dragBlobID { j += 1; continue }

                let a = blobs[i], b = blobs[j]
                let dx = b.center.x - a.center.x
                let dy = b.center.y - a.center.y
                // Merge once the two soft bodies actually overlap.
                if hypot(dx, dy) < (a.radius + b.radius) * 0.72 {
                    let mergedR = min(sqrt(a.radius * a.radius + b.radius * b.radius), rMax)
                    // Mass-weighted center + momentum conservation.
                    let ma = a.mass, mb = b.mass, mt = ma + mb
                    let center = CGPoint(x: (a.center.x * ma + b.center.x * mb) / mt,
                                         y: (a.center.y * ma + b.center.y * mb) / mt)
                    var merged = BlobEntity(center: center, radius: mergedR)
                    merged.velocityX = (a.velocityX * ma + b.velocityX * mb) / mt
                    merged.velocityY = (a.velocityY * ma + b.velocityY * mb) / mt

                    blobs.remove(at: j)
                    blobs.remove(at: i)
                    blobs.append(merged)

                    // Merge gloop: a soft, dull thud — deeper the bigger the result.
                    HapticsManager.shared.playClick(intensity: 0.5 + 0.4 * bigness(mergedR),
                                                    sharpness: 0.12)
                    SoundManager.shared.playSystemClick()
                    return
                }
                j += 1
            }
            i += 1
        }
    }

    // MARK: - CADisplayLink Physics Loop

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastTimestamp = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(stepPhysics))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func stepPhysics(_ link: CADisplayLink) {
        let now = link.timestamp
        var dt = now - lastTimestamp
        if dt <= 0 || dt > 0.1 { dt = 1.0 / 60.0 }
        lastTimestamp = now

        let dtScale = CGFloat(dt) * 60.0
        let recoilDamp = CGFloat(pow(Double(dampingFactor), dt * 60.0))
        let tetherDamp = CGFloat(pow(Double(tetherDamping), dt * 60.0))

        // Track finger speed (frame-based) for the stringy crackle.
        if isDragging {
            fingerSpeed = hypot(fingerPosition.x - prevFinger.x,
                                fingerPosition.y - prevFinger.y) / CGFloat(dt)
            prevFinger = fingerPosition
        }

        var draggedTension: CGFloat = 0
        var draggedIdx: Int? = nil

        for i in blobs.indices {
            let isDragged = isDragging && blobs[i].id == dragBlobID
            let centerBefore = blobs[i].center

            if isDragged {
                // Elastic tether: spring the center toward the finger, mass-scaled.
                let massFactor = pow(blobs[i].radius / refRadius, 2)
                let ox = fingerPosition.x - blobs[i].center.x
                let oy = fingerPosition.y - blobs[i].center.y
                let ax = ox * tetherStiffness / massFactor
                let ay = oy * tetherStiffness / massFactor
                blobs[i].velocityX = (blobs[i].velocityX + ax * CGFloat(dt)) * tetherDamp
                blobs[i].velocityY = (blobs[i].velocityY + ay * CGFloat(dt)) * tetherDamp
                blobs[i].center.x += blobs[i].velocityX * CGFloat(dt)
                blobs[i].center.y += blobs[i].velocityY * CGFloat(dt)

                draggedTension = hypot(fingerPosition.x - blobs[i].center.x,
                                       fingerPosition.y - blobs[i].center.y)
                draggedIdx = i
            } else {
                // Free motion: recoil / droplet drift, decaying to rest.
                let speed = hypot(blobs[i].velocityX, blobs[i].velocityY)
                if speed > 0.5 {
                    blobs[i].velocityX *= recoilDamp
                    blobs[i].velocityY *= recoilDamp
                    blobs[i].center.x += blobs[i].velocityX * CGFloat(dt)
                    blobs[i].center.y += blobs[i].velocityY * CGFloat(dt)
                } else {
                    blobs[i].velocityX = 0
                    blobs[i].velocityY = 0
                }
            }

            // Keep the blob on-screen — bounce off the walls.
            containWithinWalls(&blobs[i], isDragged: isDragged)

            // Soft-body ring update, fed the frame's center motion so the body
            // visibly lags/deforms rather than sliding around as a rigid disc.
            let fingerOffset: CGVector? = isDragged
                ? CGVector(dx: fingerPosition.x - blobs[i].center.x,
                           dy: fingerPosition.y - blobs[i].center.y)
                : nil
            let centerDelta = CGVector(dx: blobs[i].center.x - centerBefore.x,
                                       dy: blobs[i].center.y - centerBefore.y)
            stepRing(&blobs[i], dt: dtScale, time: now,
                     fingerOffset: fingerOffset, centerDelta: centerDelta)
        }

        // Drive the drag haptics (rumble + crackle), then either shed (fast
        // whip) or collect (slow drag) — the two halves of the loop.
        if let idx = draggedIdx {
            driveDragHaptics(radius: blobs[idx].radius, tension: draggedTension, dt: dt)
            if draggedTension >= shedThreshold(blobs[idx].radius), now >= shedCooldownUntil {
                shedDroplet(at: idx, now: now)
            } else if fingerSpeed < collectMaxSpeed {
                absorbOverlaps()
            }
        } else {
            settleStep(now: now, dt: dt)
        }

        checkMerge()

        if !isActive { stopDisplayLink() }
    }

    // MARK: - Drag Haptics

    private func driveDragHaptics(radius: CGFloat, tension: CGFloat, dt: CFTimeInterval) {
        let t = Double(min(tension / shedThreshold(radius), 1.0))
        let bias = sharpBias(radius)

        // Viscous rumble: swells with stretch and *tightens* (sharper) as it thins.
        HapticsManager.shared.updateContinuousFeedback(
            intensity: 0.06 + 0.6 * t,
            sharpness: (0.1 + 0.5 * t) * bias
        )
        // Audio squelch: pitch rises with stretch, lower overall for bigger blobs.
        let pitch = Float((80 + 320 * t) * (0.6 + 0.4 * bias))
        SoundManager.shared.updateOscillator(frequency: pitch, volume: Float(t * 0.03))

        // Stringy crackle: micro-transients whose rate ∝ tension × finger speed —
        // the felt sensation of slime fibres snapping as it stretches.
        let speedNorm = Double(min(fingerSpeed / 1500, 1))
        let prob = Double(crackleRate) * t * speedNorm * dt * 60
        if Double.random(in: 0...1) < prob {
            HapticsManager.shared.playClick(intensity: 0.15 + 0.15 * t,
                                            sharpness: 0.8 * bias)
        }
    }

    /// After release, decay the continuous rumble in time with the visible
    /// wobble so it "boings" out instead of cutting off.
    private func settleStep(now: CFTimeInterval, dt: CFTimeInterval) {
        guard settleEnergy > 0 else { return }
        settleEnergy *= CGFloat(pow(0.90, dt * 60))
        if settleEnergy > 0.03 {
            let wobble = 0.5 + 0.5 * sin(now * 34)
            HapticsManager.shared.updateContinuousFeedback(
                intensity: Double(settleEnergy) * 0.3 * wobble,
                sharpness: 0.25
            )
        } else {
            settleEnergy = 0
            HapticsManager.shared.stopContinuousFeedback()
        }
    }

    // MARK: - Soft-Body Ring

    private func stepRing(_ blob: inout BlobEntity, dt: CGFloat, time: CFTimeInterval,
                          fingerOffset: CGVector?, centerDelta: CGVector = .zero) {
        let n = blob.ring.count
        guard n >= 3 else { return }
        let rest = BlobEntity.restRing(radius: blob.radius, count: n)

        // Deformation is proportional to size: what reads as gentle breathing
        // on a big blob is a huge fraction of a droplet's radius, so small
        // blobs get proportionally calmer wobble and lag to stay recognisably
        // round.
        let sizeScale = min(blob.radius / refRadius, 1.0)

        // Inertia: ring offsets live in center-relative space, so when the
        // center moves the body should lag behind in world space and spring
        // back — that lag IS the gooey deformation of a moving blob.
        var lagX = -centerDelta.dx * inertiaLag * (0.4 + 0.6 * sizeScale)
        var lagY = -centerDelta.dy * inertiaLag * (0.4 + 0.6 * sizeScale)
        let lagCap = min(inertiaLagMaxStep, blob.radius * 0.4)
        let lagMag = hypot(lagX, lagY)
        if lagMag > lagCap {
            lagX *= lagCap / lagMag
            lagY *= lagCap / lagMag
        }

        var grabTargets: [CGVector]? = nil
        if let f = fingerOffset {
            let fMag = hypot(f.dx, f.dy)
            if fMag > 0.5 {
                let fx = f.dx / fMag, fy = f.dy / fMag
                let pullDist = max(fMag - blob.radius, 0)
                grabTargets = (0..<n).map { i in
                    let r = rest[i]
                    let rMag = hypot(r.dx, r.dy)
                    guard rMag > 0 else { return r }
                    let facing = max(0, (r.dx / rMag) * fx + (r.dy / rMag) * fy)
                    let w = pow(facing, grabFocus)
                    return CGVector(dx: r.dx + fx * pullDist * w,
                                    dy: r.dy + fy * pullDist * w)
                }
            }
        }

        for i in 0..<n {
            let cur = blob.ring[i]
            let prev = blob.ringPrev[i]
            var vx = (cur.dx - prev.dx) * vertexDamping + lagX
            var vy = (cur.dy - prev.dy) * vertexDamping + lagY

            if grabTargets == nil {
                let phase = Double(i) * 0.55
                let noise = sin(time * 1.3 + phase) + 0.55 * sin(time * 2.17 + phase * 1.7)
                let mag = hypot(rest[i].dx, rest[i].dy)
                if mag > 0 {
                    let push = idleAmplitude * sizeScale * CGFloat(noise) * dt
                    vx += rest[i].dx / mag * push
                    vy += rest[i].dy / mag * push
                }
            }

            blob.ringPrev[i] = cur
            blob.ring[i] = CGVector(dx: cur.dx + vx, dy: cur.dy + vy)
        }

        let shapeK = grabTargets == nil ? shapeStiffness : shapeStiffness * 0.35
        for _ in 0..<constraintIterations {
            for i in 0..<n {
                let o = blob.ring[i]
                blob.ring[i] = CGVector(
                    dx: o.dx + (rest[i].dx - o.dx) * shapeK,
                    dy: o.dy + (rest[i].dy - o.dy) * shapeK
                )
            }
            let snapshot = blob.ring
            for i in 0..<n {
                let a = snapshot[(i - 1 + n) % n]
                let b = snapshot[(i + 1) % n]
                let mid = CGVector(dx: (a.dx + b.dx) / 2, dy: (a.dy + b.dy) / 2)
                let o = blob.ring[i]
                blob.ring[i] = CGVector(
                    dx: o.dx + (mid.dx - o.dx) * smoothStiffness,
                    dy: o.dy + (mid.dy - o.dy) * smoothStiffness
                )
            }
            if let targets = grabTargets {
                for i in 0..<n {
                    let o = blob.ring[i]
                    blob.ring[i] = CGVector(
                        dx: o.dx + (targets[i].dx - o.dx) * grabStiffness,
                        dy: o.dy + (targets[i].dy - o.dy) * grabStiffness
                    )
                }
            }
        }
    }

    // MARK: - Walls

    /// Clamp a blob's center so it stays fully on-screen. Free-moving blobs
    /// bounce (velocity inverted × restitution) and tick on a hard impact; the
    /// dragged blob just stops at the edge so it doesn't fight the finger.
    private func containWithinWalls(_ blob: inout BlobEntity, isDragged: Bool) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        let r = blob.radius
        var impact: CGFloat = 0

        if r * 2 <= canvasSize.width {
            let minX = r, maxX = canvasSize.width - r
            if blob.center.x < minX {
                blob.center.x = minX
                if blob.velocityX < 0 {
                    impact = max(impact, -blob.velocityX)
                    blob.velocityX = isDragged ? 0 : -blob.velocityX * wallRestitution
                }
            } else if blob.center.x > maxX {
                blob.center.x = maxX
                if blob.velocityX > 0 {
                    impact = max(impact, blob.velocityX)
                    blob.velocityX = isDragged ? 0 : -blob.velocityX * wallRestitution
                }
            }
        } else {
            blob.center.x = canvasSize.width / 2
        }

        if r * 2 <= canvasSize.height {
            let minY = r, maxY = canvasSize.height - r
            if blob.center.y < minY {
                blob.center.y = minY
                if blob.velocityY < 0 {
                    impact = max(impact, -blob.velocityY)
                    blob.velocityY = isDragged ? 0 : -blob.velocityY * wallRestitution
                }
            } else if blob.center.y > maxY {
                blob.center.y = maxY
                if blob.velocityY > 0 {
                    impact = max(impact, blob.velocityY)
                    blob.velocityY = isDragged ? 0 : -blob.velocityY * wallRestitution
                }
            }
        } else {
            blob.center.y = canvasSize.height / 2
        }

        // A droplet smacking the wall gets a light tick — crisp for small ones.
        if !isDragged && impact > wallTickMinSpeed {
            HapticsManager.shared.playClick(intensity: min(Double(impact) / 900, 0.5),
                                            sharpness: 0.5 * sharpBias(r))
            SoundManager.shared.playSystemClick()
        }
    }

    // MARK: - Helpers

    private func nearestBlob(to point: CGPoint, maxDistance: CGFloat) -> BlobEntity? {
        blobs
            .filter { hypot($0.center.x - point.x, $0.center.y - point.y) <= max(maxDistance, $0.radius + 20) }
            .min   { hypot($0.center.x - point.x, $0.center.y - point.y)
                   < hypot($1.center.x - point.x, $1.center.y - point.y) }
    }
}
