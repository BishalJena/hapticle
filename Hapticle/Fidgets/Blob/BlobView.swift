import SwiftUI

struct BlobView: View {
    @StateObject private var model = BlobModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── 1. Full-screen background ────────────────────────────────
                Color.fidgetPrimary
                    .ignoresSafeArea()

                // ── 2. Neumorphic tile grid ──────────────────────────────────
                BlobBackgroundGrid(size: geo.size, colorScheme: colorScheme)
                    .allowsHitTesting(false)

                // ── 3. Stretch connector (stadium shape while dragging) ──────
                if model.isDragging,
                   let id = model.dragBlobID,
                   let blob = model.blobs.first(where: { $0.id == id }) {

                    StadiumShape(from: blob.center,
                                 to: model.fingerPosition,
                                 radius: blob.radius)
                        .fill(Color.accent)
                        // Subtle neumorphic depth on the stretch body.
                        .shadow(color: Color.white.opacity(0.28), radius: 4, x: -2, y: -2)
                        .shadow(color: Color(red: 0.537, green: 0.141, blue: 0.141).opacity(0.50),
                                radius: 7, x: 3, y: 4)
                }

                // ── 4. Blob circles ─────────────────────────────────────────
                ForEach(model.blobs) { blob in
                    Circle()
                        .fill(Color.accent)
                        .frame(width: blob.radius * 2, height: blob.radius * 2)
                        // Top-left highlight → lower-right shadow gives the blob weight.
                        .shadow(color: Color.white.opacity(0.28), radius: 4, x: -2, y: -2)
                        .shadow(color: Color(red: 0.537, green: 0.141, blue: 0.141).opacity(0.50),
                                radius: 7, x: 3, y: 4)
                        .position(blob.center)
                }
            }
            .contentShape(Rectangle())     // entire canvas receives touch events
            .gesture(dragGesture)
            .onAppear {
                model.initializeBlobs(in: geo.size)
            }
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Guard against multi-touch hijack mid-drag.
                if !model.isDragging {
                    model.handleDragStart(at: value.startLocation)
                } else {
                    model.handleDragChanged(to: value.location)
                }
            }
            .onEnded { _ in
                model.handleDragEnd()
            }
    }
}

// MARK: - Neumorphic Background Grid

/// Renders the 5-column × n-row grid of neumorphic raised tiles that fills
/// the blob canvas. Exact shadow values extracted from the Figma SVG assets.
///
/// Note: This view intentionally uses the SVG-template–friendly pattern —
/// tile fill = fidgetPrimary so `.foregroundStyle()` adapts the grid to any
/// theme automatically, with no separate SVG assets needed (per Moreno's note).
struct BlobBackgroundGrid: View {
    let size: CGSize
    let colorScheme: ColorScheme

    // Grid geometry — mirrors the Figma SVG exactly.
    private let cols: Int = 5
    private let tileSize: CGFloat = 66
    private let step: CGFloat = 76          // tile + 10pt gap
    private let cornerRadius: CGFloat = 15

    private var startX: CGFloat { colorScheme == .dark ? 17 : 16 }
    private var startY: CGFloat { colorScheme == .dark ? 17 : 15 }

    /// Compute enough rows to fill any iPhone screen height.
    private var rows: Int {
        Int(ceil((size.height - startY) / step)) + 2
    }

    // ── Shadow palette (from Figma filter nodes) ─────────────────────────────
    // Light: white highlight top-left, #A3B1C6 shadow bottom-right
    // Dark:  very subtle inversion, lower opacity on both channels.

    private var highlightColor: Color {
        colorScheme == .dark
            ? Color(white: 0.851).opacity(0.10)
            : Color.white
    }
    private var shadowColor: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.15)
            : Color(red: 0.639, green: 0.694, blue: 0.776)
    }
    private var highlightX: CGFloat { colorScheme == .dark ? -5 : -3 }
    private var highlightY: CGFloat { colorScheme == .dark ? -5 : -3 }
    private var shadowX:    CGFloat { colorScheme == .dark ?  5 :  3 }
    private var shadowY:    CGFloat { colorScheme == .dark ?  5 :  3 }

    var body: some View {
        ZStack {
            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<cols, id: \.self) { col in
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.fidgetPrimary)
                        .frame(width: tileSize, height: tileSize)
                        .shadow(color: highlightColor,
                                radius: 6,
                                x: highlightX, y: highlightY)
                        .shadow(color: shadowColor,
                                radius: 6,
                                x: shadowX, y: shadowY)
                        .position(
                            x: startX + CGFloat(col) * step + tileSize / 2,
                            y: startY + CGFloat(row) * step + tileSize / 2
                        )
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .opacity(0.5)
        .drawingGroup()     // flatten the grid to a single Metal texture — avoids
                            // 60+ individual shadow composites on every frame.
    }
}

// MARK: - Stadium Shape

/// A smooth convex hull connecting two circles: the anchor (blob.center) and
/// the fingertip. Mathematically: two tangent arcs joined by straight tangent
/// lines — equivalent to a variable-length capsule rotated toward the finger.
///
/// Implements `animatableData` so SwiftUI can interpolate the shape smoothly
/// when `from` or `to` move frame-to-frame, eliminating any jumpiness.
struct StadiumShape: Shape {
    var from: CGPoint
    var to: CGPoint
    var radius: CGFloat

    // Smooth shape morphing via SwiftUI's implicit animation system.
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>,
                                       AnimatablePair<CGFloat, CGFloat>> {
        get {
            AnimatablePair(AnimatablePair(from.x, from.y),
                           AnimatablePair(to.x, to.y))
        }
        set {
            from = CGPoint(x: newValue.first.first,  y: newValue.first.second)
            to   = CGPoint(x: newValue.second.first, y: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        let dx   = to.x - from.x
        let dy   = to.y - from.y
        let dist = hypot(dx, dy)

        // Degenerate case — collapsed to a single circle.
        guard dist > 0.5 else {
            return Path(ellipseIn: CGRect(
                x: from.x - radius, y: from.y - radius,
                width: radius * 2,  height: radius * 2
            ))
        }

        // Perpendicular unit offset (rotated 90° from the stretch direction).
        let px = -dy / dist * radius
        let py =  dx / dist * radius
        let angle = atan2(dy, dx)

        // Stadium construction:
        //   1. Move to the perpendicular-offset of `from` (left side, screen coords).
        //   2. Line along the left tangent to the perpendicular-offset of `to`.
        //   3. Arc around `to` clockwise (far cap, CW in screen coords).
        //   4. Line along the right tangent back toward `from`.
        //   5. Arc around `from` counter-clockwise (near cap, CCW in screen coords).
        //   6. closeSubpath — zero-length line back to step 1.
        var path = Path()
        path.move(to: CGPoint(x: from.x + px, y: from.y + py))
        path.addLine(to: CGPoint(x: to.x + px, y: to.y + py))
        path.addArc(center: to, radius: radius,
                    startAngle: .radians(angle + .pi / 2),
                    endAngle:   .radians(angle - .pi / 2),
                    clockwise: true)
        path.addLine(to: CGPoint(x: from.x - px, y: from.y - py))
        path.addArc(center: from, radius: radius,
                    startAngle: .radians(angle - .pi / 2),
                    endAngle:   .radians(angle + .pi / 2),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

// MARK: - Previews

struct BlobView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BlobView()
                .preferredColorScheme(.light)
                .previewDisplayName("Blob — Light")
            BlobView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Blob — Dark")
        }
    }
}
