//
//  TimelineRulerView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct TimelineRulerView: View {
    @ObservedObject var timeline: TimelineState
    let pixelsPerSecond: CGFloat
    let maxDuration: Double
    let bpm: Double?
    let timelineMode: TimelineMode

    @State private var isDragging = false
    @State private var lastHapticPosition: CGFloat = 0

    // Convert time to beats (only used in BPM mode)
    private func timeToBeat(_ time: Double) -> Double {
        guard let bpm = bpm else { return 0 }
        return (time / 60.0) * bpm
    }

    // Convert beats to time (only used in BPM mode)
    private func beatToTime(_ beat: Double) -> Double {
        guard let bpm = bpm else { return 0 }
        return (beat / bpm) * 60.0
    }

    private var totalBeats: Int {
        guard timelineMode == .bpm else { return 0 }
        return Int(ceil(timeToBeat(maxDuration)))
    }

    private var totalSeconds: Int {
        guard timelineMode == .seconds else { return 0 }
        return Int(ceil(maxDuration))
    }

    private var totalWidth: CGFloat {
        maxDuration * pixelsPerSecond
    }

    private var pointerPosition: CGFloat {
        timeline.playhead * pixelsPerSecond
    }

    // Calculate spacing between beats in pixels (BPM mode only)
    private var beatSpacing: CGFloat {
        guard let bpm = bpm else { return 0 }
        let beatDuration = 60.0 / bpm
        return CGFloat(beatDuration) * pixelsPerSecond
    }

    // Calculate spacing between seconds in pixels (seconds mode)
    private var secondSpacing: CGFloat {
        return pixelsPerSecond
    }

    // Only show numbers if there's enough space (minimum 45 pixels between markers)
    private var shouldShowNumbers: Bool {
        if timelineMode == .bpm {
            return beatSpacing >= 45
        } else {
            return secondSpacing >= 45
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background - tappable to move playhead
            Rectangle()
                .fill(Color.tapelabBlack)
                .frame(height: 30)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // Move playhead to tapped position
                    let newPlayhead = location.x / pixelsPerSecond
                    let clampedPlayhead = max(0, min(newPlayhead, maxDuration))
                    timeline.playhead = clampedPlayhead
                }

            // Markers (beats or seconds depending on mode)
            ZStack(alignment: .topLeading) {
                if timelineMode == .bpm {
                    // BPM mode - show beats
                    ForEach(1...totalBeats, id: \.self) { beat in
                        VStack(spacing: 2) {
                            if shouldShowNumbers {
                                Text("\(beat)")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                                    .frame(width: 40)
                                    .multilineTextAlignment(.center)
                            } else {
                                Color.clear
                                    .frame(width: 40, height: 14)
                            }

                            Rectangle()
                                .fill(Color.tapelabLight)
                                .frame(width: 1, height: 4)
                        }
                        .frame(width: 40)
                        .offset(x: beatToTime(Double(beat)) * pixelsPerSecond - 20, y: 0)
                    }

                    // Quarter beat dots
                    ForEach(1...totalBeats, id: \.self) { beat in
                        ForEach(1...3, id: \.self) { subdivision in
                            let quarterPosition = Double(beat - 1) + (Double(subdivision) * 0.25)
                            Circle()
                                .fill(Color.tapelabLight.opacity(0.1))
                                .frame(width: 3, height: 3)
                                .offset(
                                    x: beatToTime(quarterPosition) * pixelsPerSecond - 1.5,
                                    y: 13.5
                                )
                        }
                    }
                } else {
                    // Seconds mode - show seconds
                    ForEach(1...totalSeconds, id: \.self) { second in
                        VStack(spacing: 2) {
                            if shouldShowNumbers {
                                Text("\(second)s")
                                    .font(.tapelabMonoSmall)
                                    .foregroundColor(.tapelabLight)
                                    .frame(width: 40)
                                    .multilineTextAlignment(.center)
                            } else {
                                Color.clear
                                    .frame(width: 40, height: 14)
                            }

                            Rectangle()
                                .fill(Color.tapelabLight)
                                .frame(width: 1, height: 4)
                        }
                        .frame(width: 40)
                        .offset(x: Double(second) * pixelsPerSecond - 20, y: 0)
                    }

                    // Quarter second dots (subdivisions between seconds)
                    ForEach(1...totalSeconds, id: \.self) { second in
                        ForEach(1...3, id: \.self) { subdivision in
                            let quarterPosition = Double(second - 1) + (Double(subdivision) * 0.25)
                            Circle()
                                .fill(Color.tapelabLight.opacity(0.1))
                                .frame(width: 3, height: 3)
                                .offset(
                                    x: quarterPosition * pixelsPerSecond - 1.5,
                                    y: 13.5
                                )
                        }
                    }
                }
            }
            .frame(height: 30)
            .allowsHitTesting(false)

            // Playhead handle (larger touch target)
            ZStack {
                // Invisible larger hit area
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())

                // Visible handle - 50% opacity, no border
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.red.opacity(0.5))
                    .frame(width: 12, height: 24)
            }
            .offset(x: pointerPosition - 22, y: 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // Haptic on drag start
                        if !isDragging {
                            HapticsManager.shared.playheadDragStart()
                            isDragging = true
                            lastHapticPosition = value.location.x
                        }

                        // Use absolute location.x directly - follows your finger
                        let newPosition = max(0, min(value.location.x, totalWidth))
                        let newPlayhead = newPosition / pixelsPerSecond
                        timeline.playhead = newPlayhead

                        // Periodic haptic feedback while dragging (every ~50 pixels)
                        if abs(value.location.x - lastHapticPosition) > 50 {
                            HapticsManager.shared.playheadDragging()
                            lastHapticPosition = value.location.x
                        }
                    }
                    .onEnded { _ in
                        // Haptic on drag end
                        HapticsManager.shared.playheadDragEnd()
                        isDragging = false
                    }
            )
        }
        .frame(height: 30)
        .background(Color.tapelabBlack)
    }
}

// MARK: - Triangle Shape
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
