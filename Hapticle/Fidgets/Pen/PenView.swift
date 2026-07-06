//
//  PenView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI

enum PenButtonState {
    case unclicked   // offset 0
    case beingClicked // offset 70 (while finger is down)
    case clicked     // offset 45 (toggled "locked in" state)
}


extension View {
    /// Creates a duplicate of `maskView` filled with `color`, blurs it as a whole shape,
    /// offsets it, then re-clips to the original silhouette. Where the shifted blur
    /// no longer reaches, the original content underneath shows through — mimicking
    /// an inner shadow.
    func innerShadowShift<Mask: View>(
        mask maskView: Mask,
        color: Color,
        blur: CGFloat = 8,
        x: CGFloat = 0,
        y: CGFloat = 0
    ) -> some View {
        self.overlay(
            Rectangle()
                .fill(color)
                .mask(maskView)          // clip solid fill to the shape's silhouette
                .blur(radius: blur)      // blur the whole filled shape
                .offset(x: x, y: y)      // shift it
                .mask(maskView)          // re-clip so nothing spills outside the original shape
        )
    }
}

struct PenView: View {
    @State private var buttonState: PenButtonState = .unclicked
    @State private var preClickState: PenButtonState = .unclicked // remembers state before press
    
    private var currentOffset: CGFloat {
        switch buttonState {
        case .unclicked: return 0
        case .beingClicked: return 50
        case .clicked: return 30
        }
    }
    
    
    var body: some View {
        
        ZStack
        {
            Color.primaryWhite
                .ignoresSafeArea()
            
            //clicky part
            VStack{
                Image("Vector 3")
                    .innerShadowShift(
                        mask: Image("Vector 3"),
                        color: Color.redHighlight,
                        blur: 7, x: -20, y: -2
                    )
                    .innerShadowShift(
                        mask: Image("Vector 3"),
                        color: Color.redShadow,
                        blur: 11, x: 20, y: 5
                    )
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(.top, 160)
                    .offset(y: currentOffset)
                    .animation(
                        buttonState == .beingClicked
                        ? .easeIn(duration: 0.08)
                        : .easeOut(duration: 0.25),
                        value: buttonState
                    )
                Spacer()
            }
            // pen body
            VStack{
                Image("Vector 6")
                    .shadow(color: Color.white, radius: 6, x: -7, y: -6)
                    .shadow(color: .whiteShadow, radius: 6, x: 7, y: 6)
                    .innerShadowShift(
                        mask: Image("Vector 6"),
                        color: Color.primaryWhite,
                        blur: 13.85,
                        x: -21,
                        y: -4
                    )
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(.top, 450) //(+150
                Spacer()
            }
            
            
            //crown
            VStack{
                Image("Vector 7")
                    .shadow(color: Color.whiteShadow, radius: 3, x: 3, y: 3)
                    .shadow(color: .white, radius: 3, x: -3, y: -3)
                    .innerShadowShift(
                        mask: Image("Vector 7"),
                        color: Color.primaryWhite,
                        blur: 4.9,
                        x: -13,
                        y: 0
                    )
                    .scaledToFit()
                    .frame(width: 150, height: 150)
                    .padding(.top, 210)
                Spacer()
            }
            
            // pen clip
            VStack{
                Image("Vector9PNG")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40.37, height: 337.8)
                    .padding(.top, 300)
                    .padding(.leading, 25)
                Spacer()
            }
            
            // Hapticle text
            VStack{
                Image("hapticle")
                    .shadow(color: Color.white, radius: 1, x: -1, y: -1)
                    .shadow(color: .whiteShadow, radius:1, x: 1, y: 1)
                    .scaledToFit()
                    .padding(.top, 350)
                    .padding(.leading, 25)
                Spacer()
            }
            
            
            
        }
        .contentShape(Rectangle()) // makes the ENTIRE ZStack area (including empty space) hit-testable
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if buttonState != .beingClicked {
                                preClickState = buttonState
                                buttonState = .beingClicked
                            }
                        }
                        .onEnded { _ in
                            let generator = UIImpactFeedbackGenerator(style: .rigid)
                            generator.prepare()
                            generator.impactOccurred()
                            
                            buttonState = (preClickState == .clicked) ? .unclicked : .clicked
                        }
                )
        
    }
}

#Preview {
    PenView()
}

