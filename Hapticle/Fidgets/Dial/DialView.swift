import SwiftUI

struct DialView: View {
    @StateObject private var model = DialModel()
    var onInteractionChange: ((Bool) -> Void)? = nil
    
    #if DEBUG
    @State private var showDebugPanel = false
    #endif
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                            color: Color.shadow.opacity(0.8),
                            radius: 5.0,
                            x: 5.0,
                            y: 5.0
                        )
                        .shadow(
                            color: Color.highlight.opacity(0.9),
                            radius: 5.0,
                            x: -5.0,
                            y: -5.0
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
                                let center = CGPoint(x: 150, y: 150)
                                model.handleDragEnded(velocity: value.velocity, touchPoint: value.location, dialCenter: center)
                            }
                    )
                }
                .frame(width: 310, height: 310)
                
                Spacer()
            }
            .frame(width: 402, height: 874)
            
            // 3. Settings Gear Button - Aligned top-right and padded safely
            #if DEBUG
            Button(action: {
                withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
                    showDebugPanel.toggle()
                }
            }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.8))
                    .padding(12)
                    .background(Circle().fill(.thinMaterial))
                    .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 1)
            }
            .padding(.trailing, 24)
            .padding(.top, 16)
            #endif
            
            #if DEBUG
            // Debug Tuning Panel Overlay - completely excluded from release builds
            if showDebugPanel {
                VStack {
                    Spacer()
                    
                    VStack(spacing: 20) {
                        // Title Bar
                        HStack {
                            Text("Dial Physics Engine")
                                .font(.system(.headline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            Spacer()
                            Button(action: {
                                withAnimation(.spring(duration: 0.32, bounce: 0.12)) {
                                    showDebugPanel = false
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.title2)
                            }
                        }
                        
                        ScrollView {
                            VStack(spacing: 16) {
                                TuningSlider(title: "Mass (Inertia)", value: $model.mass, range: 0.01...2.0, format: "%.2f")
                                TuningSlider(title: "Damping (Friction)", value: $model.damping, range: 0.0...10.0, format: "%.2f")
                                TuningSlider(title: "Spring Coupling Strength", value: $model.springConstant, range: 10.0...1000.0, format: "%.0f")
                                TuningSlider(title: "Detent Torque Wells", value: $model.detentTorqueStrength, range: 0.0...100.0, format: "%.1f")
                                
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text("Detent Count (Ticks)")
                                            .font(.system(.caption, design: .rounded))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(model.detentCount)")
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.bold)
                                    }
                                    Slider(value: Binding(
                                        get: { Double(model.detentCount) },
                                        set: { model.detentCount = Int($0) }
                                    ), in: 8...60, step: 1.0)
                                }
                                
                                TuningSlider(title: "Base Haptic Intensity", value: $model.baseHapticIntensity, range: 0.0...1.0, format: "%.2f")
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 280)
                        
                        Divider()
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                let settingsText = """
                                Dial Settings:
                                Mass: \(String(format: "%.2f", model.mass))
                                Damping: \(String(format: "%.2f", model.damping))
                                Spring Constant: \(String(format: "%.0f", model.springConstant))
                                Detent Torque: \(String(format: "%.1f", model.detentTorqueStrength))
                                Detent Count: \(model.detentCount)
                                Haptic Intensity: \(String(format: "%.2f", model.baseHapticIntensity))
                                """
                                UIPasteboard.general.string = settingsText
                            }) {
                                HStack {
                                    Image(systemName: "doc.on.doc.fill")
                                    Text("Copy Settings")
                                }
                                .font(.system(.subheadline, design: .rounded))
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color.accent)
                                .cornerRadius(12)
                            }
                            
                            Button(action: {
                                model.mass = 0.2
                                model.damping = 3.0
                                model.springConstant = 350.0
                                model.detentTorqueStrength = 25.0
                                model.detentCount = 24
                                model.baseHapticIntensity = 0.6
                            }) {
                                Text("Defaults")
                                    .font(.system(.subheadline, design: .rounded))
                                    .fontWeight(.bold)
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 12)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(24)
                    .background(.thinMaterial)
                    .cornerRadius(28)
                    .shadow(color: Color.black.opacity(0.12), radius: 16, x: 0, y: 10)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #endif
        }
        .onReceive(model.$rotationAngle) { _ in
            let isActive = model.isDragging || abs(model.angularVelocity) > 0.05
            onInteractionChange?(isActive)
        }
        .onChange(of: model.isDragging) { oldValue, newValue in
            onInteractionChange?(newValue || abs(model.angularVelocity) > 0.05)
        }
    }
}

#if DEBUG
// MARK: - Tuning Slider Helper Component

struct TuningSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.bold)
            }
            Slider(value: $value, in: range)
        }
    }
}
#endif

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
