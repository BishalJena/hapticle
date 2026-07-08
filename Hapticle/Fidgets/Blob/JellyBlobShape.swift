import SwiftUI

/// A pure renderer for a soft-body blob: it takes a closed loop of perimeter
/// points (already in view coordinates) and draws a smooth, continuous outline
/// through them using a Catmull-Rom spline converted to cubic Beziers.
///
/// All deformation physics lives in `BlobModel` — this shape just draws
/// whatever ring of points the simulation produces each frame, so a single
/// shape covers rest, stretch, wobble, and mitosis with no special cases.
struct JellyBlobShape: Shape {
    var points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        Self.catmullRomClosedPath(points: points)
    }

    /// Uniform Catmull-Rom spline through a closed loop, converted to cubic
    /// Bezier segments via the standard 1/6 tangent scaling. A closed loop of
    /// ~32 points yields a smooth, organic silhouette with no visible facets.
    static func catmullRomClosedPath(points: [CGPoint]) -> Path {
        var path = Path()
        let n = points.count
        guard n >= 3 else {
            // Degenerate fallback: a dot, so we never crash on an empty ring.
            if let p = points.first {
                path.addEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2))
            }
            return path
        }

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
