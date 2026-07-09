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
    private let autoTearRotationThreshold: Double = 25.0
    
    // MARK: - Configuration Constants (Audio & Physics)
    private let tearRateFloor: Float = 3.0    // slow drag: sparse, separated snaps
    private let tearRateCeiling: Float = 40.0 // fast drag: dense "BRRRT" texture
    private let stillnessEpsilon: CGFloat = 0.3 // pts per frame below which we count as "not moving"
    
    // MARK: - Continuous Physics & Haptic Tracking
    
    private var displayLink: CADisplayLink?
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var lastTearDistance: CGFloat = 0.0
    private var smoothedVelocity: Double = 0.0
    private var hapticPhase: Double = 0.0
    
    private var tearGeneration: Int = 0
    
    // NEW: Intent Lock prevents the anchor point from fluttering mid-drag
    private var lockedTearState: TearKinematics? = nil
    private var activeTearState: TearKinematics = .straight
    
    var revealBoundaryY: CGFloat {
        slotOriginY + slotRevealPadding
    }
    
    var restOffset: CGFloat {
        revealBoundaryY + (ticketsVisibleAtRest - CGFloat(activeSequence.count)) * ticketHeight
    }
    
    // MARK: - Kinematic Logic
    
    private func determineKinematicState(translation: CGSize) -> TearKinematics {
        let dragAngle = atan2(translation.width, translation.height) * 180 / .pi
        if dragAngle > angularDeadzone {
            return .rightHinge
        } else if dragAngle < -angularDeadzone {
            return .leftHinge
        } else {
            return .straight
        }
    }
    
    func computeTearAnchor() -> UnitPoint {
        switch activeTearState {
        case .straight: return .top
        case .leftHinge: return leftPerforationAnchor
        case .rightHinge: return rightPerforationAnchor
        }
    }
    
    func computeDynamicRotation(rawTranslation: CGSize) -> Double {
        guard activeTearState != .straight else { return 0.0 }
        
        let maximumTearAngle: Double = 25.0
        let rotationalFriction: Double = 0.15
        
        // Map lateral X movement directly to the rotation angle
        let calculatedRotation = min(Double(abs(rawTranslation.width)) * rotationalFriction, maximumTearAngle)
        return activeTearState == .leftHinge ? calculatedRotation : -calculatedRotation
    }
    
    // MARK: - CADisplayLink Physics Loop
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastFrameTimestamp = CACurrentMediaTime()
        lastTearDistance = 0.0
        smoothedVelocity = 0.0
        hapticPhase = 0.0
        tearGeneration += 1   // NEW: a fresh drag invalidates any pending stop-timers from before
        
        let link = CADisplayLink(target: self, selector: #selector(stepPhysics))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        lastFrameTimestamp = 0
        SoundManager.shared.stopTearing()
    }
    
    @objc private func stepPhysics(link: CADisplayLink) {
        let currentTimestamp = link.timestamp
        var dt = currentTimestamp - lastFrameTimestamp
        if dt <= 0 || dt > 0.1 { dt = 1.0 / 60.0 }
        lastFrameTimestamp = currentTimestamp
        
        let currentDistance = activeTearState == .straight ? abs(activeDragTranslation.height) : abs(activeDragTranslation.width)
        
        let deltaDistance = Double(currentDistance - lastTearDistance)
        let instantaneousVelocity = deltaDistance / dt
        lastTearDistance = currentDistance
        
        let smoothingFactor = 0.3
        smoothedVelocity = (smoothedVelocity * (1.0 - smoothingFactor)) + (instantaneousVelocity * smoothingFactor)
        
        // --- SYNCHRONIZED AUDIO & HAPTICS ENGINE ---
        let activeDelta = CGFloat(abs(deltaDistance))
        
        if activeDelta < stillnessEpsilon || hasSeveredCurrentDrag {
            SoundManager.shared.stopTearing()
            hapticPhase = 0.0
        } else {
            let tickInterval: CGFloat = 20.0
            let perforationsPerSecond = Float((activeDelta / CGFloat(dt)) / tickInterval)
            let speedNorm = min(perforationsPerSecond / tearRateCeiling, 1.0)
            
            let volume = speedNorm * 0.85
            let effectiveRate = tearRateFloor + speedNorm * (tearRateCeiling - tearRateFloor)
            
            SoundManager.shared.startTearing(rate: effectiveRate, volume: volume)
            hapticPhase += Double(effectiveRate) * dt
            
            while hapticPhase >= 1.0 {
                hapticPhase -= 1.0
                let dynamicSharpness = 1.0 + (Double(speedNorm) * 0.4)
                HapticsManager.shared.playClick(intensity: 1.5, sharpness: dynamicSharpness)
            }
        }
    }
    
    // MARK: - Gesture Handling
    
    func processDragChanged(translation: CGSize) {
        guard !hasSeveredCurrentDrag else { return }
        
        if displayLink == nil { startDisplayLink() }
        
        let rawY = translation.height
        guard rawY > 0 else { return }
        
        // --- THE INTENT LOCK ---
        // Wait until the gesture exceeds 10 points to commit to a directional tear.
        // Once locked, it cannot flutter mid-drag.
        if lockedTearState == nil {
            if hypot(translation.width, translation.height) > 10.0 {
                lockedTearState = determineKinematicState(translation: translation)
            }
        }
        activeTearState = lockedTearState ?? .straight
        
        let tensionFrictionY: CGFloat = 0.01
        let resistedY = rawY * tensionFrictionY
        let hardLimitY = min(resistedY, tearThreshold)
        
        // If we are rotating, severely restrict the downward translation to prevent wonky diagonal offsets.
        // If we are pulling straight, allow the full elastic Y stretch.
        draggedOffset = CGSize(width: 0, height: activeTearState == .straight ? hardLimitY : hardLimitY * 0.2)
        activeDragTranslation = translation
        
        let currentRotation = abs(computeDynamicRotation(rawTranslation: translation))
        
        if hardLimitY >= tearThreshold || currentRotation >= autoTearRotationThreshold {
            hasSeveredCurrentDrag = true
            executeSeveranceProtocol(dampenedY: hardLimitY, rawTranslation: translation, isStraightTear: activeTearState == .straight)
        }
    }
    
    func processDragEnded(translation: CGSize) {
        lockedTearState = nil // Release the intent lock for the next ticket
        hapticPhase = 0.0
        
        stopDisplayLink()
        
        if hasSeveredCurrentDrag {
            hasSeveredCurrentDrag = false
            return
        }
        
        if translation.height > 10 {
            executeSeveranceProtocol(dampenedY: draggedOffset.height, rawTranslation: translation, isStraightTear: false)
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                draggedOffset = .zero
                activeDragTranslation = .zero
            }
        }
    }
    
    func executeSeveranceProtocol(dampenedY: CGFloat, rawTranslation: CGSize, isStraightTear: Bool = false) {
        stopDisplayLink()
        tearGeneration += 1                 // NEW: this severance's own generation
        let myGeneration = tearGeneration   // NEW: snapshot for the closure below
        
        if isStraightTear {
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.03) {
                    let decay = Double(i) * 0.2
                    HapticsManager.shared.playClick(intensity: 3.0 - decay, sharpness: 1.0)
                }
            }
            SoundManager.shared.startTearing(rate: 60.0, volume: 1.0)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                // NEW: only stop/snap if nothing newer has grabbed the tearing
                // audio in the meantime. If tearGeneration moved on, a later
                // rip already owns the sound — leave it alone.
                guard self.tearGeneration == myGeneration else { return }
                SoundManager.shared.stopTearing()
                SoundManager.shared.playTearSnap()
            }
        } else {
            HapticsManager.shared.playClick(intensity: 2.5, sharpness: 0.8)
            SoundManager.shared.playTearSnap()
        }
        
        // --- The rest of your detachment physics remain completely untouched ---
        let terminalTicketBaseY = restOffset + CGFloat(activeSequence.count - 1) * ticketHeight
        let exactDetachmentY = terminalTicketBaseY + dampenedY
        
        let finalSeveranceAnchor = computeTearAnchor()
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
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation(.easeOut(duration: 0.35)) {
                self.activeDispenseShift = 0
            }
        }
    }
}
