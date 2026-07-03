//
//  PenView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI

struct ThreeStatePenStyle: ButtonStyle {
    @Binding var isClicked: Bool
    
    // Optimizing the style body to minimize redrawing overhead
    func makeBody(configuration: Configuration) -> some View {
        let currentAsset = configuration.isPressed ? "PenV1_Clicking" : (isClicked ? "PenV1_Clicked" : "PenV1_Unclicked")
        
        return Image(currentAsset)
            .resizable()
            .scaledToFit()
            .frame(width: 400, height: 600)
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0, anchor: .bottom)
            .animation(.bouncy(duration: 0.1, extraBounce: 0.1), value: configuration.isPressed)
    }
}

struct PenView: View {
    @State private var isClicked: Bool = false
    
    var body: some View {
        VStack {
            Button {
                isClicked.toggle()
            } label: {
                
                Text("Toggle Pen")
            }
            .buttonStyle(ThreeStatePenStyle(isClicked: $isClicked))
            .padding(.top, 300)
            .sensoryFeedback(.impact(weight: .medium, intensity: 1.0), trigger: isClicked)
        }
        .background(Color.backgroundColour)
        .ignoresSafeArea()
    }
    
}

#Preview {
    PenView()
}
