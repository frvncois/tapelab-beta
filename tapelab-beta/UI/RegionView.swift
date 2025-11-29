//
//  RegionView.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import SwiftUI
import AVFAudio

struct RegionView: View {
    @Binding var region: Region
    let pixelsPerSecond: CGFloat
    let isSelected: Bool
    let trackNumber: Int
    let trackIndex: Int
    let regionIndex: Int
    var timeline: TimelineState? = nil
    var isRecordingTrack: Bool = false
    var recordingRegionID: UUID? = nil  // ID of the region currently being recorded
    var onPositionChanged: ((TimeInterval) -> Void)? = nil
    var onTrackChanged: ((Int) -> Void)? = nil  // New callback for track changes
    var onDeleteRequested: (() -> Void)? = nil  // Callback to request deletion
    var getRegionBuffer: ((Int, UUID) -> AVAudioPCMBuffer?)? = nil
    var trackHeight: CGFloat = 0  // Height of each track for calculating target track

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var waveformSamples: [Float] = []
    @State private var verticalDragOffset: CGFloat = 0
    @State private var isDraggingToDelete: Bool = false

    // Check if this region is selected (for visual feedback)
    private var isRegionSelected: Bool {
        guard let timeline = timeline else { return false }
        guard let selected = timeline.selectedRegion else { return false }
        return selected.trackIndex == trackIndex && selected.regionIndex == regionIndex
    }

    // Check if THIS specific region is the one being recorded
    private var isThisRegionRecording: Bool {
        guard let timeline = timeline else { return false }
        guard isRecordingTrack && timeline.isRecording else { return false }
        guard let recordingID = recordingRegionID else { return false }
        return region.id.id == recordingID
    }

    private var xPosition: CGFloat {
        let basePosition = region.startTime * pixelsPerSecond
        return isDragging ? basePosition + dragOffset : basePosition
    }

    private var width: CGFloat {
        // If THIS region is the one being recorded, calculate live duration
        if isThisRegionRecording, let timeline = timeline {
            // Live duration = current playhead - region start time
            // Use max to prevent negative width during initialization
            let liveDuration = max(0, timeline.playhead - region.startTime)
            return max(40, liveDuration * pixelsPerSecond) // Minimum 40pt width
        } else {
            return max(40, region.duration * pixelsPerSecond)
        }
    }

    private var displayDuration: Double {
        // If THIS region is the one being recorded, show live duration
        if isThisRegionRecording, let timeline = timeline {
            return max(0, timeline.playhead - region.startTime)
        } else {
            return region.duration
        }
    }

    private var regionBackgroundColor: Color {
        // Orange if selected, red if recording, dark tape-inspired color for normal regions
        if isRegionSelected {
            return Color.tapelabOrange.opacity(0.25)
        } else if isThisRegionRecording {
            return Color.tapelabRed.opacity(0.1)
        } else {
            // Tape-inspired dark background (subtle dark brown)
            return Color.tapelabButtonBg.opacity(0.4)
        }
    }

    private var regionBorderColor: Color {
        // Orange if selected, red if recording, light border for normal regions (tape aesthetic)
        if isRegionSelected {
            return Color.tapelabOrange
        } else if isThisRegionRecording {
            return Color.tapelabRed
        } else {
            // Tape-inspired light border (cream/beige)
            return Color.tapelabLight.opacity(0.5)
        }
    }

    private var waveformColor: Color {
        // Waveform color: red for recording, light for normal (tape aesthetic)
        if isThisRegionRecording {
            return Color.tapelabRed.opacity(0.7)
        } else {
            // Tape-inspired waveform (cream/beige to match border)
            return Color.tapelabLight.opacity(0.7)
        }
    }

    private var visibleWaveformSamples: [Float] {
        guard !waveformSamples.isEmpty else { return [] }

        // Waveform is already loaded for the FULL buffer
        // Just return it as-is - the WaveformView will render what it needs
        return waveformSamples
    }

    var body: some View {
        mainRegionView
    }

    // MARK: - Main Region View

    private var mainRegionView: some View {
        mainRegionContent
            .offset(x: xPosition, y: 58 + verticalDragOffset)
            .opacity(abs(verticalDragOffset) > 30 ? 0.7 : 1.0)
            .onAppear {
                loadWaveformData()
            }
            .onChange(of: region.id.id) { _, _ in
                loadWaveformData()
            }
            .onChange(of: region.duration) { _, _ in
                loadWaveformData()
            }
            .onChange(of: region.fileStartOffset) { _, _ in
                loadWaveformData()
            }
            .onChange(of: region.sourceURL) { _, _ in
                loadWaveformData()
            }
            .onChange(of: timeline?.isRecording) { _, newValue in
                if newValue == false && isRecordingTrack {
                    Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        await MainActor.run {
                            loadWaveformData()
                        }
                    }
                }
            }
            .simultaneousGesture(dragGesture)
            .onTapGesture(count: 1) {
                guard let timeline = timeline else { return }
                guard timeline.isRecording != true else { return }

                // Toggle selection: if already selected, deselect; otherwise select
                if isRegionSelected {
                    timeline.selectedRegion = nil
                } else {
                    timeline.selectedRegion = (trackIndex: trackIndex, regionIndex: regionIndex)
                }
            }
    }

    private var mainRegionContent: some View {
        ZStack(alignment: .topLeading) {
            WaveformView(
                samples: region.reversed ? visibleWaveformSamples.reversed() : visibleWaveformSamples,
                color: waveformColor,
                backgroundColor: regionBackgroundColor
            )
            .frame(width: width, height: 60)
            .animation(nil, value: width) // No implicit animation - follow data directly
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 2) {
                Text("Region \(regionIndex + 1)")
                    .font(.tapelabMonoSmall)
                    .lineLimit(1)
                    .foregroundColor(.tapelabLight)

                Text(String(format: "%.1fs", displayDuration))
                    .font(.tapelabMonoTiny)
                    .foregroundColor(.tapelabLight.opacity(0.7))
            }
            .padding(4)
            .frame(width: width, height: 60, alignment: .topLeading)
        }
        .frame(width: width, height: 60, alignment: .topLeading)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(regionBorderColor, lineWidth: isDragging ? 2 : 1)
        )
        .overlay(
            isDragging ?
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
                : nil
        )
        .overlay(deleteOverlay)
    }

    @ViewBuilder
    private var deleteOverlay: some View {
        if abs(verticalDragOffset) > 30 {
            let targetTrack = calculateTargetTrack()
            let tracksToLast = 3 - trackIndex
            let offsetToLast = CGFloat(tracksToLast) * trackHeight
            let beyondLast = abs(verticalDragOffset - offsetToLast)
            let threshold = trackHeight * 0.5
            let checkDelete = verticalDragOffset > 0 && targetTrack >= 3 && beyondLast > threshold

            if checkDelete {
                // Delete zone
                VStack {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.tapelabRed)
                    Text("Release to Delete")
                        .font(.tapelabMonoSmall)
                        .foregroundColor(.tapelabRed)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.8))
                .cornerRadius(4)
            } else {
                // Track change zone
                VStack {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 24))
                        .foregroundColor(.tapelabOrange)
                    Text("Move to Track \(targetTrack + 1)")
                        .font(.tapelabMonoTiny)
                        .foregroundColor(.tapelabOrange)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
            }
        }
    }

    private func calculateTargetTrack() -> Int {
        // Calculate which track based on vertical drag offset
        // Positive offset = dragging down, negative = dragging up
        let tracksDelta = Int(round(verticalDragOffset / trackHeight))
        let targetTrack = trackIndex + tracksDelta
        // Clamp to valid track range (0-3 for 4 tracks)
        return max(0, min(3, targetTrack))
    }

    private func isInDeleteZone() -> Bool {
        let targetTrack = calculateTargetTrack()
        let tracksToLast = 3 - trackIndex
        let offsetToLast = CGFloat(tracksToLast) * trackHeight
        let beyondLast = abs(verticalDragOffset - offsetToLast)
        let threshold = trackHeight * 0.5

        // Only in delete zone if we're dragging down past track 4 (index 3)
        let draggingDown = verticalDragOffset > 0
        let atOrPastLastTrack = targetTrack >= 3
        let beyondThreshold = beyondLast > threshold

        return draggingDown && atOrPastLastTrack && beyondThreshold
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard timeline?.isRecording != true else { return }
                guard timeline?.isPlaying != true else { return }

                let horizontalAmount = abs(value.translation.width)
                let verticalAmount = abs(value.translation.height)

                // Determine drag direction
                if verticalAmount > horizontalAmount && verticalAmount > 30 {
                    // Vertical drag detected - show track change indicator
                    verticalDragOffset = value.translation.height

                    // Update timeline state for delete zone overlay
                    if let timeline = timeline {
                        let inDeleteZone = isInDeleteZone()
                        if timeline.isDraggingToDelete != inDeleteZone {
                            timeline.isDraggingToDelete = inDeleteZone
                        }
                    }
                } else {
                    // Horizontal drag - move region
                    isDragging = true
                    dragOffset = value.translation.width
                    verticalDragOffset = 0

                    // Clear delete state
                    if let timeline = timeline {
                        timeline.isDraggingToDelete = false
                    }
                }
            }
            .onEnded { value in
                let horizontalAmount = abs(value.translation.width)
                let verticalAmount = abs(value.translation.height)

                // Check if this was a vertical drag (track change or delete gesture)
                if verticalAmount > horizontalAmount && verticalAmount > 50 {
                    if isInDeleteZone() {
                        // Delete zone - trigger delete confirmation
                        onDeleteRequested?()
                    } else {
                        // Track change zone - move to target track
                        let targetTrack = calculateTargetTrack()
                        if targetTrack != trackIndex {
                            onTrackChanged?(targetTrack)
                        }
                    }
                    verticalDragOffset = 0
                } else if isDragging {
                    // Horizontal drag - update position
                    isDragging = false
                    let deltaTime = value.translation.width / pixelsPerSecond
                    let newStartTime = max(0, region.startTime + deltaTime)
                    onPositionChanged?(newStartTime)
                    dragOffset = 0
                }

                verticalDragOffset = 0

                // Clear delete state
                if let timeline = timeline {
                    timeline.isDraggingToDelete = false
                }
            }
    }

    // MARK: - Waveform Loading

    private func loadWaveformData() {
        // Don't load waveform while THIS region is actively recording
        if isThisRegionRecording {
            waveformSamples = []
            return
        }

        // Don't load waveform if we don't have a buffer accessor
        guard let getBuffer = getRegionBuffer else {
            waveformSamples = []
            return
        }


        // Get the buffer for this region
        guard let buffer = getBuffer(trackNumber - 1, region.id.id) else {
            waveformSamples = []
            return
        }

        // Use fixed points per second of audio (not dependent on zoom level)
        // This ensures consistent waveform detail regardless of region length
        // 50 points per second gives good detail: 8 min = 480s * 50 = 24000 points max
        let pointsPerSecond: Double = 50
        let targetPoints = max(100, min(24000, Int(region.duration * pointsPerSecond)))

        // Generate waveform data on a background thread
        Task.detached(priority: .userInitiated) {
            let samples = WaveformGenerator.generateWaveformData(from: buffer, targetPoints: targetPoints)

            // Update UI on main thread
            await MainActor.run {
                waveformSamples = samples
            }
        }
    }
}
