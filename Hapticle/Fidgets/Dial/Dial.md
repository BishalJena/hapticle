# Dial Fidget Design & Brainstorming Log (Dial.md)

This log documents the design decisions, engineering trade-offs, and technical solutions for implementing the heavy rotary safe dial fidget.

---

## 1. SwiftUI vs. SVG Assets

We deliberated on whether to render the Neumorphic dial using the provided vector SVGs as images, or to build it natively using SwiftUI drawing tools.

### Option A: Image Assets (Light/Dark SVGs)
*   **Pros:** Quick to implement; guarantees 1:1 match with Figma.
*   **Cons:** Feels "lazy" and restrictive. We lose the ability to animate depth transitions in real time (e.g., dial recessing slightly when pressed). It also limits scaling and colors to static presets, making theme swaps harder.

### Option B: Pure SwiftUI Replay (Selected)
*   **Pros:** Dynamic, highly responsive, and crisp at any scale. We can implement real-time Neumorphic shadow shifts when the user presses down, matching the physical click of a button.
*   **Cons:** Requires precise layout and overlay math in SwiftUI code.
*   **Implementation Strategy:** We will stack circular shapes inside a `ZStack` and apply custom Neumorphic offsets:
    1.  **Outer Circular Well:** A debossed (recessed) circle that provides the "groove" the dial sits inside.
    2.  **Dial Body:** An embossed (extruded) circle floating above the well.
    3.  **Grip Ridges:** Programmatic ticks spaced uniformly around the dial border.
    4.  **Indicator Dot:** A small red circle with a subtle debossed/recessed shadow, offset radially from the center.

---

## 2. Rotational Lighting Mechanics & Shadow Stability

A key challenge in rotating Neumorphic components is maintaining the illusion of a **fixed light source** (typically shining from the top-left).

*   **The Issue:** If we rotate the entire dial (with its embossed shadows) using `.rotationEffect()`, the highlight will spin to the bottom-right and the shadow to the top-left at $180^\circ$ of rotation. This destroys the 3D Neumorphic illusion.
*   **The Solution:** 
    - The **shadow-casting base circle** of the dial body remains **statically aligned** (unrotated) relative to the screen coordinates. Its shadow offsets remain fixed at `x: -6, y: -6` (highlight) and `x: 6, y: 6` (shadow).
    - Only the **surface elements**—the circular ticks (detents), the center grip grooves, and the red indicator dot—are placed in a container and rotated.
*   **Spinning the Red Dot:** The red dot rotates in perfect synchrony with the detent ticks by placing them in the same rotated `ZStack`. The red dot's internal shadow can either rotate with it (giving the impression of a physical, moving slot) or remain statically offset relative to the screen to preserve lighting consistency.

---

## 3. State & Physics Separation: View vs. Model (MVVM-M)

We deliberated on where the physics computations (momentum, leverage torque, detent triggers) should live.

### Option A: All Physics in DialView
*   **Pros:** Simplifies gesture code since drag offsets and touch locations are directly available.
*   **Cons:** Clutters UI code, prevents unit testing of inertia decay, and makes watchOS adaptation harder to maintain since watchOS cannot share SwiftUI view gesture structures.

### Option B: Decoupled MVVM-M (Selected)
*   **DialView (SwiftUI UI + Gestures):** 
    - Captures the drag position coordinates `(x, y)` relative to the dial center.
    - Sends touch state (drag started, dragging, drag ended) and coordinates to `DialModel`.
    - Renders the dial face rotation based on `@Published` angle properties in the model.
*   **DialModel (ObservableObject Physics Simulator):**
    - Maintains rotation angle ($\theta$) and angular velocity ($\omega$).
    - Calculates the fulcrum leverage torque ($M_t$) based on distance from center.
    - Runs a `CADisplayLink` or high-frequency timer when the user "flicks" the dial to compute momentum decay and friction:
      $$\omega_{t+1} = \omega_t \cdot (1 - \mu M_t)$$
    - Monitors when the angle crosses $15^\circ$ detent ticks and commands `HapticsManager` and `SoundManager` to fire click transients.

This keeps our logic clean, highly performant, and 100% testable.
