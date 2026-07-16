//
//  IdleTracker.swift
//  Hapticle
//

import SwiftUI
import Observation

@MainActor
@Observable

final class IdleTracker {
    /// True when the user has not touched the screen for the defined 3.5s threshold.
    var isIdleAFK: Bool = false
    
    private var afkTask: Task<Void, Never>?
    private let idleThresholdSeconds: Double = 0.75
    
    /// Called whenever ANY touch event occurs globally.
    func userInteracted() {
        if isIdleAFK {
            // Instantly remove the visual AFK state
            withAnimation(.easeOut(duration: 0.2)) {
                self.isIdleAFK = false
            }
        }
        // Cancel the current timer so it doesn't fire while interacting
        afkTask?.cancel()
    }
    
    /// Called when the user lifts their finger off the screen.
    func restartTimer() {
        afkTask?.cancel()
        
        afkTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(idleThresholdSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                withAnimation(.easeInOut(duration: 1.2)) {
                    self.isIdleAFK = true
                }
            }
        }
    }
}
