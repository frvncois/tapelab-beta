//
//  MetronomeSheetView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct MetronomeSheetView: View {
    @ObservedObject var runtime: AudioRuntime
    @Environment(\.dismiss) var dismiss

    @State private var localBPM: Double = 120.0
    @State private var localTimeSignature: TimeSignature = .fourFour
    @State private var countInEnabled: Bool = true
    @State private var playWhileRecording: Bool = false
    @State private var lastSliderHapticTime = Date()

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                Text("Metronome")
                    .font(.tapelabMonoHeadline)
                    .foregroundColor(.tapelabLight)
                    .padding(.top)

                Spacer()

                // BPM Display
                VStack(spacing: 8) {
                    Text("\(Int(localBPM))")
                        .font(.system(size: 72, weight: .bold, design: .monospaced))
                        .foregroundColor(.tapelabAccentFull)

                    Text("BPM")
                        .font(.tapelabMono)
                        .foregroundColor(.tapelabLight)
                }

                // BPM Slider
                VStack(spacing: 8) {
                    Slider(value: $localBPM, in: 40...240, step: 1)
                        .accentColor(.tapelabAccentFull)
                        .padding(.horizontal, 32)
                        .onChange(of: localBPM) { newValue in
                            // Update metronome BPM in real-time
                            runtime.metronome.bpm = newValue
                            // Rate-limited haptic feedback
                            if Date().timeIntervalSince(lastSliderHapticTime) >= 0.1 {
                                HapticsManager.shared.sliderAdjusted()
                                lastSliderHapticTime = Date()
                            }
                        }

                    HStack {
                        Text("40")
                            .font(.tapelabMonoSmall)
                            .foregroundColor(.tapelabAccentFull)

                        Spacer()

                        Text("240")
                            .font(.tapelabMonoSmall)
                            .foregroundColor(.tapelabAccentFull)
                    }
                    .padding(.horizontal, 32)
                }

                // Time Signature Picker - Segmented Control Style
                VStack(spacing: 12) {
                    Text("Time Signature")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)

                    // Segmented control style - all options in one row
                    HStack(spacing: 0) {
                        ForEach(TimeSignature.allCases, id: \.self) { sig in
                            Button(action: {
                                localTimeSignature = sig
                                // Update metronome time signature in real-time
                                runtime.metronome.timeSignature = sig
                                HapticsManager.shared.effectToggled()
                            }) {
                                Text(sig.displayName)
                                    .font(.tapelabMono)
                                    .foregroundColor(localTimeSignature == sig ? .tapelabBackground : .tapelabLight)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 44)
                                    .background(localTimeSignature == sig ? Color.tapelabAccentFull : Color.tapelabAccent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.tapelabAccentFull, lineWidth: 1)
                    )
                    .padding(.horizontal, 32)
                }

                // Recording Options
                VStack(alignment: .leading, spacing: 16) {
                    Text("Recording Options")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)

                    // Count-in toggle
                    HStack {
                        Toggle(isOn: $countInEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Count-in Before Recording")
                                    .font(.tapelabMono)
                                    .foregroundColor(.tapelabLight)
                                Text("Play \(localTimeSignature.beatsPerMeasure) beats before recording starts")
                                    .font(.tapelabMonoTiny)
                                    .foregroundColor(.tapelabAccentFull)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .tapelabGreen))
                        .onChange(of: countInEnabled) { _ in
                            HapticsManager.shared.effectToggled()
                        }
                    }

                    // Play while recording toggle
                    HStack {
                        Toggle(isOn: $playWhileRecording) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Play While Recording")
                                    .font(.tapelabMono)
                                    .foregroundColor(.tapelabLight)
                                Text("Keep metronome playing during recording")
                                    .font(.tapelabMonoTiny)
                                    .foregroundColor(.tapelabAccentFull)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .tapelabGreen))
                        .onChange(of: playWhileRecording) { _ in
                            HapticsManager.shared.effectToggled()
                        }
                    }
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.tapelabBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        // Dismiss will trigger onDisappear which applies changes
                        dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.tapelabAccentFull)
                    }
                }
            }
        }
        .onAppear {
            // Initialize local BPM and time signature from session (source of truth)
            localBPM = runtime.session.bpm
            localTimeSignature = runtime.session.timeSignature
            // Sync metronome with session BPM and time signature
            runtime.metronome.bpm = runtime.session.bpm
            runtime.metronome.timeSignature = runtime.session.timeSignature
            // Initialize recording options from session
            countInEnabled = runtime.session.metronomeCountIn
            playWhileRecording = runtime.session.metronomeWhileRecording

            // Auto-start metronome when sheet opens
            Task {
                await runtime.metronome.play()
            }
        }
        .onDisappear {
            // Apply all changes to session when sheet closes
            runtime.session.bpm = localBPM
            runtime.session.timeSignature = localTimeSignature
            runtime.session.metronomeCountIn = countInEnabled
            runtime.session.metronomeWhileRecording = playWhileRecording

            // Stop metronome when sheet closes
            runtime.metronome.stop()
        }
    }
}
