
//
//  TicketModel.swift
//  Hapticle
//

import SwiftUI
import Combine

/// Defines the directional kinematics during a user's tearing interaction.
enum TearKinematics {
    case straight, leftHinge, rightHinge
}

/// Represents a detached ticket entity undergoing gravitational displacement.
struct SeveredTicket: Identifiable {
    let id = UUID()
    let initialOffset: CGSize
    let dragTrajectory: CGSize
    let initialRotation: Double
    let tearAnchor: UnitPoint
}

final class TicketModel: ObservableObject {
    // MARK: - State Properties
    
    @Published var slotOriginY: CGFloat = 0
    @Published var ticketHeight: CGFloat = 0
    @Published var activeSequence: [UUID] = (0..<3).map { _ in UUID() }
    
    @Published var activeDispenseShift: CGFloat = 0
    @Published var draggedOffset: CGSize = .zero
    @Published var activeDragTranslation: CGSize = .zero
    
    @Published var severedTickets: [SeveredTicket] = []
    @Published var hasSeveredCurrentDrag: Bool = false
    
    // MARK: - Configuration Constants
    
    let slotRevealPadding: CGFloat = 90
    let ticketsVisibleAtRest: CGFloat = 1.5
    private let leftPerforationAnchor = UnitPoint(x: 0.08, y: 0)
    private let rightPerforationAnchor = UnitPoint(x: 0.92, y: 0)
    
    private let tearThreshold: CGFloat = 0.5
    private let angularDeadzone: Double = 15.0
    private let autoTearRotationThreshold: Double = 20.0
    
    // NEW: Differential tracking variables for sustained scrubbing haptics
    private var previousDragTranslation: CGSize = .zero
    private var hapticOdometer: CGFloat = 0
    
    var revealBoundaryY: CGFloat {
        slotOriginY + slotRevealPadding
    }
    
    var restOffset: CGFloat {
        revealBoundaryY + (ticketsVisibleAtRest - CGFloat(activeSequence.count)) * ticketHeight
    }
    
    // MARK: - Kinematic Logic
    
    func determineKinematicState(translation: CGSize) -> TearKinematics {
        let dragAngle = atan2(translation.width, translation.height) * 180 / .pi
        if dragAngle > angularDeadzone {
            return .rightHinge
        } else if dragAngle < -angularDeadzone {
            return .leftHinge
        } else {
            return .straight
        }
    }
    
    func computeTearAnchor(rawTranslation: CGSize) -> UnitPoint {
        switch determineKinematicState(translation: rawTranslation) {
        case .straight: return .top
        case .leftHinge: return leftPerforationAnchor
        case .rightHinge: return rightPerforationAnchor
        }
    }
    
    func computeDynamicRotation(rawTranslation: CGSize) -> Double {
        let state = determineKinematicState(translation: rawTranslation)
        guard state != .straight else { return 0.0 }
        
        let maximumTearAngle: Double = 25.0
        let rotationalFriction: Double = 0.1
        let calculatedRotation = min(Double(abs(rawTranslation.width)) * rotationalFriction, maximumTearAngle)
        
        return state == .leftHinge ? calculatedRotation : -calculatedRotation
    }
    
    // MARK: - Gesture Handling
    
    func processDragChanged(translation: CGSize) {
        guard !hasSeveredCurrentDrag else { return }
        
        let rawX = translation.width
        let rawY = translation.height
        guard rawY > 0 else { return }
        
        let tensionFrictionY: CGFloat = 0.01
        let resistedY = rawY * tensionFrictionY
        let hardLimitY = min(resistedY, tearThreshold)
        
        draggedOffset = CGSize(width: 0, height: hardLimitY)
        activeDragTranslation = translation
        
        let currentRotation = abs(computeDynamicRotation(rawTranslation: translation))
        let tearState = determineKinematicState(translation: translation)
        
        // --- CONTINUOUS ODOMETER LOGIC ---
        let deltaX = abs(translation.width - previousDragTranslation.width)
        let deltaY = abs(translation.height - previousDragTranslation.height)
        let activeDelta = tearState == .straight ? deltaY : deltaX
        
        hapticOdometer += activeDelta
        previousDragTranslation = translation
        
        let tickInterval: CGFloat = tearState == .straight ? 35.0 : 20.0
        
        if hapticOdometer >= tickInterval {
            hapticOdometer -= tickInterval
            
            // Only play "Zipper" feedback for diagonal (hinge) tears.
            // Straight down drags are silent until the final snap.
            if tearState != .straight {
                HapticsManager.shared.playClick(intensity: 2.5, sharpness: 1.0)
                SoundManager.shared.playSystemClick()
            }
        }
        // --------------------------------------------------------
        
        // AUTO-RIP LOGIC:
        // This threshold check triggers the severance automatically
        // the moment you hit the limit, no lift required.
        if hardLimitY >= tearThreshold || currentRotation >= autoTearRotationThreshold {
            hasSeveredCurrentDrag = true
            executeSeveranceProtocol(dampenedY: hardLimitY, rawTranslation: translation, isStraightTear: tearState == .straight)
        }
    }
    
    func processDragEnded(translation: CGSize) {
        previousDragTranslation = .zero
        hapticOdometer = 0
        
        if hasSeveredCurrentDrag {
            hasSeveredCurrentDrag = false
            return
        }
        
        // If they lift finger before auto-rip threshold, treat as manual tear
        if translation.height > 10 {
            executeSeveranceProtocol(dampenedY: draggedOffset.height, rawTranslation: translation, isStraightTear: false)
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                draggedOffset = .zero
                activeDragTranslation = .zero
            }
        }
    }
    
    private func executeSeveranceProtocol(dampenedY: CGFloat, rawTranslation: CGSize, isStraightTear: Bool = false) {
        if isStraightTear {
            // --- EXPLOSIVE BURST LOGIC ---
            // Chain 3 haptics tightly to create a "crackle" effect
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.03) {
                    // Slightly decaying intensity gives the burst a "natural" energy falloff
                    let decay = Double(i) * 0.2
                    HapticsManager.shared.playClick(intensity: 3.0 - decay, sharpness: 1.0)
                }
            }
            // Anchor the 3 haptics with one clean, physical sound pop
            SoundManager.shared.playSystemClick()
            // ----------------------------
        } else {
            // Standard snappy hinge tear (Single pop)
            HapticsManager.shared.playClick(intensity: 2.0, sharpness: 0.5)
            SoundManager.shared.playSystemClick()
        }
        
        let terminalTicketBaseY = restOffset + CGFloat(activeSequence.count - 1) * ticketHeight
        let exactDetachmentY = terminalTicketBaseY + dampenedY
        
        let finalSeveranceAnchor = computeTearAnchor(rawTranslation: rawTranslation)
        let finalSeveranceAngle = computeDynamicRotation(rawTranslation: rawTranslation)
        
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
        
        severedTickets.append(fallingUnit)
        activeSequence.removeLast()
        activeSequence.insert(UUID(), at: 0)
        
        activeDispenseShift = -ticketHeight
        draggedOffset = .zero
        activeDragTranslation = .zero
        
        // Simultaneously reset the differential trackers alongside standard kinematic variables
        previousDragTranslation = .zero
        hapticOdometer = 0
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.35)) {
                self.activeDispenseShift = 0
            }
        }
    }
}
