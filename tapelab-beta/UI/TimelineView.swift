//
//  TimelineView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI

struct TimelineView: View {
    @ObservedObject var timeline: TimelineState
    @Binding var tracks: [Track]
    @Binding var armedTrack: Int
    let runtime: AudioRuntime
    let basePixelsPerSecond: CGFloat
    let maxDuration: Double

    @State private var zoomScale: CGFloat = 2.0
    @State private var lastZoomScale: CGFloat = 2.0
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteTrack: Int?
    @State private var pendingDeleteRegion: Int?

    private var pixelsPerSecond: CGFloat {
        basePixelsPerSecond * zoomScale
    }

    private var totalWidth: CGFloat {
        maxDuration * pixelsPerSecond
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Main timeline area with sticky headers
                ZStack(alignment: .topLeading) {
                    let rulerHeight: CGFloat = 30
                    let availableHeight = max(0, geometry.size.height - rulerHeight)
                    let trackHeight = tracks.count > 0 ? availableHeight / CGFloat(tracks.count) : 0

                    // Single scrollable area containing ruler and tracks
                    ScrollViewReader { scrollProxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            VStack(spacing: 0) {
                                // Time ruler (scrolls with content)
                                TimelineRulerView(
                                    timeline: timeline,
                                    pixelsPerSecond: pixelsPerSecond,
                                    maxDuration: maxDuration
                                )
                                .frame(width: totalWidth, height: rulerHeight)
                                .background(Color.tapelabBlack)

                                // Timeline content
                                ZStack(alignment: .topLeading) {
                                    // Invisible scroll anchor system (bottom layer)
                                    HStack(spacing: 0) {
                                        Color.clear
                                            .frame(width: max(0, timeline.playhead * pixelsPerSecond), height: 1)

                                        Color.clear
                                            .frame(width: 1, height: 1)
                                            .id("playhead")

                                        Color.clear
                                            .frame(width: max(0, totalWidth - timeline.playhead * pixelsPerSecond), height: 1)
                                    }
                                    .frame(height: 1)

                                    // Background grid (seconds-based)
                                    let totalSeconds = Int(ceil(maxDuration))
                                    ForEach(0...totalSeconds, id: \.self) { second in
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: 1, height: availableHeight)
                                            .offset(x: CGFloat(second) * pixelsPerSecond, y: 0)
                                    }

                                    // Track lanes content (no headers in scrollable area)
                                    VStack(spacing: 0) {
                                        ForEach(tracks.indices, id: \.self) { index in
                                            trackContentView(for: index, height: trackHeight)
                                        }
                                    }
                                    .frame(width: totalWidth, alignment: .leading)

                                    // Playhead overlay (on top of everything)
                                    PlayheadView(
                                        timeline: timeline,
                                        pixelsPerSecond: pixelsPerSecond,
                                        totalHeight: availableHeight
                                    )
                                }
                                .frame(width: totalWidth, height: availableHeight)
                            }
                            .contentShape(Rectangle())
                        }
                        .onChange(of: timeline.playhead) { oldValue, newValue in
                            // Always auto-scroll to keep playhead centered
                            // No animation - follow CADisplayLink updates directly for smoothness
                            scrollProxy.scrollTo("playhead", anchor: .center)
                        }
                    }
                    .simultaneousGesture(
                        MagnificationGesture()
                            .onChanged { value in
                                // Clamp zoom between 0.5x and 4x
                                let newZoom = lastZoomScale * value
                                zoomScale = min(max(newZoom, 0.5), 4.0)
                            }
                            .onEnded { value in
                                // Save the final zoom level
                                lastZoomScale = zoomScale
                            }
                    )

                    // Sticky headers overlay (full viewport width, non-scrollable)
                    VStack(spacing: 0) {
                        // Spacer for ruler
                        Color.clear
                            .frame(height: rulerHeight)

                        ForEach(tracks.indices, id: \.self) { index in
                            VStack(spacing: 0) {
                                TrackHeaderView(
                                    trackNumber: index + 1,
                                    armedTrack: $armedTrack,
                                    track: $tracks[index],
                                    runtime: runtime
                                )
                                .frame(width: geometry.size.width, alignment: .leading)

                                Spacer()
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // Clear selection when tapping on empty space below header
                                        timeline.selectedRegion = nil
                                    }
                            }
                            .frame(height: trackHeight)
                        }
                    }
                    .frame(width: geometry.size.width)
                    .allowsHitTesting(true) // Allow interaction with buttons
                }
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func trackContentView(for index: Int, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            // Background - matches button background color with 50% opacity
            Rectangle()
                .fill(Color.tapelabButtonBg.opacity(0.5))
                .frame(width: maxDuration * pixelsPerSecond, height: height)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    // Double tap to arm track (also clears edit mode)
                    if !timeline.isPlaying && !timeline.isRecording {
                        // Clear selection/edit mode
                        timeline.selectedRegion = nil

                        // Arm the track
                        HapticsManager.shared.trackSelected()
                        armedTrack = index + 1
                    }
                }
                .onTapGesture(count: 1) {
                    // Single tap to clear selection when tapping on empty track area
                    timeline.selectedRegion = nil
                }

            // Regions
            ForEach(Array(tracks[index].regions.enumerated()), id: \.element.id.id) { regionIndex, region in
                RegionView(
                    region: $tracks[index].regions[regionIndex],
                    pixelsPerSecond: pixelsPerSecond,
                    isSelected: false, // Deprecated parameter
                    trackNumber: index + 1,
                    trackIndex: index,
                    regionIndex: regionIndex,
                    timeline: timeline,
                    isRecordingTrack: armedTrack == index + 1 && timeline.isRecording,
                    recordingRegionID: runtime.recorder.activeRecording?.regionID.id,
                    onPositionChanged: { newStartTime in
                        // Update region position - find current index by ID
                        if let currentIndex = runtime.session.tracks[index].regions.firstIndex(where: { $0.id == region.id }) {
                            runtime.updateRegionPosition(
                                trackIndex: index,
                                regionIndex: currentIndex,
                                newStartTime: newStartTime
                            )
                        }
                    },
                    onTrackChanged: { newTrackIndex in
                        // Move region to different track - find current index by ID
                        if let currentIndex = runtime.session.tracks[index].regions.firstIndex(where: { $0.id == region.id }) {
                            runtime.moveRegionToTrack(
                                fromTrackIndex: index,
                                regionIndex: currentIndex,
                                toTrackIndex: newTrackIndex
                            )
                        }
                    },
                    onDeleteRequested: {
                        // Store pending delete and show confirmation
                        if let currentIndex = runtime.session.tracks[index].regions.firstIndex(where: { $0.id == region.id }) {
                            pendingDeleteTrack = index
                            pendingDeleteRegion = currentIndex
                            showDeleteConfirmation = true
                        }
                    },
                    getRegionBuffer: { trackIdx, regionID in
                        // Access buffer through runtime's player, passing current session
                        runtime.player.getRegionBuffer(
                            trackIndex: trackIdx,
                            regionID: regionID,
                            session: runtime.session
                        )
                    },
                    trackHeight: height
                )
                .id(region.id.id) // Force new view when region ID changes
            }

            // Active recording overlay (if recording on this track)
            if let activeRecording = runtime.recorder.activeRecording,
               activeRecording.trackIndex == index {
                // Use playhead position for smooth animation (updated at 60fps via CADisplayLink)
                // instead of activeRecording.duration which updates in chunks
                let recordingDuration = max(0, timeline.playhead - activeRecording.startTime)
                let recordingWidth = max(CGFloat(recordingDuration) * pixelsPerSecond, 40)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.red.opacity(0.3))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.red, lineWidth: 2)
                        )
                }
                .frame(
                    width: recordingWidth,
                    height: 60
                )
                .position(
                    x: CGFloat(activeRecording.startTime) * pixelsPerSecond + (recordingWidth / 2),
                    y: 58 + 30  // 58pt top offset (matching RegionView) + 30pt (half of 60pt height)
                )
                .allowsHitTesting(false) // Don't intercept touches
            }
        }
        .frame(height: height)
        .alert(
            "Delete Region",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                pendingDeleteTrack = nil
                pendingDeleteRegion = nil
            }
            Button("Delete", role: .destructive) {
                guard let track = pendingDeleteTrack, let region = pendingDeleteRegion else { return }
                // Clear selection first
                runtime.timeline.selectedRegion = nil
                // Delete the region
                runtime.deleteRegion(trackIndex: track, regionIndex: region)
                // Clear pending state
                pendingDeleteTrack = nil
                pendingDeleteRegion = nil
            }
        } message: {
            if let regionIdx = pendingDeleteRegion {
                Text("Are you sure you want to delete \"Region \(regionIdx + 1)\"? This action cannot be undone.")
            } else {
                Text("Are you sure you want to delete this region? This action cannot be undone.")
            }
        }
    }
}
