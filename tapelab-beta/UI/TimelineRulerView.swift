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

    @State private var isDragging = false
    @State private var lastHapticPosition: CGFloat = 0
    @State private var isDraggingLoopStart = false
    @State private var isDraggingLoopEnd = false

    private var totalSeconds: Int {
        return Int(ceil(maxDuration))
    }

    private var totalWidth: CGFloat {
        maxDuration * pixelsPerSecond
    }

    private var pointerPosition: CGFloat {
        timeline.playhead * pixelsPerSecond
    }

    // Calculate spacing between seconds in pixels
    private var secondSpacing: CGFloat {
        return pixelsPerSecond
    }

    // Only show numbers if there's enough space (minimum 45 pixels between markers)
    private var shouldShowNumbers: Bool {
        return secondSpacing >= 45
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background - tappable to move playhead
            Rectangle()
                .fill(Color.tapelabBlack)
                .frame(height: 30)
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // Move playhead to tapped position (only if not in loop mode)
                    if !timeline.isLoopMode {
                        let newPlayhead = location.x / pixelsPerSecond
                        let clampedPlayhead = max(0, min(newPlayhead, maxDuration))
                        timeline.playhead = clampedPlayhead
                    }
                }

            // Loop region overlay (orange)
            if timeline.isLoopMode {
                loopOverlay
            }

            // Markers (seconds)
            ZStack(alignment: .topLeading) {
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

    // MARK: - Loop Overlay
    private var loopOverlay: some View {
        let loopStartX = timeline.loopStart * pixelsPerSecond
        let loopEndX = timeline.loopEnd * pixelsPerSecond
        let loopWidth = loopEndX - loopStartX

        return ZStack(alignment: .topLeading) {
            // Orange overlay region
            Rectangle()
                .fill(Color.tapelabOrange.opacity(0.2))
                .frame(width: loopWidth, height: 30)
                .offset(x: loopStartX, y: 0)
                .allowsHitTesting(false)

            // Loop start handle (left edge)
            ZStack {
                // Larger touch target
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())

                // Visible handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.tapelabOrange.opacity(0.8))
                    .frame(width: 8, height: 30)
            }
            .offset(x: loopStartX - 22, y: 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDraggingLoopStart {
                            HapticsManager.shared.playheadDragStart()
                            isDraggingLoopStart = true
                        }

                        let newPosition = max(0, min(value.location.x, timeline.loopEnd * pixelsPerSecond - pixelsPerSecond * 0.5))
                        let newLoopStart = newPosition / pixelsPerSecond
                        timeline.loopStart = newLoopStart
                    }
                    .onEnded { _ in
                        HapticsManager.shared.playheadDragEnd()
                        isDraggingLoopStart = false
                    }
            )

            // Loop end handle (right edge)
            ZStack {
                // Larger touch target
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())

                // Visible handle
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.tapelabOrange.opacity(0.8))
                    .frame(width: 8, height: 30)
            }
            .offset(x: loopEndX - 22, y: 0)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDraggingLoopEnd {
                            HapticsManager.shared.playheadDragStart()
                            isDraggingLoopEnd = true
                        }

                        let newPosition = max(timeline.loopStart * pixelsPerSecond + pixelsPerSecond * 0.5, min(value.location.x, totalWidth))
                        let newLoopEnd = newPosition / pixelsPerSecond
                        timeline.loopEnd = newLoopEnd
                    }
                    .onEnded { _ in
                        HapticsManager.shared.playheadDragEnd()
                        isDraggingLoopEnd = false
                    }
            )
        }
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
