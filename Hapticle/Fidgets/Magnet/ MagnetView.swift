import SwiftUI

struct MagnetView: View {
    @StateObject private var model = MagnetModel()
    @Environment(\.colorScheme) private var colorScheme
    var onInteractionChange: ((Bool) -> Void)? = nil

    /// True while a drag that began too far from the knob is being ignored,
    /// so sweeping past the knob mid-gesture doesn't suddenly grab it.
    @State private var dragRejected = false

    private let ringOuterDiameter: CGFloat = 291   // 145.5 * 2, from the mid-fi bezel
    private let ringInnerDiameter: CGFloat = 272   // 136 * 2, the recessed track
    private let ringStrokeWidth: CGFloat = 19
    private let knobDiameter: CGFloat = 56
    /// Touches within this distance of the knob center grab it (~2× its radius,
    /// so it's thumb-friendly and forgiving mid-play).
    private let grabRadius: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.fidgetPrimary
                    .ignoresSafeArea()

                // 1. Static neumorphic ring — never rotates; only the knob moves over it.
                ZStack {
                    Circle()
                        .fill(Color.fidgetPrimary)
                        .frame(width: ringInnerDiameter, height: ringInnerDiameter)
                        .overlay(innerShadowOverlay)

                    Circle()
                        .stroke(Color.fidgetPrimary, lineWidth: ringStrokeWidth)
                        .frame(width: ringOuterDiameter, height: ringOuterDiameter)
                        .shadow(color: Color.shadow.opacity(0.8), radius: 6, x: 6, y: 6)
                        .shadow(color: Color.highlight.opacity(0.9), radius: 6, x: -6, y: -6)
                }
                .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // 2. The draggable magnet knob.
                knobView
                    .position(
                        x: geo.size.width / 2 + model.position.x,
                        y: geo.size.height / 2 + model.position.y
                    )
                    .allowsHitTesting(false) // the canvas-wide gesture below owns all touches
            }
            .contentShape(Rectangle()) // entire canvas receives touch events
            .gesture(dragGesture(in: geo))
            .onAppear { model.configure(canvasSize: geo.size) }
            .onChange(of: geo.size) { newSize in
                model.configure(canvasSize: newSize)
            }
        }
        .onReceive(model.$position) { _ in
            let isActive = model.isDragging || hypot(model.velocity.dx, model.velocity.dy) > 2
            onInteractionChange?(isActive)
        }
        .onChange(of: model.isDragging) { newValue in
            onInteractionChange?(newValue || hypot(model.velocity.dx, model.velocity.dy) > 2)
        }
    }

    // MARK: - Knob

    private var knobView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(red: 245/255, green: 246/255, blue: 248/255),
                                 Color(red: 148/255, green: 152/255, blue: 160/255)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: knobDiameter, height: knobDiameter)
                .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 1))
                .shadow(
                    color: Color.shadow.opacity(model.isOnRing ? 0.6 : 0.35),
                    radius: model.isOnRing ? 4 : 8,
                    x: model.isOnRing ? 3 : 6,
                    y: model.isOnRing ? 3 : 6
                )

            poleMarker
        }
        // Lifted off the glass while free, settling back down when it seats.
        .scaleEffect(model.isPressed ? 0.94 : (model.isOnRing ? 1.0 : 1.06))
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.isPressed)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: model.isOnRing)
    }

    /// The red "polarity" marker: an open ring in light mode, a filled dot in dark mode,
    /// matching the mid-fi mockup for each color scheme.
    @ViewBuilder
    private var poleMarker: some View {
        if colorScheme == .dark {
            Circle()
                .fill(Color.accent)
                .frame(width: 14, height: 14)
        } else {
            Circle()
                .stroke(Color.accent, lineWidth: 3)
                .frame(width: 16, height: 16)
        }
    }

    private var innerShadowOverlay: some View {
        ZStack {
            Circle()
                .stroke(Color.shadow.opacity(0.35), lineWidth: 8)
                .blur(radius: 6)
                .offset(x: 4, y: 4)
            Circle()
                .stroke(Color.highlight.opacity(0.5), lineWidth: 8)
                .blur(radius: 6)
                .offset(x: -4, y: -4)
        }
        .frame(width: ringInnerDiameter, height: ringInnerDiameter)
        .clipShape(Circle())
    }

    // MARK: - Drag Gesture

    /// Canvas-wide gesture: grabs the knob only if the touch begins within
    /// `grabRadius` of it, then tracks the finger in canvas coordinates.
    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if model.isDragging {
                    model.handleDragUpdated(to: value.location)
                } else if !dragRejected {
                    let knobCenter = CGPoint(
                        x: geo.size.width / 2 + model.position.x,
                        y: geo.size.height / 2 + model.position.y
                    )
                    let distance = hypot(value.startLocation.x - knobCenter.x,
                                         value.startLocation.y - knobCenter.y)
                    if distance <= grabRadius {
                        model.handleDragStarted(at: value.startLocation)
                        model.handleDragUpdated(to: value.location)
                    } else {
                        dragRejected = true
                    }
                }
            }
            .onEnded { _ in
                dragRejected = false
                if model.isDragging {
                    model.handleDragEnded()
                }
            }
    }
}

// MARK: - Previews

struct MagnetView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MagnetView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")

            MagnetView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
