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
