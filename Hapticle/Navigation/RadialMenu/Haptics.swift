//
//  Haptics.swift
//  Hapticle
//
//  Thin haptic seam. The radial menu speaks to this protocol, not to any
//  concrete engine, so it compiles and runs today via UIKit and upgrades to
//  Core Haptics (HapticsManager) without touching the menu.
//

import UIKit

/// Abstracts a single haptic transient described by intensity + sharpness.
protocol HapticFeedback {
    func transient(intensity: Float, sharpness: Float)
    func play(_ beat: HapticBeat)
}

extension HapticFeedback {
    func play(_ beat: HapticBeat) {
        transient(intensity: beat.intensity, sharpness: beat.sharpness)
    }
}

/// Default implementation backed by `UIImpactFeedbackGenerator`. Not as
/// expressive as Core Haptics (no true sharpness control), but it gives the
/// menu real feedback on device now.
///
/// TODO: once `HapticsManager` implements Core Haptics, add an adapter that
/// forwards `transient(intensity:sharpness:)` to `HapticsManager.shared`.
final class UIKitHaptics: HapticFeedback {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)

    init() { prepare() }

    /// Prime the generators so the first transient isn't delayed.
    func prepare() {
        [light, medium, rigid, heavy].forEach { $0.prepare() }
    }

    func transient(intensity: Float, sharpness: Float) {
        // Pick a generator by intensity; bias toward the crisper "rigid"
        // generator when sharpness is high so sharp beats feel snappier.
        let generator: UIImpactFeedbackGenerator
        switch intensity {
        case ..<0.3: generator = light
        case ..<0.6: generator = sharpness > 0.7 ? rigid : medium
        case ..<0.85: generator = rigid
        default: generator = heavy
        }
        generator.impactOccurred(intensity: CGFloat(min(max(intensity, 0), 1)))
        generator.prepare()
    }
}
