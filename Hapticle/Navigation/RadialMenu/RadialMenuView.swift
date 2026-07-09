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
    
    @State private var model = RadialMenuModel()
    @State private var breathe = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private static let space = "radialMenu"
    private let holdMenuText = Array("HOLD FOR MENU · HOLD FOR MENU · ")
    
    var body: some View {
        GeometryReader { geo in
            let ringCenter = CGPoint(x: geo.size.width / 2,
                                     y: geo.size.height - RadialMenuConfig.bottomInset)
            let swipeCenter = CGPoint(x: geo.size.width * 0.65,
                                      y: geo.size.height * 0.35)
            
            ZStack {
                backdrop
                
                    // TWO FINGER SWIPE ARTIFACT
//                if model.isOpen {
//                    SwipeInstructionOverlay(placement: swipeCenter)
//                        .padding(.bottom, 300)
//                }
                
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
        ZStack {
            // Liquid Glass Toggle Button - exactly 46x46
            ZStack {
                // Glass Base
                //                Circle()
                //                    .fill(.thinMaterial)
                //
                //                // Inner Shadow (recessed peephole look)
                //                Circle()
                //                    .stroke(Color.black.opacity(0.18), lineWidth: 3)
                //                    .blur(radius: 2)
                //                    .offset(x: 1.5, y: 1.5)
                //                    .mask(Circle())
                //
                //                // Outer Bezel Stroke
                //                Circle()
                //                    .stroke(
                //                        LinearGradient(
                //                            colors: [.white.opacity(0.55), .clear, .black.opacity(0.15)],
                //                            startPoint: .topLeading,
                //                            endPoint: .bottomTrailing
                //                        ),
                //                        lineWidth: 1.0
                //                    )
                
                // Red Charge Indicators (Behind Menu Image)
                if model.isCharging || model.isOpen {
                    // A. Static target boundary ring
                    Circle()
                        .stroke(Color.accent, lineWidth: 1.5)
                        .frame(width: RadialMenuConfig.chargeIndicatorDiameter,
                               height: RadialMenuConfig.chargeIndicatorDiameter)
                    
                    // B. Linearly growing progress circle
                    Circle()
                        .fill(Color.accent)
                        .frame(width: RadialMenuConfig.chargeIndicatorDiameter * CGFloat(model.chargeProgress),
                               height: RadialMenuConfig.chargeIndicatorDiameter * CGFloat(model.chargeProgress))
                    
                    // C. Rotating Circular Instruction Text
                    CircularTextView(characters: holdMenuText)
                }
                
                // Scaled central toggle Icon/Menu
                Image("Icon/Menu")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)
            }
            .frame(width: RadialMenuConfig.satelliteDiameter,
                   height: RadialMenuConfig.satelliteDiameter)
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
        .opacity(isMenuVisible ? 1.0 : 0.015)
        .contentShape(Circle())
        .gesture(drag(ringCenter: center))
        .position(center)
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
            .onEnded { _ in model.touchUp() }
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
    
    var body: some View {
        ZStack {
            ForEach(0..<characters.count, id: \.self) { index in
                let char = String(characters[index])
                let angle = Double(index) * (360.0 / Double(characters.count))
                
                Text(char)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.accent)
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


// MARK: - Animated Swipe Instruction Overlay

/// An autonomous, self-animating instructional module that continuously translates
/// from right to left to visually articulate the required directional gesture.
struct SwipeInstructionOverlay: View {
    let placement: CGPoint
    private let swipeText = Array("SWIPE TO CYCLE · SWIPE TO CYCLE · ")
    
    @State private var horizontalOffset: CGFloat = 35.0
    
    // Defines the precise temporal parameters for the kinetic cycle
    private let swipeDuration: TimeInterval = 0.8
    private let terminalPause: TimeInterval = 0.5
    
    
    private var chargedCircle: some View {
        ZStack {
            // A. Static target boundary ring
            Circle()
                .stroke(Color.accent, lineWidth: 1.5)
                .frame(width: RadialMenuConfig.chargeIndicatorDiameter,
                       height: RadialMenuConfig.chargeIndicatorDiameter)
            
            // C. Rotating Circular Instruction Text utilizing the swipe array
            CircularTextView(characters: swipeText)
        }
        .frame(width: RadialMenuConfig.satelliteDiameter,
               height: RadialMenuConfig.satelliteDiameter)
        .allowsHitTesting(false) // Ensures the graphic does not obstruct underlying drag events
    }
    
    var body: some View {
        VStack{
            chargedCircle
                .padding(100)
            chargedCircle
        }
        .frame(width: 46, height: 46)
        .offset(x: horizontalOffset)
        .position(placement)
        .allowsHitTesting(false)
        .onAppear {
            initiateKineticLoop()
        }
        .transition(.opacity)
    }
    
    /// Orchestrates an infinite loop detailing instantaneous resets,
    /// decelerating translations, and calculated chronological delays.
    func initiateKineticLoop() {
        Task {
            // Continuously execute until the view is dismantled and the task cancels
            while !Task.isCancelled {
                
                // 1. Instantaneous Reset: Snap the graphic to the starting right-side coordinate
                // by explicitly overriding and disabling any implicit SwiftUI animations.
                await MainActor.run {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        horizontalOffset = 35.0
                    }
                }
                
                // Yield the thread momentarily to guarantee the rendering engine processes
                // the un-animated coordinate jump before commencing the actual swipe.
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                
                // 2. The Swipe: Execute the translation utilizing a non-linear interpolation.
                // The .easeOut curve manifests high initial velocity that gracefully degrades
                // as the element approaches its terminal left-side destination.
                await MainActor.run {
                    withAnimation(.easeOut(duration: swipeDuration)) {
                        horizontalOffset = -100.0
                    }
                }
                
                // 3. The Pause: Suspend the loop execution for the combined duration of the
                // physical animation plus the requested rigid observation period.
                let totalCycleDelay = swipeDuration + terminalPause
                try? await Task.sleep(nanoseconds: UInt64(totalCycleDelay * 1_000_000_000))
            }
        }
    }
}
