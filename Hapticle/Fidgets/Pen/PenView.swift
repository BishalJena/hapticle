//
//  PenView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//
//  Renders the Pen fidget: a layered composite of neumorphic vector
//  artwork (button, body, crown, clip, wordmark), each styled with
//  drop-shadow pairs and a custom "inner shadow" approximation, since
//  Figma-exported SVGs carry shape data only — effects (shadows, blurs)
//  are not embedded and must be reconstructed in SwiftUI. This view
//  contains no state or physics logic; all of that lives in `PenModel`
//  per the MVVM-M separation described in the Hapticle TDD §1.1.
//

import SwiftUI

/// The Pen fidget's root view. Composes five layered vector assets into a
/// single neumorphic pen illustration, and forwards raw touch events to
/// `PenModel` for state resolution and physics-driven feedback dispatch.
///
/// Layer order (back to front, matching Figma's asset stacking):
/// 1. `PenClick` — the clickable red button (animates on press/release)
/// 2. `PenBody` — the pen's main body
/// 3. `PenCrown` — the crown, overlaps the button's top edge
/// 4. `PenClip` — the pocket clip
/// 5. `HapticleText` — the wordmark text
struct PenView: View {
    @StateObject private var model = PenModel()
    @Environment(\.colorScheme) private var colorScheme
    
//    // Opacity multipliers — only reduced in dark mode; full strength in light mode.
//    private var highlightOpacity: Double { colorScheme == .dark ? 0.25 : 1.0 }
//    private var shadowOpacity: Double { colorScheme == .dark ? 0.75 : 1.0 }
//    private var innerShadowOpacity: Double { colorScheme == .dark ? 0.5 : 1.0 }
    
    
    var body: some View {
        
        ZStack {
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            // MARK: - Clicky part (button)
            // Animates its Y-offset based on `model.currentOffset`, using
            // a fast ease-in while being pressed and a slower ease-out on
            // release, so the press reads as quick/responsive while the
            // release settles more naturally.
            VStack {
                Image("PenClick")
                    .renderingMode(.template)
                    .foregroundColor(Color.accent)
                    .innerShadowShift(
                        mask: Image("PenClick"),
                        color: Color.accentHighlight,
                        blur: 4.9, x: -10, y: -8
                    )
                    .innerShadowShift(
                        mask: Image("PenClick"),
                        color: Color.accentShadow,
                        blur: 10, x: 25, y: 3
                    )
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(.top, 165)
                    .offset(y: model.currentOffset)
                    .animation(
                        model.buttonState == .beingClicked
                        ? .easeIn(duration: 0.08)
                        : .easeOut(duration: 0.25),
                        value: model.buttonState
                    )
                Spacer()
            }
            
            // MARK: - Pen body
            // Static neumorphic shell: standard drop-shadow pair (light
            // top-left highlight, dark bottom-right shadow) plus an inner
            // shadow to suggest a subtle concave surface.
            VStack {
                Image("PenBody")
                    .renderingMode(.template)
                    .foregroundColor(Color.fidgetPrimary)
                    .shadow(color: Color.highlight.opacity(0.2), radius: 6, x: -7, y: -6)
                    .shadow(color: Color.shadow, radius: 6, x: 7, y: 6)
                    .innerShadowShift(
                        mask: Image("PenBody"),
                        color: Color.shadow.opacity(1.0),
                        blur: 20,
                        x: 55, y: 0
                    )
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(.top, 450)
                Spacer()
            }
            
            
            // MARK: - Crown
            // Sits above and overlapping the clicky part in Z-order (drawn
            // after it in the ZStack), so as the button presses down it
            // slides partially behind the crown's fixed silhouette.
            VStack {
                Image("PenCrown")
                    .renderingMode(.template)
                    .foregroundColor(Color.shadow)
                        .shadow(color: Color.shadow, radius: 3, x: 3, y: 3)
                    .shadow(color: Color.highlight.opacity(0.2), radius: 3, x: -3, y: -3)
                    .innerShadowShift(
                        mask: Image("PenCrown"),
                        color: Color.fidgetPrimary,
                        blur: 5.0,
                        x: -10, y: -0.8
                    )
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(.top, 215)
                Spacer()
            }
            
            // MARK: - Pen clip
            // Flat PNG asset (pre-flattened shadows baked into the image
            // itself, unlike the vector layers above which reconstruct
            // shadows in code).
            VStack {
                Image("PenClip")
                    .renderingMode(.template)
                        .foregroundColor(Color.fidgetPrimary)
                        .shadow(color: Color.highlight.opacity(0.4), radius: 3, x: -3, y: -3)
                    .shadow(color: Color.shadow, radius: 3, x: 3, y: 3)
                    .innerShadowShift(
                        mask: Image("PenClip"),
                        color: Color.shadow,
                        blur: 15,
                        x: 25, y: 0
                    )
                    .scaledToFit()
                    .frame(width: 40.37, height: 337.8)
                    .padding(.top, 300)
                    .padding(.leading, 25)
                Spacer()
            }
            
            // MARK: - Wordmark
            VStack {
                Image("HapticleText")
                    .renderingMode(.template)
                        .foregroundColor(Color.fidgetPrimary)
                    .shadow(color: Color.highlight.opacity(0.4), radius: 1, x: -1, y: -1)
                    .shadow(color: Color.shadow, radius: 1, x: 1, y: 1)
                    .scaledToFit()
                    .padding(.top, 350)
                    .padding(.leading, 25)
                Spacer()
            }
            
        }
        // Expands the hit-testable area to the full screen (rather than
        // just the visible pixels of child views), so a tap anywhere
        // triggers the button's press/release cycle — not just direct
        // taps on the button artwork itself.
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in model.onTouchDown(velocity: value.velocity) }
                .onEnded { _ in model.onTouchUp() }
        )
    }
}

struct PenView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Light Mode Preview
            PenView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            
            // Dark Mode Preview
            PenView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}

