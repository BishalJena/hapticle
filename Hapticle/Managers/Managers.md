# Hapticle Sensory Managers Specification (Managers.md)

This log documents the technical architecture and implementation details of the shared sensory feedback managers: **HapticsManager** and **SoundManager** located under [Hapticle/Managers/](file:///Users/moreno_m5/Projects/hapticle/Hapticle/Managers/).

These managers act as **actuators/renderers** (similar to a GPU rendering vertex streams). They hold zero physical state, perform no mechanical simulation, and carry no view references. Instead, they receive a unified physical state snapshot at each frame step and translate the raw numbers into low-latency hardware outputs.

---

## 1. Haptics Actuator System (HapticsManager.swift)

[HapticsManager.swift](file:///Users/moreno_m5/Projects/hapticle/Hapticle/Managers/HapticsManager.swift) implements a dual-engine architecture to ensure crisp feedback on physical iOS devices while maintaining compatibility inside Xcode Simulators.

### 1.1 CoreHaptics Engine (Physical Devices)
For devices supporting the Taptic Engine, the manager initializes a `CHHapticEngine` and coordinates two types of events:
1.  **Transient Clicks (`.hapticTransient`):**
    *   Triggered when the dial crosses a detent boundary.
    *   **Intensity & Sharpness:** Dynamically scaled by the collision velocity ($I \propto |\omega|$ and $S = S_{base} + k_s \cdot |\omega|$).
2.  **Continuous Rumble (`.hapticContinuous`):**
    *   Synthesized using `CHHapticAdvancedPatternPlayer` during fast rotation phases.
    *   **Dynamic Parameter Updates:** On each frame step, the physics loop updates LRA parameters on the fly using `.sendParameters([intensityParam, sharpnessParam], atTime: 0)`. This alters LRA amplitude and vibration frequency in real time.

### 1.2 UIKit Fallback System (Simulators & Older Hardware)
Since the Xcode iOS Simulator and some older devices do not support custom `CHHapticPattern` playback:
*   The manager detects capability availability via `CHHapticEngine.capabilitiesForHardware().supportsHaptics`.
*   If unsupported, it falls back to standard UIKit generators:
    *   **Selection Tick:** `UISelectionFeedbackGenerator` (for low-intensity ticks).
    *   **Medium Click:** `UIImpactFeedbackGenerator(style: .medium)`.
    *   **Heavy Impact:** `UIImpactFeedbackGenerator(style: .heavy)`.
*   These fallback engines are pre-warmed via `.prepare()` during initialization to minimize lag.

---

## 2. Low-Latency Audio Synthesizer (SoundManager.swift)

[SoundManager.swift](file:///Users/moreno_m5/Projects/hapticle/Hapticle/Managers/SoundManager.swift) provides dual audio pipelines to support discrete impact clicks and continuous rotational whirrs.

### 2.1 Low-Latency Mechanical Clicks
For discrete clicks, rather than playing static wav/mp3 files (which require file decoding and introduce buffer-loading latency):
*   Uses Apple's low-latency System Sound Services: `AudioServicesPlaySystemSound(1104)`.
*   **System Sound ID 1104** is the iOS system-level sound for the Apple Watch Digital Crown rotation and selector scroll ticks. It triggers instantly on the hardware's fast-path audio channel.

### 2.2 Procedural Audio Synthesizer (Oscillator Whirr)
To generate continuous mechanical whirrs during rapid rotation:
*   Initializes an **`AVAudioEngine`** and attaches a custom **`AVAudioSourceNode`** (running at $44.1\text{ kHz}$ standard sample rate).
*   **Waveform Generation:** The rendering block synthesizes a sine wave sample-by-sample:
    $$Waveform(t) = \sin(\phi) \cdot \text{Volume}$$
    where the phase step is updated at each sample frame:
    $$\Delta\phi = \frac{2\pi \cdot f_{rep}}{SampleRate}$$
*   **Real-Time Frequency Modulation:** When the dial spins faster, the physics engine updates `currentFrequency` (Hz) and `currentVolume`. The audio node immediately synthesizes the new frequency on the next audio buffer block with zero phase clicks.

---

## 3. Decoupled Frame Update Architecture

Every frame, the active Fidget Model computes its physics updates and calls the managers synchronously:

```swift
// Triggered inside DialModel's CADisplayLink step update
let state = FidgetPhysicsState(
    position: rotationAngle,
    velocity: angularVelocity,
    torque: netTorque,
    crossedDetent: crossedBoundary,
    detentIndex: currentIndex
)

HapticsManager.shared.update(with: state, model: self)
SoundManager.shared.update(with: state, model: self)
```

By computing Hz ($f_{rep} = \frac{|\omega| \cdot N_{detents}}{2\pi}$) and fading the signals dynamically based on this frequency, the managers ensure that visual rotation, tactile buzz, and audio whirr remain perfectly in phase at all speeds.

---

## 4. Fidget Modularity & Material Timbre Presets

The managers are built to be **highly modular** and are fully equipped to support the remaining four fidgets (Pen, Ticket, Magnet, Blob) by mapping physical states to generic parametric parameters.

### 4.1 Fidget-to-Manager Mapping

| Fidget | Physical Event | Actuator Pipeline | Dynamic Parameter Mapping |
| :--- | :--- | :--- | :--- |
| **The Pen** | Latch Click Down / Release Up | Transient Click (`playClick`) | Stiff high-intensity transient on click down, slightly lower-sharpness click on release. |
| | Slide Friction along Track | Continuous Rumble (`updateContinuous`) | Damping resistance mapped to touch drag speed. |
| **The Ticket** | Perforation Snap (12pt steps) | Transient Clicks (`playClick`) | Low-intensity, high-repetition ticks as fibers yield. |
| | Tear-off Release (12pt final) | Transient Click (`playClick`) | Stiff, high-intensity pop click. |
| | Tearing card fibers | Audio Impulse Burst | Rapid, randomized click impulses mimicking ripping paper. |
| **The Magnet** | Center Orbit Rotation | Continuous Rumble (`updateContinuous`) | Magnetic attraction/repulsion hum. Volume/Intensity $\propto \frac{1}{\text{distance}}$. |
| | Pole Lock (attract snap) | Transient Click (`playClick`) | High-intensity, low-sharpness metallic snap-to-pole. |
| **The Blob** | Jelly Drag Stretch | Continuous Rumble (`updateContinuous`) | Damping rumble representing fluid viscosity. Rumble intensity $\propto \text{stretch distance}$. |
| | Mitosis Division Pop | Transient Click (`playClick`) | Bubble-burst pop (high intensity, low sharpness). |

### 4.2 Supporting Material Timbres
To prevent all fidgets from sounding like the metal dial casing, the managers will support **Timbral Material Presets** using a generic `Material` enum:
```swift
enum FidgetMaterial {
    case metal      // High sharpness, low damping, resonant (Dial, Pen latch)
    case plastic    // Medium-high sharpness, medium decay (Pen casing)
    case paper      // Low sharpness, high decay, high friction (Ticket tearing)
    case organic    // Very low sharpness, high damping (Blob viscous squelches)
}
```
Expanding the managers with this enum allows the audio oscillators and LRA haptic players to scale their base frequencies and decay envelopes ($f_0$, $\lambda$, $t_{decay}$) dynamically—ensuring a unique, physically cohesive identity for each of the five fidgets.

---

## 5. Developer Integration Guide (For Coders)

This section provides a concrete, step-by-step integration guide for coders implementing new fidget elements (Pen, Ticket, Magnet, Blob) to connect them to the shared haptic and audio pipelines.

### 5.1 Step 1: Declare the State Model
In your fidget’s physics model (e.g. `PenModel.swift`), declare the mechanical properties needed to track motion. Ensure you publish states to SwiftUI views and maintain internal variables for speed calculations:

```swift
class PenModel: ObservableObject {
    @Published var dragOffset: CGFloat = 0.0      // Current finger position along track
    @Published var isPressed: Bool = false        // Button touch state
    
    // Physical simulation states
    var velocity: Double = 0.0
    var isLatched: Bool = false
    
    // Core parameters (Exposed to Debug Control Panel)
    var springConstant: Double = 120.0
    var frictionCoefficient: Double = 2.5
    var mass: Double = 0.15
}
```

### 5.2 Step 2: Formulate the Physics Frame Update
Initialize a frame-synchronous loop (such as `CADisplayLink` or a high-frequency `Timer`). On each physics tick ($dt$):
1.  Calculate total net force $\Sigma F$ acting on the fidget (incorporating touch elastic springs, friction damping, detent blocks, and collisions).
2.  Compute acceleration $a = \frac{\Sigma F}{m}$.
3.  Integrate velocity and position: $v_{t+1} = v_t + a \cdot dt$ and $x_{t+1} = x_t + v_{t+1} \cdot dt$.
4.  Package these physical variables into the shared `FidgetPhysicsState` struct and notify the managers.

Here is a standard update block:

```swift
func stepPhysics(dt: Double) {
    // 1. Calculate physical forces
    let springForce = isPressed ? springConstant * Double(15.0 - dragOffset) : 0.0
    let dampingForce = -frictionCoefficient * velocity
    let netForce = springForce + dampingForce
    
    // 2. Integrate motion equations
    let acceleration = netForce / mass
    velocity += acceleration * dt
    dragOffset += CGFloat(velocity * dt)
    
    // 3. Detect discrete click collisions (e.g. hitting the bottom cap boundary at y = 8.0)
    var crossedBoundary = false
    if dragOffset >= 8.0 && !isLatched {
        isLatched = true
        crossedBoundary = true
        velocity = 0.0 // Hard collision stop
    }
    
    // 4. Pack and actuate
    let state = FidgetPhysicsState(
        position: Double(dragOffset),
        velocity: velocity,
        torque: netForce,
        crossedDetent: crossedBoundary,
        detentIndex: isLatched ? 1 : 0
    )
    
    // Notify sensory renderers
    actuateSensoryOutputs(with: state)
}
```

### 5.3 Step 3: Actuate Haptic and Sound Managers
In your actuation handler, calculate the frequency equivalent of the movement ($f_{rep}$) to determine the cross-fade factor ($\alpha$). Trigger transients and Continuous rumbles:

```swift
private func actuateSensoryOutputs(with state: FidgetPhysicsState) {
    let speed = abs(state.velocity)
    
    // 1. Translate velocity into an equivalent repetition frequency
    // (e.g. for Pen slide, 100pt per second = 10Hz crossing frequency)
    let f_rep = speed * 0.10
    
    // Calculate cross-fade parameter alpha
    let alpha = min(max((f_rep - 10.0) / 10.0, 0.0), 1.0)
    
    // 2. Handle Discrete Click Collisions (Discrete & Cross-Fade Domains)
    if alpha < 1.0 && state.crossedDetent {
        // High-velocity clicks feel sharper and stronger
        let intensity = 0.7 * (1.0 - alpha)
        let sharpness = 0.6 + 0.3 * (speed / 10.0)
        
        // Haptics Manager handles device transients or UIKit fallback
        HapticsManager.shared.playClick(intensity: intensity, sharpness: sharpness)
        
        // Sound Manager plays the low-latency crown tick click
        SoundManager.shared.playSystemClick()
    }
    
    // 3. Handle Continuous Sliding Friction (Cross-Fade & Continuous Domains)
    if alpha > 0.0 && speed > 0.05 {
        // Modulate continuous LRA rumble
        let intensity = min((speed / 12.0) * alpha * 0.35, 1.0)
        let sharpness = min(0.4 + 0.3 * alpha, 1.0)
        
        HapticsManager.shared.startContinuousFeedback(intensity: intensity, sharpness: sharpness)
        
        // Modulate procedural audio whirr/hum node
        let volume = Float(alpha * min(speed / 12.0, 1.0) * 0.06)
        let frequency = Float(f_rep * 3.0) // Scale frequency for the sliding pitch
        
        SoundManager.shared.startOscillator(frequency: frequency, volume: volume)
    } else {
        HapticsManager.shared.stopContinuousFeedback()
        SoundManager.shared.stopOscillator()
    }
}
```

### 5.4 Best Practices for Developers
*   **Decouple the view:** Never call `HapticsManager` or `SoundManager` from a SwiftUI View gesture closure. Keep them inside the physics loop of the `Model` to guarantee frame synchronization.
*   **Coordinate system consistency:** Ensure all speeds ($\omega$ or $v$) and forces ($\tau$ or $F$) mapped to haptic parameters are passed as **absolute values** (`abs()`). Actuators do not care about vector direction, only magnitude.
*   **Conservation of resources:** Always call `HapticsManager.shared.stopContinuousFeedback()` and `SoundManager.shared.stopOscillator()` when the fidget is static (`velocity == 0`), and invalidate your `CADisplayLink` loop to save battery.

