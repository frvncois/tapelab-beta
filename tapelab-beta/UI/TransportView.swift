//
//  TransportView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct TransportView: View {
    @ObservedObject var runtime: AudioRuntime
    let armedTrack: Int

    @State private var rewindTimer: Timer?
    @State private var forwardTimer: Timer?
    @State private var scrubSpeed: Double = 0.0
    @State private var scrubStartTime: Date?
    @State private var showMetronomeSheet = false

    var body: some View {
        VStack(spacing: 20) {
            // Top row: [TUNER] - - - [controls] - - - [MTRO]
            HStack(spacing: 12) {
                // Tuner Button (left)
                Button(action: {
                    // TODO: Tuner functionality
                }) {
                    Text("TUNER")
                        .font(.tapelabMonoTiny)
                        .foregroundColor(.tapelabLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.tapelabButtonBg)
                        .cornerRadius(16)
                }

                Spacer()

                // Main transport controls - centered
                HStack(spacing: 16) {
                    // Rewind button
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                        .foregroundColor(.tapelabAccentFull)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            // Double tap: jump to start
                            runtime.timeline.seek(to: 0)
                        }
                        .onTapGesture(count: 1) {
                            // Single tap: rewind 1 second
                            let newPosition = max(0, runtime.timeline.playhead - 1.0)
                            runtime.timeline.seek(to: newPosition)
                        }
                        .onLongPressGesture(minimumDuration: 0.3, pressing: { isPressing in
                            if isPressing {
                                // Start scrubbing backward
                                startRewindScrub()
                            } else {
                                // Stop scrubbing
                                stopRewindScrub()
                            }
                        }, perform: {})

                    // Play/Stop toggle button
                    Button(action: {
                        print("🔘 PLAY BUTTON PRESSED")
                        if runtime.timeline.isPlaying && !runtime.timeline.isRecording {
                            print("🔘 Stopping playback")
                            HapticsManager.shared.stopPressed()
                            runtime.stopPlayback(resetPlayhead: false)
                        } else if !runtime.timeline.isRecording {
                            print("🔘 Starting playback")
                            HapticsManager.shared.playPressed()
                            Task { await runtime.startPlayback() }
                        }
                    }) {
                        Image(systemName: (runtime.timeline.isPlaying && !runtime.timeline.isRecording) ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .foregroundColor((runtime.timeline.isPlaying && !runtime.timeline.isRecording) ? .tapelabRed : .tapelabGreen)
                    }
                    .buttonStyle(.plain)
                    .disabled(runtime.timeline.isRecording)

                    // Record/Stop Record toggle button
                    Button(action: {
                        if runtime.timeline.isRecording {
                            HapticsManager.shared.recordStop()
                            runtime.stopRecording(onTrack: armedTrack - 1)
                        } else {
                            HapticsManager.shared.recordStart()
                            Task { await runtime.startRecording(onTrack: armedTrack - 1) }
                        }
                    }) {
                        Image(systemName: runtime.timeline.isRecording ? "stop.circle.fill" : "circle.fill")
                            .font(.title)
                            .foregroundColor(.tapelabRed)
                    }
                    .buttonStyle(.plain)
                    .disabled(runtime.timeline.isPlaying && !runtime.timeline.isRecording)

                    // Forward button
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                        .foregroundColor(.tapelabAccentFull)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            // Double tap: jump to end
                            let maxDuration = runtime.session.maxDuration
                            runtime.timeline.seek(to: maxDuration)
                        }
                        .onTapGesture(count: 1) {
                            // Single tap: forward 1 second
                            let maxDuration = runtime.session.maxDuration
                            let newPosition = min(maxDuration, runtime.timeline.playhead + 1.0)
                            runtime.timeline.seek(to: newPosition)
                        }
                        .onLongPressGesture(minimumDuration: 0.3, pressing: { isPressing in
                            if isPressing {
                                // Start scrubbing forward
                                startForwardScrub()
                            } else {
                                // Stop scrubbing
                                stopForwardScrub()
                            }
                        }, perform: {})
                }

                Spacer()

                // Tempo Button (right)
                Button(action: {
                    showMetronomeSheet = true
                }) {
                    Text("TEMP")
                        .font(.tapelabMonoTiny)
                        .foregroundColor(.tapelabLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.tapelabButtonBg)
                        .cornerRadius(16)
                }
            }
            .padding(.horizontal)

            // Input Level Meter (always visible)
            VStack(spacing: 0) {
                // Level meter
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.tapelabAccent)
                            .frame(height: 4)
                            .cornerRadius(4)

                        Rectangle()
                            .fill(
                                runtime.recorder.inputLevel > 0.8 ? Color.tapelabRed :
                                runtime.recorder.inputLevel > 0.6 ? Color.tapelabOrange :
                                Color.tapelabGreen
                            )
                            .frame(width: geometry.size.width * CGFloat(min(1.0, runtime.recorder.inputLevel)), height: 4)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 4)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.top, 20)
        .padding(.horizontal)
        .padding(.bottom)
        .background(Color.tapelabBlack)
        .sheet(isPresented: $showMetronomeSheet) {
            MetronomeSheetView(runtime: runtime)
        }
    }

    // MARK: - Scrubbing Helper Functions

    private func startRewindScrub() {
        scrubStartTime = Date()
        scrubSpeed = 0.0
        var lastHapticTime = Date()

        rewindTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] _ in
            Task { @MainActor in
                // Calculate ease-in speed based on how long the button has been held
                let holdDuration = Date().timeIntervalSince(self.scrubStartTime ?? Date())

                // Ease-in curve: speed increases over 2 seconds
                let targetSpeed = min(holdDuration / 2.0, 1.0) // Normalized 0-1 over 2 seconds

                // Apply easing function (ease-in-out cubic)
                let easedSpeed = self.easeInOutCubic(targetSpeed)

                // Convert to actual scrub speed (0.5 to 10 seconds per second)
                self.scrubSpeed = 0.5 + (easedSpeed * 9.5)

                // Move playhead backward
                let newPosition = max(0, self.runtime.timeline.playhead - (self.scrubSpeed * 0.05))
                self.runtime.timeline.seek(to: newPosition)

                // Haptic feedback every 100ms
                if Date().timeIntervalSince(lastHapticTime) >= 0.1 {
                    HapticsManager.shared.scrubTick()
                    lastHapticTime = Date()
                }
            }
        }
    }

    private func stopRewindScrub() {
        rewindTimer?.invalidate()
        rewindTimer = nil
        scrubSpeed = 0.0
        scrubStartTime = nil
    }

    private func startForwardScrub() {
        scrubStartTime = Date()
        scrubSpeed = 0.0
        var lastHapticTime = Date()

        forwardTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [self] _ in
            Task { @MainActor in
                // Calculate ease-in speed based on how long the button has been held
                let holdDuration = Date().timeIntervalSince(self.scrubStartTime ?? Date())

                // Ease-in curve: speed increases over 2 seconds
                let targetSpeed = min(holdDuration / 2.0, 1.0) // Normalized 0-1 over 2 seconds

                // Apply easing function (ease-in-out cubic)
                let easedSpeed = self.easeInOutCubic(targetSpeed)

                // Convert to actual scrub speed (0.5 to 10 seconds per second)
                self.scrubSpeed = 0.5 + (easedSpeed * 9.5)

                // Move playhead forward
                let maxDuration = self.runtime.session.maxDuration
                let newPosition = min(maxDuration, self.runtime.timeline.playhead + (self.scrubSpeed * 0.05))
                self.runtime.timeline.seek(to: newPosition)

                // Haptic feedback every 100ms
                if Date().timeIntervalSince(lastHapticTime) >= 0.1 {
                    HapticsManager.shared.scrubTick()
                    lastHapticTime = Date()
                }
            }
        }
    }

    private func stopForwardScrub() {
        forwardTimer?.invalidate()
        forwardTimer = nil
        scrubSpeed = 0.0
        scrubStartTime = nil
    }

    // Ease-in-out cubic function
    private func easeInOutCubic(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let f = (2 * t) - 2
            return 0.5 * f * f * f + 1
        }
    }
}
