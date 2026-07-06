//
//  DialView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI


struct DialView: View {
    
    var body: some View {
        
        ZStack
        {
            Color.primaryWhite
                .ignoresSafeArea()
            
            VStack {
                
                ZStack {
                    
                    //main body
                    VStack{
                        Image("Vector6PNG")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 111, height: 647)
                            .padding(.top, 300)
                        Spacer()
                    }
                    
                    //side part
                    VStack{
                        Image("Vector9PNG")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40.37, height: 337.8)
                            .padding(.top, 330)
                            .padding(.leading, 25)
                        Spacer()
                    }
                    
                    //crown
                    VStack{
                        Image("Vector7PNG")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 116, height: 56)
                            .padding(.top, 300)
                        Spacer()
                    }
                    
                    
                    //hapticle text
                    VStack{
                        Image("hapticlePNG")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15, height: 88)
                            .padding(.top, 370)
                            .padding(.leading, 25)
                        Spacer()
                    }
                    
                    
                    
                }
            }
            
        }
        
    }
    
}

#Preview {
    DialView()
}

