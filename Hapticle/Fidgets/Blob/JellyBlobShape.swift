import SwiftUI

/// A soft-body, gooey blob outline: 8 radial control points around the
/// anchor↔tip axis, connected by a Catmull-Rom spline. Replaces the old
/// pairing of a static `Circle()` + rigid `StadiumShape` connector — this is
/// one continuous shape whether the blob is resting or mid-drag, so there's
/// no seam between "circle" and "stretch connector".
///
/// - `anchor` is the blob's rest center.
/// - `tip` equals `anchor` when idle, or the (spring-lagged) drag point while
///   stretching — the shape naturally collapses to a wobbly near-circle when
///   `tip == anchor`.
/// - `tension` (0...1) drives elongation + waist necking as the blob stretches.
/// - `wobblePhase` drives a continuous idle jiggle so the blob never looks static.
struct JellyBlobShape: Shape {
    var anchor: CGPoint
    var tip: CGPoint
    var baseRadius: CGFloat
    var tension: CGFloat
    var wobblePhase: CGFloat

    /// Number of control points around the blob's silhouette.
    private static let pointCount = 8

    var animatableData: AnimatableVector {
        get {
            AnimatableVector(values: [
                Double(anchor.x), Double(anchor.y),
                Double(tip.x), Double(tip.y),
                Double(baseRadius), Double(tension), Double(wobblePhase),
            ])
        }
        set {
            anchor = CGPoint(x: newValue.values[0], y: newValue.values[1])
            tip = CGPoint(x: newValue.values[2], y: newValue.values[3])
            baseRadius = CGFloat(newValue.values[4])
            tension = CGFloat(newValue.values[5])
            wobblePhase = CGFloat(newValue.values[6])
        }
    }

    func path(in rect: CGRect) -> Path {
        let points = Self.controlPoints(
            anchor: anchor, tip: tip, baseRadius: baseRadius,
            tension: tension, wobblePhase: wobblePhase
        )
        return Self.catmullRomClosedPath(points: points)
    }

    /// Computes the 8 radial control points that outline the blob.
    ///
    /// Geometry: the blob is an ellipse-ish ring stretched along the
    /// anchor→tip axis. `semiMajor` grows with the anchor↔tip distance
    /// (elongation toward the finger); `semiMinor` shrinks with `tension`
    /// (necking/thinning at the waist — the "sticky jelly pinch"). A
    /// multi-frequency per-point sine wobble keeps the outline alive at rest.
    static func controlPoints(
        anchor: CGPoint, tip: CGPoint, baseRadius: CGFloat,
        tension: CGFloat, wobblePhase: CGFloat
    ) -> [CGPoint] {
        let dx = tip.x - anchor.x
        let dy = tip.y - anchor.y
        let dist = hypot(dx, dy)

        let ux: CGFloat
        let uy: CGFloat
        if dist > 0.5 {
            ux = dx / dist
            uy = dy / dist
        } else {
            ux = 1
            uy = 0
        }
        // Perpendicular axis.
        let vx = -uy
        let vy = ux

        let mid = CGPoint(x: (anchor.x + tip.x) / 2, y: (anchor.y + tip.y) / 2)
        let halfLen = dist / 2

        let clampedTension = min(max(tension, 0), 1)
        let endBulge: CGFloat = 1 + 0.15 * clampedTension
        let waistScale: CGFloat = max(1 - 0.55 * clampedTension, 0.28)

        let semiMajor = baseRadius * endBulge + halfLen
        let semiMinor = baseRadius * waistScale

        let wobbleAmp: CGFloat = 0.06

        return (0..<pointCount).map { i -> CGPoint in
            let theta = CGFloat(i) / CGFloat(pointCount) * 2 * .pi
            let wobble = sin(wobblePhase + CGFloat(i) * 0.73) * 0.5
                       + sin(wobblePhase * 1.31 + CGFloat(i) * 1.9) * 0.5
            let rx = semiMajor * cos(theta) * (1 + wobbleAmp * wobble)
            let ry = semiMinor * sin(theta) * (1 + wobbleAmp * wobble)
            return CGPoint(x: mid.x + rx * ux + ry * vx,
                            y: mid.y + rx * uy + ry * vy)
        }
    }

    /// Uniform Catmull-Rom spline through a closed loop of points, converted
    /// to cubic Bezier segments via the standard 1/6 tangent scaling.
    static func catmullRomClosedPath(points: [CGPoint]) -> Path {
        var path = Path()
        let n = points.count
        guard n >= 3 else { return path }

        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]

            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6,
                               y: p1.y + (p2.y - p0.y) / 6)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6,
                               y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        path.closeSubpath()
        return path
    }
}

/// Minimal `VectorArithmetic` wrapper so SwiftUI can interpolate an arbitrary
/// fixed-length list of `Double`s (used by `JellyBlobShape.animatableData`).
struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero = AnimatableVector(values: Array(repeating: 0, count: 7))

    static func + (lhs: Self, rhs: Self) -> Self {
        AnimatableVector(values: zip(lhs.values, rhs.values).map(+))
    }

    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }

    static func - (lhs: Self, rhs: Self) -> Self {
        AnimatableVector(values: zip(lhs.values, rhs.values).map(-))
    }

    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }

    mutating func scale(by rhs: Double) {
        values = values.map { $0 * rhs }
    }

    var magnitudeSquared: Double {
        values.reduce(0) { $0 + $1 * $1 }
    }
}
