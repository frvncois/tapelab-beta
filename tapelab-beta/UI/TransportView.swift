//
//  TransportView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct TransportView: View {
    @ObservedObject var runtime: AudioRuntime
    @ObservedObject var timeline: TimelineState
    let armedTrack: Int
    var onBounce: (() -> Void)?

    @State private var rewindTimer: Timer?
    @State private var forwardTimer: Timer?
    @State private var scrubSpeed: Double = 0.0
    @State private var scrubStartTime: Date?

    init(runtime: AudioRuntime, armedTrack: Int, onBounce: (() -> Void)? = nil) {
        self.runtime = runtime
        self.timeline = runtime.timeline
        self.armedTrack = armedTrack
        self.onBounce = onBounce
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 12) {
                Button(action: {
                    HapticsManager.shared.trackSelected()
                    toggleLoopMode()
                }) {
                    Text("LOOP")
                        .font(.tapelabMonoTiny)
                        .foregroundColor(timeline.isLoopMode ? .tapelabBlack : .tapelabLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(timeline.isLoopMode ? Color.tapelabOrange : Color.tapelabButtonBg)
                        .cornerRadius(16)
                }
                .disabled(timeline.isRecording)
                .opacity(timeline.isRecording ? 0.5 : 1.0)

                Spacer()

                HStack(spacing: 16) {
                    Image(systemName: "backward.end.fill")
                        .font(.title2)
                        .foregroundColor(.tapelabAccentFull)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            timeline.seek(to: 0)
                        }
                        .onTapGesture(count: 1) {
                            let newPosition = max(0, timeline.playhead - 1.0)
                            timeline.seek(to: newPosition)
                        }
                        .onLongPressGesture(minimumDuration: 0.3, pressing: { isPressing in
                            if isPressing {
                                startRewindScrub()
                            } else {
                                stopRewindScrub()
                            }
                        }, perform: {})

                    Button(action: {
                        if timeline.isPlaying && !timeline.isRecording {
                            HapticsManager.shared.stopPressed()
                            runtime.stopPlayback(resetPlayhead: false)
                        } else if !timeline.isRecording {
                            HapticsManager.shared.playPressed()
                            Task { await runtime.startPlayback() }
                        }
                    }) {
                        let isPlayingOnly = timeline.isPlaying && !timeline.isRecording
                        Image(systemName: isPlayingOnly ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title)
                            .foregroundColor(isPlayingOnly ? .tapelabOrange : .tapelabGreen)
                    }
                    .buttonStyle(.plain)
                    .disabled(timeline.isRecording)

                    // Record/Stop Record toggle button
                    Button(action: {
                        if timeline.isRecording {
                            HapticsManager.shared.recordStop()
                            runtime.stopRecording(onTrack: armedTrack - 1)
                        } else {
                            HapticsManager.shared.recordStart()
                            Task {
                                let success = await runtime.startRecording(onTrack: armedTrack - 1)
                                if !success {
                                    // Recording didn't start (headphones not connected)
                                    // Alert is already shown by AudioRuntime
                                }
                            }
                        }
                    }) {
                        Image(systemName: timeline.isRecording ? "stop.circle.fill" : "circle.fill")
                            .font(.title)
                            .foregroundColor(.tapelabRed)
                    }
                    .buttonStyle(.plain)
                    .disabled(timeline.isPlaying && !timeline.isRecording)

                    // Forward button
                    Image(systemName: "forward.end.fill")
                        .font(.title2)
                        .foregroundColor(.tapelabAccentFull)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            // Double tap: jump to end
                            let maxDuration = runtime.session.maxDuration
                            timeline.seek(to: maxDuration)
                        }
                        .onTapGesture(count: 1) {
                            // Single tap: forward 1 second
                            let maxDuration = runtime.session.maxDuration
                            let newPosition = min(maxDuration, timeline.playhead + 1.0)
                            timeline.seek(to: newPosition)
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

                // Bounce button (right side)
                Button(action: {
                    onBounce?()
                }) {
                    Text("BOUNCE")
                        .font(.tapelabMonoTiny)
                        .foregroundColor(.tapelabLight)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.tapelabButtonBg)
                        .cornerRadius(16)
                }
                .disabled(timeline.isRecording || timeline.isPlaying)
                .opacity((timeline.isRecording || timeline.isPlaying) ? 0.5 : 1.0)
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
        .onDisappear {
            // Clean up any running timers when view disappears
            rewindTimer?.invalidate()
            rewindTimer = nil
            forwardTimer?.invalidate()
            forwardTimer = nil
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
                let newPosition = max(0, self.timeline.playhead - (self.scrubSpeed * 0.05))
                self.timeline.seek(to: newPosition)

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
                let newPosition = min(maxDuration, self.timeline.playhead + (self.scrubSpeed * 0.05))
                self.timeline.seek(to: newPosition)

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

    // Toggle loop mode
    private func toggleLoopMode() {
        // Don't allow toggling loop during recording
        guard !timeline.isRecording else { return }

        timeline.isLoopMode.toggle()

        if timeline.isLoopMode {
            // Enable loop mode - set loop region starting at current playhead with 2s duration
            timeline.loopStart = timeline.playhead
            timeline.loopEnd = timeline.playhead + 2.0

            // Ensure loop end doesn't exceed max duration
            if timeline.loopEnd > runtime.session.maxDuration {
                timeline.loopEnd = runtime.session.maxDuration
                timeline.loopStart = max(0, timeline.loopEnd - 2.0)
            }

        } else {
        }
    }
}
