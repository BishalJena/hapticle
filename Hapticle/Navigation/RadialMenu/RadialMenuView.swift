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
    @Binding var isMenuVisible: Bool
    /// Fired on commit with the chosen fidget.
    var onSelect: (FidgetID) -> Void
    
    @Environment(IdleTracker.self) private var idleTracker
    
    @State private var model = RadialMenuModel()
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private static let space = "radialMenu"
    let holdMenuText = Array("HOLD FOR MENU · HOLD FOR MENU · ")
    
    var body: some View {
        GeometryReader { geo in
            let ringCenter = CGPoint(x: geo.size.width / 2,
                                     y: geo.size.height - RadialMenuConfig.bottomInset)
            ZStack {
                bottomScrim
                backdrop
                ForEach(FidgetID.allCases) { id in
                    satellite(id, ringCenter: ringCenter)
                }
                ringButton(at: ringCenter)
            }
            .coordinateSpace(.named(Self.space))
        }
        .ignoresSafeArea()
        .onAppear {
            model.onSelect = onSelect
            breathe = true
        }
    }
    
    // MARK: Bottom scrim — grounds the menu pop-up without dimming the whole screen

    /// Only the menu's own section dims: strongest at the bottom edge, easing
    /// to clear before it reaches the fidget. Rises and falls with exactly the
    /// states in which the ring visuals are on screen.
    private var bottomScrim: some View {
        let visible = (model.isCharging || model.isOpen
                       || (idleTracker.isIdleAFK && model.isResting)) && isMenuVisible
        let dim = RadialMenuConfig.scrimMaxOpacity
        // Multi-stop quadratic falloff so the top edge dissolves without a band.
        return LinearGradient(
            stops: [
                .init(color: Color.shadow.opacity(dim), location: 0),
                .init(color: Color.shadow.opacity(dim * 0.62), location: 0.3),
                .init(color: Color.shadow.opacity(dim * 0.28), location: 0.55),
                .init(color: Color.shadow.opacity(dim * 0.09), location: 0.8),
                .init(color: Color.shadow.opacity(0), location: 1)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: RadialMenuConfig.scrimHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .opacity(visible ? 1 : 0)
        // Same asymmetric ease-out language as the backdrop: gentle in, quick out.
        .animation(reduceMotion ? .easeOut(duration: 0.15)
                   : .easeOut(duration: visible ? 0.35 : 0.2),
                   value: visible)
    }

    // MARK: Backdrop — subtle frosted blur while open (masks the swap, focuses the fan)
    
    private var backdrop: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .opacity(model.isOpen && isMenuVisible ? 1 : 0)
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
            assetName: id.assetName,
            isHovered: model.hoveredID == id,
            recede: model.hoveredID != nil && model.hoveredID != id
        )
        .rotationEffect(.degrees(fanSwing(for: id)))          // hand-fan swing-in
        .scaleEffect(satelliteScale(id))
        .opacity(model.isOpen && !committing && isMenuVisible ? 1 : 0)         // chosen dissolves as it flares
        .disabled(!isMenuVisible)
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
            // Active state covers both the charging wind-up AND the fully open menu.
            let isActiveState = model.isCharging || model.isOpen
            // Idle state only triggers if the global tracker fires AND no one is actively holding the button.
            let isIdleState = idleTracker.isIdleAFK && model.isResting
            
            return ZStack {
                // 1. The Omnipresent Geometric Anchor
                // Remains structurally identical and always captures gestural input.
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: RadialMenuConfig.chargeIndicatorDiameter,
                           height: RadialMenuConfig.chargeIndicatorDiameter)

                // 2. The Shared Base (Stroke & Text)
                // Visible if the user is charging, the menu is open, OR the app is in AFK mode.
                ZStack {
                    Circle()
                        .stroke(Color.accent, lineWidth: 1.5)
                    
                    CircularTextView(characters: holdMenuText)
                }
                .frame(width: RadialMenuConfig.chargeIndicatorDiameter,
                       height: RadialMenuConfig.chargeIndicatorDiameter)
                .opacity(isActiveState || isIdleState ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.2), value: isActiveState || isIdleState)
                
                // 3. The Active Fill
                // Stays visible when `model.isOpen` is true.
                Circle()
                    .fill(Color.accent)
                    .frame(width: RadialMenuConfig.chargeIndicatorDiameter * CGFloat(model.chargeProgress),
                           height: RadialMenuConfig.chargeIndicatorDiameter * CGFloat(model.chargeProgress))
                    .opacity(isActiveState ? 1.0 : 0.0)
                    .animation(.easeOut(duration: 0.2), value: isActiveState)

            }
            .frame(width: RadialMenuConfig.satelliteDiameter,
                   height: RadialMenuConfig.satelliteDiameter)
            .contentShape(Circle())
            .gesture(drag(ringCenter: center))
            .position(center)
            
            // Breathing animation applies strictly to the AFK prompt
            .scaleEffect(model.isResting && breathe && isIdleState && !reduceMotion
                         ? RadialMenuConfig.breathScale : 1)
            .animation(.easeInOut(duration: RadialMenuConfig.breathPeriod)
                        .repeatForever(autoreverses: true),
                       value: breathe)
            
            // Physical charge deboss maps to the user's pressure/time
            .scaleEffect(model.isCharging ? 1 + CGFloat(model.chargeProgress) * 0.08 : 1)
            .animation(.spring(RadialMenuConfig.hoverSpring), value: model.chargeProgress)
        }
    
    // MARK: Gesture — one continuous press → charge → drag → release
    
    private func drag(ringCenter: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                                
                if !isMenuVisible {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isMenuVisible = true
                    }
                }
                
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
            .onEnded { _ in
                model.touchUp()
                // Re-engage the countdown the precise millisecond the screen is relinquished
            }
    }
}

#Preview {
    ZStack {
        Color.fidgetPrimary.ignoresSafeArea()
        RadialMenuView(isMenuVisible: .constant(true), onSelect: { print("selected \($0.label)") })
    }
}

/// Helper view that displays text characters evenly distributed along a circular boundary,
/// rotating continuously to indicate the hold-to-charge action.
struct CircularTextView: View {
    let characters: [Character] // 32 characters total
    private let radius: CGFloat = (RadialMenuConfig.chargeIndicatorDiameter/2)+12                          // Fits outside the 46x46 boundary

    @State private var rotation: Double = 0.0
    @Environment(\.colorScheme) private var colorScheme

    /// accentShadow disappears against the dark background; use the highlight there.
    private var textColor: Color {
        colorScheme == .dark ? Color.accentHighlight : Color.accentShadow
    }

    var body: some View {
        ZStack {
            ForEach(0..<characters.count, id: \.self) { index in
                let char = String(characters[index])
                let angle = Double(index) * (360.0 / Double(characters.count))

                Text(char)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(textColor)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(angle))
            }
        }
        .rotationEffect(.degrees(rotation))
        .onAppear {
            // Animate local state for a smooth continuous 0.1 rev/sec rotation
            withAnimation(.linear(duration:10.0).repeatForever(autoreverses: false)) {
                rotation = 360.0
            }
        }
    }
}

