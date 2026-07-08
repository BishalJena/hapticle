//
//  TicketView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI

// MARK: - Preferences & Extensions

struct SlotPositionKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct TicketHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func innerShadowShift<Mask: View>(mask maskView: Mask, color: Color, blur: CGFloat = 8, x: CGFloat = 0, y: CGFloat = 0) -> some View {
        self.overlay(
            Rectangle()
                .fill(color)
                .mask(maskView)
                .blur(radius: blur)
                .offset(x: x, y: y)
                .mask(maskView)
        )
    }
}

// MARK: - Main View Chassis

struct TicketView: View {
    @StateObject private var model = TicketModel()
    
    private let slotRevealPadding: CGFloat = 90
    private let ticketsVisibleAtRest: CGFloat = 1.5
    
    var body: some View {
        ZStack {
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            // LAYER 1: Base Machine Chassis
            VStack {
                Image("Machine")
                    .renderingMode(.template)
                    .foregroundStyle(Color.fidgetPrimary)
                    .shadow(color: Color.highlight, radius: 6, x: -6, y: -6)
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
            
            // LAYER 2: The Autonomous Sequence
            GeometryReader { geometry in
                AutoReplenishingTicketRoll(model: model)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .mask(
                        VStack(spacing: 0) {
                            Color.clear.frame(height: max(0, model.slotOriginY + slotRevealPadding))
                            Color.white
                        }
                        .ignoresSafeArea()
                    )
            }
            .ignoresSafeArea()
            
            // LAYER 3: Foreground Slot Mechanism Overlay
            VStack {
                Image("Machine")
                    .opacity(0)
                    .overlay {
                        VStack(spacing: -14.5){
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
        .coordinateSpace(name: "GlobalMachineSpace")
        .onPreferenceChange(SlotPositionKey.self) { yPosition in
            model.slotOriginY = yPosition
        }
    }
    
    // MARK: Subcomponents
    
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
            .shadow(color: Color.highlight.opacity(0.25), radius: 6, x: -3, y: -3)
            .shadow(color: .shadow.opacity(0.25), radius: 6, x: 3, y: 3)
    }
    
    private var hole: some View {
        Image("MachineHole")
            .renderingMode(.template)
            .foregroundStyle(Color.fidgetPrimary)
            .innerShadowShift(mask: Image("MachineHole"), color: Color.shadow.opacity(0.25), blur: 3, x: 0, y: -3)
            .innerShadowShift(mask: Image("MachineHole"), color: Color.highlight.opacity(0.25), blur: 5, x: 0, y: 7)
    }
}

// MARK: - Kinetic Components

struct AutoReplenishingTicketRoll: View {
    @ObservedObject var model: TicketModel
    
    private var restOffset: CGFloat {
        (model.slotOriginY + 90) + (1.5 - CGFloat(model.activeSequence.count)) * model.ticketHeight
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            ForEach(model.severedTickets) { detachedUnit in
                FallingTicketView(ticketData: detachedUnit)
            }
            
            VStack(spacing: 0) {
                ForEach(Array(model.activeSequence.enumerated()), id: \.element) { index, ticketID in
                    let isActiveTerminalTicket = index == model.activeSequence.count - 1
                    
                    Image("Ticket")
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: TicketHeightKey.self, value: geo.size.height)
                            }
                        )
                        .offset(x: 0, y: isActiveTerminalTicket ? model.draggedOffset.height : 0)
                        .rotationEffect(
                            isActiveTerminalTicket ? .degrees(model.computeDynamicRotation(for: model.activeDragTranslation)) : .zero,
                            anchor: isActiveTerminalTicket ? model.computeTearAnchor(for: model.activeDragTranslation) : .top
                        )
                }
            }
            .offset(y: restOffset + model.activeDispenseShift)
            .opacity(model.ticketHeight > 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    model.processDragGesture(translation: gesture.translation)
                }
                .onEnded { gesture in
                    model.finalizeDragGesture(translation: gesture.translation)
                }
        )
        .onPreferenceChange(TicketHeightKey.self) { height in
            if model.ticketHeight == 0 {
                model.ticketHeight = height
            }
        }
    }
}

struct FallingTicketView: View {
    let ticketData: SeveredTicket
    
    @State private var fallDriftX: CGFloat = 0
    @State private var fallDropY: CGFloat = 0
    @State private var rotationShift: Double = 0.0
    
    var body: some View {
        Image("Ticket")
            .offset(
                x: ticketData.initialOffset.width + fallDriftX,
                y: ticketData.initialOffset.height + fallDropY
            )
            .rotationEffect(.degrees(ticketData.initialRotation + rotationShift), anchor: ticketData.tearAnchor)
            .onAppear {
                let absoluteIntensity = abs(ticketData.initialRotation) / 45.0
                let baseDuration = 0.85
                let dynamicDuration = baseDuration + (absoluteIntensity * 0.45)
                
                let momentumMultiplier: CGFloat = 0.8
                let directionalIntensity = ticketData.initialRotation / 25.0
                let terminalRotationShift = directionalIntensity * 20.0
                
                let naturalAirDrift = sin(-ticketData.initialRotation * .pi / 180.0) * 45.0
                
                withAnimation(.easeOut(duration: dynamicDuration)) {
                    fallDriftX = naturalAirDrift + (ticketData.dragTrajectory.width * 0.5)
                    rotationShift = terminalRotationShift
                }
                
                withAnimation(.easeIn(duration: dynamicDuration)) {
                    let safeDropDistance = min(ticketData.dragTrajectory.height * momentumMultiplier + 350, 700)
                    fallDropY = max(1000, safeDropDistance)
                }
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
