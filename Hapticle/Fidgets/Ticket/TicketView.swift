//
//  TicketView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI

/// Extracts the vertical boundary coordinate of the machine's aperture.
struct SlotPositionKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Dynamically acquires the exact rendered vertical dimension of a single ticket asset.
struct TicketHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension View {
    func innerShadowShift<Mask: View>(
        mask maskView: Mask,
        color: Color,
        blur: CGFloat = 8,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> some View {
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

struct TicketView: View {
    @State private var slotOriginY: CGFloat = 0

    /// Extra vertical distance below the measured slot/overhang position
    /// where the roll actually becomes visible. Exists because the
    /// overhang's own measured frame doesn't sit exactly at the visual
    /// aperture edge — there's a bit of machine artwork/lip below it
    /// before the ticket should actually show through.
    ///
    /// IMPORTANT: this is the single source of truth for "where the
    /// roll becomes visible." Both the mask below AND
    /// `AutoReplenishingTicketRoll`'s rest-position math read from this
    /// same value — previously the mask used
    /// `slotOriginY + slotRevealPadding` while the roll's offset assumed
    /// the reveal boundary was just `slotOriginY`, a ~90pt mismatch that
    /// silently ate into the "visible tickets" budget (showing ~0.5
    /// tickets instead of the intended 1.5). Passing the same constant
    /// into both places prevents that class of bug from recurring.
    private let slotRevealPadding: CGFloat = 90

    /// How many ticket-heights should remain visible below the slot at
    /// rest. 1.5 means: one fully visible ticket, plus half of the one
    /// still chained above it, so the roll always reads as a continuous
    /// attached strip rather than a single isolated ticket.
    private let ticketsVisibleAtRest: CGFloat = 1.5

    var body: some View {
        ZStack {
            Color.fidgetPrimary
                .ignoresSafeArea()

            // LAYER 1: The Foundational Base Machine Chassis
            VStack {
                Image("Machine")
                    .renderingMode(.template)
                    .foregroundStyle(Color.fidgetPrimary)
                    .shadow(color: Color.highlight, radius: 6, x: -6, y: -6)
                    .shadow(color: .shadow, radius: 6, x: 6, y: 6)
                    .overlay {
                        VStack {
                            HStack {
                                bolt
                                Spacer()
                                bolt
                            }
                            Spacer()
                            HStack {
                                bolt
                                Spacer()
                                bolt
                            }
                        }
                        .padding(20)
                    }
                    .overlay {
                        VStack {
                            Spacer()
                            hole
                                .padding(.top, 11)
                            Spacer()
                        }
                    }
                    .padding(.top, 50)

                Spacer()
            }

            // LAYER 2: The Autonomous, Auto-Replenishing Ticket Sequence
            GeometryReader { geometry in
                AutoReplenishingTicketRoll(
                    slotOriginY: slotOriginY,
                    revealPadding: slotRevealPadding,
                    ticketsVisibleAtRest: ticketsVisibleAtRest
                )
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .mask(
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(height: max(0, slotOriginY + slotRevealPadding))

                            Color.white
                        }
                        .ignoresSafeArea()
                    )
            }
            .ignoresSafeArea()

            // LAYER 3: The Foreground Slot Mechanism Overlay
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
            self.slotOriginY = yPosition
        }
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
            .shadow(color: Color.highlight.opacity(0.25), radius: 6, x: -3, y: -3)
            .shadow(color: .shadow.opacity(0.25), radius: 6, x: 3, y: 3)
    }

    private var hole: some View {
        Image("MachineHole")
            .renderingMode(.template)
            .foregroundStyle(Color.fidgetPrimary)
            .innerShadowShift(
                mask: Image("MachineHole"),
                color: Color.shadow.opacity(0.25),
                blur: 3,
                x: 0,
                y: -3
            )
            .innerShadowShift(
                mask: Image("MachineHole"),
                color: Color.highlight.opacity(0.25),
                blur: 5,
                x: 0,
                y: 7
            )
    }
}

/// Orchestrates the kinetic logic required to simulate an infinite physical dispenser while retaining strict dimensional boundaries.
struct AutoReplenishingTicketRoll: View {
    let slotOriginY: CGFloat
    /// Same reveal-boundary constant the parent view's mask uses — see
    /// the comment on `TicketView.slotRevealPadding` for why this must
    /// match exactly rather than being independently guessed here.
    let revealPadding: CGFloat
    /// How many ticket-heights should remain visible below the reveal
    /// boundary at rest (e.g. 1.5 = one full ticket + half of the next).
    let ticketsVisibleAtRest: CGFloat

    @State private var ticketHeight: CGFloat = 0
    // Sustaining exactly four components ensures sufficient overflow to hide the upper manipulation beyond the aperture.
    @State private var activeSequence: [UUID] = (0..<3).map { _ in UUID() }

    @State private var activeDispenseShift: CGFloat = 0
    @State private var draggedOffset: CGSize = .zero
    @State private var severedTickets: [SeveredTicket] = []

    struct SeveredTicket: Identifiable {
        let id = UUID()
        let initialOffset: CGSize
    }

    /// The vertical position at which content becomes visible below the
    /// mask — i.e. where the machine's aperture actually reveals the
    /// roll. Single source of truth for the offset math below, so the
    /// roll and the parent's mask can never disagree about where "the
    /// slot" actually is.
    private var revealBoundaryY: CGFloat {
        slotOriginY + revealPadding
    }

    /// Resting vertical offset for the whole ticket stack: pin the stack
    /// to the top of the screen, then push it down so that exactly
    /// `ticketsVisibleAtRest` ticket-heights remain below the reveal
    /// boundary. With `activeSequence.count` total segments in the
    /// stack, the stack's bottom edge sits at `offset + count * ticketHeight`;
    /// solving for the offset that leaves `ticketsVisibleAtRest * ticketHeight`
    /// of that below `revealBoundaryY` gives:
    private var restOffset: CGFloat {
        revealBoundaryY + (ticketsVisibleAtRest - CGFloat(activeSequence.count)) * ticketHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Isolates the physics of any detached elements, allowing them to fall independently from the structured roll.
            ForEach(severedTickets) { detachedUnit in
                FallingTicketView(ticketHeight: ticketHeight, initialOffset: detachedUnit.initialOffset)
            }

            VStack(spacing: 0) {
                ForEach(Array(activeSequence.enumerated()), id: \.element) { index, ticketID in
                    Image("Ticket")
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: TicketHeightKey.self, value: geo.size.height)
                            }
                        )
                        // Isolating the tactile gesture strictly to the terminal object in the array.
                        .offset(index == activeSequence.count - 1 ? draggedOffset : .zero)
                        .gesture(
                            index == activeSequence.count - 1 ?
                            DragGesture()
                                .onChanged { gesture in
                                    // Constraining manipulation to predominantly downward vectors prevents unnatural horizontal sliding.
                                    if gesture.translation.height > 0 {
                                        draggedOffset = gesture.translation
                                    }
                                }
                                .onEnded { gesture in
                                    // Evaluating if the physical displacement exceeds the requisite threshold to trigger detachment.
                                    if gesture.translation.height > 80 {
                                        executeSeveranceProtocol(finalTranslation: gesture.translation)
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                            draggedOffset = .zero
                                        }
                                    }
                                }
                            : nil
                        )
                }
            }
            // Pinned to the top of the screen, then pushed down by
            // `restOffset` so exactly `ticketsVisibleAtRest` ticket-heights
            // sit below the (shared) reveal boundary.
            .offset(y: restOffset + activeDispenseShift)
            // Suppressing visibility entirely until the spatial dimensions calculate perfectly prevents early initialization flickers.
            .opacity(ticketHeight > 0 ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(TicketHeightKey.self) { height in
            if ticketHeight == 0 {
                self.ticketHeight = height
            }
        }
    }

    private func executeSeveranceProtocol(finalTranslation: CGSize) {
        // The falling ticket starts wherever it visually was at the
        // moment of detachment — approximated here as the reveal
        // boundary itself, since that's where the torn-free ticket
        // reads as separating from the still-visible roll above it.
        let absoluteSeveranceY = revealBoundaryY
        let fallingUnit = SeveredTicket(initialOffset: CGSize(width: finalTranslation.width, height: absoluteSeveranceY + finalTranslation.height))

        severedTickets.append(fallingUnit)

        // Cyclically mutating the array: expelling the bottom layer and concurrently infusing a replacement at the structural origin.
        activeSequence.removeLast()
        activeSequence.insert(UUID(), at: 0)

        // Counteracting the inherent downward shift caused by prepending a new element, achieving momentary visual stasis.
        activeDispenseShift = -ticketHeight
        draggedOffset = .zero

        // Dissipating the counter-shift mathematically forces the framework to render the authentic downward rolling extrusion.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.45)) {
                self.activeDispenseShift = 0
            }
        }
    }
    
}

/// A specialized ephemeral container designed to process gravitational descent and gradual visual dissipation post-severance.
struct FallingTicketView: View {
    let ticketHeight: CGFloat
    let initialOffset: CGSize

    @State private var kineticFallOffset: CGSize = .zero
    @State private var dissipationOpacity: Double = 1.0

    var body: some View {
        Image("Ticket")
            .offset(x: initialOffset.width + kineticFallOffset.width, y: initialOffset.height + kineticFallOffset.height)
            .opacity(dissipationOpacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.6)) {
                    kineticFallOffset = CGSize(width: initialOffset.width * 1.2, height: 500)
                    dissipationOpacity = 0
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
