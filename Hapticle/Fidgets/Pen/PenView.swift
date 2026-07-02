//
//  PenView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI

struct PenView: View {
    
    @State private var isClicked: Bool = false
    
    var body: some View {
        
        VStack {
            Image(isClicked ? "PenPlaceholder_Clicked" : "PenPlaceholder")
                .resizable()
                .scaledToFit()
                .frame(width: 1000, height: 1000)
                .onTapGesture {
                    isClicked.toggle()
                }
                .padding(.top, 600)
                .sensoryFeedback(isClicked ? .impact(flexibility: .solid) : .impact(flexibility: .rigid), trigger: isClicked)
        }
        .background(Color.backgroundColour)
        
    }
}

#Preview {
    PenView()
}
