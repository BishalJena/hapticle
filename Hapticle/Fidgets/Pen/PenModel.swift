//
//  PenDial.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import Foundation
import Combine
import CoreGraphics

enum PenButtonState {
    case unclicked    // offset 0
    case beingClicked // offset 50, while finger is down
    case clicked      // offset 30, toggled "locked in" state
}

class PenModel: ObservableObject {
    @Published private(set) var buttonState: PenButtonState = .unclicked
    private var preClickState: PenButtonState = .unclicked
    private var pressStartTime: Date?
    
    var currentOffset: CGFloat {
        switch buttonState {
        case .unclicked: return 0
        case .beingClicked: return 50
        case .clicked: return 30
        }
    }
    
    /// Called with the drag's current velocity to make press haptics feel
        /// physical: a fast/hard tap gives a sharper, stronger click; a slow,
        /// deliberate press gives a softer one.
        func onTouchDown(velocity: CGSize = .zero) {
            pressStartTime = Date()
            
            if buttonState != .beingClicked {
                preClickState = buttonState
                buttonState = .beingClicked
                
                let speed = min(abs(velocity.height) / 1000.0, 1.0) // normalize px/s to 0...1
                let intensity = 0.6 + (speed * 0.4)   // ranges ~0.6 (gentle) to 1.0 (slammed)
                let sharpness = 0.5 + (speed * 0.4)   // faster press = crisper transient
                
                HapticsManager.shared.playClick(intensity: Double(intensity), sharpness: Double(sharpness))
            }
        }
        
        func onTouchUp() {
            let pressDuration = pressStartTime.map { Date().timeIntervalSince($0) } ?? 0.2
            pressStartTime = nil
            
            buttonState = (preClickState == .clicked) ? .unclicked : .clicked
            
            // A quick press-release (rapid tap) gives a snappier, higher-sharpness
            // release click; a held-then-released press feels softer/duller.
            let heldFactor = min(pressDuration / 0.5, 1.0) // 0 = instant, 1 = held 0.5s+
            let intensity = 0.7 - (heldFactor * 0.2)  // long holds land slightly softer
            let sharpness = 0.6 - (heldFactor * 0.2)
            
            HapticsManager.shared.playClick(intensity: Double(intensity), sharpness: Double(sharpness))
        }
}
