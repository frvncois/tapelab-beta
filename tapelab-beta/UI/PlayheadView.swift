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

    private var xPosition: CGFloat {
        timeline.playhead * pixelsPerSecond
    }

    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: totalHeight)
            .offset(x: xPosition, y: 0)
    }
}
