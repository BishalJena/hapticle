import SwiftUI

struct MagnetView: View {
    @StateObject private var model = MagnetModel()
    @Environment(\.colorScheme) private var colorScheme
    var onInteractionChange: ((Bool) -> Void)? = nil

    @State private var dragStartFingerPosition: CGPoint = .zero

    private let ringOuterDiameter: CGFloat = 291   // 145.5 * 2, from the mid-fi bezel
    private let ringInnerDiameter: CGFloat = 272   // 136 * 2, the recessed track
    private let ringStrokeWidth: CGFloat = 19
    private let knobDiameter: CGFloat = 56

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
                    .contentShape(Circle())
                    .gesture(dragGesture(in: geo))
            }
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
                    color: Color.shadow.opacity(model.couplingState == .attached ? 0.6 : 0.35),
                    radius: model.couplingState == .attached ? 4 : 8,
                    x: model.couplingState == .attached ? 3 : 6,
                    y: model.couplingState == .attached ? 3 : 6
                )

            poleMarker
        }
        .scaleEffect(model.isPressed ? 0.94 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: model.isPressed)
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

    /// Tracks translation from the knob's own position at drag-start rather than
    /// raw gesture-local coordinates, so the model always receives finger position
    /// in the same absolute canvas space as `ringCenter`.
    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !model.isDragging {
                    dragStartFingerPosition = CGPoint(
                        x: geo.size.width / 2 + model.position.x,
                        y: geo.size.height / 2 + model.position.y
                    )
                    model.handleDragStarted(at: dragStartFingerPosition)
                }
                let updated = CGPoint(
                    x: dragStartFingerPosition.x + value.translation.width,
                    y: dragStartFingerPosition.y + value.translation.height
                )
                model.handleDragUpdated(to: updated)
            }
            .onEnded { _ in
                model.handleDragEnded()
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
