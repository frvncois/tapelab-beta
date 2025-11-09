//
//  LaunchScreenView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct LaunchScreenView: View {
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            Image("LaunchImage")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
    }
}

#Preview {
    LaunchScreenView()
}
