//
//  tapelab_betaApp.swift
//  tapelab-beta
//
//  Created by Francois Lemieux on 5/11/25.
//
import SwiftUI

@main
struct tapelab_betaApp: App {
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if showSplash {
                    LaunchScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                } else {
                    DashboardView()
                        .preferredColorScheme(.dark)
                        .background(Color.tapelabBackground)
                        .transition(.opacity)
                }
            }
            .onAppear {
                // Show splash for 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
        }
    }
}
