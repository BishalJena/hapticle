import SwiftUI

struct ContentView: View {
    @State private var activeFidget: FidgetID = .dial // Default start on the dial
    
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
                    DialView()
                case .ticket:
                    TicketView()
                case .magnet:
                    MagnetView()
                case .blob:
                    BlobView()
                }
            }
            .transition(.opacity) // Smooth opacity shift between features
            
            // 2. Global Bottom-Anchored Radial Selector
            RadialMenuView { selectedFidget in
                withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
                    activeFidget = selectedFidget
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
