import SwiftUI
import Combine

// MARK: - Blob Entity

/// A single blob instance — a soft body that lives on the canvas.
///
/// Its shape is a ring of `ringCount` particles stored as **offsets from
/// `center`** (so the existing center-based recoil/mitosis/merge logic moves
/// the whole blob for free). Each particle is a Verlet point: we keep its
/// current offset plus its previous offset, and velocity is implicit
/// (`offset - offsetPrev`). That implicit velocity is what gives the jelly
/// real inertia — it lags, overshoots, and settles instead of snapping.
struct BlobEntity: Identifiable {
    static let ringCount = 32

    var id: UUID = UUID()
    var center: CGPoint
    var radius: CGFloat = 33          // 66pt diameter — fits one grid tile
    var velocityX: CGFloat = 0        // post-mitosis recoil velocity (pt/s)
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
}

// MARK: - BlobModel

/// Physics model for the Blob fidget.
///
/// Two coupled simulations run on the same CADisplayLink:
///   1. **Center dynamics** — post-mitosis recoil velocity + damping + merge
///      detection (unchanged: drives where each blob *is*).
///   2. **Soft-body dynamics** — per-blob Verlet ring with shape springs,
///      neighbour smoothing, a finger-grab pull, and a whisper of idle noise
///      (drives what each blob *looks like*).
///
/// Follows the same ObservableObject + CADisplayLink pattern as DialModel.
class BlobModel: ObservableObject {

    // MARK: - Published State

    @Published var blobs: [BlobEntity] = []

    /// True while a finger is actively stretching a blob.
    @Published var isDragging: Bool = false

    /// The id of the blob currently being stretched.
    @Published var dragBlobID: UUID? = nil

    /// Current finger position in view-coordinate space.
    @Published var fingerPosition: CGPoint = .zero

    // MARK: - Tunable Parameters — Center Dynamics

    /// Distance (pt) from blob center at which mitosis fires. TDD spec: T > 180pt.
    @Published var mitosisThreshold: CGFloat = 180

    /// Speed (pt/s) of each child blob's post-split recoil.
    @Published var recoilSpeed: CGFloat = 95

    /// Per-frame velocity decay multiplier (at 60 fps).
    @Published var dampingFactor: CGFloat = 0.80

    /// Centers within this distance (pt) will merge on next physics tick.
    @Published var mergeDistance: CGFloat = 52

    // MARK: - Tunable Parameters — Soft Body

    /// How hard each particle springs back toward its resting circle. Lower =
    /// looser, wobblier jelly that takes longer to reform. (0…1 per iteration)
    private let shapeStiffness: CGFloat = 0.09

    /// How strongly each particle is pulled toward the midpoint of its two
    /// neighbours. This smooths kinks and lets a local pull propagate around
    /// the ring as a travelling wave — the essence of the jelly look.
    private let smoothStiffness: CGFloat = 0.24

    /// Verlet velocity retention. High = lots of inertia / many wobbles before
    /// settling; low = stiff and dead. 0.90 gives a lively, quick-settling jelly.
    private let vertexDamping: CGFloat = 0.90

    /// How eagerly the grabbed region chases the finger. < 1 so the surface
    /// lags behind the fingertip — this is the "thick, sticky" viscous feel.
    private let grabStiffness: CGFloat = 0.5

    /// Exponent on the finger-facing weight. Higher = the pull concentrates
    /// nearer the fingertip (pointier nose); lower = broader, rounder stretch.
    private let grabFocus: CGFloat = 1.6

    /// Constraint solver iterations per frame. 2 is plenty for a smooth blob.
    private let constraintIterations: Int = 2

    /// Peak radial idle displacement (pt) fed in each frame as a gentle force.
    /// Filtered through the spring/damper system so it reads as a living
    /// breathing surface, never a raw mechanical sine.
    private let idleAmplitude: CGFloat = 0.22

    // MARK: - Private

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var isActive: Bool = false          // true while the Blob view is on screen

    // MARK: - View Lifecycle

    /// Call from the view's `onAppear`. Centers the first blob and starts the
    /// simulation so the resting jelly breathes even before it's touched.
    func activate(in size: CGSize) {
        isActive = true
        if blobs.isEmpty {
            blobs = [BlobEntity(center: CGPoint(x: size.width / 2, y: size.height / 2))]
        }
        startDisplayLink()
    }

    /// Call from the view's `onDisappear` to stop burning CPU off-screen.
    func deactivate() {
        isActive = false
        isDragging = false
        dragBlobID = nil
        stopDisplayLink()
        HapticsManager.shared.stopContinuousFeedback()
        SoundManager.shared.stopOscillator()
    }

    // MARK: - Gesture Entry Points

    func handleDragStart(at location: CGPoint) {
        // Only pick up a blob whose center is within ~2× radius of the touch.
        guard let blob = nearestBlob(to: location, maxDistance: 66) else { return }
        dragBlobID = blob.id
        fingerPosition = location
        isDragging = true
        startDisplayLink()

        // Begin a gentle continuous rumble at low intensity.
        HapticsManager.shared.startContinuousFeedback(intensity: 0.08, sharpness: 0.2)
    }

    func handleDragChanged(to location: CGPoint) {
        guard isDragging,
              let id = dragBlobID,
              let idx = blobs.firstIndex(where: { $0.id == id }) else { return }

        fingerPosition = location

        let blob = blobs[idx]
        let tension = hypot(location.x - blob.center.x,
                            location.y - blob.center.y)
        // Normalised stretch ratio 0…1
        let t = min(tension / mitosisThreshold, 1.0)

        // Scale haptic rumble with tension — feels like pulling taffy.
        HapticsManager.shared.updateContinuousFeedback(
            intensity: Double(t) * 0.72,
            sharpness: 0.15
        )

        // Squelch audio: pitch rises smoothly from 80 Hz → 400 Hz as stretch grows.
        SoundManager.shared.startOscillator(
            frequency: Float(80 + t * 320),
            volume: Float(t * 0.025)
        )

        // Snap into mitosis the moment threshold is crossed.
        if tension >= mitosisThreshold {
            performMitosis(at: idx)
        }
    }

    func handleDragEnd() {
        HapticsManager.shared.stopContinuousFeedback()
        SoundManager.shared.stopOscillator()
        isDragging = false
        dragBlobID = nil
        fingerPosition = .zero
        // The soft body keeps wobbling and settles on its own via the ring
        // simulation; the display link keeps running while the view is active.
    }

    // MARK: - Mitosis

    private func performMitosis(at idx: Int) {
        let blob = blobs[idx]
        let finger = fingerPosition

        let dx = finger.x - blob.center.x
        let dy = finger.y - blob.center.y
        let dist = hypot(dx, dy)
        guard dist > 0 else { return }

        // Unit vector pointing from anchor → finger.
        let ux = dx / dist
        let uy = dy / dist

        // Per TDD spec §2.4: C₁ = anchor + r/4 along stretch axis,
        //                     C₂ = finger  − r/4 along stretch axis.
        let c1 = CGPoint(x: blob.center.x + ux * dist * 0.25,
                         y: blob.center.y + uy * dist * 0.25)
        let c2 = CGPoint(x: finger.x - ux * dist * 0.25,
                         y: finger.y - uy * dist * 0.25)

        // Opposite recoil velocities so the two babies bounce apart.
        var b1 = BlobEntity(center: c1)
        var b2 = BlobEntity(center: c2)
        b1.velocityX = -ux * recoilSpeed
        b1.velocityY = -uy * recoilSpeed
        b2.velocityX =  ux * recoilSpeed
        b2.velocityY =  uy * recoilSpeed

        // Seed the children mid-stretch so they *spring* back to round rather
        // than popping in as perfect circles — the ring recoil sells the split.
        stretchChild(&b1, along: (-ux, -uy))
        stretchChild(&b2, along: (ux, uy))

        blobs.remove(at: idx)
        blobs.append(b1)
        blobs.append(b2)

        // End the active drag immediately.
        isDragging = false
        dragBlobID = nil
        fingerPosition = .zero

        // Organic "pop" — low sharpness, dull transient (not a crisp click).
        HapticsManager.shared.stopContinuousFeedback()
        HapticsManager.shared.playClick(intensity: 0.9, sharpness: 0.2)
        SoundManager.shared.stopOscillator()
        SoundManager.shared.playSystemClick()
    }

    /// Give a freshly-split blob an initial elongation along the split axis so
    /// its Verlet ring springs back and jiggles instead of appearing round.
    private func stretchChild(_ blob: inout BlobEntity, along dir: (CGFloat, CGFloat)) {
        for i in blob.ring.indices {
            let o = blob.ring[i]
            let mag = hypot(o.dx, o.dy)
            guard mag > 0 else { continue }
            // Points facing the split direction get pushed out; sides pull in.
            let dot = (o.dx / mag) * dir.0 + (o.dy / mag) * dir.1
            let scale = 1 + 0.35 * dot
            blob.ring[i] = CGVector(dx: o.dx * scale, dy: o.dy * scale)
        }
        // Zero relative velocity so the spring-back starts from the stretch.
        blob.ringPrev = blob.ring
    }

    // MARK: - Merge Detection

    private func checkMerge() {
        guard blobs.count > 1 else { return }

        var i = 0
        while i < blobs.count {
            if blobs[i].id == dragBlobID { i += 1; continue }

            var j = i + 1
            while j < blobs.count {
                if blobs[j].id == dragBlobID { j += 1; continue }

                let dx = blobs[j].center.x - blobs[i].center.x
                let dy = blobs[j].center.y - blobs[i].center.y

                if hypot(dx, dy) < mergeDistance {
                    let merged = CGPoint(
                        x: (blobs[i].center.x + blobs[j].center.x) / 2,
                        y: (blobs[i].center.y + blobs[j].center.y) / 2
                    )
                    blobs.remove(at: j)
                    blobs.remove(at: i)
                    blobs.append(BlobEntity(center: merged))

                    // Same organic pop — mirrors mitosis but softer.
                    HapticsManager.shared.playClick(intensity: 0.78, sharpness: 0.2)
                    SoundManager.shared.playSystemClick()
                    return  // indices invalidated — let next tick handle remaining pairs
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
        if dt <= 0 || dt > 0.1 { dt = 1.0 / 60.0 }  // guard against cold-start spikes
        lastTimestamp = now

        let dtScale = CGFloat(dt) * 60.0             // 1.0 at 60fps, 0.5 at 120fps
        let damp = CGFloat(pow(Double(dampingFactor), dt * 60.0))
        let elapsed = now

        for i in blobs.indices {
            // 1. Center recoil (post-mitosis) — unchanged.
            let speed = hypot(blobs[i].velocityX, blobs[i].velocityY)
            if speed > 0.5 {
                blobs[i].velocityX *= damp
                blobs[i].velocityY *= damp
                blobs[i].center.x  += blobs[i].velocityX * CGFloat(dt)
                blobs[i].center.y  += blobs[i].velocityY * CGFloat(dt)
            } else {
                blobs[i].velocityX = 0
                blobs[i].velocityY = 0
            }

            // 2. Soft-body ring simulation.
            let isDragged = isDragging && blobs[i].id == dragBlobID
            let fingerOffset: CGVector? = isDragged
                ? CGVector(dx: fingerPosition.x - blobs[i].center.x,
                           dy: fingerPosition.y - blobs[i].center.y)
                : nil
            stepRing(&blobs[i], dt: dtScale, time: elapsed, fingerOffset: fingerOffset)
        }

        checkMerge()

        // Keep breathing while the view is on screen; stop only when off-screen.
        if !isActive {
            stopDisplayLink()
        }
    }

    /// One Verlet step + constraint-solve for a single blob's ring.
    ///
    /// `fingerOffset` (finger position relative to `center`) is non-nil while
    /// this blob is being dragged.
    private func stepRing(_ blob: inout BlobEntity, dt: CGFloat, time: CFTimeInterval,
                          fingerOffset: CGVector?) {
        let n = blob.ring.count
        guard n >= 3 else { return }
        let rest = BlobEntity.restRing(radius: blob.radius, count: n)

        // Precompute the per-vertex grab target: extend each particle along the
        // finger direction in proportion to how much it *faces* the finger. The
        // fingertip-facing vertex reaches the finger; the sides follow less and
        // the far side stays put — a smooth taffy teardrop with a natural waist,
        // instead of the thin spike you get from yanking one lone vertex.
        var grabTargets: [CGVector]? = nil
        if let f = fingerOffset {
            let fMag = hypot(f.dx, f.dy)
            if fMag > 0.5 {
                let fx = f.dx / fMag, fy = f.dy / fMag
                let pullDist = max(fMag - blob.radius, 0)   // how far past the rim
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

        // — Verlet integration: advance by implicit velocity, add idle breath —
        for i in 0..<n {
            let cur = blob.ring[i]
            let prev = blob.ringPrev[i]
            var vx = (cur.dx - prev.dx) * vertexDamping
            var vy = (cur.dy - prev.dy) * vertexDamping

            // Idle breath: a two-octave, per-vertex-phased noise pushed along
            // the radial direction. Injected as a force, so the spring/damper
            // network turns it into smooth living undulation, not a visible sine.
            if grabTargets == nil {
                let phase = Double(i) * 0.55
                let noise = sin(time * 1.3 + phase) + 0.55 * sin(time * 2.17 + phase * 1.7)
                let mag = hypot(rest[i].dx, rest[i].dy)
                if mag > 0 {
                    let push = idleAmplitude * CGFloat(noise) * dt
                    vx += rest[i].dx / mag * push
                    vy += rest[i].dy / mag * push
                }
            }

            blob.ringPrev[i] = cur
            blob.ring[i] = CGVector(dx: cur.dx + vx, dy: cur.dy + vy)
        }

        // — Constraint solve —
        // When grabbed, relax the pull-to-circle so the finger can win; the
        // grab targets already carry the round rest shape as their baseline.
        let shapeK = grabTargets == nil ? shapeStiffness : shapeStiffness * 0.35
        for _ in 0..<constraintIterations {
            // Shape memory: spring every particle back toward its rest circle.
            for i in 0..<n {
                let o = blob.ring[i]
                blob.ring[i] = CGVector(
                    dx: o.dx + (rest[i].dx - o.dx) * shapeK,
                    dy: o.dy + (rest[i].dy - o.dy) * shapeK
                )
            }
            // Neighbour smoothing: pull each particle toward the midpoint of its
            // two neighbours so pulls propagate as waves and kinks vanish.
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
            // Finger grab: pull the whole finger-facing arc toward its target.
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

    // MARK: - Helpers

    private func nearestBlob(to point: CGPoint, maxDistance: CGFloat) -> BlobEntity? {
        blobs
            .filter { hypot($0.center.x - point.x, $0.center.y - point.y) <= maxDistance }
            .min   { hypot($0.center.x - point.x, $0.center.y - point.y)
                   < hypot($1.center.x - point.x, $1.center.y - point.y) }
    }
}
