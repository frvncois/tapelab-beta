//
//  VOLSheetView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct VOLSheetView: View {
    @Binding var track: Track
    let runtime: AudioRuntime
    @Environment(\.dismiss) var dismiss

    @State private var lastSliderHapticTime = Date()

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Volume & Pan
                    VStack(alignment: .leading, spacing: 8) {
                        Text("MIX")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        HStack {
                            Text("Volume")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.1f dB", track.fx.volumeDB))
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { track.fx.volumeDB },
                            set: { newValue in
                                track.fx.volumeDB = newValue
                                applyFXUpdate()
                                triggerSliderHaptic()
                            }
                        ), in: -40...12, step: 0.5)

                        HStack {
                            Text("Pan")
                                .font(.caption)
                            Spacer()
                            Text(track.fx.pan < 0 ? String(format: "L%.0f", abs(track.fx.pan) * 100) :
                                 track.fx.pan > 0 ? String(format: "R%.0f", track.fx.pan * 100) :
                                 "C")
                                .font(.caption)
                                .monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { Double(track.fx.pan) },
                            set: { newValue in
                                track.fx.pan = Float(newValue)
                                applyFXUpdate()
                                triggerSliderHaptic()
                            }
                        ), in: -1...1, step: 0.1)
                    }
                }
                .padding()
            }
            .navigationTitle("Track \(track.number) Volume")
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
