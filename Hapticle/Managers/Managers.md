# Hapticle Sensory Managers Specification (Managers.md)

This log documents the technical architecture and implementation details of the shared sensory feedback managers: **HapticsManager** and **SoundManager** located under [Hapticle/Managers/](file:///Users/moreno_m5/Projects/hapticle/Hapticle/Managers/).

These managers act as **direct actuators/renderers** (similar to a GPU rendering raw draw calls). They hold zero physical state, perform no mechanical simulation, and carry no view references. Instead, they expose a clean, low-latency API to play transient clicks, trigger continuous feedback, and generate pitch-modulated sound whirrs.

---

## 1. Haptics Actuator System (HapticsManager.swift)

[HapticsManager.swift](file:///Users/moreno_m5/Projects/hapticle/Hapticle/Managers/HapticsManager.swift) implements a dual-engine architecture to ensure crisp feedback on physical iOS devices while maintaining compatibility inside Xcode Simulators.

### 1.1 CoreHaptics Engine (Physical Devices)
For devices supporting the Taptic Engine, the manager initializes a `CHHapticEngine` and coordinates two types of events:
1.  **Transient Clicks (`playClick`):**
    *   Synthesizes a crisp `.hapticTransient` event at the requested intensity and sharpness.
    *   **Throttling & Rate-Limiting:** Incorporates a strict **30ms click throttle** (~33.3Hz max) using `CACurrentMediaTime()` to drop extra clicks and prevent CoreHaptics engine rate-limit drops (`error -4805`).
    *   **Auto-Restart:** Safely checks `isEngineRunning` before starting and restarts the engine if it was stopped asynchronously.
2.  **Continuous Rumble (`startContinuousFeedback` / `updateContinuousFeedback`):**
    *   Synthesizes a continuous texture (`.hapticContinuous`) using `CHHapticAdvancedPatternPlayer` with a base duration of 100 seconds.
    *   **Dynamic Parameter Control:** Updates LRA amplitude (`.hapticIntensityControl`) and frequency (`.hapticSharpnessControl`) dynamically on the active player.
    *   **Auto-Invalidation Recovery:** If parameter updates fail (due to backgrounding or engine suspension), the manager invalidates the reference (`continuousPlayer = nil`), forcing a clean recreation on the next frame.
    *   **Mute Modulation:** To avoid expensive player creation overhead, the physics loop keeps the player running during active states and simply modulates its intensity to `0.0` to mute it, stopping it completely only when the fidget settles.

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
*   **On-Demand Laziness:** The engine and nodes are only started when active whirring begins (`volume > 0.0`) and are fully paused/stopped when rotation ceases, saving battery and CPU.

---

## 3. Decoupled Architecture

The physics loops (like `DialModel`'s `CADisplayLink` updates) calculate all mechanical characteristics, frequencies, and transition factors locally. They call the managers directly via stateless, decoupled methods:

```swift
// Triggered inside DialModel's stepPhysics loop
if alpha < 1.0 {
    HapticsManager.shared.playClick(intensity: clickIntensity, sharpness: baseHapticSharpness)
    SoundManager.shared.playSystemClick()
}

if speed > 0.05 {
    HapticsManager.shared.startContinuousFeedback(intensity: whirrIntensity, sharpness: whirrSharpness)
    SoundManager.shared.startOscillator(frequency: f_rep * 4.0, volume: whirrVolume)
} else {
    HapticsManager.shared.startContinuousFeedback(intensity: 0.0, sharpness: 0.0)
    SoundManager.shared.stopOscillator()
}
```

This keeps the manager codebase extremely simple, clean, and 100% focused on direct hardware actuation.

---

## 4. Fidget Modularity & Timbre Mapping

The managers are fully equipped to support the remaining four fidgets (Pen, Ticket, Magnet, Blob) by mapping physical states to generic parameters.

| Fidget | Physical Event | Actuator Pipeline | Dynamic Parameter Mapping |
| :--- | :--- | :--- | :--- |
| **The Pen** | Latch Click Down / Release Up | Transient Click (`playClick`) | Stiff high-intensity transient on click down, slightly lower-sharpness click on release. |
| | Slide Friction along Track | Continuous Rumble (`startContinuousFeedback`) | Damping resistance mapped to touch drag speed. |
| **The Ticket** | Perforation Snap (12pt steps) | Transient Clicks (`playClick`) | Low-intensity, high-repetition ticks as fibers yield. |
| | Tear-off Release (12pt final) | Transient Click (`playClick`) | Stiff, high-intensity pop click. |
| **The Magnet** | Center Orbit Rotation | Continuous Rumble (`startContinuousFeedback`) | Magnetic attraction/repulsion hum. Volume/Intensity $\propto \frac{1}{\text{distance}}$. |
| | Pole Lock (attract snap) | Transient Click (`playClick`) | High-intensity, low-sharpness metallic snap-to-pole. |
| **The Blob** | Jelly Drag Stretch | Continuous Rumble (`startContinuousFeedback`) | Damping rumble representing fluid viscosity. Rumble intensity $\propto \text{stretch distance}$. |
| | Mitosis Division Pop | Transient Click (`playClick`) | Bubble-burst pop (high intensity, low sharpness). |

---

## 5. Developer API Quick Reference

### 5.1 Transient Clicks
```swift
// Intensity: 0.0 ... 1.0, Sharpness: 0.0 ... 1.0
HapticsManager.shared.playClick(intensity: 0.6, sharpness: 0.5)

// System crown click sound
SoundManager.shared.playSystemClick()
```

### 5.2 Continuous Rumble (Friction & Hum)
```swift
// Start or update continuous vibration texture
HapticsManager.shared.startContinuousFeedback(intensity: 0.3, sharpness: 0.2)

// Stop or mute continuous vibration
HapticsManager.shared.stopContinuousFeedback()
```

### 5.3 Continuous Audio whirr (Fidget Pitch Oscillator)
```swift
// Start procedural oscillator at specific pitch and volume
SoundManager.shared.startOscillator(frequency: 220.0, volume: 0.1)

// Stop oscillator synthesis
SoundManager.shared.stopOscillator()
```
