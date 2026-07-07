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

extension View {
    /// Approximates Figma's directional "inner shadow" effect for a
    /// vector `Image`, which — unlike a native SwiftUI `Shape` — cannot be
    /// stroked, so a mask-based technique is used instead.
    ///
    /// How it works: a solid-color duplicate of `maskView`'s silhouette is
    /// created, blurred as a whole shape, then shifted by `(x, y)`. Where
    /// the shifted, blurred copy no longer reaches, the original content
    /// underneath shows through once re-clipped to `maskView`'s silhouette
    /// — producing a soft light/shadow gradient that appears to originate
    /// from inside the shape, falling off toward the opposite edge.
    ///
    /// - Parameters:
    ///   - maskView: The same image/shape being decorated, reused as both
    ///     the fill mask and the final re-clip mask. Must be visually
    ///     identical (same asset, same frame) to the view this modifier is
    ///     applied to, or the effect will misalign.
    ///   - color: The inner shadow's color (matches Figma's shadow color
    ///     swatch, e.g. `#A3B1C6`).
    ///   - blur: Blur radius applied to the solid-color duplicate before
    ///     offsetting. Figma's `Blur` value is roughly 2× this SwiftUI radius.
    ///   - x: Horizontal shift of the shadow's origin. Matches Figma's inner
    ///     shadow `X` position field.
    ///   - y: Vertical shift of the shadow's origin. Matches Figma's inner
    ///     shadow `Y` position field.
    func innerShadowShift<Mask: View>(
        mask maskView: Mask,
        color: Color,
        blur: CGFloat = 8,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> some View {
        self.overlay(
            Rectangle()
                .fill(color)
                .mask(maskView)          // clip solid fill to the shape's silhouette
                .blur(radius: blur)      // blur the whole filled shape
                .offset(x: x, y: y)      // shift it toward the shadow's origin
                .mask(maskView)          // re-clip so nothing spills outside the original shape
        )
    }
}

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

    var body: some View {

        ZStack {
            Color.primaryWhite
                .ignoresSafeArea()

            // MARK: - Clicky part (button)
            // Animates its Y-offset based on `model.currentOffset`, using
            // a fast ease-in while being pressed and a slower ease-out on
            // release, so the press reads as quick/responsive while the
            // release settles more naturally.
            VStack {
                Image("PenClick")
                    .innerShadowShift(
                        mask: Image("PenClick"),
                        color: Color.redHighlight,
                        blur: 7, x: -20, y: -2
                    )
                    .innerShadowShift(
                        mask: Image("PenClick"),
                        color: Color.redShadow,
                        blur: 11, x: 20, y: 5
                    )
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(.top, 160)
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
                    .shadow(color: Color.white, radius: 6, x: -7, y: -6)
                    .shadow(color: .whiteShadow, radius: 6, x: 7, y: 6)
                    .innerShadowShift(
                        mask: Image("PenBody"),
                        color: Color.primaryWhite,
                        blur: 13.85,
                        x: -21, y: -4
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
                    .shadow(color: Color.whiteShadow, radius: 3, x: 3, y: 3)
                    .shadow(color: .white, radius: 3, x: -3, y: -3)
                    .innerShadowShift(
                        mask: Image("PenCrown"),
                        color: Color.primaryWhite,
                        blur: 4.9,
                        x: -13, y: 0
                    )
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(.top, 210)
                Spacer()
            }

            // MARK: - Pen clip
            // Flat PNG asset (pre-flattened shadows baked into the image
            // itself, unlike the vector layers above which reconstruct
            // shadows in code).
            VStack {
                Image("PenClip")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40.37, height: 337.8)
                    .padding(.top, 300)
                    .padding(.leading, 25)
                Spacer()
            }

            // MARK: - Wordmark
            VStack {
                Image("HapticleText")
                    .shadow(color: Color.white, radius: 1, x: -1, y: -1)
                    .shadow(color: .whiteShadow, radius: 1, x: 1, y: 1)
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

#Preview {
    PenView()
}
