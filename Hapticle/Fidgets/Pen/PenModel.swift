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

            // Normalize vertical drag velocity (px/s) to a 0...1 "speed" factor.
            // Divisor of 400 was tuned empirically so that typical finger-tap
            // velocities span a meaningful portion of the 0...1 range, rather
            // than clustering near 0 (which was the case with a 1000 divisor).
            let speed = min(abs(velocity.height) / 400.0, 1.0)

            // intensity: overall haptic strength. Ranges 0.3 (soft tap) to 1.0 (slammed).
            let intensity = 0.3 + (speed * 0.7)
            // sharpness: haptic "timbre" — dull/soft vs. crisp/metallic. Ranges 0.2 to 1.0.
            let sharpness = 0.2 + (speed * 0.8)

            HapticsManager.shared.playClick(intensity: Double(intensity), sharpness: Double(sharpness))
            SoundManager.shared.playSystemClick()
        }
    }

    /// Call when the touch ends (`DragGesture.onEnded`).
    ///
    /// Resolves `buttonState` by toggling away from whatever state preceded
    /// the press (`preClickState`): if the button was `.clicked` before this
    /// press, it resolves to `.unclicked`, and vice versa. Fires a release
    /// haptic + system click whose strength scales inversely with how long
    /// the button was held — a quick tap-and-release snaps crisply, while a
    /// long hold-then-release lands softer/duller.
    func onTouchUp() {
        let pressDuration = pressStartTime.map { Date().timeIntervalSince($0) } ?? 0.2
        pressStartTime = nil

        buttonState = (preClickState == .clicked) ? .unclicked : .clicked

        // heldFactor: 0 = instant release, 1 = held 0.5s or longer.
        let heldFactor = min(pressDuration / 0.5, 1.0)
        // Release clicks are intentionally softer/duller than press clicks
        // (per TDD §4.1's Pen mapping: "slightly lower-sharpness click on
        // release"), further reduced the longer the button was held.
        let intensity = 0.8 - (heldFactor * 0.5) // ranges 0.3 (long hold) to 0.8 (snap release)
        let sharpness = 0.7 - (heldFactor * 0.4) // ranges 0.3 to 0.7

        HapticsManager.shared.playClick(intensity: Double(intensity), sharpness: Double(sharpness))
        SoundManager.shared.playSystemClick()
    }
}
