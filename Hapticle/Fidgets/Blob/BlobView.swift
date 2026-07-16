import SwiftUI

struct BlobView: View {
    @StateObject private var model = BlobModel()
    @Environment(\.colorScheme) private var colorScheme
    @Environment(IdleTracker.self) private var idleTracker
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── 1. Full-screen background ────────────────────────────────
                Color.fidgetPrimary
                    .ignoresSafeArea()
                
                // ── 2. Neumorphic tile grid ──────────────────────────────────
                BlobBackgroundGrid(size: geo.size, colorScheme: colorScheme)
                    .allowsHitTesting(false)
                
                // ── 3. Soft-body jelly blobs ─────────────────────────────────
                //  Each blob is a Verlet ring simulated in BlobModel; the view
                //  just draws whatever perimeter the physics produces. The ring
                //  breathes at rest and jiggles/settles when stretched, so no
                //  procedural wobble or separate stretch connector is needed.
                ForEach(model.blobs) { blob in
                    JellyBlobRender(points: blob.ringPoints)
                }
            }
            .contentShape(Rectangle())     // entire canvas receives touch events
            .gesture(dragGesture)
            .onAppear { model.activate(in: geo.size) }
            .onDisappear { model.deactivate() }
        }
    }
    
    // MARK: - Drag Gesture
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // 2. Trigger interaction on touch (dragging the jelly)
                idleTracker.userInteracted()
                
                // Guard against multi-touch hijack mid-drag.
                if !model.isDragging {
                    model.handleDragStart(at: value.startLocation)
                } else {
                    model.handleDragChanged(to: value.location)
                }
            }
            .onEnded { _ in
                // 3. Restart AFK timer on release, even while jelly is still jiggling
                idleTracker.restartTimer()
                model.handleDragEnd()
            }
    }
}

// MARK: - Jelly Blob Render

/// Draws one soft-body blob from its perimeter points, layering a neumorphic
/// drop shadow, the body fill, and a soft inner rim so it reads as a glossy,
/// slightly translucent piece of jelly rather than a flat sticker.
private struct JellyBlobRender: View {
    let points: [CGPoint]
    
    var body: some View {
        let shape = JellyBlobShape(points: points)
        shape
            .fill(Color.accent)
        // Top-left highlight → lower-right shadow gives the blob weight.
            .shadow(color: Color.white.opacity(0.28), radius: 4, x: -2, y: -2)
            .shadow(color: Color(red: 0.537, green: 0.141, blue: 0.141).opacity(0.50),
                    radius: 7, x: 3, y: 4)
        // Soft glossy rim — a faint bright edge that catches the light and
        // sells the wet, gelatinous surface as the outline flexes.
            .overlay {
                shape.stroke(Color.white.opacity(0.22), lineWidth: 2)
                    .blur(radius: 1.5)
                    .blendMode(.plusLighter)
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

// MARK: - Previews

struct BlobView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            BlobView()
                .preferredColorScheme(.light)
                .previewDisplayName("Blob — Light")
                .environment(IdleTracker())

            BlobView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Blob — Dark")
                .environment(IdleTracker())

        }
    }
}
