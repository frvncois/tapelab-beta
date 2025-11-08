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
    let bpm: Double

    @State private var isDragging = false
    @State private var lastHapticPosition: CGFloat = 0

    // Convert time to beats
    private func timeToBeat(_ time: Double) -> Double {
        return (time / 60.0) * bpm
    }

    // Convert beats to time
    private func beatToTime(_ beat: Double) -> Double {
        return (beat / bpm) * 60.0
    }

    private var totalBeats: Int {
        Int(ceil(timeToBeat(maxDuration)))
    }

    private var totalWidth: CGFloat {
        maxDuration * pixelsPerSecond
    }

    private var pointerPosition: CGFloat {
        timeline.playhead * pixelsPerSecond
    }

    // Calculate spacing between beats in pixels
    private var beatSpacing: CGFloat {
        let beatDuration = 60.0 / bpm
        return CGFloat(beatDuration) * pixelsPerSecond
    }

    // Only show numbers if there's enough space (minimum 45 pixels between beats)
    private var shouldShowNumbers: Bool {
        return beatSpacing >= 45
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

            // Beat markers (positioned at exact grid lines)
            ZStack(alignment: .topLeading) {
                ForEach(1...totalBeats, id: \.self) { beat in
                    VStack(spacing: 2) {
                        // Show beat number only if there's enough space
                        if shouldShowNumbers {
                            Text("\(beat)")
                                .font(.tapelabMonoSmall)
                                .foregroundColor(.tapelabLight)
                                .frame(width: 40) // Fixed width for centering
                                .multilineTextAlignment(.center)
                        } else {
                            // Show empty space to maintain layout
                            Color.clear
                                .frame(width: 40, height: 14)
                        }

                        Rectangle()
                            .fill(Color.tapelabLight)
                            .frame(width: 1, height: 4)
                    }
                    .frame(width: 40) // Fixed width container
                    .offset(x: beatToTime(Double(beat)) * pixelsPerSecond - 20, y: 0) // Center the 40pt frame on grid line
                }

                // Quarter beat dots (subdivisions between beats)
                ForEach(1...totalBeats, id: \.self) { beat in
                    // Add 3 dots between this beat and the next (at 0.25, 0.5, 0.75 of beat duration)
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
            }
            .frame(height: 30)
            .allowsHitTesting(false) // Don't intercept taps, let background handle it

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
