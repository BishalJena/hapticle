import SwiftUI

struct MagnetView: View {
    var body: some View {
        ZStack {
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Magnet Fidget")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                // Placeholder shape (Horseshoes Magnet)
                Circle()
                    .trim(from: 0.1, to: 0.9)
                    .stroke(Color.accent, lineWidth: 30)
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(90))
                    .shadow(color: Color.shadow.opacity(0.5), radius: 8, x: 5, y: 5)
            }
        }
    }
}

#Preview {
    MagnetView()
}
