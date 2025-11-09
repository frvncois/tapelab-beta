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

                    Divider()
                        .padding(.vertical, 8)

                    // EQ Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("EQUALIZER")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        ForEach(track.fx.eqBands.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 6) {
                                // Band label
                                Text(eqBandLabel(for: index))
                                    .font(.caption)
                                    .fontWeight(.semibold)

                                // Frequency control
                                HStack {
                                    Text("Frequency")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatFrequency(track.fx.eqBands[index].frequency))
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { track.fx.eqBands[index].frequency },
                                    set: { newValue in
                                        track.fx.eqBands[index].frequency = newValue
                                        applyFXUpdate()
                                        triggerSliderHaptic()
                                    }
                                ), in: frequencyRange(for: index), step: frequencyStep(for: index))

                                // Gain control
                                HStack {
                                    Text("Gain")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatGain(track.fx.eqBands[index].gainDB))
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { track.fx.eqBands[index].gainDB },
                                    set: { newValue in
                                        track.fx.eqBands[index].gainDB = newValue
                                        applyFXUpdate()
                                        triggerSliderHaptic()
                                    }
                                ), in: -12...12, step: 0.5)

                                // Q control
                                HStack {
                                    Text("Q Factor")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatQ(track.fx.eqBands[index].q))
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: Binding(
                                    get: { track.fx.eqBands[index].q },
                                    set: { newValue in
                                        track.fx.eqBands[index].q = newValue
                                        applyFXUpdate()
                                        triggerSliderHaptic()
                                    }
                                ), in: 0.5...3.0, step: 0.1)

                                // Divider between bands (except last)
                                if index < track.fx.eqBands.count - 1 {
                                    Divider()
                                        .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Track \(track.number) Volume & EQ")
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

    // MARK: - EQ Helper Functions

    private func eqBandLabel(for index: Int) -> String {
        switch index {
        case 0: return "Low (100 Hz)"
        case 1: return "Low-Mid (500 Hz)"
        case 2: return "High-Mid (2 kHz)"
        case 3: return "High (8 kHz)"
        default: return "Band \(index + 1)"
        }
    }

    private func frequencyRange(for index: Int) -> ClosedRange<Double> {
        switch index {
        case 0: return 60...250      // Low
        case 1: return 250...1000    // Low-Mid
        case 2: return 1000...4000   // High-Mid
        case 3: return 4000...16000  // High
        default: return 60...16000
        }
    }

    private func frequencyStep(for index: Int) -> Double {
        switch index {
        case 0: return 5      // Low: 5 Hz steps
        case 1: return 10     // Low-Mid: 10 Hz steps
        case 2: return 50     // High-Mid: 50 Hz steps
        case 3: return 100    // High: 100 Hz steps
        default: return 10
        }
    }

    private func formatFrequency(_ frequency: Double) -> String {
        if frequency >= 1000 {
            return String(format: "%.1f kHz", frequency / 1000)
        } else {
            return String(format: "%.0f Hz", frequency)
        }
    }

    private func formatGain(_ gain: Double) -> String {
        if gain >= 0 {
            return String(format: "+%.1f dB", gain)
        } else {
            return String(format: "%.1f dB", gain)
        }
    }

    private func formatQ(_ q: Double) -> String {
        return String(format: "Q: %.1f", q)
    }
}
