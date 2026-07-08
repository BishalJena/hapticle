import SwiftUI
import Combine

// MARK: - Blob Entity

/// A single blob instance — a circle that lives on the canvas.
/// Diameter = 66pt exactly, matching one neumorphic background tile.
struct BlobEntity: Identifiable {
    var id: UUID = UUID()
    var center: CGPoint
    var radius: CGFloat = 33          // 66pt diameter — fits one grid tile
    var velocityX: CGFloat = 0        // post-mitosis recoil velocity (pt/s)
    var velocityY: CGFloat = 0
}

// MARK: - BlobModel

/// Physics model for the Blob fidget.
///
/// Lifecycle:
///   Resting → Drag starts → Stretch shape grows from blob center toward finger →
///   Tension exceeds mitosisThreshold → performMitosis() → Two blobs with recoil →
///   Physics loop damps velocities → Blobs approach merge radius → checkMerge() →
///   Unified blob. Repeat.
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

    /// Spring-lagged visual tip used only for rendering the jelly stretch —
    /// purely cosmetic viscosity. Tension/haptics/mitosis math continues to
    /// use raw `fingerPosition` so gameplay feel is unchanged.
    @Published var visualTipPosition: CGPoint = .zero
    private var visualTipVelocity: CGPoint = .zero

    // MARK: - Tunable Parameters

    /// Distance (pt) from blob center at which mitosis fires.
    /// TDD spec: T > 180pt.
    @Published var mitosisThreshold: CGFloat = 180

    /// Speed (pt/s) of each child blob's post-split recoil.
    @Published var recoilSpeed: CGFloat = 95

    /// Per-frame velocity decay multiplier (at 60 fps).
    /// 0.80 = 20% speed lost per frame → settles in ~18 frames ≈ 300 ms.
    @Published var dampingFactor: CGFloat = 0.80

    /// Centers within this distance (pt) will merge on next physics tick.
    /// Set to < 2*radius (66pt) so blobs must visually overlap before merging.
    @Published var mergeDistance: CGFloat = 52

    // MARK: - Private

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    // MARK: - Initialization

    /// Call from the view's onAppear with the actual available canvas size
    /// so the starting blob is perfectly centered regardless of screen size.
    func initializeBlobs(in size: CGSize) {
        guard blobs.isEmpty else { return }
        blobs = [BlobEntity(center: CGPoint(x: size.width / 2, y: size.height / 2))]
    }

    // MARK: - Gesture Entry Points

    func handleDragStart(at location: CGPoint) {
        // Only pick up a blob whose center is within ~2× radius of the touch.
        guard let blob = nearestBlob(to: location, maxDistance: 66) else { return }
        dragBlobID = blob.id
        fingerPosition = location
        visualTipPosition = location   // snap-init so it doesn't spring in from .zero
        visualTipVelocity = .zero
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
        visualTipPosition = .zero
        visualTipVelocity = .zero
        // Display link keeps running to damp any post-mitosis recoil.
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

        blobs.remove(at: idx)
        blobs.append(b1)
        blobs.append(b2)

        // End the active drag immediately.
        isDragging = false
        dragBlobID = nil
        fingerPosition = .zero
        visualTipPosition = .zero
        visualTipVelocity = .zero

        // Organic "pop" — low sharpness, dull transient (not a crisp click).
        HapticsManager.shared.stopContinuousFeedback()
        HapticsManager.shared.playClick(intensity: 0.9, sharpness: 0.2)
        SoundManager.shared.stopOscillator()
        SoundManager.shared.playSystemClick()
    }

    // MARK: - Merge Detection

    /// Called every physics tick. Merges the first colliding pair it finds,
    /// then returns (array mutation invalidates indices — restart next tick).
    private func checkMerge() {
        guard blobs.count > 1 else { return }

        var i = 0
        while i < blobs.count {
            // Never merge a blob that's actively being stretched.
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

    /// Euler integration with per-frame-rate–independent exponential damping.
    /// Runs at 60 Hz (or ProMotion 120 Hz) via CADisplayLink.
    @objc private func stepPhysics(_ link: CADisplayLink) {
        let now = link.timestamp
        var dt = now - lastTimestamp
        if dt <= 0 || dt > 0.1 { dt = 1.0 / 60.0 }  // guard against cold-start spikes
        lastTimestamp = now

        // Frame-rate–independent damping: raise per-60fps factor to (dt × 60).
        let damp = CGFloat(pow(Double(dampingFactor), dt * 60.0))

        var anyMoving = false

        for i in blobs.indices {
            let speed = hypot(blobs[i].velocityX, blobs[i].velocityY)
            guard speed > 0.5 else {
                blobs[i].velocityX = 0
                blobs[i].velocityY = 0
                continue
            }
            anyMoving = true
            blobs[i].velocityX *= damp
            blobs[i].velocityY *= damp
            blobs[i].center.x  += blobs[i].velocityX * CGFloat(dt)
            blobs[i].center.y  += blobs[i].velocityY * CGFloat(dt)
        }

        // Overdamped spring pulling the visual tip toward the raw finger
        // position — purely cosmetic viscosity ("thick honey" drag lag).
        // Does not affect tension/haptics/mitosis, which use fingerPosition.
        if isDragging {
            let stiffness: CGFloat = 220
            let dampingRatio: CGFloat = 1.4   // > 1 = overdamped = slow, sticky settle
            let damping = dampingRatio * 2 * sqrt(stiffness)

            let ddx = fingerPosition.x - visualTipPosition.x
            let ddy = fingerPosition.y - visualTipPosition.y
            visualTipVelocity.x += (stiffness * ddx - damping * visualTipVelocity.x) * CGFloat(dt)
            visualTipVelocity.y += (stiffness * ddy - damping * visualTipVelocity.y) * CGFloat(dt)
            visualTipPosition.x += visualTipVelocity.x * CGFloat(dt)
            visualTipPosition.y += visualTipVelocity.y * CGFloat(dt)
        }

        checkMerge()

        // Stop burning CPU once everything has settled.
        if !anyMoving && !isDragging {
            stopDisplayLink()
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
