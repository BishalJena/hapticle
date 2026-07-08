import SwiftUI

struct PenView: View {
    var body: some View {
        ZStack {
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Pen Fidget")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                // Placeholder shape (Pen Cap Button)
                Capsule()
                    .fill(Color.accent)
                    .frame(width: 80, height: 180)
                    .shadow(color: Color.shadow.opacity(0.5), radius: 8, x: 5, y: 5)
            }
        }
    }
}

#Preview {
    PenView()
}
