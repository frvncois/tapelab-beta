//
//  MetronomeSheetView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI
import Combine

struct MetronomeSheetView: View {
    @ObservedObject var runtime: AudioRuntime
    @Environment(\.dismiss) var dismiss

    @State private var localBPM: Double = 120.0
    @State private var localTimeSignature: TimeSignature = .fourFour
    @State private var countInEnabled: Bool = true
    @State private var playWhileRecording: Bool = false
    @State private var applyToSession: Bool = false
    @State private var lastSliderHapticTime = Date()
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseTimer: Timer?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                // Header
                Text("Metronome")
                    .font(.tapelabMonoHeadline)
                    .foregroundColor(.tapelabLight)
                    .padding(.top)

                // BPM Display - Pulsing Circle
                ZStack {
                    // Animated pulse circle
                    Circle()
                        .stroke(Color.tapelabAccentFull, lineWidth: 2)
                        .frame(width: 160, height: 160)
                        .scaleEffect(pulseScale)
                        .animation(.easeInOut(duration: 60.0 / localBPM), value: pulseScale)

                    // Background circle
                    Circle()
                        .fill(Color.tapelabLight.opacity(0.1))
                        .frame(width: 160, height: 160)

                    // BPM text
                    VStack(spacing: 4) {
                        Text("\(Int(localBPM))")
                            .font(.system(size: 52, weight: .bold, design: .monospaced))
                            .foregroundColor(.tapelabAccentFull)

                        Text("BPM")
                            .font(.tapelabMonoSmall)
                            .foregroundColor(.tapelabLight)
                    }
                }
                .padding(.vertical, 16)

                // BPM Slider
                VStack(spacing: 8) {
                    Slider(value: $localBPM, in: 40...240, step: 1)
                        .accentColor(.tapelabAccentFull)
                        .padding(.horizontal, 32)
                        .onChange(of: localBPM) { newValue in
                            // Update metronome BPM in real-time
                            runtime.metronome.bpm = newValue

                            // If BPM is applied to session, update it in real-time
                            if applyToSession {
                                var updatedSession = runtime.session
                                updatedSession.bpm = newValue
                                runtime.session = updatedSession
                                // Force UI update
                                runtime.objectWillChange.send()
                            }

                            // Restart pulse animation with new BPM
                            restartPulseAnimation()

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

                // Time Signature Picker - Brand Theme Style
                VStack(spacing: 12) {
                    Text("TIME SIGNATURE")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)

                    // Horizontal layout with brand-themed buttons
                    HStack(spacing: 12) {
                        ForEach(TimeSignature.allCases, id: \.self) { sig in
                            Button(action: {
                                localTimeSignature = sig
                                // Update metronome time signature in real-time
                                runtime.metronome.timeSignature = sig
                                HapticsManager.shared.effectToggled()
                            }) {
                                Text(sig.displayName)
                                    .font(.tapelabMonoSmall)
                                    .lineLimit(1)
                                    .foregroundColor(localTimeSignature == sig ? .tapelabAccentFull : .tapelabLight)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(localTimeSignature == sig ? Color.tapelabButtonBg.opacity(0.8) : Color.tapelabButtonBg)
                                    .cornerRadius(16)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(localTimeSignature == sig ? Color.tapelabAccentFull : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 32)
                }

                // Apply to Session Toggle
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Toggle(isOn: $applyToSession) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("APPLY BPM TO SESSION")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .tapelabGreen))
                        .onChange(of: applyToSession) { newValue in
                            HapticsManager.shared.effectToggled()
                            // Update session timeline mode immediately
                            var updatedSession = runtime.session
                            if newValue {
                                updatedSession.bpm = localBPM
                                updatedSession.timelineMode = .bpm
                            } else {
                                updatedSession.timelineMode = .seconds
                            }
                            // Reassign session to trigger @Published wrapper
                            runtime.session = updatedSession
                            // Force UI update
                            runtime.objectWillChange.send()
                        }
                    }
                }
                .padding(.horizontal, 32)

                // Recording Options
                VStack(alignment: .leading, spacing: 32) {

                    // Count-in toggle
                    HStack {
                        Toggle(isOn: $countInEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("COUNT-IN BEFORE RECORDING")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .tapelabGreen))
                        .onChange(of: countInEnabled) { newValue in
                            HapticsManager.shared.effectToggled()
                            // Auto-enable "Apply to Session" when enabling count-in
                            if newValue && !applyToSession {
                                applyToSession = true
                            }
                        }
                    }

                    // Play while recording toggle
                    HStack {
                        Toggle(isOn: $playWhileRecording) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("PLAY WHILE RECORDING")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                            }
                        }
                        .toggleStyle(SwitchToggleStyle(tint: .tapelabGreen))
                        .onChange(of: playWhileRecording) { newValue in
                            HapticsManager.shared.effectToggled()
                            // Auto-enable "Apply to Session" when enabling play while recording
                            if newValue && !applyToSession {
                                applyToSession = true
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity)
            }
            .background(Color.tapelabDark)
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
            localBPM = runtime.session.bpm ?? 120.0
            localTimeSignature = runtime.session.timeSignature
            applyToSession = runtime.session.timelineMode == .bpm

            // Sync metronome with local BPM and time signature
            runtime.metronome.bpm = localBPM
            runtime.metronome.timeSignature = runtime.session.timeSignature

            // Initialize recording options from session
            countInEnabled = runtime.session.metronomeCountIn
            playWhileRecording = runtime.session.metronomeWhileRecording

            // Auto-start metronome when sheet opens
            Task {
                await runtime.metronome.play()
            }

            // Start pulse animation
            startPulseAnimation()
        }
        .onDisappear {
            // Apply changes to session when sheet closes
            var updatedSession = runtime.session
            updatedSession.timeSignature = localTimeSignature
            updatedSession.metronomeCountIn = countInEnabled
            updatedSession.metronomeWhileRecording = playWhileRecording

            // Update timeline mode and BPM based on "Apply to Session" toggle
            if applyToSession {
                updatedSession.bpm = localBPM
                updatedSession.timelineMode = .bpm
            } else {
                updatedSession.timelineMode = .seconds
            }

            // Reassign session to trigger @Published wrapper
            runtime.session = updatedSession
            // Force UI update
            runtime.objectWillChange.send()

            // Stop pulse animation and metronome when sheet closes
            stopPulseAnimation()
            runtime.metronome.stop()
        }
    }

    // MARK: - Pulse Animation

    private func startPulseAnimation() {
        // Calculate beat duration from BPM (beats per minute -> seconds per beat)
        let beatDuration = 60.0 / localBPM

        // Start from base scale
        pulseScale = 1.0

        // Immediately pulse on first beat
        withAnimation(.easeOut(duration: 0.1)) {
            pulseScale = 1.15
        }
        withAnimation(.easeIn(duration: beatDuration - 0.1).delay(0.1)) {
            pulseScale = 1.0
        }

        // Schedule precise repeating timer on main run loop
        pulseTimer = Timer.scheduledTimer(withTimeInterval: beatDuration, repeats: true) { [self] _ in
            // Reset to base immediately (on the beat)
            pulseScale = 1.0

            // Quick pulse out
            withAnimation(.easeOut(duration: 0.1)) {
                pulseScale = 1.15
            }

            // Slow return to base
            withAnimation(.easeIn(duration: beatDuration - 0.1).delay(0.1)) {
                pulseScale = 1.0
            }
        }

        // Ensure timer fires on common run loop modes (won't be blocked by scrolling)
        if let timer = pulseTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopPulseAnimation() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseScale = 1.0
    }

    private func restartPulseAnimation() {
        stopPulseAnimation()
        startPulseAnimation()
    }
}
