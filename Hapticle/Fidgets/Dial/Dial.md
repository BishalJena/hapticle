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

---

## 5. Advanced Physical Simulation & Detent Modeling

Implementing tunable **Mass (Moment of Inertia)**, **Virtual Spring Touch Coupling**, and **Equilibrium Detent Wells** creates a highly immersive simulation. By adjusting these physical parameters, we can replicate multiple real-world devices (from free-spinning combination safes to ratcheting CNC encoders).

### 5.1 The Physics Model

We define the following tunable parameters inside `DialModel`:
*   $m$ (**Dial Mass**): Represents the simulated mass of the dial. Since the dial is a disc, its Moment of Inertia is:
    $$I = \frac{1}{2} m R^2$$
    where $R$ is the dial radius ($155\text{ pt}$).
*   $c$ (**Rotational Damping/Friction**): Damps the velocity continuously.
*   $k_{spring}$ (**Touch Coupling Spring Constant**): Connects the dial's physical angle to the user's touch angle.
*   $T_{detent}$ (**Detent Torque Strength**): The peak force pulling the dial into the nearest tick mark.
*   $N_{detents}$ (**Detent Count**): Number of ticks per full rotation (default: 24, spacing: $\Delta\theta = \frac{2\pi}{N_{detents}}$).

### 5.2 Equations of Motion

At each timestep $dt$ inside our update loop, we compute the torques acting on the dial:

1.  **Touch Torque ($\tau_{touch}$):**
    During a drag gesture, we model the link between the finger angle $\theta_{finger}$ and the dial angle $\theta$ as a virtual torsion spring:
    $$\tau_{touch} = \begin{cases} 
      k_{spring} \cdot (\theta_{finger} - \theta) & \text{if dragging} \\
      0 & \text{if released}
    \end{cases}$$
    *   *Note:* If Mass is high, the dial lag feels heavy and authentic. If Mass is low or Spring is infinite, it snaps directly to the touch.
2.  **Detent Restoring Torque ($\tau_{detent}$):**
    Detents are represented as sinusoidal potential energy wells. The restoring torque pulls the dial toward the nearest equilibrium index:
    $$\tau_{detent} = -T_{detent} \cdot \sin(N_{detents} \cdot \theta)$$
    This torque is zero exactly at the detent centers (stable) and halfway between them (unstable), pulling the dial back to a tick.
3.  **Friction Damping Torque ($\tau_{friction}$):**
    $$\tau_{friction} = -c \cdot \omega$$

The net torque $\tau_{net}$ yields the angular acceleration $\alpha$:
$$\tau_{net} = \tau_{touch} + \tau_{detent} + \tau_{friction}$$
$$\alpha = \frac{\tau_{net}}{I}$$

Using Euler-Cromer integration, we update velocity and position:
$$\omega_{t+1} = \omega_t + \alpha \cdot dt$$
$$\theta_{t+1} = \theta_t + \omega_{t+1} \cdot dt$$

### 5.3 Preset Configurations

By adjusting $m$, $T_{detent}$, and $c$, we can instantly switch modes in the app:

| Encoder Preset | Mass ($m$) | Damping ($c$) | Detent Torque ($T_{detent}$) | Spacing ($N_{detents}$) | Behavior Description |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Heavy Combination Safe** | High | Low | Very Low (or $0$) | 100 | Spins freely for a long time; heavy momentum; clicks are purely sensory. |
| **Ball Detent Encoder** | Low-Med | Medium | High | 24 | Strong physical detents; clicks into place, bounces slightly in the wells; can be flicked past multiple notches. |
| **Ratcheting CNC Wheel** | Very Low | High | Very High | 60 | No momentum; stops instantly in the next notch; ticks grip the wheel tightly. |

---

## 6. Architectural Philosophy: Coupled vs. Decoupled Physics & Sensory Synthesis

You are completely right: **procedural haptics and sound are technically part of the physics simulation itself**. If we treat them as decoupled reactive systems (e.g. listening to angle changes asynchronously), we introduce latency and lose state coherency, which ruins high-fidelity physical feedback.

To merge the clean architecture of MVVM-M with zero-latency physical rendering, we will utilize the **"Physical Readout Model"**.

### 6.1 The Problem with Extreme Decoupling
*   **Latency Spikes:** Sending an event from `DialModel` $\rightarrow$ `HapticsManager` $\rightarrow$ system drivers introduces a $5\text{--}15\text{ms}$ phase delay. At high rotational speeds (high RPM), a click that triggers after the boundary is crossed feels disconnected from the visual ticks on screen.
*   **Lack of State Coherency:** Procedural sounds (like a friction whirr or spring hum) are not discrete events. They are continuous signals where:
    *   $\text{AudioAmplitude}(t) \propto \text{FrictionForce}(t)$ or $\omega(t)$
    *   $\text{AudioFrequency}(t) \propto \text{RotationalSpeed}(t)$
    If the physics model doesn't compute these directly, the sound generator has to run its own duplicate math to approximate them, causing divergence.

### 6.2 The Solution: The "Physical Readout Model"

We treat the managers (`HapticsManager` and `SoundManager`) as **dumb actuators/renderers** (analogous to how a GPU renders raw vertex data). The physics loop owns the mathematical truth and outputs a unified frame state struct at each timestep:

```swift
struct FidgetPhysicsState {
    let position: Double        // Current angle θ
    let velocity: Double        // Angular speed ω
    let acceleration: Double    // Net α
    let activeTorque: Double    // Total force applied
    let detentForce: Double     // Instaneous restoring pull
    let crossedDetent: Bool     // Discrete tick crossing flag
    let detentIndex: Int        // Index of current detent
}
```

### 6.3 Frame-by-Frame Actuation Pipeline

During each update frame inside the `CADisplayLink` loop:

```
[Touch Input] 
     │
     ▼
[DialModel Physics Loop] (Computes equations of motion)
     │
     ├─► Generates FidgetPhysicsState struct
     │
     ├─► [SoundManager] (Modulates sine wave frequency based on state.velocity)
     │
     ├─► [HapticsManager] (Triggers transient vibe with intensity proportional to state.detentForce)
     │
     └─► [DialView] (Renders rotation transformation using state.position)
```

1.  **Pure Mathematics Isolation:** `DialModel` has zero dependencies on `CoreHaptics` or `AVFoundation`. It only computes pure mathematical variables and packs them into `FidgetPhysicsState`. This keeps the model 100% testable on any platform (including command-line unit tests).
2.  **Synchronous Actuation:** The view, sound engine, and haptic engine are updated synchronously inside the same frame step. The haptic pulse and whirr pitch are calculated directly from `PhysicsState` variables, ensuring **zero phase lag**.
3.  **Procedural Whirr:** The whirring frequency is directly bound to `state.velocity`, and click sound/haptic intensity is bound to `state.detentForce`. As a result, the physical sensation feels organic, heavy, and responsive.

---

## 7. Acoustics & Psychoacoustics of Procedural Clicks

A "click" is not a simple static sound event. To build a premium tactile engine, we synthesize clicks procedurally by modeling the **physics of wave impulses** and how the human brain processes repetitive acoustic transients.

### 7.1 What is a "Click" mathematically?

In signal processing:
1.  **The Unit Impulse (Dirac Delta):** A single sample spike in a quiet digital stream. An impulse contains **all frequencies at equal amplitude** (a flat spectrum, similar to white noise but compressed into a single instant). In a speaker, this spike excites the physical cone's natural resonance, causing a "pop" or "click".
2.  **The Damped Tonal Resonator:** In mechanical reality, a click (like a spring tooth sliding off a gear) is a collision that triggers a localized high-frequency vibration, which decays exponentially. We model this as a **damped sine wave**:
    $$x(t) = A \cdot e^{-\lambda t} \sin(2\pi f_0 t)$$
    where:
    *   $A$ is the **Initial Amplitude** (proportional to the impact speed/force).
    *   $\lambda$ is the **Decay Rate** (controls damping; a high $\lambda$ creates a tight "tick", a low $\lambda$ creates a metallic ringing "ping").
    *   $f_0$ is the **Carrier Frequency** (controls timbre; $2000\text{ Hz}$ represents plastic click, $800\text{ Hz}$ wood case resonance, and $150\text{ Hz}$ low-end mechanical thud).

### 7.2 Frequency Layering for Physical Realism

To prevent clicks from sounding synthetic ("synthetic beeps"), we synthesize them by layering three frequency bands:

```
                  ┌──► [High-Freq Transient] (2.5 kHz, rapid decay)  ──► Sharp contact point
                  │
[Detent Trigger] ─┼──► [Mid-Freq Case Resonator] (900 Hz, med decay) ──► Dial structure volume
                  │
                  └──► [Low-Freq Thud] (120 Hz, heavy decay)         ──► Mass and weight
```

*   **Wave Synthesis Formula:**
    $$Waveform(t) = e^{-\lambda_{high} t} \sin(2\pi f_{high} t) \cdot w_1 + e^{-\lambda_{mid} t} \sin(2\pi f_{mid} t) \cdot w_2 + \text{Noise}(t) \cdot e^{-\lambda_{noise} t} \cdot w_3$$
    where $w_1, w_2, w_3$ are weights determining the physical material of the dial (e.g. metal vs. plastic).

### 7.3 Rate Repetition & Psychoacoustic Pitch Shifts

As the dial's rotation speed increases, the repetition rate of the clicks ($f_{rep}$) increases. This creates two distinct physical and psychoacoustic shifts:

1.  **Click Repetition Pitch (Pulse Train Transition):**
    *   At low speeds ($f_{rep} < 20\text{ Hz}$), the human brain hears clicks as **discrete events**: *tick... tick... tick*.
    *   At high speeds ($f_{rep} > 20\text{ Hz}$), the brain's temporal resolution limit is crossed. The individual clicks blend together, and the brain perceives a **continuous pitched tone** (a whirr or buzz). The fundamental pitch of this tone is *exactly* the repetition rate:
        $$f_{fundamental} = f_{rep} = \frac{\text{clicks}}{\text{second}}$$
        *This is not a psychological trick; it is a physical reality.* Periodic repetition of short impulses mathematically transforms the spectrum, concentrating energy into harmonics of the repetition frequency.
2.  **Impact Brightening (Velocity Frequency Scaling):**
    *   When the dial spins faster, the physical collision force is stronger and shorter. 
    *   To model this, we scale the **carrier frequencies** of the individual clicks based on the rotational velocity:
        $$f_{high}(t) = f_{base} + k_{velocity} \cdot |\omega(t)|$$
    *   As a result, individual clicks physically become **brighter and higher-pitched** when flicked quickly, mimicking the increased kinetic energy of the mechanical impact.




