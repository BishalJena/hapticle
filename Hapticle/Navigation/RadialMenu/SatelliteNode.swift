//
//  SatelliteNode.swift
//  Hapticle
//
//  One neumorphic satellite in the fan. Pure, prop-driven view: the parent owns
//  position + bloom; this owns its own hover/recede styling.
//

import SwiftUI

struct SatelliteNode: View {
    let assetName: String
    /// The finger is over this node — magnetize (scale up, lift).
    var isHovered: Bool
    /// Another node is hovered — recede slightly to defer focus.
    var recede: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Glass Base
            Circle()
                .fill(.thinMaterial)
                
            // Inner Shadow (recessed peephole look)
            Circle()
                .stroke(Color.black.opacity(0.18), lineWidth: 3)
                .blur(radius: 2)
                .offset(x: 1.5, y: 1.5)
                .mask(Circle())
            
            // Outer Bezel Stroke
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .clear, .black.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.0
                )
            
            // Scaled original image icon
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
        }
        .frame(width: RadialMenuConfig.satelliteDiameter,
               height: RadialMenuConfig.satelliteDiameter)
        .scaleEffect(scale)
        .shadow(color: Color.black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 6 : 2, x: 0, y: isHovered ? 4 : 1)
        .animation(hoverAnim, value: isHovered)
        .animation(hoverAnim, value: recede)
    }

    /// Reduce Motion keeps the transition but drops the scale pop.
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
