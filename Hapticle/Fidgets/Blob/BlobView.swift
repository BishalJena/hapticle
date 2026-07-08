import SwiftUI

struct BlobView: View {
    var body: some View {
        ZStack {
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Blob Fidget")
                    .font(.system(.title, design: .rounded))
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                // Placeholder shape (Jelly Blob)
                RoundedRectangle(cornerRadius: 40)
                    .fill(Color.accent)
                    .frame(width: 160, height: 160)
                    .shadow(color: Color.shadow.opacity(0.5), radius: 8, x: 5, y: 5)
            }
        }
    }
}

#Preview {
    BlobView()
}
