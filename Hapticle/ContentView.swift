//
//  ContentView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        
        TabView {
            DialView()
                .tabItem {
                    Label("Dial", systemImage: "dial.low")
                }
            
            PenView()
                .tabItem {
                    Label("Pen", systemImage: "applepencil.gen1")
                }
        }
        // Launches the standalone radial fidget selector demo.
    }
}

#Preview {
    ContentView()
}
