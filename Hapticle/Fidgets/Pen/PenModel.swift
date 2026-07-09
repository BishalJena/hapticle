//
//  PenModel.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//
//  State manager (ViewModel) for the Pen fidget's clicky button component.
//  Owns all state transitions, offset math, and dispatches haptic/audio
//  feedback through the shared Managers layer. Conforms to the MVVM-M
//  architecture described in the Hapticle TDD §1.1 — this class contains
//  zero UI code and can be tested independently of SwiftUI.
//

import Foundation
import Combine
import CoreGraphics
import AVFAudio

/// The three visual/physical resting states of the Pen's clicky button.
///
/// Unlike the four-state latch machine described in TDD §3.1 (Extended →
/// Latching → Retracted → Unlatching → Extended), this implementation
/// collapses the two "in-transit" states (Latching/Unlatching) into a single
/// `beingClicked` state, since both represent the same physical
/// appearance (fully pressed in) regardless of which direction the toggle
/// is about to resolve.
enum PenButtonState {
    /// Fully extended / at rest. Visual offset: 0pt.
    case unclicked
    /// Finger is currently down; button is fully pressed in. Visual offset: 50pt.
    /// This state is transient — it always resolves to either `.unclicked`
    /// or `.clicked` on touch-up, based on `preClickState`.
    case beingClicked
    /// Toggled "locked in" resting state (as if the pen is retracted).
    /// Visual offset: 30pt.
    case clicked
}

/// State manager and physics-to-haptics translator for the Pen fidget's
/// clickable button.
///
/// Responsibilities (per TDD §1.1 Model layer):
/// - Tracks the current `PenButtonState` and remembers which resting state
///   preceded the current press, so a touch-up can correctly toggle between
///   `.unclicked` and `.clicked`.
/// - Computes a physical offset for the View to animate (`currentOffset`).
/// - Estimates "how hard" a press/release was from gesture velocity and
///   press duration (since neither iPhone 14 Pro Max nor iPhone 17 support
///   3D Touch / `UITouch.force` — see note below), and maps that estimate
///   onto CoreHaptics' continuous `intensity`/`sharpness` parameters via
///   `HapticsManager`.
/// - Fires a paired system click through `SoundManager` alongside each
///   haptic event, matching the dual haptic+audio dispatch pattern
///   described in TDD §1.2/§4.1.
class PenModel: ObservableObject {
    
    /// Current resting/transient state of the button. Read by `PenView` to
    /// drive both the offset animation and the animation curve selection.
    @Published private(set) var buttonState: PenButtonState = .unclicked
    
    /// Snapshot of `buttonState` taken the moment a press begins, so
    /// `onTouchUp()` knows which resting state to toggle *away from* even
    /// though `buttonState` itself has since moved to `.beingClicked`.
    private var preClickState: PenButtonState = .unclicked
    
    /// Timestamp recorded on touch-down, used to compute how long the
    /// button was held before release (`onTouchUp`'s `heldFactor`).
    private var pressStartTime: Date?
    
    /// Visual Y-offset (in points) the View should apply to the button
    /// artwork for the current `buttonState`.
    ///
    /// - `unclicked` → 0pt (fully extended)
    /// - `beingClicked` → 50pt (fully pressed in)
    /// - `clicked` → 30pt (partially extended, "locked" resting position)
    var currentOffset: CGFloat {
        switch buttonState {
        case .unclicked: return 0
        case .beingClicked: return 50
        case .clicked: return 30
        }
    }
    
    /// Call when a touch begins on the button (`DragGesture.onChanged`,
    /// first call only is meaningful — guarded internally).
    ///
    /// Transitions `buttonState` to `.beingClicked` (unless already there),
    /// remembers the prior resting state in `preClickState`, and fires a
    /// press haptic + system click whose strength scales with the
    /// gesture's vertical velocity — a fast/hard tap produces a stronger,
    /// sharper click than a slow, deliberate press.
    ///
    /// - Parameter velocity: The current `DragGesture.Value.velocity` at
    ///   the moment of this call. Defaults to `.zero` for callers that
    ///   don't have gesture velocity available (e.g. programmatic presses).
    ///
    /// - Note: Neither the iPhone 14 Pro Max nor the iPhone 17 support
    ///   3D Touch (discontinued after the iPhone XS/XS Max in 2018), so
    ///   `UITouch.force` is not available as a pressure signal on this
    ///   project's target devices. Gesture velocity is used as the closest
    ///   available physical proxy for "how hard" a press was.
    func onTouchDown(velocity: CGSize = .zero) {
        pressStartTime = Date()
        
        if buttonState != .beingClicked {
            preClickState = buttonState
            buttonState = .beingClicked
            
            let speed = min(abs(velocity.height) / 400.0, 1.0)
            
            let intensity = 0.3 + (speed * 0.7)
            let sharpness = 0.2 + (speed * 0.8)
            
            HapticsManager.shared.playClick(intensity: Double(intensity), sharpness: Double(sharpness))
            
            // NEW: Fire the procedural synth (isRelease: false)
            SoundManager.shared.playPenClick(intensity: intensity, sharpness: sharpness, isRelease: false)
        }
    }
    
    func onTouchUp() {
        let pressDuration = pressStartTime.map { Date().timeIntervalSince($0) } ?? 0.2
        pressStartTime = nil
        
        buttonState = (preClickState == .clicked) ? .unclicked : .clicked
        
        let heldFactor = min(pressDuration / 0.5, 1.0)
        
        let intensity = 0.8 - (heldFactor * 0.5)
        let sharpness = 0.7 - (heldFactor * 0.4)
        
        HapticsManager.shared.playClick(intensity: Double(intensity), sharpness: Double(sharpness))
        
        // NEW: Fire the procedural synth (isRelease: true)
        SoundManager.shared.playPenClick(intensity: intensity, sharpness: sharpness, isRelease: true)
    }
}
