# Hapticle - Technical Report (TR)

**Team:** SMBBC (Super Mobile Button-Bashing Club)  
**Project:** Hapticle (Neumorphic Sensory Fidget Application)  
**Date:** July 5, 2026  

---

## 1. Executive Summary & Team Mission

**SMBBC** is a team of passionate fidgeters, designers, and developers. Our mission with **Hapticle** is to deeply explore the interactive capabilities, hardware sensor limits, and UI framework depth of iOS and watchOS. 

Instead of building a conventional functional utility, we designed an application centered around the tactile, auditory, and visual satisfaction of physical fidgeting. The core challenge of this project is to achieve a high degree of fidelity in physical sensation, recreating the satisfying mechanical feedback of real-world objects under strict resource and framework constraints.

---

## 2. Starting Assumptions & Redefining Haptics

### Initial Assumption
When planning Hapticle, we initially viewed haptic feedback (`CoreHaptics`) as a supplementary feature—a utilitarian notification tool (e.g., error vibration, success buzz) or a minor visual delight (e.g., button press reaction). We assumed that standard UI animations would carry the user experience, while basic iOS system vibrations would be sufficient to convey touch interactions.

### The Pivot
We quickly realized that relying on flat layouts with generic haptic impulses would result in a sterile and boring app. Fidgeting is intrinsically sensory, physical, and mechanical. If the tactile feedback was a mere afterthought, the app would fail to capture the subconscious draw of a real fidget toy. 

We decided to flip our design priority: **CoreHaptics would serve as the main staple and architectural foundation of the app**, driving the logic, visual timings, and audio synthesis, rather than reacting to them.

---

## 3. Exploration Log & Market Analysis

Before writing code, we performed a competitive evaluation of existing apps in the App Store, focusing on their strengths, shortcomings, and sensory implementation:

### 3.1 *Fidgetable*
*   **Observations:** Proved that there is a large, eager market for digital fidgeting applications on mobile and watch platforms.
*   **Key Deficiency:** The app focuses heavily on tactile responses but completely lacks an auditory experience. Sensory feedback feels incomplete; we noticed that without sound, the brain fails to trick itself into believing a physical object is being manipulated.
*   **Inspiration:** They successfully shipped a companion Apple Watch app, proving that users enjoy having fidget options on their wrists.

### 3.2 *NotBoring* Apps (NotBoring Weather, Calculator, etc.)
*   **Observations:** The *NotBoring* line of apps does not contain dedicated fidgets, yet they are incredibly satisfying to interact with.
*   **Key Success:** They achieve sensory excellence by tightly coupling **Tactile, Audio, and Visual feedback**. A button press isn't just a click; it's a dynamic visual compression, accompanied by a precise synth click and a matching haptic transient.
*   **Inspiration:** The "Sensory Trinity" (visual deformation + customized sound frequency + high-fidelity haptics) is the blueprint for true user delight.

### Our Strategy
We resolved to merge these findings. Hapticle takes the dedicated fidget-toy focus of *Fidgetable* and elevates it with the rich, synchronized, tri-sensory feedback loop pioneered by *NotBoring*.

| Competitor | Visuals | Audio | Tactile | Category | Target Experience |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Fidgetable** | Simple 2D | None | Medium | Fidget Toy | Purely tactile, silent |
| **NotBoring** | Premium 3D | Rich Synth | High-Fidelity | Utility Apps | Stylized tool micro-interactions |
| **Hapticle** | Neumorphic 3D | Real-time Synth | High-Fidelity | Fidget Toy | Fully synchronized tri-sensory flow |

---

## 4. Iterative Design: What We Tried & Dropped

In our pursuit of realism, we explored several advanced visual and physics concepts but ultimately streamlined them to fit our development velocity and performance goals:

### 4.1 Physically Based Rendering (PBR) & 3D Scenes
*   **The Idea:** Render the fidgets (pen, dial, magnet) in a real 3D environment using SceneKit or Metal with PBR textures.
*   **Why We Dropped It:** Implementing 3D meshes, setting up lighting environments, and managing the render loop was too complex. The development cost was too high for a small team, and it would distract us from mastering the core haptic and audio APIs.

### 4.2 Complex Physics Simulation Engines
*   **The Idea:** Integrate a full physical body simulation (rigid bodies, magnetic fields, fluid friction) to govern the movement of elements like the Dial, Magnet, and Blob.
*   **Why We Dropped It:** Translating raw physics formulas into robust Swift code without bugs was a major undertaking, and we set a strict boundary not to rely on generative AI to write our core mathematical engines. We understood the physics concepts but realized that coding an accurate simulation within our tight timeline would overcomplicate the project. 
*   **The Pivot:** We replaced heavy physics engines with clean, performant mathematical approximations (e.g., basic torque multipliers, Spring mass equations, and Coulomb's Law distance scaling) calculated on standard frame loops.

---

## 5. Real Technical & Hardware Limitations

As we pushed the limits of the iOS and watchOS SDKs, we encountered hard hardware and API walls that forced us to pivot:

### 5.1 watchOS CoreHaptics Absence
*   **The Limitation:** We set out to create a mirror companion app for Apple Watch. However, we discovered that Apple does not expose the `CoreHaptics` framework (`CHHapticEngine`) on watchOS.
*   **The Pivot:** Because *Fidgetable* succeeded in making a watch app, we researched alternative solutions. We bypassed `CoreHaptics` on watchOS and utilized **WatchKit**’s basic haptic API (`WKInterfaceDevice.current().play(_:)`) to trigger physical crown clicks and sensory vibrations, allowing us to maintain a tactile experience on the wrist.

### 5.2 iPhone Capacitive Camera Control Button
*   **The Limitation:** The latest iPhone models feature a capacitive touch-and-pressure sensor on the side (Camera Control button). We wanted to leverage this sensor to let users spin the dial or click the pen without touching the screen.
*   **The Pivot:** This physical sensor is strictly locked down to Apple's `AVFoundation` / `AVCapture` framework for camera functions. Accessing it for arbitrary gesture input would require unstable, private APIs that are highly prone to rejection or crash. We dropped this concept to focus on a polished screen-and-volume-button experience.

---

## 6. Revised Design Language: Full Neumorphism

To solve the visual challenge within our timeline, we moved away from mixed-media aesthetics:
*   **Cohesive Challenge:** We experimented with mixed textures and vector designs, but found that creating a consistent, premium feel across 5 different fidgets was too time-consuming.
*   **The Choice:** We chose to go full **Neumorphism (Soft UI)**.
*   **Why Neumorphism Works for Fidgets:** Neumorphism mimics real-world soft plastics and metals by using extruded and recessed shapes, soft shadows, and light highlights. Because the UI elements look like physical, touchable buttons and grooves extruded from the device's screen, the visual style naturally matches the tactile simulations of our physical fidgets.

---

## 7. Framework Architecture & API Selection

Our team adopted a strict minimalist approach to frameworks. We stripped our dependencies down to the bare minimum required to build the core experience.

> [!IMPORTANT]
> **Our Philosophy:** We chose depth over breadth. We preferred to build a deep, solid understanding of a few key frameworks (`CoreHaptics`, `AVFoundation`, `SwiftUI`) rather than cobbling together multiple third-party libraries that we only understood on a surface level.

### iOS Stack
*   **SwiftUI:** Declares the visual layout and captures touch gestures.
*   **CoreHaptics:** Programmatically structures transient and continuous physical waveforms to synthesize sensations like tearing paper, snapping magnets, and mechanical detents.
*   **AudioToolbox:** Triggers ultra-low latency system sound effects (such as click sounds) matching physical taps.
*   **AVFoundation (`AVAudioEngine`):** Modulates sound synthesizer pitch and frequency in real-time to match physical velocities (such as Dial RPM).

### watchOS Stack
*   **WatchKit:** Handles the watch app interface and triggers basic Apple Watch Taptic Engine patterns.

### 7.3 Developer Tooling: Parameter Tuning Overlay
To solve the issue of slow iteration cycles during physical testing, we implemented a custom float-over **Debug Control Panel** in the app's root view structure (`HapticleApp.swift`).
*   **Why We Need It:** Physical constants (e.g. spring stiffness, friction coefficients, and haptic transient levels) require extensive physical testing to "feel" right. Re-compiling and deploying to physical devices for every parameter adjustment is highly inefficient.
*   **Real-time Tuning & Copy Pipeline:** The panel includes interactive sliders representing active fidget properties. Once a developer achieves the desired tactile sensation, they can tap **"Copy Settings as Text"** to serialize the configurations directly to their device clipboard. This block can be pasted directly into code configuration models, completely eliminating manual transcription and transcription errors.

---

## 8. Accessibility, Localization, & Privacy

### 8.1 Accessibility & Visual Modes
With a highly visual and neumorphic style, contrast is a key challenge. We implemented dedicated neumorphic shadow and highlight color tokens across three core themes to ensure that the soft 3D extrusions remain visible and accessible in any lighting environment:
*   **Light Theme (Light Mode):** Base ![#E0E5EC](Colors/primary_light.svg) `PrimaryLight` (`#E0E5EC`), Highlight ![#FFFFFF](Colors/highlight_light.svg) `HighlightLight` (`#FFFFFF`), Shadow ![#A3B1C6](Colors/shadow_light.svg) `ShadowLight` (`#A3B1C6`)
*   **Dark Theme (Dark Mode):** Base ![#454545](Colors/primary_dark.svg) `PrimaryDark` (`#454545`), Highlight ![#D9D9D9](Colors/highlight_dark.svg) `HighlightDark` (`#D9D9D9`), Shadow ![#000000](Colors/shadow_dark.svg) `ShadowDark` (`#000000`)
*   **Accent Theme (Active/Accent):** Base ![#C73535](Colors/accent.svg) `Accent` (`#C73535`), Highlight ![#D86E6E](Colors/accent_highlight.svg) `AccentHighlight` (`#D86E6E`), Shadow ![#892424](Colors/accent_shadow.svg) `AccentShadow` (`#892424`)

### 8.2 Universal UX & Navigation Deliberations
To cycle through the five fidget interfaces, the application currently implements a custom **2-finger swipe gesture**. Because this navigation scheme is not a standard system gesture, we introduced a minimal onboarding text instruction in the initial user flow to guide users: *"Swipe with two fingers to change fidgets."*
*   **Typography & Styling:** This text guidance conforms to standard Apple HIG layout spacing, styled in `SF Pro Rounded`, size `17 pt`, and `Medium` weight.
*   **Active Deliberation & UX Concerns:** We are concerned that users will forget the 2-finger swipe gesture once the initial onboarding text disappears. To address this, we are deliberating on an alternative hold-based radial menu selector:
    - **Radial Menu Mechanics:** Holding down a menu button initiates a circular progress indicator. When filled, 4 circular selections representing the other fidgets pop up in a radius starting from the left ($180^\circ$) and spaced every $60^\circ$ clockwise (at $180^\circ$, $240^\circ$, $300^\circ$, and $360^\circ$/$0^\circ$).
    - **Interactive Selection:** The user swipes toward their choice while holding the finger down, releasing it to select, or letting go outside the nodes to cancel.
    - **Localization Impact:** This selector menu uses purely visual targets (circular previews or icons), maintaining our goal of a minimalist, highly universal visual design with low localization overhead.


### 8.3 Figma Static Component Note
Our source Figma components are strictly static designs without pre-defined interactive states. The dynamic behaviors—such as visual depth recessions, spring tensions, and dial rotations—are synthesized programmatically in SwiftUI, rather than replicated from Figma variant states.

### 8.4 Privacy Compliance
Our application requires no network connectivity, profile creation, or data storage. It is built to run entirely on the user's device:
*   **No User Data Collected:** We do not track, store, or transmit any user behavior or metrics, ensuring 100% user privacy.

---

## 9. Fidget Implementations & Folder Structure

Our implementation architecture utilizes the **Model-View-ViewModel-Manager (MVVM-M)** design pattern, keeping logic separated from the UI. Below is the organized directory and file layout showing the placement of the 5 interactive fidgets and core system managers:

### 9.1 Folder/File Structure

```
hapticle/
├── Documentation/
│   ├── DD.md
│   └── TDD.md
├── Hapticle/
│   ├── HapticleApp.swift
│   ├── ContentView.swift
│   ├── Fidgets/
│   │   ├── Pen/
│   │   │   ├── PenView.swift
│   │   │   └── PenModel.swift
│   │   ├── Dial/
│   │   │   ├── DialView.swift
│   │   │   └── DialModel.swift
│   │   ├── Ticket/
│   │   │   ├── TicketView.swift
│   │   │   └── TicketModel.swift
│   │   ├── Magnet/
│   │   │   ├──  MagnetView.swift
│   │   │   └── MagnetModel.swift
│   │   └── Blob/
│   │       ├── BlobView.swift
│   │       └── BlobModel.swift
│   └── Managers/
│       ├── HapticsManager.swift
│       └── SoundManager.swift
└── Hapticle Watch App/
    ├── HapticleApp.swift
    └── ContentView.swift
```

---

### 9.2 The Fidgets

#### 1. The Pen (Retractable Ballpoint)
*   **Concept:** Clicking a retractable ballpoint pen using dual-state latch logic.
*   **Logic:** Volume button clicks or screen taps toggle state. The latch only engages upon releasing the button (`TouchUp`), which fires a second haptic transient. Quick taps fire both transients in rapid succession.
*   **Key Files:** [hapticle/Hapticle/Fidgets/Pen/PenView.swift](hapticle/Hapticle/Fidgets/Pen/PenView.swift) & [hapticle/Hapticle/Fidgets/Pen/PenModel.swift](hapticle/Hapticle/Fidgets/Pen/PenModel.swift)

#### 2. The Dial (Rotary Detent)
*   **Concept:** A heavy rotary dial with angular momentum, friction decay, and fulcrum physics.
*   **Logic:** Drag torque changes based on the finger's distance from the center. Detents are triggered at $15^\circ$ increments, firing haptic ticks. Pitch scales dynamically based on angular velocity ($\omega$).
*   **Key Files:** [hapticle/Hapticle/Fidgets/Dial/DialView.swift](hapticle/Hapticle/Fidgets/Dial/DialView.swift) & [hapticle/Hapticle/Fidgets/Dial/DialModel.swift](hapticle/Hapticle/Fidgets/Dial/DialModel.swift)

#### 3. The Ticket (Perforation Tear)
*   **Concept:** Tear-off arcade ticket.
*   **Logic:** Dragging downwards increases spring-like tension ($F = k \cdot y$). Crossing perforation intervals drops tension temporarily and triggers micro-haptic "snaps" before final separation.
*   **Key Files:** [hapticle/Hapticle/Fidgets/Ticket/TicketView.swift](hapticle/Hapticle/Fidgets/Ticket/TicketView.swift) & [hapticle/Hapticle/Fidgets/Ticket/TicketModel.swift](hapticle/Hapticle/Fidgets/Ticket/TicketModel.swift)

#### 4. The Magnet (Field Orbitals)
*   **Concept:** A free-floating magnetic puck snapped to a ring of alternating fixed poles.
*   **Logic:** Applies Coulomb's Law approximations combined with spring physics between the finger and puck. Alternates push-pull forces, causing Orbit Lock and breakaway snapping.
*   **Key Files:** [hapticle/Hapticle/Fidgets/Magnet/ MagnetView.swift](hapticle/Hapticle/Fidgets/Magnet/%20MagnetView.swift) & [hapticle/Hapticle/Fidgets/Magnet/MagnetModel.swift](hapticle/Hapticle/Fidgets/Magnet/MagnetModel.swift)

#### 5. The Blob (Elastic Viscous Mitosis)
*   **Concept:** Squishy, viscous soft-body creature.
*   **Logic:** Dragging deforms the vector blob and warps the grid. Stretching past a threshold triggers cell mitosis, splitting it into two separate blobs with a suction/pop haptic pattern.
*   **Key Files:** [hapticle/Hapticle/Fidgets/Blob/BlobView.swift](hapticle/Hapticle/Fidgets/Blob/BlobView.swift) & [hapticle/Hapticle/Fidgets/Blob/BlobModel.swift](hapticle/Hapticle/Fidgets/Blob/BlobModel.swift)

---

### 9.3 Hardware Managers
*   **Haptics Service:** Wraps `CHHapticEngine` and abstracts haptic transients, continuous rumbles, and custom waveforms.
    *   *Reference:* [hapticle/Hapticle/Managers/HapticsManager.swift](hapticle/Hapticle/Managers/HapticsManager.swift)
*   **Audio Service:** Manages sound synthesis and rapid system sounds. Modulates frequency parameters via `AVAudioUnitTimePitch`.
    *   *Reference:* [hapticle/Hapticle/Managers/SoundManager.swift](hapticle/Hapticle/Managers/SoundManager.swift)

---

## 10. Conclusion & Future Outlook

By setting aside 3D rendering and overly complex physics engines, SMBBC focused on the core interactions that make fidgeting compelling: **immediacy, physical consistency, and rich multi-sensory feedback**. 

The resulting architecture shows that core iOS frameworks like `CoreHaptics` and `AVFoundation`, when combined with unified neumorphic design principles, can synthesize highly convincing mechanical textures. In future versions, we plan to refine watchOS feedback loops further and continue optimizing inertial decay algorithms for even greater tactile realism.

---
*For visual assets, engineering plans, and technical specification details, please consult [hapticle/Documentation/DD.md](hapticle/Documentation/DD.md) and [hapticle/Documentation/TDD.md](hapticle/Documentation/TDD.md).*
