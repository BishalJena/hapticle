import SwiftUI

struct TicketView: View {
    var body: some View {
        ZStack {
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Ticket Fidget")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                // Placeholder shape (Ticket stub)
                Rectangle()
                    .fill(Color.accent)
                    .frame(width: 180, height: 110)
                    .cornerRadius(12)
                    .shadow(color: Color.shadow.opacity(0.5), radius: 8, x: 5, y: 5)
            }
        }
    }
}

#Preview {
    TicketView()
}
