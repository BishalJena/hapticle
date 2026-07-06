//
//  PenView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI

extension View {
    /// Inner shadow that works on any View (including Image), using the view
    /// itself as the alpha mask rather than requiring a Shape.
    func innerShadow<Mask: View>(
        mask maskView: Mask,
        color: Color = .black,
        radius: CGFloat = 5,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> some View {
        self.overlay(
            Rectangle()
                .fill(color)
                .mask(maskView)       // clip the fill to the shape's silhouette
                .offset(x: x, y: y)   // push it in the shadow direction
                .blur(radius: radius) // soften it
                .mask(maskView)       // clip again so blur doesn't spill outside the shape
        )
    }
}

struct PenView: View {
    let slateShadow = Color(red: 0.64, green: 0.69, blue: 0.78)
    
    var body: some View {
        VStack {
            ZStack {
                
                Image("hapticle")
                Image("Vector 6")
                // crown
                Image("Vector 9")
                Image("Vector 7")
                    .shadow(color: Color.whiteShadow, radius: 3, x: 3, y: 3)
                    .shadow(color: .white, radius: 3, x: -3, y: -3)
                    .innerShadow(
                        mask: Image("Vector 7"),
                        color: Color.whiteShadow,
                        radius: 5,
                        x: -13,
                        y: 0
                    )

                
            }
            
        }
        .background(Color.black)
    }
}

#Preview {
    PenView()
}

