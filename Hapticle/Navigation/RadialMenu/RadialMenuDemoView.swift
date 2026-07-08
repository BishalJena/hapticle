////
////  RadialMenuDemoView.swift
////  Hapticle
////
////  Standalone harness for the radial selector. Shows a placeholder fidget screen
////  (A–E) and overlays the menu; committing pulls the chosen screen up via a
////  hero-zoom/cross-fade. Swap `PlaceholderScreen` for real fidgets later.
////
//
//import SwiftUI
//
//struct RadialMenuDemoView: View {
//    @State private var current: FidgetID = .a
//
//    var body: some View {
//        ZStack {
//            Color.hpBase.ignoresSafeArea()
//
//            PlaceholderScreen(id: current)
//                .id(current)
//                // Scales up from 0.92 (never from nothing) as the chosen node
//                // flares out — together they read as one hero-zoom.
//                .transition(.scale(scale: 0.92).combined(with: .opacity))
//
//            RadialMenuView(onSelect: select)
//        }
//    }
//
//    private func select(_ id: FidgetID) {
//        guard id != current else { return }
//        withAnimation(.spring(RadialMenuConfig.collapseSpring)) {
//            current = id
//        }
//    }
//}
//
///// A neumorphic stand-in for a fidget screen: a big recessed letter card.
//private struct PlaceholderScreen: View {
//    let id: FidgetID
//
//    var body: some View {
//        VStack(spacing: 24) {
//            Text(id.label)
//                .font(.system(size: 96, weight: .bold, design: .rounded))
//                .foregroundStyle(Color(hex: "#6B7A90"))
//                .frame(width: 200, height: 200)
//                .background(Circle().fill(Color.hpBase))
//                .neumorphicCircle(isPressed: true)
//
//            Text("Fidget \(id.label)")
//                .font(.system(size: 17, weight: .medium, design: .rounded))
//                .foregroundStyle(Color(hex: "#6B7A90"))
//        }
//    }
//}
//
//#Preview {
//    RadialMenuDemoView()
//}
