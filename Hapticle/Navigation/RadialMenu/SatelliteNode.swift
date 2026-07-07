//
//  SatelliteNode.swift
//  Hapticle
//
//  One neumorphic satellite in the fan. Pure, prop-driven view: the parent owns
//  position + bloom; this owns its own hover/recede styling.
//

import SwiftUI

struct SatelliteNode: View {
    let label: String
    /// The finger is over this node — magnetize (scale up, lift, accent tint).
    var isHovered: Bool
    /// Another node is hovered — recede slightly to defer focus.
    var recede: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var idleLabelColor: Color { Color(hex: "#6B7A90") }

    var body: some View {
        Text(label)
            .font(.system(size: 22, weight: .semibold, design: .rounded))
            .foregroundStyle(isHovered ? Color.white : idleLabelColor)
            .frame(width: RadialMenuConfig.satelliteDiameter,
                   height: RadialMenuConfig.satelliteDiameter)
            .neumorphicCircle(depth: isHovered ? 1.5 : 1, accent: isHovered)
            .scaleEffect(scale)
            .animation(hoverAnim, value: isHovered)
            .animation(hoverAnim, value: recede)
    }

    /// Reduce Motion keeps the accent/tint change but drops the scale pop.
    private var scale: CGFloat {
        if reduceMotion { 1 }
        else if isHovered { RadialMenuConfig.hoverScale }
        else if recede { RadialMenuConfig.siblingScale }
        else { 1 }
    }

    private var hoverAnim: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(RadialMenuConfig.hoverSpring)
    }
}
