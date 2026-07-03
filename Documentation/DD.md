# Hapticle - Design Document (DD)

Hapticle is a mixed-media fidget application built for **Challenge 4 of the Apple Developer Academy (ADA)**. The core objective of the challenge is to explore, learn, and implement native iOS frameworks. Hapticle specifically focuses on **CoreHaptics** (vibrations and haptic feedback) and **AudioToolbox** (audio feedback and sound synthesis) to create a highly tactile, playful, and responsive fidget experience.

---

## 1. Visual & Interaction Style (Neumorphism & Mixed Media)

Hapticle blends playful, photorealistic mixed-media elements (such as scanned or hand-drawn textures) with a modern **Neumorphic (soft 3D)** user interface. The UI elements appear to be extruded from or recessed into the background, simulating real-world plastic, rubber, and metal surfaces.

### Color Palette & Design Tokens

| Theme Token | Light Mode | Dark Mode | Description |
| :--- | :--- | :--- | :--- |
| **Primary (Background)** | `#E0E5EC` | `#454545` | The base canvas color; all neumorphic shapes blend into this. |
| **Highlight** | `#FFFFFF` | `#D9D9D9` | Applied to the top-left edges of elements to simulate reflected light. |
| **Shadow** | `#A3B1C6` | `#2B2B2B` | Applied to the bottom-right edges to simulate cast shadows. |
| **Accent / Active** | `#007AFF` | `#0A84FF` | Used sparingly for active states or focal points. |

---

## 2. Fidget Interactivity & Design Specifications

### 2.1 The Pen (Retractable Ballpoint Fidget)

The Pen fidget simulates the tactile pleasure of clicking a real retractable ballpoint pen. It uses a combination of cropped photo assets, keyframe-based sprite animations, and custom haptic transients.

*   **Visual Assets:** Uses three cropped photo states:
    1.  **Full Up:** The pen in its unclicked/extended state.
    2.  **Half (Latched):** The intermediate state before clicking or when latched.
    3.  **Full Down:** The fully depressed state when clicked.
*   **Animations:**
    *   Sprite frame switching based on interaction state.
    *   Animated motion lines appearing on click events.
    *   Subtle spring-back motion on release.
*   **Interaction Model:**
    *   **Physical Buttons:** Can be interacted with via the iPhone's physical Volume buttons.
    *   **On-Screen Interaction:** Playable by tapping/pressing the pen sprite on-screen.
    *   **Latch Logic:** Long presses do *not* trigger the latch. The latch only engages when a long press is released.
    *   **Click Sensations:**
        *   While pressing down (screen/button down): Only *one* click is felt.
        *   Upon letting go (screen/button up): *Another* click is felt.
        *   Quick Taps: Two fast clicks are felt in rapid succession.

![Pen Lo-Fi Sketch](Pen_lofi.jpeg)

---

### 2.2 The Dial (Rotary Inertial Fidget)

The Dial simulates a heavy, physical rotary dial (like a safe dial or volume knob) featuring moment of inertia, angular momentum, and physical detents.

*   **Interaction Model:**
    *   Rotated via drag gesture on-screen.
    *   **Leverage / Fulcrum Physics:** Rotational torque varies based on the distance of the finger from the center (fulcrum). If the finger is in the center, leverage is zero and the dial cannot be spun. The further out the finger is, the higher the leverage and the easier it is to spin.
    *   **Momentum:** Flipping the finger adds angular momentum. The dial continues spinning and slows down gradually due to simulated friction.
*   **Haptic Design:**
    *   Vibrations are triggered as the dial crosses angular "detents" (ticks).
    *   Detent frequency increases with rotation speed.
*   **Audio Design:**
    *   Sound pitch and volume are dynamically modulated based on the RPM (Revolutions Per Minute).
    *   Faster RPM results in a higher pitch, mimicking a mechanical whirr or clicking ratchet.

![Dial Lo-Fi Sketch](Dial_lofi.jpeg)

---

### 2.3 The Ticket (Tear-Off Arcade Fidget)

The Ticket simulates the satisfying feeling of tearing a perforated cardboard arcade ticket.

*   **Visual Assets:**
    *   Drawn and scanned textures of a classic arcade ticket.
    *   Animated tear lines and falling paper fragments.
*   **Interaction Model:**
    *   The user drags the ticket downward to rip it along a perforated line.
    *   As the ticket is pulled, the tension increases.
    *   Once a ticket is completely torn off, the ticket sheet shifts down, generating a new ticket.
*   **Haptic Design:**
    *   Simulates the sequential tearing of paper fibers ("dud dud dud dud dud dud").
    *   Provides a strong snap haptic at the moment of final separation.
*   **Audio Design:**
    *   A ripping sound effect synthesized dynamically or pitched according to the speed of the tear.

![Ticket Lo-Fi Sketch](Ticket_lofi.jpeg)

---

### 2.4 The Magnet (MagSafe & Field Physics Fidget)

The Magnet simulates playing with magnets, mimicking the MagSafe ring on the back of an iPhone. It features a ring of fixed magnets and a free-floating magnet that follows the finger.

*   **Visual Assets:**
    *   Playful mixed-media magnet sprites.
    *   Visual field lines or ripple effects showing magnetic pull.
*   **Interaction Model:**
    *   The user drags a free magnet near a fixed circular ring of magnets.
    *   **Elastic Pull:** The magnet doesn't stick perfectly to the finger; it acts as if attached by an elastic spring, lagging behind to convey mass and "force".
    *   **Snap-to-Ring:** When close to the ring, the magnet snaps to the nearest magnetic node.
    *   **Orbiting & Push-Pull:**
        *   If pulled with enough velocity/force, it breaks free of the snap.
        *   If moved with low force, it orbits the ring.
        *   The ring contains alternating poles (N/S), creating alternating push and pull forces (Coulomb's Law) as the magnet moves around it.
*   **Haptic Design:**
    *   Continuous hum haptic that scales with magnetic force/tension.
    *   Transient snaps when locking onto a magnetic node.
    *   Repulsive pushback felt via high-frequency micro-haptics when passing repulsive poles.

![Magnet Lo-Fi Sketch](Magnet_lofi.jpeg)

---

### 2.5 The Blob (Elastic Viscous Fidget)

The Blob is a squishy, jelly-like creature centered on a grid background.

*   **Visual Assets:**
    *   Deformable vector blob or organic soft-body sprite.
    *   Grid background that warps slightly to show gravitational/viscous pull.
*   **Interaction Model:**
    *   The user drags any part of the blob to stretch it.
    *   **Mitosis Mechanism:** If stretched past a critical threshold length, the blob undergoes mitosis and splits into two independent blobs.
    *   The two separate blobs can eventually merge back if they touch.
*   **Haptic Design:**
    *   Squishy, rubbery, low-frequency rumble that increases in amplitude as the blob stretches.
    *   A clean pop/suction transient when the blob splits or merges.
*   **Audio Design:**
    *   Squelching audio effects pitch-shifted during stretching.
    *   A satisfying "pop" sound effect upon division.

![Blob Lo-Fi Sketch](Blob_lofi.jpeg)
