//
//  TicketView.swift
//  Hapticle
//

import SwiftUI

/// Extracts the vertical boundary coordinate of the machine's aperture.
struct SlotPositionKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Dynamically acquires the exact rendered vertical dimension of a single ticket asset.
struct TicketHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A standalone component rendering the full ticket visual asset stack.
struct Ticket: View {
    var body: some View {
        Image("Ticket")
            .renderingMode(.template)
            .foregroundStyle(Color.accent)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: TicketHeightKey.self, value: geo.size.height)
                }
            )
            .overlay {
                ZStack {
                    Image("TicketInnerSquare")
                        .renderingMode(.template)
                        .foregroundStyle(Color.accent)
                        .shadow(color: Color.accentHighlight, radius: 6, x: -6, y: -6)
                        .shadow(color: .accentShadow, radius: 6, x: 6, y: 6)
                    
                    Image("TicketText")
                        .renderingMode(.template)
                        .foregroundStyle(Color.accent)
                        .shadow(color: Color.accentHighlight.opacity(0.5), radius: 6, x: -3, y: -3)
                        .shadow(color: .accentShadow.opacity(1.0), radius: 3, x: 3, y: 3)
                        .padding(.leading, 10)
                    
                    Image("TicketAdmitText")
                        .renderingMode(.template)
                        .foregroundStyle(Color.accent)
                        .shadow(color: Color.accentHighlight.opacity(0.5), radius: 3, x: -1, y: -1)
                        .shadow(color: .accentShadow.opacity(1.0), radius: 1.5, x: 1, y: 1)
                        .padding(.trailing, 80)
                    
                    Image("TicketHapticleText")
                        .renderingMode(.template)
                        .foregroundStyle(Color.accent)
                        .shadow(color: Color.accentHighlight.opacity(0.5), radius: 5, x: -1, y: -1)
                        .shadow(color: .accentShadow.opacity(1.0), radius: 1.5, x: 1, y: 1)
                        .padding(.leading, 135)
                    
                    Image("TicketNumberText")
                        .renderingMode(.template)
                        .foregroundStyle(Color.accent)
                        .shadow(color: Color.accentHighlight.opacity(0.5), radius: 3, x: -1, y: -1)
                        .shadow(color: .accentShadow.opacity(1.0), radius: 1.5, x: 1, y: 1)
                        .padding(.trailing, 135)
                }
            }
    }
}

struct TicketView: View {
    @StateObject private var model = TicketModel()
    
    var body: some View {
        ZStack {
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            // LAYER 1: Foundational Base Machine Chassis
            machineBackground
            
            // LAYER 2: Autonomous, Auto-Replenishing Ticket Sequence
            GeometryReader { geometry in
                AutoReplenishingTicketRoll(model: model)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .mask(
                        VStack(spacing: 0) {
                            Color.clear.frame(height: max(0, model.revealBoundaryY))
                            Color.white
                        }
                            .ignoresSafeArea()
                    )
            }
            .ignoresSafeArea()
            
            // LAYER 3: Foreground Slot Mechanism Overlay
            machineForegroundOverlay
        }
        .coordinateSpace(name: "GlobalMachineSpace")
        .onPreferenceChange(SlotPositionKey.self) { yPosition in
            model.slotOriginY = yPosition
        }
    }
    
    // MARK: - Subviews
    
    private var machineBackground: some View {
        VStack {
            Image("Machine")
                .renderingMode(.template)
                .foregroundStyle(Color.fidgetPrimary)
                .shadow(color: Color.highlight.opacity(0.4), radius: 6, x: -6, y: -6)
                .shadow(color: .shadow, radius: 6, x: 6, y: 6)
                .overlay {
                    VStack {
                        HStack { bolt; Spacer(); bolt }
                        Spacer()
                        HStack { bolt; Spacer(); bolt }
                    }
                    .padding(20)
                }
                .overlay {
                    VStack {
                        Spacer()
                        hole.padding(.top, 11)
                        Spacer()
                    }
                }
                .padding(.top, 50)
            Spacer()
        }
    }
    
    private var machineForegroundOverlay: some View {
        VStack {
            Image("Machine")
                .opacity(0)
                .overlay {
                    VStack(spacing: -14.5) {
                        Spacer()
                        overhang
                            .padding(.bottom, 14.5)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: SlotPositionKey.self,
                                        value: geo.frame(in: .named("GlobalMachineSpace")).minY
                                    )
                                }
                            )
                        Spacer()
                    }
                }
                .padding(.top, 50)
            Spacer()
        }
        .allowsHitTesting(false)
    }
    
    private var bolt: some View {
        Image("MachineBolt")
            .renderingMode(.template)
            .foregroundStyle(Color.fidgetPrimary)
            .shadow(color: Color.highlight, radius: 6, x: -3, y: -3)
            .shadow(color: .shadow, radius: 6, x: 3, y: 3)
    }
    
    private var overhang: some View {
        Image("MachineOverhang")
            .renderingMode(.template)
            .foregroundStyle(Color.fidgetPrimary)
            .shadow(color: Color.highlight.opacity(0.4), radius: 6, x: -3, y: -3)
            .shadow(color: .shadow.opacity(0.25), radius: 3, x: 3, y: 3)
    }
    
    private var hole: some View {
        Image("MachineHole")
            .renderingMode(.template)
            .foregroundStyle(Color.fidgetPrimary)
            .innerShadowShift(mask: Image("MachineHole"), color: Color.shadow.opacity(0.50), blur: 3, x: 0, y: -3)
            .innerShadowShift(mask: Image("MachineHole"), color: Color.highlight.opacity(0.25), blur: 5, x: 0, y: 7)
    }
}

/// Orchestrates the physical dispenser simulation while retaining strict dimensional boundaries.
struct AutoReplenishingTicketRoll: View {
    @ObservedObject var model: TicketModel
    
    var body: some View {
        ZStack(alignment: .top) {
            ForEach(model.severedTickets) { detachedUnit in
                FallingTicketView(ticket: detachedUnit)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(model.activeSequence.enumerated()), id: \.element) { index, _ in
                    let isActiveTerminalTicket = index == model.activeSequence.count - 1
                    
                    Ticket()
                        .offset(x: 0, y: isActiveTerminalTicket ? model.draggedOffset.height : 0)
                        .rotationEffect(
                            isActiveTerminalTicket ? .degrees(model.computeDynamicRotation(rawTranslation: model.activeDragTranslation)) : .zero,
                            anchor: isActiveTerminalTicket ? model.computeTearAnchor(rawTranslation: model.activeDragTranslation) : .top
                        )
                }
            }
            .offset(y: model.restOffset + model.activeDispenseShift)
            .opacity(model.ticketHeight > 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { gesture in model.processDragChanged(translation: gesture.translation) }
                .onEnded { gesture in model.processDragEnded(translation: gesture.translation) }
        )
        .onPreferenceChange(TicketHeightKey.self) { height in
            if model.ticketHeight == 0 { model.ticketHeight = height }
        }
    }
}

/// A specialized ephemeral container designed to process gravitational descent and momentum extrapolation.
struct FallingTicketView: View {
    let ticket: SeveredTicket
    
    @State private var fallDriftX: CGFloat = 0
    @State private var fallDropY: CGFloat = 0
    @State private var rotationShift: Double = 0.0
    
    var body: some View {
        Ticket()
            .offset(
                x: ticket.initialOffset.width + fallDriftX,
                y: ticket.initialOffset.height + fallDropY
            )
            .rotationEffect(.degrees(ticket.initialRotation + rotationShift), anchor: ticket.tearAnchor)
            .onAppear { applyDescentPhysics() }
    }
    
    private func applyDescentPhysics() {
        let absoluteIntensity = abs(ticket.initialRotation) / 45.0
        let dynamicDuration = 0.85 + (absoluteIntensity * 0.45)
        
        let directionalIntensity = ticket.initialRotation / 25.0
        let terminalRotationShift = directionalIntensity * 20.0
        let naturalAirDrift = sin(-ticket.initialRotation * .pi / 180.0) * 45.0
        
        withAnimation(.easeOut(duration: dynamicDuration)) {
            fallDriftX = naturalAirDrift + (ticket.dragTrajectory.width * 0.5)
            rotationShift = terminalRotationShift
        }
        
        withAnimation(.easeIn(duration: dynamicDuration)) {
            let safeDropDistance = min(ticket.dragTrajectory.height * 0.8 + 350, 700)
            fallDropY = max(1000, safeDropDistance)
        }
    }
}

struct TicketView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            TicketView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            
            TicketView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
