//
//  AboutView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI
import Lottie

struct AboutView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Section header with dot
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.tapelabLight)
                                .frame(width: 3, height: 3)

                            Text("ABOUT TAPELAB")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight)
                        }
                        .padding(.top, 8)

                        // Lottie animation with background image
                        ZStack {
                            // Background image
                            Image("background")
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 200)
                                .clipped()
                                .cornerRadius(12)

                            // Lottie animation overlay
                            LottieView(animation: .named("loop"))
                                .playing(loopMode: .loop)
                                .resizable()
                                .frame(width: 200, height: 200)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .cornerRadius(12)

                        // About text content
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Built with ❤️ in Montréal.")
                                .font(.tapelabMono)
                                .foregroundColor(.tapelabLight)

                            Text("Record, layer, and mix music on your phone. Inspired by classic cassette recorders, TAPELAB gives you 4 tracks to capture ideas, overdub instruments, and create complete songs. Built-in effects, metronome, and tuner. Simple, focused, creative.")
                                .font(.tapelabMono)
                                .foregroundColor(.tapelabLight)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.tapelabAccentFull)
                    }
                }
            }
        }
    }
}

#Preview {
    AboutView()
}
