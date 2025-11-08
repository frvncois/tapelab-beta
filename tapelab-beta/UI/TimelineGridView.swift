//
//  TimelineGridView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct TimelineGridView: View {
    let pixelsPerSecond: CGFloat
    let maxDuration: Double
    let height: CGFloat
    let bpm: Double

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

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Main beat markers with numbers
            ForEach(0...totalBeats, id: \.self) { beat in
                VStack(spacing: 0) {
                    // Beat label
                    Text("\(beat)")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabLight)
                        .frame(width: 35, height: 14)
                        .background(Color.tapelabBackground.opacity(0.9))

                    // Tall tick mark
                    Rectangle()
                        .fill(Color.tapelabLight.opacity(0.5))
                        .frame(width: 2, height: height - 14)
                }
                .offset(x: beatToTime(Double(beat)) * pixelsPerSecond - 17.5, y: 0) // Center the text over the tick
            }

            // Quarter-beat tick marks (16th notes as dashes)
            ForEach(0..<(totalBeats * 4), id: \.self) { quarterBeat in
                // Skip tick marks that fall on whole beats
                if quarterBeat % 4 != 0 {
                    VStack(spacing: 0) {
                        Spacer()
                            .frame(height: 14)

                        // Short tick mark
                        Rectangle()
                            .fill(Color.tapelabLight.opacity(0.3))
                            .frame(width: 1, height: 8)

                        Spacer()
                    }
                    .frame(height: height)
                    .offset(x: beatToTime(Double(quarterBeat) / 4.0) * pixelsPerSecond, y: 0)
                }
            }
        }
    }
}
