//
//  TicketModel.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI
import Combine

/// Defines the immutable structural pivot points for the ticket asset.
enum TicketAnchors {
    static let leftPerforation = UnitPoint(x: 0.08, y: 0)
    static let rightPerforation = UnitPoint(x: 0.92, y: 0)
}

/// Represents the three absolute kinematic states a ticket can occupy during a drag event.
enum TearKinematics {
    case straight
    case leftHinge
    case rightHinge
}

/// A physical payload representing a ticket that has breached the structural failure threshold.
struct SeveredTicket: Identifiable {
    let id = UUID()
    let initialOffset: CGSize
    let dragTrajectory: CGSize
    let initialRotation: Double
    let tearAnchor: UnitPoint
}

/// The centralized physics engine and state manager for the autonomous ticket dispenser.
class TicketModel: ObservableObject {
    @Published var ticketHeight: CGFloat = 0
    @Published var activeSequence: [UUID] = (0..<3).map { _ in UUID() }
    
    @Published var activeDispenseShift: CGFloat = 0
    @Published var draggedOffset: CGSize = .zero
    @Published var activeDragTranslation: CGSize = .zero
    
    @Published var severedTickets: [SeveredTicket] = []
    @Published var hasSeveredCurrentDrag: Bool = false
    
    // MARK: - Gesture Handling Lifecycle
    
    /// Processes continuous raw drag data, applies friction, and evaluates structural failure.
    func processDragGesture(translation: CGSize) {
        guard !hasSeveredCurrentDrag else { return }
        
        let rawX = translation.width
        let rawY = translation.height
        
        if rawY > 0 {
            let dragAngle = atan2(rawX, rawY) * 180 / .pi
            let isSideways = abs(dragAngle) > 15.0
            
            // DIFFERENTIAL FRICTION: Requires significant physical distance to achieve visual movement.
            let tensionFrictionY: CGFloat = isSideways ? 0.01 : 0.01
            let resistedY = rawY * tensionFrictionY
            
            let tearThreshold: CGFloat = 25.0
            let hardLimitY = min(resistedY, tearThreshold)
            
            // Isolate visual rendering (Y only) from the mathematical rotation fuel (Raw X/Y).
            self.draggedOffset = CGSize(width: 0, height: hardLimitY)
            self.activeDragTranslation = translation
            
            // Threshold Breached: Trigger Severance
            if hardLimitY >= tearThreshold {
                self.hasSeveredCurrentDrag = true
                self.executeSeveranceProtocol(dampenedY: hardLimitY, rawTranslation: translation)
            }
        }
    }
    
    /// Determines the final state of the sequence when the user lifts their finger.
    func finalizeDragGesture(translation: CGSize) {
        if hasSeveredCurrentDrag {
            hasSeveredCurrentDrag = false
            return
        }
        
        // If the drag was substantial but didn't tear, execute a delayed tear. Otherwise, snap back.
        if translation.height > 10 {
            executeSeveranceProtocol(dampenedY: draggedOffset.height, rawTranslation: translation)
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                self.draggedOffset = .zero
                self.activeDragTranslation = .zero
            }
        }
    }
    
    // MARK: - Angular Trajectory Evaluators
    
    /// Derives the spatial pivot state based on the angle of the drag vector.
    func determineKinematicState(for translation: CGSize) -> TearKinematics {
        let dragAngle = atan2(translation.width, translation.height) * 180 / .pi
        let angularDeadzone: Double = 15.0
        
        if dragAngle > angularDeadzone {
            return .rightHinge
        } else if dragAngle < -angularDeadzone {
            return .leftHinge
        } else {
            return .straight
        }
    }
    
    /// Translates the kinematic state into a hardcoded SwiftUI anchor point.
    func computeTearAnchor(for rawTranslation: CGSize) -> UnitPoint {
        switch determineKinematicState(for: rawTranslation) {
        case .straight: return .top
        case .leftHinge: return TicketAnchors.leftPerforation
        case .rightHinge: return TicketAnchors.rightPerforation
        }
    }
    
    /// Derives the visual rotation angle utilizing the raw, unsuppressed horizontal drag.
    func computeDynamicRotation(for rawTranslation: CGSize) -> Double {
        let state = determineKinematicState(for: rawTranslation)
        if state == .straight { return 0.0 }
        
        let maximumTearAngle: Double = 25.0
        let rotationalFriction: Double = 0.05
        
        let calculatedRotation = min(Double(abs(rawTranslation.width)) * rotationalFriction, maximumTearAngle)
        return state == .leftHinge ? calculatedRotation : -calculatedRotation
    }
    
    // MARK: - Severance Protocol
    
    /// Packages the terminal state of the torn ticket and hands it off to the aerial physics container.
    private func executeSeveranceProtocol(dampenedY: CGFloat, rawTranslation: CGSize) {
        let terminalTicketBaseY = (slotOriginY + 90) + (1.5 - CGFloat(activeSequence.count)) * ticketHeight
        let exactDetachmentY = terminalTicketBaseY + dampenedY
        
        let finalSeveranceAnchor = computeTearAnchor(for: rawTranslation)
        let finalSeveranceAngle = computeDynamicRotation(for: rawTranslation)
        
        // Translating residual drag energy into downward momentum.
        let safeKineticTrajectory = CGSize(
            width: rawTranslation.width * 0.4,
            height: dampenedY * 2.0
        )
        
        let fallingUnit = SeveredTicket(
            initialOffset: CGSize(width: 0, height: exactDetachmentY),
            dragTrajectory: safeKineticTrajectory,
            initialRotation: finalSeveranceAngle,
            tearAnchor: finalSeveranceAnchor
        )
        
        self.severedTickets.append(fallingUnit)
        
        // Cycle the IDs to replenish the visual roll
        self.activeSequence.removeLast()
        self.activeSequence.insert(UUID(), at: 0)
        
        self.activeDispenseShift = -ticketHeight
        self.draggedOffset = .zero
        self.activeDragTranslation = .zero
        
        // Delayed replenishment to emphasize the visual tear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.35)) {
                self.activeDispenseShift = 0
            }
        }
    }
    
    // MARK: - Utility
    
    var slotOriginY: CGFloat = 0
}
