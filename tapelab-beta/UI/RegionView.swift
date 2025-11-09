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
    var onPositionChanged: ((TimeInterval) -> Void)? = nil
    var onTrimChanged: ((TimeInterval, TimeInterval) -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var getRegionBuffer: ((Int, UUID) -> AVAudioPCMBuffer?)? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var waveformSamples: [Float] = []
    @State private var verticalDragOffset: CGFloat = 0
    @State private var showDeleteConfirmation: Bool = false

    // Trim mode state
    @State private var trimStartOffset: CGFloat = 0
    @State private var trimEndOffset: CGFloat = 0
    @State private var originalDuration: TimeInterval = 0
    @State private var originalFileStartOffset: TimeInterval = 0

    // Check if this region is selected (for visual feedback)
    private var isRegionSelected: Bool {
        guard let timeline = timeline else { return false }
        guard let selected = timeline.selectedRegion else { return false }
        return selected.trackIndex == trackIndex && selected.regionIndex == regionIndex
    }

    // Check if this region is in trim mode (TRIM button was clicked)
    private var isTrimMode: Bool {
        guard let timeline = timeline else { return false }
        guard let trimRegion = timeline.trimModeRegion else { return false }
        return trimRegion.trackIndex == trackIndex && trimRegion.regionIndex == regionIndex
    }

    private var xPosition: CGFloat {
        let basePosition = region.startTime * pixelsPerSecond
        return isDragging ? basePosition + dragOffset : basePosition
    }

    private var width: CGFloat {
        // If this is the last region on a recording track, calculate live duration
        if let timeline = timeline, isRecordingTrack && timeline.isRecording {
            // Live duration = current playhead - region start time
            let liveDuration = max(0, timeline.playhead - region.startTime)
            return liveDuration * pixelsPerSecond
        } else {
            let baseWidth = region.duration * pixelsPerSecond
            // In trim mode, adjust width based on trim offsets
            if isTrimMode {
                return max(40, baseWidth - trimStartOffset - trimEndOffset)
            }
            return baseWidth
        }
    }

    private var adjustedXPosition: CGFloat {
        // In trim mode, shift right as we trim from start
        if isTrimMode {
            return xPosition + trimStartOffset
        }
        return xPosition
    }

    private var displayDuration: Double {
        // If this is the last region on a recording track, show live duration
        if let timeline = timeline, isRecordingTrack && timeline.isRecording {
            return max(0, timeline.playhead - region.startTime)
        } else {
            return region.duration
        }
    }

    private var regionBackgroundColor: Color {
        // Orange if selected, red if currently recording, accent for normal regions
        if isRegionSelected {
            return Color.tapelabOrange.opacity(0.25)
        } else if let timeline = timeline, isRecordingTrack && timeline.isRecording {
            return Color.tapelabRed.opacity(0.1)
        } else {
            return Color.tapelabAccent
        }
    }

    private var regionBorderColor: Color {
        // Orange if selected, red if currently recording, accent for normal regions
        if isRegionSelected {
            return Color.tapelabOrange
        } else if let timeline = timeline, isRecordingTrack && timeline.isRecording {
            return Color.tapelabRed
        } else {
            return Color.tapelabAccentFull
        }
    }

    private var waveformColor: Color {
        // Waveform color matches border color for consistency
        if let timeline = timeline, isRecordingTrack && timeline.isRecording {
            return Color.tapelabRed.opacity(0.7)
        } else {
            return Color.tapelabAccentFull.opacity(0.6)
        }
    }

    private var visibleWaveformSamples: [Float] {
        guard !waveformSamples.isEmpty else { return [] }

        // If not in trim mode, return full waveform
        guard isTrimMode else { return waveformSamples }

        // Calculate trim as percentage of original duration
        let originalWidth = region.duration * pixelsPerSecond
        guard originalWidth > 0 else { return waveformSamples }

        let startTrimPercent = trimStartOffset / originalWidth
        let endTrimPercent = trimEndOffset / originalWidth

        // Calculate slice indices
        let totalSamples = waveformSamples.count
        let startIndex = Int(startTrimPercent * Double(totalSamples))
        let endIndex = totalSamples - Int(endTrimPercent * Double(totalSamples))

        // Clamp to valid range
        let clampedStart = max(0, min(startIndex, totalSamples))
        let clampedEnd = max(clampedStart, min(endIndex, totalSamples))

        // Return sliced array
        return Array(waveformSamples[clampedStart..<clampedEnd])
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainRegionView

            // Trim handles (only visible in trim mode)
            if isTrimMode {
                trimHandle(isStart: true)
                    .offset(x: adjustedXPosition - 6, y: 45)

                trimHandle(isStart: false)
                    .offset(x: adjustedXPosition + width - 6, y: 45)

                trimButtons()
                    .offset(x: adjustedXPosition, y: 110)
            }
        }
        .alert("Delete Region?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete this region? This action cannot be undone.")
        }
    }

    // MARK: - Main Region View

    private var mainRegionView: some View {
        mainRegionContent
            .offset(x: adjustedXPosition, y: 58 + verticalDragOffset)
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
            .onChange(of: isTrimMode) { _, newValue in
                // When entering trim mode, initialize trim state
                if newValue {
                    enterTrimMode()
                }
            }
            .simultaneousGesture(!isTrimMode ? dragGesture : nil)
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
            .allowsHitTesting(!isTrimMode)
    }

    private var mainRegionContent: some View {
        ZStack(alignment: .topLeading) {
            WaveformView(
                samples: region.reversed ? visibleWaveformSamples.reversed() : visibleWaveformSamples,
                color: waveformColor,
                backgroundColor: regionBackgroundColor
            )
            .frame(width: max(width, 40), height: 60)
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
            .frame(width: max(width, 40), height: 60, alignment: .topLeading)
        }
        .frame(width: max(width, 40), height: 60, alignment: .topLeading)
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(regionBorderColor, lineWidth: isDragging || isTrimMode ? 2 : 1)
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
            VStack {
                Image(systemName: "trash")
                    .font(.system(size: 24))
                    .foregroundColor(.red)
                Text("Release to Delete")
                    .font(.tapelabMonoTiny)
                    .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard timeline?.isRecording != true else { return }

                let horizontalAmount = abs(value.translation.width)
                let verticalAmount = abs(value.translation.height)

                // Determine drag direction
                if verticalAmount > horizontalAmount && verticalAmount > 30 {
                    // Vertical drag detected - show delete indicator
                    verticalDragOffset = value.translation.height
                } else {
                    // Horizontal drag - move region
                    isDragging = true
                    dragOffset = value.translation.width
                    verticalDragOffset = 0
                }
            }
            .onEnded { value in
                let horizontalAmount = abs(value.translation.width)
                let verticalAmount = abs(value.translation.height)

                // Check if this was a vertical drag (delete gesture)
                if verticalAmount > horizontalAmount && verticalAmount > 50 {
                    // Show delete confirmation
                    showDeleteConfirmation = true
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
            }
    }

    // MARK: - Trim Mode UI

    @ViewBuilder
    private func trimHandle(isStart: Bool) -> some View {
        Rectangle()
            .fill(Color.tapelabAccentFull)
            .frame(width: 12, height: 60)
            .overlay(
                VStack(spacing: 3) {
                    Circle().fill(Color.white).frame(width: 3, height: 3)
                    Circle().fill(Color.white).frame(width: 3, height: 3)
                    Circle().fill(Color.white).frame(width: 3, height: 3)
                }
            )
            .contentShape(Rectangle()) // Make entire rectangle tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let baseWidth = region.duration * pixelsPerSecond

                        if isStart {
                            // Trim from start: dragging RIGHT increases offset (trims more)
                            let dragDistance = value.translation.width
                            // Limit: can't trim more than region width - 40px
                            let maxTrim = baseWidth - 40
                            trimStartOffset = max(0, min(dragDistance, maxTrim - trimEndOffset))
                        } else {
                            // Trim from end: dragging LEFT increases trim (negative drag = more trim)
                            let dragDistance = -value.translation.width
                            // Limit: can't trim more than region width - 40px
                            let maxTrim = baseWidth - 40
                            trimEndOffset = max(0, min(dragDistance, maxTrim - trimStartOffset))
                        }
                    }
                    .onEnded { _ in
                        // Keep the offsets for confirm/cancel
                        print("✂️ Trim handle \(isStart ? "START" : "END"): offset=\(isStart ? trimStartOffset : trimEndOffset)px")
                    }
            )
    }

    @ViewBuilder
    private func trimButtons() -> some View {
        HStack(spacing: 8) {
            Button(action: confirmTrim) {
                Text("Confirm")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green)
                    .cornerRadius(4)
            }

            Button(action: cancelTrim) {
                Text("Cancel")
                    .font(.tapelabMonoSmall)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.red)
                    .cornerRadius(4)
            }
        }
    }

    // MARK: - Trim Mode Actions

    private func enterTrimMode() {
        // Initialize trim state when entering trim mode
        trimStartOffset = 0
        trimEndOffset = 0
        originalDuration = region.duration
        originalFileStartOffset = region.fileStartOffset
        print("✂️ Entered trim mode for region \(region.id.id)")
    }

    private func confirmTrim() {
        // Calculate new duration and file offset
        let startTrimTime = trimStartOffset / pixelsPerSecond
        let endTrimTime = trimEndOffset / pixelsPerSecond
        let newDuration = max(0.1, originalDuration - startTrimTime - endTrimTime)
        let newFileStartOffset = originalFileStartOffset + startTrimTime

        // Call the callback
        onTrimChanged?(newDuration, newFileStartOffset)

        // Exit trim mode and deselect region
        exitTrimMode()
    }

    private func cancelTrim() {
        exitTrimMode()
    }

    private func exitTrimMode() {
        // Clear trim state
        trimStartOffset = 0
        trimEndOffset = 0

        // Clear trim mode but keep region selected (so edit buttons remain visible)
        timeline?.trimModeRegion = nil

        print("✂️ Exited trim mode")
    }

    // MARK: - Waveform Loading

    private func loadWaveformData() {
        // Don't load waveform while actively recording
        if let timeline = timeline, isRecordingTrack && timeline.isRecording {
            waveformSamples = []
            return
        }

        // Don't load waveform if we don't have a buffer accessor
        guard let getBuffer = getRegionBuffer else {
            print("⚠️ RegionView: No buffer accessor available")
            waveformSamples = []
            return
        }

        print("📊 RegionView attempting to load waveform for region \(region.id.id) on track \(trackNumber)")

        // Get the buffer for this region
        guard let buffer = getBuffer(trackNumber - 1, region.id.id) else {
            print("⚠️ RegionView: No buffer available for region \(region.id.id)")
            waveformSamples = []
            return
        }

        // Generate waveform data on a background thread
        Task.detached(priority: .userInitiated) {
            let samples = WaveformGenerator.generateWaveformData(from: buffer, targetPoints: 500)

            // Update UI on main thread
            await MainActor.run {
                waveformSamples = samples
                print("📊 Loaded waveform for region \(region.id.id): \(samples.count) points")
            }
        }
    }
}
