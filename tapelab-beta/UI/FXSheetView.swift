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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Reverb
                    VStack(alignment: .leading, spacing: 8) {
                        Text("REVERB")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Mix")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", track.fx.reverb.wetMix))
                                .font(.caption)
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

                        Toggle("Large Hall", isOn: Binding(
                            get: { track.fx.reverb.roomSize },
                            set: { newValue in
                                track.fx.reverb.roomSize = newValue
                                applyFXUpdate()
                                HapticsManager.shared.effectToggled()
                            }
                        ))
                        .font(.caption)
                    }

                    Divider()

                    // Delay
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DELAY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Mix")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", track.fx.delay.wetMix))
                                .font(.caption)
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

                        HStack {
                            Text("Time")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.2f s", track.fx.delay.time))
                                .font(.caption)
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

                        HStack {
                            Text("Feedback")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", track.fx.delay.feedback))
                                .font(.caption)
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
                    }

                    Divider()

                    // Saturation
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SATURATION")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Mix")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.0f%%", track.fx.saturation.wetMix))
                                .font(.caption)
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

                        HStack {
                            Text("Drive")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.1f dB", track.fx.saturation.preGain))
                                .font(.caption)
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
                    }
                }
                .padding()
            }
            .navigationTitle("Track \(track.number) FX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
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
