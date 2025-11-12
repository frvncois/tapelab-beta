//
//  PlayheadView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct PlayheadView: View {
    @ObservedObject var timeline: TimelineState
    let pixelsPerSecond: CGFloat
    let totalHeight: CGFloat

    @State private var isDragging: Bool = false
    @State private var dragOffset: CGFloat = 0

    private var xPosition: CGFloat {
        let basePosition = timeline.playhead * pixelsPerSecond
        return isDragging ? basePosition + dragOffset : basePosition
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Invisible wider hit area for easier dragging
            Rectangle()
                .fill(Color.clear)
                .frame(width: 44, height: totalHeight)
                .contentShape(Rectangle())
                .offset(x: xPosition - 22, y: 0)
                .gesture(dragGesture)

            // Visible playhead line - centered on position
            Rectangle()
                .fill(isDragging ? Color.tapelabOrange : Color.red)
                .frame(width: isDragging ? 3 : 2, height: totalHeight)
                .offset(x: xPosition - (isDragging ? 1.5 : 1), y: 0)
                .allowsHitTesting(false)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Don't allow dragging while recording
                guard !timeline.isRecording else { return }

                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                guard !timeline.isRecording else { return }

                isDragging = false

                // Calculate new playhead position
                let deltaTime = value.translation.width / pixelsPerSecond
                let newPlayhead = max(0, timeline.playhead + deltaTime)

                // Seek to new position
                timeline.seek(to: newPlayhead)

                dragOffset = 0
            }
    }
}
