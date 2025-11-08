//
//  TrackLaneView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct TrackLaneView: View {
    @Binding var track: Track
    let trackNumber: Int
    let pixelsPerSecond: CGFloat
    let maxDuration: Double
    @State private var selectedRegionID: RegionID?

    var body: some View {
        // Track content area only (header is now separate in TimelineView)
        ZStack(alignment: .topLeading) {
            // Background - matches button background color with 50% opacity
            Rectangle()
                .fill(Color.tapelabButtonBg.opacity(0.5))
                .frame(width: maxDuration * pixelsPerSecond, height: 80)

            // Top border - very light
            Rectangle()
                .fill(Color.tapelabLight.opacity(0.1))
                .frame(width: maxDuration * pixelsPerSecond, height: 1)
                .offset(y: 0)

            // Regions
            ForEach(track.regions.indices, id: \.self) { index in
                RegionView(
                    region: $track.regions[index],
                    pixelsPerSecond: pixelsPerSecond,
                    isSelected: selectedRegionID == track.regions[index].id,
                    trackNumber: trackNumber,
                    trackIndex: trackNumber - 1,
                    regionIndex: index
                )
                .onTapGesture {
                    selectedRegionID = track.regions[index].id
                }
            }
        }
        .frame(height: 80)
    }
}
