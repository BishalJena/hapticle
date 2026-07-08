# Hapticle Ticket Dispenser Specification (Ticket.md)

This document delineates the architectural paradigms, physical simulations, and structural mechanics governing the **Ticket fidget**, designed to emulate an infinite, interactive dispenser. The implementation rigorously adheres to the Model-View-ViewModel (MVVM) separation of concerns, decoupling spatial rendering from complex kinetic mathematics.

---

## 1. Overview

The Ticket module manifests a continuous sequence of perforated paper assets emerging from a rigid metallic aperture. The system supports multi-modal interaction, including granular scrubbing haptics and catastrophic material failure (tearing), followed by a physics-based gravitational descent.

| Component | Functionality |
| :--- | :--- |
| `TicketModel.swift` | Centralized physics engine and state orchestrator. Manages differential friction, infinite sequence mutation, and the continuous `hapticOdometer` for synchronized sensory feedback. |
| `TicketView.swift` | Visual compositing layer. Handles layered chassis rendering, `PreferenceKey` dimensional extraction, and gesture-to-model data piping. |

---

## 2. The Illusion of Infinity (State Management)

The dispenser uses a three-element `UUID` array (`activeSequence`) to represent the continuous stock. When the terminal ticket is severed, the system performs a synchronized array mutation and vertical translation reset to maintain the infinite loop.

### 2.1 Rest Position Mathematics
The equilibrium location of the roll is defined by:
`restOffset = revealBoundaryY + (ticketsVisibleAtRest - activeSequence.count) * ticketHeight`

This ensures 1.5 tickets protrude beyond the lip, providing a consistent grip area for the user.

---

## 3. Kinematic Physics & Haptic Feedback

The system now utilizes a `hapticOdometer` to provide granular, frame-perfect feedback during dragging interactions, moving beyond simple static triggers.

### 3.1 Differential Friction & Haptic Odometer
Vertical touch velocity undergoes 99% attenuation to simulate physical resistance:
$$resistedY = rawY \times 0.01$$

The odometer calculates the delta of translation. When `hapticOdometer` exceeds the `tickInterval` (35.0 for straight pulls, 20.0 for hinges), the system fires coordinated Haptic and Sound Manager events.

### 3.2 Hinge Logic & Rotational Stress
The engine evaluates drag vectors against an `angularDeadzone` of 15 degrees:

* **Straight Pull:** Originates at `.top`.
* **Left/Right Hinge:** If the drag angle exceeds the deadzone, the anchor shifts to the periphery (`0.08, 0` or `0.92, 0`).
* **Stress:** Horizontal drag is multiplied by 0.1, creating rotational tension capped at 25 degrees.

---

## 4. Visual Composition & Spatial Extraction

The `TicketView` architecture uses a Z-stack layered approach to simulate material depth.

### 4.1 Layer Stack Architecture

| Layer | Component | Description |
| --- | --- | --- |
| **1. Background** | Base Chassis | Foundational template with `innerShadowShift` for depth. |
| **2. Midground** | Ticket Roll | The `AutoReplenishingTicketRoll` sequence, masked to the machine’s aperture. |
| **3. Foreground** | Overhang Overlay | Exposed metal lip providing the visual "severance edge." |

---

## 5. Severance and Gravitational Descent

Upon breaching the 25-point stretch limit or the 20-degree rotation threshold, the `executeSeveranceProtocol` transitions the terminal unit into a `SeveredTicket` struct.

### 5.1 Momentum Handoff
The terminal ticket adopts an independent kinetic state:
* **Horizontal:** 40% of unmitigated X-axis drag.
* **Vertical:** 200% of dampened Y stretch.

### 5.2 Ephemeral Descent
The `FallingTicketView` manages the independent lifecycle of the detached paper, incorporating `naturalAirDrift` based on the initial tear angle to ensure a realistic, physics-simulated descent.
