//
//  TicketModel.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//
//  Step 2 of the Ticket fidget: makes the roll scrollable via drag.
//  Owns only the roll's vertical scroll offset for now — no tear/rotate
//  physics yet. Kept as a separate ObservableObject from the start so the
//  tear mechanic can be layered in later without restructuring PenView-
//  style state management, per the MVVM-M separation in the Hapticle
//  TDD §1.1.
//

import Foundation
import Combine
import CoreGraphics

class TicketModel: ObservableObject {

    /// Current vertical offset applied to the entire ticket roll. Purely
    /// additive to the roll's resting top position — the Machine graphic
    /// never reads or reacts to this value, so it stays fixed regardless
    /// of how far the roll has been scrolled.
    @Published private(set) var scrollOffset: CGFloat = 0

    /// Offset that was already "committed" (i.e. left in place) before
    /// the currently in-progress drag gesture began. `DragGesture`'s
    /// `translation` is always relative to the start of the *current*
    /// gesture, so this needs to be tracked separately and added back in
    /// to get a continuously accumulating scroll position across
    /// multiple separate drags.
    private var committedOffset: CGFloat = 0

    /// Call on every `DragGesture.onChanged` update.
    func onDragChanged(translationY: CGFloat) {
        scrollOffset = committedOffset + translationY
    }

    /// Call on `DragGesture.onEnded`. Folds the just-finished drag's
    /// translation into `committedOffset` so the next drag continues
    /// from here rather than resetting.
    func onDragEnded(translationY: CGFloat) {
        committedOffset += translationY
        scrollOffset = committedOffset
    }
}
