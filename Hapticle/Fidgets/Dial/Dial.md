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

---

## 4. Implementation Plan

To implement the physics and interactive behaviors of the safe dial, we will execute a 4-phase plan in accordance with [DD.md](file:///Users/moreno_m5/Projects/hapticle/Documentation/DD.md) and [TDD.md](file:///Users/moreno_m5/Projects/hapticle/Documentation/TDD.md):

### Phase 1: Touch Angle & Leverage Coordinate Mapping
*   **Coordinate Translation:** In `DialView`, translate the drag coordinates relative to the dial center $(155, 155)$.
*   **Angle Wrapping:** Convert the coordinates to radians using `atan2(y, x)`. Track full multi-rotation accumulation (unwrapped angle) to ensure the angle does not jump from $+\pi$ to $-\pi$ on boundary crossings.
*   **Leverage Factor Computation:** On every drag update, calculate the distance $r = \sqrt{x^2 + y^2}$ from the center and evaluate the torque leverage $M_{leverage}$ defined in the specifications:
    *   $r < 20\text{ pt} \implies M_{leverage} = 0.0$ (no rotational leverage in the dead-zone).
    *   $20 \le r \le 120\text{ pt} \implies M_{leverage} = \frac{r - 20}{100}$ (linear ramp).
    *   $r > 120\text{ pt} \implies M_{leverage} = 1.0$ (maximum leverage).

### Phase 2: Momentum Simulation & Decay Loop
*   **Trailing Velocity Capture:** Track the timestamped historical drag angles during the drag gesture to calculate a moving average of the angular velocity $\omega$ at release.
*   **Display Synchronization Loop:** Upon gesture release, start a frame-synchronized `CADisplayLink` (on the main thread, or using an active Timer loop) to run the simulation:
    *   Update the angle: $\theta_{t+1} = \theta_t + \omega_t \cdot dt$.
    *   Apply friction decay: $\omega_{t+1} = \omega_t \cdot (1 - \mu \cdot M_{leverage} \cdot dt)$, where the default friction coefficient $\mu = 0.05$.
    *   **Loop Termination:** Stop the timer when $|\omega_t| < 0.01\text{ rad/s}$ to conserve battery and CPU resources.

### Phase 3: Detent Crossing Haptics & Whirr Modulation
*   **Detent Detection:** Divide the angle space into $15^\circ$ detent steps. On every frame update (during both dragging and free-spinning):
    *   Calculate the integer detent index: $k = \lfloor \frac{\theta}{15^\circ} \rfloor$.
    *   If $k \ne \text{lastTriggeredDetentIndex}$, update the index and trigger:
        1.  `HapticsManager.shared.playClick(intensity: sharpness:)` for a transient touch pulse.
        2.  `SoundManager.shared.playSystemClick()` to hear the mechanical click.
*   **Audio Pitch Modulation:** Calculate the RPM of the dial rotation:
    $$\text{RPM} = \frac{|\omega| \cdot 60}{2\pi}$$
    Continuously feed this RPM value to `SoundManager` to modulate the frequency and volume of a synthesized sine wave, producing a whirring/clicking sound that aligns with the rotation speed.

### Phase 4: Debug Tuning Panel Bindings
*   **State Variable Bindings:** Expose physical properties inside `DialModel` as `@Published` parameters:
    *   `frictionCoefficient` (mapping to $\mu$).
    *   `detentSpacing` (default $15.0$ degrees).
    *   `hapticIntensity` and `hapticSharpness`.
*   **Overlay & Clipboard Integration:** Wire these parameters directly to the debug settings sliders in the overlay control panel. When the user clicks "Copy Settings as Text", serialize these variables into the clipboard Swift structure for copy-paste compilation.

