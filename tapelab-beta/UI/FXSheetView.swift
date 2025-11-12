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

    @State private var lastSliderHapticTime = Date()

    var body: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // REVERB Section
                        VStack(alignment: .leading, spacing: 12) {
                            // Section header with dot
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tapelabLight)
                                    .frame(width: 3, height: 3)

                                Text("REVERB")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }

                            VStack(spacing: 16) {
                                // Mix control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("MIX")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.0f%%", track.fx.reverb.wetMix))
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.reverb.wetMix) },
                                        set: { newValue in
                                            track.fx.reverb.wetMix = Float(newValue)
                                            applyFXUpdate()
                                            triggerSliderHaptic()
                                        }
                                    ), in: 0...100, step: 1)
                                    .accentColor(.tapelabAccentFull)
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)

                                // Room Size control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("ROOM SIZE")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(track.fx.reverb.roomSize ? "LARGE HALL" : "SMALL ROOM")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabAccentFull)
                                    }
                                    Toggle("", isOn: Binding(
                                        get: { track.fx.reverb.roomSize },
                                        set: { newValue in
                                            track.fx.reverb.roomSize = newValue
                                            applyFXUpdate()
                                            HapticsManager.shared.effectToggled()
                                        }
                                    ))
                                    .labelsHidden()
                                    .tint(.tapelabAccentFull)
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)
                            }
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

                            VStack(spacing: 16) {
                                // Mix control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("MIX")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.0f%%", track.fx.delay.wetMix))
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.delay.wetMix) },
                                        set: { newValue in
                                            track.fx.delay.wetMix = Float(newValue)
                                            applyFXUpdate()
                                            triggerSliderHaptic()
                                        }
                                    ), in: 0...100, step: 1)
                                    .accentColor(.tapelabAccentFull)
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)

                                // Time control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("TIME")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.2f S", track.fx.delay.time))
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { track.fx.delay.time },
                                        set: { newValue in
                                            track.fx.delay.time = newValue
                                            applyFXUpdate()
                                            triggerSliderHaptic()
                                        }
                                    ), in: 0.01...2.0, step: 0.01)
                                    .accentColor(.tapelabAccentFull)
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)

                                // Feedback control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("FEEDBACK")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.0f%%", track.fx.delay.feedback))
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.delay.feedback) },
                                        set: { newValue in
                                            track.fx.delay.feedback = Float(newValue)
                                            applyFXUpdate()
                                            triggerSliderHaptic()
                                        }
                                    ), in: 0...100, step: 1)
                                    .accentColor(.tapelabAccentFull)
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)
                            }
                        }

                        // SATURATION Section
                        VStack(alignment: .leading, spacing: 12) {
                            // Section header with dot
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tapelabLight)
                                    .frame(width: 3, height: 3)

                                Text("SATURATION")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }

                            VStack(spacing: 16) {
                                // Mix control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("MIX")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.0f%%", track.fx.saturation.wetMix))
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.saturation.wetMix) },
                                        set: { newValue in
                                            track.fx.saturation.wetMix = Float(newValue)
                                            applyFXUpdate()
                                            triggerSliderHaptic()
                                        }
                                    ), in: 0...100, step: 1)
                                    .accentColor(.tapelabAccentFull)
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)

                                // Drive control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("DRIVE")
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.1f DB", track.fx.saturation.preGain))
                                            .font(.tapelabMono)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.saturation.preGain) },
                                        set: { newValue in
                                            track.fx.saturation.preGain = Float(newValue)
                                            applyFXUpdate()
                                            triggerSliderHaptic()
                                        }
                                    ), in: -40...40, step: 0.5)
                                    .accentColor(.tapelabAccentFull)
                                }
                                .padding(16)
                                .background(TapelabTheme.Colors.surface)
                                .cornerRadius(8)
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("Track \(track.number) FX")
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

    private func applyFXUpdate() {
        // Apply FX changes in real-time if playing
        if runtime.timeline.isPlaying {
            let trackIndex = track.number - 1
            runtime.engine.trackBuses[trackIndex].applyFX(track.fx)
        }
    }

    private func triggerSliderHaptic() {
        // Rate-limit haptics to every 100ms to avoid overwhelming the haptic engine
        if Date().timeIntervalSince(lastSliderHapticTime) >= 0.1 {
            HapticsManager.shared.sliderAdjusted()
            lastSliderHapticTime = Date()
        }
    }
}
