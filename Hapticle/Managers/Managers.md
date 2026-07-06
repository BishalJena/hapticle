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

To make implementation as simple as possible, the managers support two levels of integration depending on your fidget's complexity. **You do not need a complex physics engine or state tracking for simple fidgets (like the Pen or the Blob).**

---

### 5.1 Level 1: The Simple One-Line API (Recommended for Pen, Blob, and Magnet)

If your fidget only needs simple, discrete taps (like clicking the Pen button, splitting the Blob, or locking a Magnet pole), you can trigger haptics and sounds with **single-line calls directly inside your gesture handlers or tap actions**.

#### A. Triggering Clicks (Discrete Events)
For a button press, snap, or release:
```swift
// Trigger a crisp transient click (intensity: 0.0 to 1.0, sharpness: 0.0 to 1.0)
HapticsManager.shared.playClick(intensity: 0.6, sharpness: 0.5)

// Trigger the native digital-crown physical click sound
SoundManager.shared.playSystemClick()
```
*Use case: Trigger this on Pen button down/up, Blob mitosis split, or Magnet pole lock.*

#### B. Triggering Simple Friction (Continuous Textures)
If you want a simple texture or rumble while dragging an object:
```swift
// In your drag gesture on-changed: start or update the continuous texture
HapticsManager.shared.startContinuousFeedback(intensity: 0.3, sharpness: 0.2)

// In your drag gesture on-ended: stop the texture immediately
HapticsManager.shared.stopContinuousFeedback()
```
*Use case: Start rumble when stretching the Blob or sliding the Pen along its track; stop it when the finger is released.*

---

### 5.2 Level 2: The Advanced Physics-Bound API (Only for Dial & High-Speed Scrolling)

This level is **only necessary** if your fidget is a high-speed free-spinning element (like the safe Dial) that needs real-time frequency-modulated whirrs and haptic cross-fades above $20\text{ Hz}$.

If your fidget requires this:
1.  Package your physical speed and state into `FidgetPhysicsState` every frame inside your `CADisplayLink` loop.
2.  Pass it to the managers to let them calculate instantaneous frequency ($f_{rep}$) and handle the cross-fade:

```swift
// Inside your model's frame step update loop:
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

### 5.3 Developer Best Practices
*   **Keep simple things simple:** Do not write a `CADisplayLink` or compute angular frequency for the Pen or the Blob. Just use the Level 1 **One-Line API** inside your standard SwiftUI gestures.
*   **Clean Up Damping:** Always ensure you call `HapticsManager.shared.stopContinuousFeedback()` and `SoundManager.shared.stopOscillator()` when a gesture ends, otherwise the phone will vibrate endlessly.
*   **Prepare/Pre-Warm:** Both managers automatically pre-warm and handle fallbacks for the Xcode Simulator, so you can test your view code safely in Xcode Previews.


