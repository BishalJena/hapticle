import SwiftUI

struct DialView: View {
    @StateObject private var model = DialModel()
    var onInteractionChange: ((Bool) -> Void)? = nil
    
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
                    
                    // 1. Static Embossed Bezel Ring (Outer Circular Rim/Well Border) - Does not spin
                    Circle()
                        .stroke(Color.fidgetPrimary, lineWidth: 25)
                        .frame(width: 300, height: 300)
                        .shadow(
                            color: Color.shadow.opacity(model.isPressed ? 0.5 : 0.8),
                            radius: model.isPressed ? 3.5 : 5.0,
                            x: model.isPressed ? 3.5 : 5.0,
                            y: model.isPressed ? 3.5 : 5.0
                        )
                        .shadow(
                            color: Color.highlight.opacity(model.isPressed ? 0.6 : 0.9),
                            radius: model.isPressed ? 3.5 : 5.0,
                            x: model.isPressed ? -3.5 : -5.0,
                            y: model.isPressed ? -3.5 : -5.0
                        )
                    
                    // 2. Rotating Foreground Markings (Only the ticks and Red Dot spin)
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
                    .frame(width: 300, height: 300)
                    .contentShape(Circle()) // Ensures the drag gesture catches touches over the entire inner region
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let center = CGPoint(x: 150, y: 150) // Center of 300x300 coordinate system
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
        .onReceive(model.$rotationAngle) { _ in
            let isActive = model.isDragging || abs(model.angularVelocity) > 0.05
            onInteractionChange?(isActive)
        }
        .onChange(of: model.isDragging) { newValue in
            onInteractionChange?(newValue || abs(model.angularVelocity) > 0.05)
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
