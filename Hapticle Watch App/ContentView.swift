//
//  ContentView.swift
//  Hapticle
//
//  Created by Syauqi Auliya M on 02/07/26.
//

import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct ContentView: View {
    var body: some View {
        VStack(spacing: 40) {
            
            Text("Hapticle")
            Button("Test Watch Haptic") {
                #if os(watchOS)
                // Commands the wrist-worn Taptic Engine to fire a sharp, mechanical tap
                WKInterfaceDevice.current().play(.click)
                #else
                print("Watch haptic simulated (Deploy to a watchOS target to feel the physical response).")
                #endif
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }
}

#Preview {
    ContentView()
}
