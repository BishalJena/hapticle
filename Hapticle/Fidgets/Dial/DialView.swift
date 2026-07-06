import SwiftUI

struct DialView: View {
    @StateObject private var model = DialModel()
    
    var body: some View {
        ZStack {
            // Background Canvas (adapts to primary light or dark theme background)
            Color.fidgetPrimary
                .ignoresSafeArea()
            
            // Layout safe container (reproducing CSS 402px x 874px boundary)
            VStack {
                Spacer()
                
                // Circle Dial Container (310px x 310px)
                ZStack {
                    
                    // 1. Inner Concave Well (recessed circle base: Ellipse 4)
                    Circle()
                        .fill(Color.fidgetPrimary)
                        .frame(width: 260, height: 260)
                        // Inset shadows recreating the CSS box-shadow inset properties
                        .overlay(
                            Circle()
                                .stroke(Color.shadow.opacity(0.35), lineWidth: 6.85)
                                .blur(radius: 8.14 / 2)
                                .offset(x: 6.85, y: 6.85)
                                .mask(Circle().fill(LinearGradient(
                                    colors: [Color.shadow, Color.clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.highlight.opacity(0.9), lineWidth: 12.42)
                                .blur(radius: 12.42 / 2)
                                .offset(x: -6.85, y: -6.85)
                                .mask(Circle().fill(LinearGradient(
                                    colors: [Color.clear, Color.highlight],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )))
                        )
                    
                    // 2. Outer Circular Rim/Well Border (embossed ring: Ellipse 1)
                    Circle()
                        .stroke(Color.fidgetPrimary, lineWidth: 16.27)
                        .frame(width: 293.73, height: 293.73) // stroke-width centers to 310 diameter
                        .shadow(color: Color.shadow.opacity(0.8), radius: 10.28 / 2, x: 5.14, y: 5.14)
                        .shadow(color: Color.highlight.opacity(0.9), radius: 10.28 / 2, x: -5.14, y: -5.14)
                    
                    // 3. Rotating Dial Face details (ticks & indicator)
                    ZStack {
                        // 24 Ticks (Rectangle 7) rotated in 15-degree increments at radius 149
                        ForEach(0..<24) { i in
                            let angle = Double(i) * 15.0
                            let isKeyTick = (i == 9) // 135 degrees (Frame 10 in CSS is larger)
                            
                            Rectangle()
                                .fill(LinearGradient(
                                    colors: [Color(red: 210/255, green: 213/255, blue: 218/255), 
                                             Color(red: 148/255, green: 152/255, blue: 160/255)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ))
                                .frame(width: isKeyTick ? 4 : 3, height: isKeyTick ? 18 : 12)
                                .cornerRadius(2)
                                // Place ticks on the border of the 310px rim
                                .offset(y: -149 + (isKeyTick ? -3 : 0))
                                .rotationEffect(.degrees(angle))
                        }
                        
                        // Red Indicator Dot (Ellipse 17) - diameter 20, offset by (-73, 65)
                        Circle()
                            .fill(Color.accent)
                            .frame(width: 20, height: 20)
                            // Inset shadow recreating: inset 2px 3px 4px rgba(0, 0, 0, 0.4)
                            .overlay(
                                Circle()
                                    .stroke(Color.black.opacity(0.4), lineWidth: 2)
                                    .blur(radius: 2)
                                    .offset(x: 2, y: 3)
                                    .mask(Circle())
                            )
                            .offset(x: -73, y: 65)
                    }
                    .rotationEffect(.radians(model.rotationAngle))
                    .contentShape(Circle()) // Ensures the drag gesture catches touches over the entire dial
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let center = CGPoint(x: 155, y: 155) // Center of 310x310 coordinate system
                                if !model.isDragging {
                                    model.handleDragStarted(at: value.startLocation, dialCenter: center)
                                }
                                model.handleDragUpdated(to: value.location, dialCenter: center)
                            }
                            .onEnded { value in
                                model.handleDragEnded(velocity: value.velocity)
                            }
                    )
                }
                .frame(width: 310, height: 310)
                
                Spacer()
            }
            .frame(width: 402, height: 874)
        }
    }
}

// MARK: - Previews

struct DialView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Light Mode Preview
            DialView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            
            // Dark Mode Preview
            DialView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
#Preview {
    DialView()
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark Mode")
}
#Preview{
    DialView()
        .preferredColorScheme(.light)
        .previewDisplayName("Light Mode")
}
