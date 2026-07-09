import SwiftUI

struct ContentView: View {
    @State private var activeFidget: FidgetID = .dial // Default start on the dial
    @State private var isMenuVisible = true
    @State private var menuHideTimer: Timer?
    @State private var isDialActive = false
    @State private var isMagnetActive = false
    
    @State private var idleTracker = IdleTracker()
    
    var body: some View {
        ZStack {
            // Background Canvas
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            // 1. The Active Fidget View
            Group {
                switch activeFidget {
                case .pen:
                    PenView()
                case .dial:
                    DialView(onInteractionChange: { active in
                        isDialActive = active
                        if active {
                            triggerInteraction()
                        } else {
                            endInteraction()
                        }
                    })
                case .ticket:
                    TicketView()
                case .magnet:
                    MagnetView(onInteractionChange: { active in
                        isMagnetActive = active
                        if active {
                            triggerInteraction()
                        } else {
                            endInteraction()
                        }
                    })
                case .blob:
                    BlobView()
                }
            }
            .transition(.opacity) // Smooth opacity shift between features
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        triggerInteraction()
                    }
                    .onEnded { _ in
                        // Only schedule menu to reappear if the dial/magnet isn't still actively moving
                        if !isDialActive && !isMagnetActive {
                            endInteraction()
                        }
                    }
            )
            
            // 2. Global Bottom-Anchored Radial Selector
            RadialMenuView(isMenuVisible: $isMenuVisible) { selectedFidget in
                withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
                    activeFidget = selectedFidget
                }
            }
        }
        // 2. Inject into the environment for RadialMenuView to read
        .environment(idleTracker)
        // 3. Start the AFK countdown when the app first launches
        .onAppear {
            idleTracker.restartTimer()
        }
    }
    
    private func triggerInteraction() {
        menuHideTimer?.invalidate()
        menuHideTimer = nil
        if isMenuVisible {
            withAnimation(.easeInOut(duration: 0.2)) {
                isMenuVisible = false
            }
        }
        idleTracker.userInteracted()
    }
    
    private func endInteraction() {
        menuHideTimer?.invalidate()
        menuHideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isMenuVisible = true
            }
        }
        idleTracker.restartTimer()
    }
}

#Preview ("English") {
    ContentView()
        .environment(\.locale, Locale(identifier: "en"))

}

#Preview ("Indo") {
    ContentView()
        .environment(\.locale, Locale(identifier: "id"))

}

#Preview ("japanese") {
    ContentView()
        .environment(\.locale, Locale(identifier: "ja"))

}
