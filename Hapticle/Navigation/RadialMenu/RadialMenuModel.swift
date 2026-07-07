//
//  RadialMenuModel.swift
//  Hapticle
//
//  The radial menu's state machine. Owns phase, charge progress, ring-relative
//  geometry, hover detection, and haptic dispatch. Screen geometry stays in the
//  view; this model works purely in ring-relative coordinates.
//

import Foundation
import Observation

@MainActor
@Observable
final class RadialMenuModel {

    enum Phase: Equatable {
        case idle
        case charging
        case open
        case hovering(FidgetID)
        case committing(FidgetID)   // chosen; playing the confirm flare
    }

    private(set) var phase: Phase = .idle
    /// 0→1 fill of the charge arc while holding.
    private(set) var chargeProgress: Double = 0

    /// Fired once, on commit, with the chosen fidget.
    var onSelect: (FidgetID) -> Void = { _ in }

    private let haptics: HapticFeedback
    private var chargeTask: Task<Void, Never>?

    init(haptics: HapticFeedback = HapticsAdapter()) {
        self.haptics = haptics
    }

    // MARK: Derived state (read by the view)

    var isResting: Bool { phase == .idle }
    var isCharging: Bool { phase == .charging }
    /// The fan is on screen (open, being hovered, or playing its commit flare).
    var isOpen: Bool {
        switch phase {
        case .open, .hovering, .committing: true
        default: false
        }
    }
    var hoveredID: FidgetID? {
        if case .hovering(let id) = phase { id } else { nil }
    }
    /// Non-nil only while the chosen node plays its confirm flare.
    var committingID: FidgetID? {
        if case .committing(let id) = phase { id } else { nil }
    }

    // MARK: Geometry (ring-relative, SwiftUI coords with y pointing down)

    /// Offset of a satellite's center from the ring center when fully bloomed.
    func offset(for id: FidgetID) -> CGSize {
        let a = id.domeAngleDegrees * .pi / 180
        // -sin puts the node above the ring (screen y grows downward).
        return CGSize(width: RadialMenuConfig.bloomRadius * cos(a),
                      height: -RadialMenuConfig.bloomRadius * sin(a))
    }

    /// The nearest satellite within the hit radius of a ring-relative point.
    func hoverTarget(at point: CGPoint) -> FidgetID? {
        var best: (id: FidgetID, dist: CGFloat)?
        for id in FidgetID.allCases {
            let o = offset(for: id)
            let dx = point.x - o.width
            let dy = point.y - o.height
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= RadialMenuConfig.hitRadius, best == nil || d < best!.dist {
                best = (id, d)
            }
        }
        return best?.id
    }

    // MARK: Gesture entry points (called by the view's DragGesture)

    func touchDown() {
        guard phase == .idle else { return }
        phase = .charging
        chargeProgress = 0
        haptics.play(RadialMenuConfig.hapticPress)
        startCharge()
    }

    func dragChanged(to point: CGPoint) {
        guard isOpen else { return }        // don't track hover mid-charge
        let target = hoverTarget(at: point)
        if target != hoveredID {
            if let target {
                haptics.play(RadialMenuConfig.hapticHoverEnter)
                phase = .hovering(target)
            } else {
                haptics.play(RadialMenuConfig.hapticHoverLeave)
                phase = .open
            }
        }
    }

    func touchUp() {
        switch phase {
        case .hovering(let id):
            // Commit: fire selection now (screen begins pulling up) and play the
            // confirm flare for one beat before collapsing to idle.
            haptics.play(RadialMenuConfig.hapticCommit)
            chargeTask?.cancel()
            phase = .committing(id)
            onSelect(id)
            Task { [weak self] in
                try? await Task.sleep(
                    nanoseconds: UInt64(RadialMenuConfig.commitBeat * 1_000_000_000))
                if case .committing = self?.phase { self?.reset() }
            }
        case .open:
            haptics.play(RadialMenuConfig.hapticCancel)   // released on empty
            reset()
        case .charging, .idle, .committing:
            reset()                                        // quick tap / mid-commit
        }
    }

    // MARK: Charge

    private func startCharge() {
        let count = RadialMenuConfig.chargeTickCount
        let duration = RadialMenuConfig.holdDuration
        // Accelerating tick schedule (ease-in): sparse early, dense near the end.
        let tickTimes = (1...count).map { duration * pow(Double($0) / Double(count), 1.6) }

        chargeTask = Task { [weak self] in
            let start = Date()
            var nextTick = 0
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = Date().timeIntervalSince(start)
                self.chargeProgress = min(elapsed / duration, 1)
                while nextTick < tickTimes.count, elapsed >= tickTimes[nextTick] {
                    self.haptics.play(RadialMenuConfig.hapticChargeTick)
                    nextTick += 1
                }
                if elapsed >= duration { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
            if !Task.isCancelled { self?.open() }
        }
    }

    private func open() {
        guard phase == .charging else { return }
        phase = .open
        chargeProgress = 1
        haptics.play(RadialMenuConfig.hapticBloom)
        scheduleLandingTicks()
    }

    /// One micro-tick per satellite, staggered, so the fan is *felt* fanning out.
    private func scheduleLandingTicks() {
        Task { [weak self] in
            for _ in FidgetID.allCases {
                guard let self, self.isOpen else { return }
                self.haptics.play(RadialMenuConfig.hapticSatelliteLand)
                try? await Task.sleep(
                    nanoseconds: UInt64(RadialMenuConfig.bloomStagger * 1_000_000_000))
            }
        }
    }

    private func reset() {
        chargeTask?.cancel()
        chargeTask = nil
        phase = .idle
        chargeProgress = 0
    }
}
