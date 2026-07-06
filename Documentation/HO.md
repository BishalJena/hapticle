# Hapticle - Developer Hand-Off Document (HO)

**Status:** Source of Truth (SOT) for Frontend & Hardware Implementation  
**Figma Reference:** [Figma Design File](https://www.figma.com/design/cRjdjva7DCcEfmy2M9u2My/Hapticle-Mid-fi?node-id=1-4&t=pTGScvGNydCUxVjF-1)  
**Parent Documentation:** [Design Document (DD)](file:///Users/moreno_m5/Projects/hapticle/Documentation/DD.md) & [Technical Design Document (TDD)](file:///Users/moreno_m5/Projects/hapticle/Documentation/TDD.md)  

---

## 1. Global Visual & Design System

To reproduce the soft 3D neumorphic visuals from Figma, developers must adhere to the exact color palette specifications and SwiftUI styling modifiers defined below.

### 1.1 Color Palette Specifications
All color variables should be registered in assets and mapped via `Color` extensions.

| Color Name | Preview | HEX | RGBA | HSL | Neumorphic Role |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **White** | ![#E0E5EC](Colors/white.svg) | `#E0E5EC` | `rgba(224, 229, 236, 1.00)` | `hsl(215, 24%, 90%)` | Light Theme Background |
| **White Highlight** | ![#FFFFFF](Colors/white_highlight.svg) | `#FFFFFF` | `rgba(255, 255, 255, 1.00)` | `hsl(0, 0%, 100%)` | Light Theme Highlight |
| **White Shadow** | ![#A3B1C6](Colors/white_shadow.svg) | `#A3B1C6` | `rgba(163, 177, 198, 1.00)` | `hsl(216, 23%, 71%)` | Light Theme Shadow |
| **Primary Grey** | ![#454545](Colors/primary_grey.svg) | `#454545` | `rgba(69, 69, 69, 1.00)` | `hsl(0, 0%, 27%)` | Dark Theme Background |
| **Grey Highlight** | ![#D9D9D9](Colors/grey_highlight.svg) | `#D9D9D9` | `rgba(217, 217, 217, 1.00)` | `hsl(0, 0%, 85%)` | Dark Theme Highlight |
| **Grey Shadow** | ![#000000](Colors/grey_shadow.svg) | `#000000` | `rgba(0, 0, 0, 1.00)` | `hsl(0, 0%, 0%)` | Dark Theme Shadow |
| **Primary Red** | ![#C73535](Colors/primary_red.svg) | `#C73535` | `rgba(199, 53, 53, 1.00)` | `hsl(0, 58%, 49%)` | Red Theme Background |
| **Red Highlight** | ![#D86E6E](Colors/red_highlight.svg) | `#D86E6E` | `rgba(216, 110, 110, 1.00)` | `hsl(0, 58%, 64%)` | Red Theme Highlight |
| **Red Shadow** | ![#892424](Colors/red_shadow.svg) | `#892424` | `rgba(137, 36, 36, 1.00)` | `hsl(0, 58%, 34%)` | Red Theme Shadow |

---

### 1.2 Neumorphic Shadow Modifiers (SwiftUI)

Use the following `ViewModifier` to extrude or recess vector shapes dynamically.

```swift
import SwiftUI

struct NeumorphicModifier: ViewModifier {
    var isPressed: Bool
    var theme: FidgetTheme // .white, .grey, .red
    var cornerRadius: CGFloat = 16

    func body(content: Content) -> some View {
        let background = theme.backgroundColor
        let highlight = theme.highlightColor
        let shadow = theme.shadowColor

        if isPressed {
            // Recessed (Pressed/Debossed) State
            content
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(shadow, lineWidth: 3)
                        .blur(radius: 3)
                        .offset(x: 1.5, y: 1.5)
                        .mask(RoundedRectangle(cornerRadius: cornerRadius).fill(LinearGradient(colors: [shadow, Color.clear], startPoint: .topLeading, endPoint: .bottomTrailing)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(highlight, lineWidth: 3)
                        .blur(radius: 3)
                        .offset(x: -1.5, y: -1.5)
                        .mask(RoundedRectangle(cornerRadius: cornerRadius).fill(LinearGradient(colors: [Color.clear, highlight], startPoint: .topLeading, endPoint: .bottomTrailing)))
                )
        } else {
            // Extruded (Raised/Embossed) State
            content
                .background(background)
                .shadow(color: shadow, radius: 8, x: 6, y: 6)
                .shadow(color: highlight, radius: 8, x: -6, y: -6)
        }
    }
}
```

---

## 2. Core Architecture & Managers

We enforce a strict **MVVM-M** (Model-View-ViewModel-Manager) structure to decouple gesture handlers from physical hardware pipelines.

### 2.1 Haptics Interface (`HapticsManager.swift`)
Handles core-level transient and continuous haptics.
*   **Location:** `hapticle/Hapticle/Managers/HapticsManager.swift`
*   **API Specification:**
    ```swift
    class HapticsManager {
        static let shared = HapticsManager()
        private var engine: CHHapticEngine?

        func playTransient(intensity: Float, sharpness: Float)
        func playContinuous(intensity: Float, sharpness: Float, duration: TimeInterval)
    }
    ```

### 2.2 Audio Interface (`SoundManager.swift`)
Handles ultra-low latency system sound triggers and real-time frequency modulation.
*   **Location:** `hapticle/Hapticle/Managers/SoundManager.swift`
*   **API Specification:**
    ```swift
    class SoundManager {
        static let shared = SoundManager()
        private var audioEngine: AVAudioEngine?
        private var pitchNode: AVAudioUnitTimePitch?

        func playSystemClick(soundID: SystemSoundID = 1104)
        func setContinuousPitch(factor: Float) // Range: -2400 to 2400 cents
        func stopContinuousSound()
    }
    ```

---

## 3. Fidget Blueprints (SOT for Coders)

This section maps the Figma designs to mathematical layouts, gesture bindings, and hardware feedback parameters.

### 3.1 The Pen (Retractable Button Fidget)

*   **Visual Layout Details:**
    - **Outer Barrel:** Vertical capsule (`Capsule()`), `Width: 120pt`, `Height: 360pt`.
    - **Well Recess:** Nested circular track (`Circle()`), `Diameter: 80pt`, positioned at the top of the barrel.
    - **Interactive Button:** Circle (`Circle()`), `Diameter: 72pt`. Extruded when extended, recessed when clicked. Shifting down `y = 8pt` in clicked state.
*   **State Machine:**
    ```
    [Extended] --(Touch Down)--> [Latching (Transient Click 1)]
    [Latching] --(Touch Up, Duration < 0.15s)--> [Retracted (Transient Click 2)]
    [Latching] --(Touch Up, Duration >= 0.15s)--> [Extended (Toggle Cancelled)]
    [Retracted] --(Touch Down)--> [Unlatching (Transient Click 1)]
    [Unlatching] --(Touch Up)--> [Extended (Transient Click 2)]
    ```
*   **Sensory Blueprint:**
    - **Click Down:** Haptic `intensity = 0.8`, `sharpness = 0.9` + Audio system sound `1104` (standard snap).
    - **Click Up (Latch Release):** Haptic `intensity = 0.7`, `sharpness = 0.8` + Audio system sound `1104`.
*   **Implementation Skeleton:**
    - View: `hapticle/Hapticle/Fidgets/Pen/PenView.swift`
    - Model: `hapticle/Hapticle/Fidgets/Pen/PenModel.swift`

---

### 3.2 The Dial (Rotary Detent Fidget)

*   **Visual Layout Details:**
    - **Safe Dial Plate:** Centered `Circle()`, `Diameter: 240pt`.
    - **Physical Detents:** Circular recesses (`Circle()`), `Diameter: 12pt`, placed uniformly at radius `r = 100pt` from center.
*   **Interaction & Feel:**
    - **Rotational Inertial Decay:** The dial acts like a heavy mechanical safe dial. Once the user lets go after a flick, it continues spinning and slowly decelerates due to simulated friction, giving the knob a physical weight.
    - **Fulcrum Leverage:** The rotational torque varies depending on where the user grabs the dial. Spinnings initiated close to the center feel stiff with zero leverage. Spinnings from the outer edge feel highly responsive and fluid.
    - **Detent Ticks:** Ticks are felt as the dial crosses $15^\circ$ angular intervals. As the speed increases, the detents should feel less like distinct knocks and more like a continuous vibration.
*   **Sensory Blueprint:**
    - **Detent Tick:** Haptic transient whose intensity scales with the spin speed (faster spin = slightly stronger click), `sharpness = 0.7`.
    - **Audio Loop:** Continuous sound pitched and amplified dynamically based on RPM (faster RPM = higher frequency mechanical whirr).
*   **Implementation Skeleton:**
    - View: `hapticle/Hapticle/Fidgets/Dial/DialView.swift`
    - Model: `hapticle/Hapticle/Fidgets/Dial/DialModel.swift`

---

### 3.3 The Ticket (Perforation Tear Fidget)

*   **Visual Layout Details:**
    - **Card Shell:** Extruded rectangular ticket (`RoundedRectangle(cornerRadius: 12)`), `Width: 280pt`, `Height: 420pt`.
    - **Perforation Line:** Horizontal series of small recessed circles (`Circle()`), `Diameter: 8pt`, spaced every `16pt` across width.
*   **Interaction & Feel:**
    - **Elastic Resistance:** Pulling the ticket down should feel like stretching a heavy rubber band—resistance builds up smoothly as displacement increases.
    - **Perforation Snaps:** During the pull, the user passes perforation line segments (spaced every `12pt` of displacement). Each boundary crossing should generate a distinct micro-snap, briefly dropping resistance to simulate paper fibers tearing.
    - **Separation Limit:** When pulled past `120pt`, the ticket breaks free with a complete drop in force, prompting the sheet to slide back.
*   **Sensory Blueprint:**
    - **Fiber Snap:** Micro-transient haptic `intensity = 0.3`, `sharpness = 0.4` to simulate paper popping.
    - **Separation Snap:** Strong impact transient `intensity = 1.0`, `sharpness = 0.8` + Audio tearing sound.
*   **Implementation Skeleton:**
    - View: `hapticle/Hapticle/Fidgets/Ticket/TicketView.swift`
    - Model: `hapticle/Hapticle/Fidgets/Ticket/TicketModel.swift`

---

### 3.4 The Magnet (Field Orbitals Fidget)

*   **Visual Layout Details:**
    - **Magnet Ring:** Circular track, `Diameter: 260pt`.
    - **Fixed Nodes:** 8 circular nodes, `Diameter: 24pt`, placed every $45^\circ$ along the ring. Alternating colors indicate polar charges.
    - **Free Puck:** Extruded circular puck, `Diameter: 48pt`, following the drag gesture with elastic lag.
*   **Interaction & Feel:**
    - **Elastic Spring Lag:** The puck does not lock directly to the finger coordinate; it lags behind with a springy, weighted connection, creating a sense of mass and drag.
    - **Push-Pull Fields:** Moving around the ring, the puck experiences alternating attractive and repulsive forces from the poles. Moving near a node snaps the puck into place, while moving past opposite poles creates small bounces.
    - **Tug Breakaway:** To break the orbital snap, the user must pull their finger away until the elastic tension overcomes the magnetic attraction, triggering a quick breakaway release.
*   **Sensory Blueprint:**
    - **Orbit Hum:** Continuous continuous haptic. Intensity scales with magnetic force/tension.
    - **Node Lock-on Snap:** Sharp transient haptic `intensity = 0.8`, `sharpness = 0.6`.
*   **Implementation Skeleton:**
    - View: `hapticle/Hapticle/Fidgets/Magnet/ MagnetView.swift`
    - Model: `hapticle/Hapticle/Fidgets/Magnet/MagnetModel.swift`

---

### 3.5 The Blob (Viscous Mitosis Fidget)

*   **Visual Layout Details:**
    - **Soft Body Shape:** Deformable vector path built using 8 radial control points, dynamically recalculating curves based on stretch vector.
    - **Background Grid:** Grid lines warp slightly toward the center-mass coordinates of the blob.
*   **Interaction & Feel:**
    - **Viscous Fluid Friction:** Dragging the blob should feel like stretching sticky jelly or slime—there is a thick, slow resistance that increases the faster or further it is stretched.
    - **Elongated Mitosis:** As the user stretches the shape past `180pt`, the blob thins out at the center and splits into two independent blobs with spring-back recoil centroid shifts.
*   **Sensory Blueprint:**
    - **Stretch Resistance:** Continuous rumble. Intensity scales with the stretch tension.
    - **Mitosis Pop:** Custom transient `intensity = 0.9`, `sharpness = 0.2` (dull, organic pop/suction sound) + Audio pop.
*   **Implementation Skeleton:**
    - View: `hapticle/Hapticle/Fidgets/Blob/BlobView.swift`
    - Model: `hapticle/Hapticle/Fidgets/Blob/BlobModel.swift`

---

## 4. watchOS Adaptation

Due to the absence of `CoreHaptics` on Apple Watch, developers must replicate these behaviors inside `Hapticle Watch App/` using WatchKit's native feedback engines:

*   **Rotary detents:** Map crown rotation updates (`digitalCrownRotation`) to `WKInterfaceDevice.current().play(.click)`.
*   **Impact transients:** Replicate snaps (Pen click, Ticket break, Magnet lock) with `WKInterfaceDevice.current().play(.directionUp)` or `WKInterfaceDevice.current().play(.failure)`.
*   **Continuous rumbles:** Map stretching actions to repeated pulses using `.retry` or `.directionDown`.

---

## 5. Appendix: Physics Simulation References (Optional / Non-1:1)

For developers looking to implement numerical approximations of the physical sensations, refer to the formulas below. Note that these are reference models and do not need to be modeled 1:1; coding the "feel" and interactive timing is the priority.

### 5.1 Dial Physics (Momentum & Leverage)
*   **Leverage Torque ($M_t$):** For dial center $\mathbf{C} = (x_c, y_c)$ and touch $\mathbf{P} = (x, y)$:
    $$r = \|\mathbf{P} - \mathbf{C}\|$$
    $$M_t = \begin{cases} 0 & \text{if } r < 20pt \\ \frac{r - 20}{100} & \text{if } 20 \le r \le 120pt \\ 1 & \text{if } r > 120pt \end{cases}$$
*   **Decay & Detents:**
    $$\theta_{t+1} = \theta_t + \omega_t \Delta t, \quad \omega_{t+1} = \omega_t \cdot (1 - \mu M_t) \quad (\mu \approx 0.05)$$
    $$k = \lfloor \theta / 15^\circ \rfloor \quad (\text{Fire transient when } k_{t} \neq k_{t-1})$$

### 5.2 Ticket Physics (Spring Tension)
*   **Elastic Resistance Force ($F_{res}$):** For displacement $y$:
    $$F_{res} = k_{elastic} \cdot y \quad (k_{elastic} \approx 2.0)$$
*   **Perforation Snaps:** Dropping resistance by $40\%$ at intervals of $12pt$.

### 5.3 Magnet Physics (Coulomb Fields)
*   **Puck Lagrangian Spring:**
    $$\mathbf{F}_{spring} = -k_{spring} \cdot (\mathbf{P}_{puck} - \mathbf{P}_{finger})$$
*   **Magnetic Forces (Coulomb Attraction/Repulsion):** Alternating charges $q_i \in \{-1, 1\}$:
    $$\mathbf{F}_{mag, i} = C_{coulomb} \cdot \frac{q_{free} \cdot q_i}{\|\mathbf{P}_{puck} - \mathbf{P}_{fixed, i}\|^2 + \epsilon} \cdot \hat{\mathbf{u}}_i$$

### 5.4 Blob Physics (Tension & Centroids)
*   **Stretch Metric ($T$):**
    $$T = \|\mathbf{P}_{finger} - \mathbf{P}_{anchor}\|$$
*   **Mitosis Centroids (Split at $T > 180pt$):**
    $$\mathbf{C}_1 = \mathbf{P}_{anchor} + \frac{\mathbf{r}}{4}, \quad \mathbf{C}_2 = \mathbf{P}_{finger} - \frac{\mathbf{r}}{4}$$

---
*Developers should refer directly to [hapticle/Documentation/TDD.md](file:///Users/moreno_m5/Projects/hapticle/Documentation/TDD.md) for full manager implementations, and execute layout alignments in accordance with the [Figma design specs](https://www.figma.com/design/cRjdjva7DCcEfmy2M9u2My/Hapticle-Mid-fi?node-id=1-4&t=pTGScvGNydCUxVjF-1).*
