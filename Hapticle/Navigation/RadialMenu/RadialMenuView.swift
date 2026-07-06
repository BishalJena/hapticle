//
//  RadialMenuView.swift
//  Hapticle
//
//  The bottom-anchored hold-to-radial selector overlay. Owns one continuous
//  DragGesture (press → charge → drag → release) and drives the seven-beat
//  neumorphic choreography. Screen→ring translation lives here; the model stays
//  in ring-relative space.
//

import SwiftUI

struct RadialMenuView: View {
    /// Fired on commit with the chosen fidget.
    var onSelect: (FidgetID) -> Void

    @State private var model = RadialMenuModel()
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let space = "radialMenu"

    var body: some View {
        GeometryReader { geo in
            let ringCenter = CGPoint(x: geo.size.width / 2,
                                     y: geo.size.height - RadialMenuConfig.bottomInset)
            ZStack {
                backdrop
                ForEach(FidgetID.allCases) { id in
                    satellite(id, ringCenter: ringCenter)
                }
                ringButton(at: ringCenter)
            }
            .coordinateSpace(.named(Self.space))
            .contentShape(Rectangle())
            .gesture(drag(ringCenter: ringCenter))
        }
        .ignoresSafeArea()
        .onAppear {
            model.onSelect = onSelect
            breathe = true
        }
    }

    // MARK: Backdrop — subtle frosted blur while open (masks the swap, focuses the fan)

    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(model.isOpen ? 1 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            // Ease-out both ways, but exit is quicker than enter (asymmetric).
            .animation(reduceMotion ? .easeOut(duration: 0.15)
                       : .easeOut(duration: model.isOpen ? 0.28 : 0.16),
                       value: model.isOpen)
    }

    // MARK: A satellite (bloom, fan-swing, and commit choreography driven here)

    private func satellite(_ id: FidgetID, ringCenter: CGPoint) -> some View {
        let o = model.offset(for: id)
        let target = CGPoint(x: ringCenter.x + o.width, y: ringCenter.y + o.height)
        let isChosen = model.committingID == id
        let committing = model.committingID != nil

        return SatelliteNode(
            label: id.label,
            isHovered: model.hoveredID == id,
            recede: model.hoveredID != nil && model.hoveredID != id
        )
        .rotationEffect(.degrees(fanSwing(for: id)))          // hand-fan swing-in
        .scaleEffect(satelliteScale(id))
        .opacity(model.isOpen && !committing ? 1 : 0)         // chosen dissolves as it flares
        .position(committing && !isChosen ? siblingFallPosition(o, from: ringCenter)
                  : (model.isOpen ? target : ringCenter))    // emerge from / return to the dot
        .animation(satelliteAnimation(id), value: model.phase)
    }

    /// Bloom scale: emerge from the dot, flare on commit, else full size.
    private func satelliteScale(_ id: FidgetID) -> CGFloat {
        guard model.isOpen else { return RadialMenuConfig.satelliteStartScale }
        if model.committingID == id { return RadialMenuConfig.commitFlareScale }
        if model.committingID != nil { return RadialMenuConfig.siblingScale }
        return 1
    }

    /// Outward tilt when closed that swings to 0 as the fan opens (hand-fan feel).
    private func fanSwing(for id: FidgetID) -> Double {
        guard !reduceMotion, !model.isOpen else { return 0 }   // upright once open
        let side = (90 - id.domeAngleDegrees) / 90             // A(180)→−1 … E(0)→+1
        return side * RadialMenuConfig.fanSwingDegrees
    }

    /// Unchosen nodes drift a little further out as they fall away on commit.
    private func siblingFallPosition(_ o: CGSize, from ringCenter: CGPoint) -> CGPoint {
        let len = max((o.width * o.width + o.height * o.height).squareRoot(), 1)
        let reach = RadialMenuConfig.bloomRadius + RadialMenuConfig.siblingFallDrift
        return CGPoint(x: ringCenter.x + o.width / len * reach,
                       y: ringCenter.y + o.height / len * reach)
    }

    /// Per-node animation: staggered lively open, snappy close, spring flare on commit.
    private func satelliteAnimation(_ id: FidgetID) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.15) }
        if model.committingID == id { return .spring(RadialMenuConfig.commitSpring) }
        if model.isOpen {
            return .spring(RadialMenuConfig.openSpring)
                .delay(Double(id.rawValue) * RadialMenuConfig.bloomStagger)
        }
        return .spring(RadialMenuConfig.closeSpring)
    }

    // MARK: Home ring + charge arc

    private func ringButton(at center: CGPoint) -> some View {
        ZStack {
            // Resting/pressed neumorphic ring with an inner recessed detail
            // (echoes the idle ring glyph in the reference).
            Circle()
                .fill(Color.hpBase)
                .frame(width: RadialMenuConfig.ringDiameter,
                       height: RadialMenuConfig.ringDiameter)
                .neumorphicCircle(isPressed: model.isCharging || model.isOpen)
                .overlay(
                    Circle()
                        .stroke(Color.hpShadow.opacity(0.55), lineWidth: 2)
                        .frame(width: RadialMenuConfig.ringDiameter * 0.42,
                               height: RadialMenuConfig.ringDiameter * 0.42)
                )
                // Idle breathing — subtle, and skipped under Reduce Motion.
                .scaleEffect(model.isResting && breathe && !reduceMotion
                             ? RadialMenuConfig.breathScale : 1)
                .animation(.easeInOut(duration: RadialMenuConfig.breathPeriod)
                            .repeatForever(autoreverses: true),
                           value: breathe)
                // Charge feedback: the dot presses in (deboss above) and
                // swells slightly while held. No colored progress ring.
                .scaleEffect(model.isCharging ? 1 + CGFloat(model.chargeProgress) * 0.08 : 1)
                .animation(.spring(RadialMenuConfig.hoverSpring), value: model.chargeProgress)
        }
        .position(center)
    }

    // MARK: Gesture — one continuous press → charge → drag → release

    private func drag(ringCenter: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if model.isResting {
                    // Only begin charging if the touch started on the ring.
                    let d = hypot(value.startLocation.x - ringCenter.x,
                                  value.startLocation.y - ringCenter.y)
                    if d <= RadialMenuConfig.ringDiameter { model.touchDown() }
                }
                let local = CGPoint(x: value.location.x - ringCenter.x,
                                    y: value.location.y - ringCenter.y)
                model.dragChanged(to: local)
            }
            .onEnded { _ in model.touchUp() }
    }
}

#Preview {
    ZStack {
        Color.hpBase.ignoresSafeArea()
        RadialMenuView(onSelect: { print("selected \($0.label)") })
    }
}
