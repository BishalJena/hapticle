//
//  RadialMenuConfig.swift
//  Hapticle
//
//  All tunable constants for the radial fidget selector live here so the
//  whole feel of the menu can be dialed in from one place.
//

import CoreGraphics
import Foundation

/// The five fidget slots the menu selects between. Placeholder labels for now
/// (A–E); these map to Pen / Dial / Ticket / Magnet / Blob once those exist.
enum FidgetID: Int, CaseIterable, Identifiable {
    case a, b, c, d, e

    var id: Int { rawValue }

    /// Placeholder glyph shown inside the satellite and on the demo screen.
    var label: String {
        switch self {
        case .a: "A"
        case .b: "B"
        case .c: "C"
        case .d: "D"
        case .e: "E"
        }
    }

    /// Angle (degrees, standard math convention: 0° = right, CCW positive) at
    /// which this node sits on the dome. Evenly spaced every 45° across 180°,
    /// so every node lands above the home ring: A=180 (left) … E=0 (right).
    var domeAngleDegrees: Double {
        180 - Double(rawValue) * 45
    }
}

/// Layout, timing, motion, and haptic parameters. One source of truth for tuning.
enum RadialMenuConfig {

    // MARK: Layout
    /// Diameter of the resting/home ring button.
    static let ringDiameter: CGFloat = 64
    /// Diameter of each satellite node.
    static let satelliteDiameter: CGFloat = 56
    /// Distance from ring center to each satellite center when fully bloomed.
    static let bloomRadius: CGFloat = 115
    /// How far above the bottom safe area the ring center sits.
    static let bottomInset: CGFloat = 96
    /// A drag point within this distance of a node's center counts as hovering it.
    static let hitRadius: CGFloat = 36

    // MARK: Timing
    /// Hold duration required to fully charge and open the menu.
    static let holdDuration: TimeInterval = 0.8
    /// Delay between each satellite launching, for the staggered fan.
    static let bloomStagger: TimeInterval = 0.03
    /// Number of accelerating "wind-up" ticks felt during the charge.
    static let chargeTickCount = 8

    // MARK: Motion (Apple-style springs: duration + subtle bounce)
    // Asymmetric by design — the deliberate open is lively; the exits snap.
    /// Fan opening: lively, small overshoot.
    static let openSpring = SpringParams(duration: 0.40, bounce: 0.24)
    /// Fan cancel/close: snappier, no bounce — the system responding.
    static let closeSpring = SpringParams(duration: 0.24, bounce: 0.0)
    /// Hover magnetize: quick pop that settles.
    static let hoverSpring = SpringParams(duration: 0.22, bounce: 0.30)
    /// Commit confirm flare (node grows into the screen).
    static let commitSpring = SpringParams(duration: 0.34, bounce: 0.18)
    /// Demo screen swap on commit.
    static let collapseSpring = SpringParams(duration: 0.32, bounce: 0.12)

    /// Satellites emerge from the dot at this scale (never from 0 — nothing
    /// appears from nothing; the dot is their spatial origin).
    static let satelliteStartScale: CGFloat = 0.5
    /// Scale applied to the satellite the finger is hovering (magnetize).
    static let hoverScale: CGFloat = 1.18
    /// Scale applied to non-hovered siblings while another is hovered (recede).
    static let siblingScale: CGFloat = 0.9
    /// Chosen node flares to this scale as it commits (hero into the screen).
    static let commitFlareScale: CGFloat = 1.6
    /// Fan swings open like a hand fan: peak tilt (deg) that settles to 0.
    static let fanSwingDegrees: Double = 14
    /// Outward drift (pt) of unchosen nodes as they fall away on commit.
    static let siblingFallDrift: CGFloat = 22
    /// How long the commit confirm plays before the menu resets.
    static let commitBeat: TimeInterval = 0.30

    // MARK: Idle breathing (subtle — a constantly-visible decorative motion)
    static let breathScale: CGFloat = 1.025
    static let breathPeriod: TimeInterval = 3.0

    // MARK: Haptic score  (intensity, sharpness) — see design spec §7
    static let hapticPress = HapticBeat(intensity: 0.4, sharpness: 0.5)
    static let hapticChargeTick = HapticBeat(intensity: 0.2, sharpness: 0.6)
    static let hapticBloom = HapticBeat(intensity: 0.7, sharpness: 0.7)
    static let hapticSatelliteLand = HapticBeat(intensity: 0.15, sharpness: 0.8)
    static let hapticHoverEnter = HapticBeat(intensity: 0.5, sharpness: 0.9)
    static let hapticHoverLeave = HapticBeat(intensity: 0.2, sharpness: 0.5)
    static let hapticCommit = HapticBeat(intensity: 1.0, sharpness: 0.7)
    static let hapticCancel = HapticBeat(intensity: 0.3, sharpness: 0.3)
}

/// A single haptic transient's parameters.
struct HapticBeat {
    let intensity: Float
    let sharpness: Float
}

/// Spring description convertible to a SwiftUI `Animation`. Uses Apple's
/// duration+bounce model (easier to reason about than stiffness/damping).
struct SpringParams {
    let duration: Double
    let bounce: Double
}
