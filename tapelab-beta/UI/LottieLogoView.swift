//
//  LottieLogoView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI
import Lottie

struct LottieLogoView: View {
    var body: some View {
        LottieView(animation: .named("logo"))
            .playing(loopMode: .playOnce)
            .animationSpeed(1.0)
            .resizable()
            .frame(height: 40)
    }
}

#Preview {
    LottieLogoView()
        .background(Color.black)
}
