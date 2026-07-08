//
//  NeumorphicStyle.swift
//  Hapticle
//
//  In-code neumorphic palette + styling. Colors are defined here rather than in
//  an asset catalog so the component is fully self-contained; migrate to assets
//  later if desired (see DD.md §Color Palette).
//

import SwiftUI

extension Color {
    /// Build a color from a hex string like "#E0E5EC" or "E0E5EC".
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r = Double((value & 0xFF0000) >> 16) / 255
        let g = Double((value & 0x00FF00) >> 8) / 255
        let b = Double(value & 0x0000FF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    // White (light) neumorphic theme — the app's default surface.
    static let hpBase = Color(hex: "#E0E5EC")
    static let hpHighlight = Color(hex: "#FFFFFF")
    static let hpShadow = Color(hex: "#A3B1C6")

    // Red accent theme — used for the active/hovered node and the charge arc.
    static let hpAccent = Color(hex: "#C73535")
    static let hpAccentHighlight = Color(hex: "#D86E6E")
    static let hpAccentShadow = Color(hex: "#892424")
}

/// Soft-3D styling for a circular surface. `isPressed` recesses (debosses) it;
/// otherwise it extrudes. `depth` scales the shadow spread so motion can inflate
/// or deflate the elevation. `tint` swaps in an accent surface when active.
struct NeumorphicCircle: ViewModifier {
    var isPressed: Bool = false
    var depth: CGFloat = 1
    var accent: Bool = false

    private var base: Color { accent ? .hpAccent : .hpBase }
    private var highlight: Color { accent ? .hpAccentHighlight : .hpHighlight }
    private var shadow: Color { accent ? .hpAccentShadow : .hpShadow }

    func body(content: Content) -> some View {
        if isPressed {
            // Recessed: inner shadow top-left, inner highlight bottom-right.
            content
                .background(Circle().fill(base))
                .overlay(
                    Circle()
                        .stroke(shadow, lineWidth: 3)
                        .blur(radius: 3)
                        .offset(x: 1.5, y: 1.5)
                        .mask(Circle().fill(
                            LinearGradient(colors: [shadow, .clear],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)))
                )
                .overlay(
                    Circle()
                        .stroke(highlight, lineWidth: 3)
                        .blur(radius: 3)
                        .offset(x: -1.5, y: -1.5)
                        .mask(Circle().fill(
                            LinearGradient(colors: [.clear, highlight],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing)))
                )
                .clipShape(Circle())
        } else {
            // Extruded: cast shadow bottom-right, reflected highlight top-left.
            content
                .background(Circle().fill(base))
                .clipShape(Circle())
                .shadow(color: shadow.opacity(0.9), radius: 8 * depth, x: 6 * depth, y: 6 * depth)
                .shadow(color: highlight.opacity(0.9), radius: 8 * depth, x: -6 * depth, y: -6 * depth)
        }
    }
}

extension View {
    /// Apply the circular neumorphic surface style.
    func neumorphicCircle(isPressed: Bool = false, depth: CGFloat = 1, accent: Bool = false) -> some View {
        modifier(NeumorphicCircle(isPressed: isPressed, depth: depth, accent: accent))
    }
}
