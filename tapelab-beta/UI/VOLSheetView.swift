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

    
    var body: some View {
        NavigationView {
            ZStack {
                TapelabTheme.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // MIX Section (Volume & Pan in one box)
                        VStack(alignment: .leading, spacing: 12) {
                            // Section header with dot
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tapelabLight)
                                    .frame(width: 3, height: 3)

                                Text("MIX")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }

                            // Volume & Pan controls in one box
                            VStack(spacing: 16) {
                                // Volume control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("VOLUME")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(String(format: "%.1f dB", track.fx.volumeDB))
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { track.fx.volumeDB },
                                        set: { newValue in
                                            track.fx.volumeDB = newValue
                                            applyFXUpdate()
                                        }
                                    ), in: -40...12, step: 0.5)
                                    .accentColor(.tapelabAccentFull)
                                }

                                // Pan control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("PAN")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(track.fx.pan < 0 ? String(format: "L%.0f", abs(track.fx.pan) * 100) :
                                             track.fx.pan > 0 ? String(format: "R%.0f", track.fx.pan * 100) :
                                             "C")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { Double(track.fx.pan) },
                                        set: { newValue in
                                            track.fx.pan = Float(newValue)
                                            applyFXUpdate()
                                        }
                                    ), in: -1...1, step: 0.1)
                                    .accentColor(.tapelabAccentFull)
                                }
                            }
                            .padding(16)
                            .background(TapelabTheme.Colors.surface)
                            .cornerRadius(8)
                        }

                        // EQUALIZER Section (Simple 2-band Low/High)
                        VStack(alignment: .leading, spacing: 12) {
                            // Section header with dot
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.tapelabLight)
                                    .frame(width: 3, height: 3)

                                Text("EQUALIZER")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }

                            // Simple Low/High EQ controls
                            VStack(spacing: 16) {
                                // Low (Bass) control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("LOW")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(formatGain(track.fx.eqBands.count > 0 ? track.fx.eqBands[0].gainDB : 0))
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { track.fx.eqBands.count > 0 ? track.fx.eqBands[0].gainDB : 0 },
                                        set: { newValue in
                                            if track.fx.eqBands.count > 0 {
                                                track.fx.eqBands[0].gainDB = newValue
                                                applyFXUpdate()
                                            }
                                        }
                                    ), in: -12...12, step: 0.5)
                                    .accentColor(.tapelabAccentFull)
                                }

                                // High (Treble) control
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("HIGH")
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabLight)
                                        Spacer()
                                        Text(formatGain(track.fx.eqBands.count > 1 ? track.fx.eqBands[1].gainDB : 0))
                                            .font(.tapelabMonoSmall)
                                            .foregroundColor(.tapelabAccentFull)
                                            .monospacedDigit()
                                    }
                                    Slider(value: Binding(
                                        get: { track.fx.eqBands.count > 1 ? track.fx.eqBands[1].gainDB : 0 },
                                        set: { newValue in
                                            if track.fx.eqBands.count > 1 {
                                                track.fx.eqBands[1].gainDB = newValue
                                                applyFXUpdate()
                                            }
                                        }
                                    ), in: -12...12, step: 0.5)
                                    .accentColor(.tapelabAccentFull)
                                }
                            }
                            .padding(16)
                            .background(TapelabTheme.Colors.surface)
                            .cornerRadius(8)
                        }

                        // Reset Button
                        Button(action: {
                            track.fx.resetVolume()
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
                    Text("Track \(track.number) Volume & EQ")
                        .font(.tapelabMonoSmall)
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


    // MARK: - Helper Functions

    private func formatGain(_ gain: Double) -> String {
        if gain >= 0 {
            return String(format: "+%.1f dB", gain)
        } else {
            return String(format: "%.1f dB", gain)
        }
    }
}
