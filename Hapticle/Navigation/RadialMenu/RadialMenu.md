# Radial Fidget Selector Menu — Design Spec

**Date:** 2026-07-06
**Component:** Hold-to-radial navigation selector for Hapticle (iOS, SwiftUI)
**Status:** Approved design → ready for implementation plan
**Parent docs:** [DD.md](../../../Documentation/DD.md) §"Navigation & Selector Menu Deliberations", [HO.md](../../../Documentation/HO.md) §1.3.2

---

## 1. Purpose

A press-and-hold radial menu that lets a user browse and switch between Hapticle's **5 fidget games**. It replaces/supplements the 2-finger swipe with a discoverable, highly animated, haptics-rich selector that matches the app's neumorphic design language and borrows motion motifs from the fidgets themselves (Dial detents, Magnet elastic, Blob pop).

This spec covers a **standalone, runnable component** built now, before the real fidget screens exist. Placeholder screens (A–E) stand in for the 5 fidgets and are swapped for real ones later through a single callback seam.

## 2. Scope

**In scope**
- Self-contained `RadialMenu` component (view + model + subviews) in a new subfolder.
- Reusable neumorphic styling (extrude/recess modifier + palette `Color` extension).
- Demo harness with 5 placeholder screens (A–E) proving the full gesture, motion, and haptic loop end to end.
- Full animation choreography and haptic score.

**Out of scope (deferred)**
- Real fidget screens/logic (Pen, Dial, Ticket, Magnet, Blob).
- 2-finger swipe cycling gesture.
- watchOS adaptation.
- Sound design (haptics only for now; `SoundManager` hook can come later).

## 3. Decisions (locked)

| Decision | Choice |
|---|---|
| Satellite count | **5, always visible** (A–E → the 5 fidgets) |
| Layout | **Bottom-center upward fan**, 180° dome |
| Anchor position | ~120pt above bottom safe area, horizontally centered |
| Gesture model | **One continuous gesture**: press → hold/charge → drag → release |
| Cancel | Release on empty space **or** back on the home ring |
| Scope | Standalone runnable demo with placeholder A–E screens |

## 4. Geometry

- **Home ring:** 64pt diameter, raised neumorphic circle, centered horizontally, ~120pt above bottom safe area.
- **Satellites:** 5 nodes, 56pt diameter, on a **180° dome** at radius **~115pt** from the ring center, evenly spaced every **45°**:
  - A = 180° (left), B = 135°, C = 90° (top), D = 45°, E = 0° (right).
  - Angle measured standard math convention (0° = right, CCW), positions land above the ring.
- **Hit zone:** a satellite is "hovered" when the drag point is within **36pt** of that node's center (generous, larger than the visual 28pt radius, because thumb dragging is imprecise). If the point is within multiple, nearest-center wins.

```
        C (90)
   B(135)   D(45)
 A(180)         E(0)
        (O)  home ring
   ==== bottom safe area ====
```

## 5. State machine

`RadialMenuModel` (`@Observable`) drives a single phase enum:

```
idle            -> (touch down)              -> charging
charging        -> (hold >= 0.8s)            -> open
charging        -> (release before 0.8s)     -> idle        (treated as cancel; quick tap = no-op)
open / hovering -> (drag into node hit zone)  -> hovering(i)
hovering(i)     -> (drag out of all zones)    -> open
open            -> (release, no hover)        -> closing -> idle   (cancel)
hovering(i)     -> (release inside zone)       -> committing(i) -> onSelect(i) -> idle
```

- Charge progress (0→1) is time-driven over `holdDuration = 0.8s`.
- The model owns geometry math, hover detection, and fires haptics at each transition.

## 6. Motion choreography

Seven beats, each a distinct physical event:

1. **Idle** — ring "breathes": slow scale pulse 1.0→1.03 + drifting highlight. Signals it's alive/tappable.
2. **Press down** — ring debosses inward (recess shadow).
3. **Charge (~0.8s)** — red-accent progress arc sweeps clockwise around the ring; ring subtly swells (stored energy).
4. **Unlock → Bloom** — satellites launch from behind the ring along radial vectors, r: 0→115pt, **staggered ~30ms each**, spring **overshoot** then settle. Each scales 0.3→1.0 while its neumorphic shadow inflates. Background dims/blurs slightly. Labels A–E fade in just after each lands.
5. **Drag / hover** — nearest satellite magnetizes: scale→1.15, deeper shadow (lift), tint toward red accent theme. Siblings recede slightly. Optional elastic tether from ring to hovered node (Magnet motif).
6. **Commit** — chosen node quick press-in; menu collapses toward it; selected screen pulled up via hero-zoom (node expands into the screen).
7. **Cancel** — satellites implode back into the ring along their vectors (reverse bloom); ring returns to idle breathing.

**Animation notes**
- Springs for bloom/hover (interpolating spring, mild overshoot); ease for progress arc.
- Neumorphic "motion" = animating shadow offset + blur radius + base scale, not moving flat pixels. All states generated in SwiftUI (Figma states are static, per HO.md note).

## 7. Haptic score

Via `HapticsManager.shared.playTransient(intensity:sharpness:)`:

| Beat | intensity / sharpness | Feel |
|---|---|---|
| Press down | 0.4 / 0.5 | soft key press |
| Charge ticks | 0.2 / 0.6, accelerating | wind-up anticipation |
| Unlock/bloom | 0.7 / 0.7 | pop/release |
| Each satellite lands | 0.15 / 0.8 ×5 staggered | feel them fan out |
| Hover enter | 0.5 / 0.9 | crisp detent |
| Hover leave | 0.2 / 0.5 | soft un-click |
| Commit | 1.0 / 0.7 | decisive confirm |
| Cancel | 0.3 / 0.3 | dull collapse |

If `HapticsManager` is not yet implemented, the component calls a thin protocol seam so it compiles and runs (no-op or `UIImpactFeedbackGenerator` fallback) and upgrades cleanly when Core Haptics lands.

## 8. Architecture & files

New subfolder `Hapticle/Navigation/RadialMenu/`, MVVM-M per HO.md:

| File | Responsibility |
|---|---|
| `RadialMenuModel.swift` | `@Observable` state machine, geometry math, hover detection, haptic dispatch. |
| `RadialMenuView.swift` | Overlay: home ring + progress arc + satellites; owns the single continuous `DragGesture(minimumDistance: 0)`. |
| `SatelliteNode.swift` | One neumorphic satellite (idle/hover/active styling + label). |
| `RadialMenuConfig.swift` | Geometry constants, timings, angles, haptic params (all tunable in one place). |
| `NeumorphicStyle.swift` | Extrude/recess `ViewModifier` (from HO.md §1.2) + `Color+Hapticle` palette extension. |
| `RadialMenuDemoView.swift` | Harness: 5 placeholder screens A–E, hosts overlay, switches active screen on `onSelect`. |

**Public seam:** the menu exposes `onSelect: (FidgetID) -> Void` (and a `FidgetID` enum for the 5 slots). Wiring to real fidgets later is a one-liner.

## 9. Interfaces (sketch)

```swift
enum FidgetID: Int, CaseIterable { case a, b, c, d, e }   // -> pen, dial, ticket, magnet, blob later

struct RadialMenuView: View {
    var onSelect: (FidgetID) -> Void
}

@Observable final class RadialMenuModel {
    enum Phase { case idle, charging(progress: Double), open, hovering(FidgetID), closing }
    private(set) var phase: Phase
    // geometry(for:), hoverTarget(at:), advanceCharge(), commit(), cancel()
}
```

## 10. Success criteria

- Runs in the demo harness on device/simulator: press-hold blooms the fan, drag magnetizes the nearest node, release commits and pulls up its placeholder screen, release-on-empty cancels.
- Every beat in §6 fires its haptic from §7 (verified on device).
- All motion is neumorphic and reads as one continuous physical gesture (no jarring cuts).
- Geometry/timing/haptic params all live in `RadialMenuConfig.swift` for easy tuning.
- No dependency on real fidget code; swappable via `onSelect`.

## 11. Open questions / future

- Elastic tether: shipping as an optional flag (default on), easy to cut if it reads busy.
- Final `holdDuration` and fan radius to be tuned by feel on device.
- Hero-zoom commit transition may be simplified to a cross-fade if the zoom fights the neumorphic base.
