//
//  FXSheetView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct FXSheetView: View {
    @Binding var track: Track
    let runtime: AudioRuntime
    @Environment(\.dismiss) var dismiss

    
    var body: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tapelabLight)
                                    .frame(width: 3, height: 3)

                                Text("REVERB")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }

                            VStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("MIX")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.0f%%", track.fx.reverb.wetMix))
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.reverb.wetMix) },
                                        set: { newValue in
                                            track.fx.reverb.wetMix = Float(newValue)
                                            applyFXUpdate()
                                        }
                                    ), in: 0...100, step: 1)
                                    .accentColor(.tapelabAccentFull)
                                }
                            }
                            .padding(16)
                            .background(TapelabTheme.Colors.surface)
                            .cornerRadius(8)
                        }

                        // DELAY Section
                        VStack(alignment: .leading, spacing: 12) {
                            // Section header with dot
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tapelabLight)
                                    .frame(width: 3, height: 3)

                                Text("DELAY")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }

                            // All delay controls in one box
                            VStack(spacing: 16) {
                                // Mix control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("MIX")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.0f%%", track.fx.delay.wetMix))
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.delay.wetMix) },
                                        set: { newValue in
                                            track.fx.delay.wetMix = Float(newValue)
                                            applyFXUpdate()
                                        }
                                    ), in: 0...100, step: 1)
                                    .accentColor(.tapelabAccentFull)
                                }

                                // Time control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("TIME")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.2f S", track.fx.delay.time))
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { track.fx.delay.time },
                                        set: { newValue in
                                            track.fx.delay.time = newValue
                                            applyFXUpdate()
                                        }
                                    ), in: 0.01...2.0, step: 0.01)
                                    .accentColor(.tapelabAccentFull)
                                }

                                // Feedback control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("FEEDBACK")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.0f%%", track.fx.delay.feedback))
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.delay.feedback) },
                                        set: { newValue in
                                            track.fx.delay.feedback = Float(newValue)
                                            applyFXUpdate()
                                        }
                                    ), in: 0...100, step: 1)
                                    .accentColor(.tapelabAccentFull)
                                }
                            }
                            .padding(16)
                            .background(TapelabTheme.Colors.surface)
                            .cornerRadius(8)
                        }

                        // Reset Button
                        Button(action: {
                            track.fx.resetFX()
                            applyFXUpdate()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 14))
                                Text("RESET")
                                    .font(.tapelabMonoSmall)
                            }
                            .foregroundColor(.tapelabLight)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.tapelabButtonBg)
                            .cornerRadius(8)
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Track \(track.number) FX")
                        .font(.tapelabMono)
                        .foregroundColor(.tapelabLight)
                }
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

    private func applyFXUpdate() {
        // Apply FX changes in real-time if playing
        if runtime.timeline.isPlaying {
            let trackIndex = track.number - 1
            runtime.engine.trackBuses[trackIndex].applyFX(track.fx)
        }
    }

}
