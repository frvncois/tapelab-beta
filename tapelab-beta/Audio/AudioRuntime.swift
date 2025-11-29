//
//  AudioRuntime.swift
//  tapelab
//
import Foundation
import AVFAudio
import Combine

@MainActor
public final class AudioRuntime: ObservableObject {
    let engine = AudioEngineController(trackCount: 4)
    let player = SessionPlayer()
    @Published var recorder = SessionRecorder()
    @Published var timeline = TimelineState()
    @Published var session = Session(name: "Untitled Session") {
        didSet {
            autoSaveSession()
        }
    }
    @Published var isProcessing: Bool = false
    @Published var processingMessage: String = ""

    // Alert state
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false

    private var autoSaveTask: Task<Void, Never>?

    init() {
        player.engineController = engine
        recorder.engineController = engine

        recorder.onSessionUpdate = { [weak self] updatedSession in
            guard let self = self else { return }
            self.session = updatedSession
            self.objectWillChange.send()
        }

        // Observe audio route disconnections
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioDeviceDisconnected"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.timeline.isRecording,
                   let trackIndex = self.recorder.currentRecordingTrackIndex {

                    self.stopRecording(onTrack: trackIndex)

                    self.showAlert(
                        title: "Recording Stopped",
                        message: "Your audio device was disconnected. The recording has been saved."
                    )
                }
            }
        }

        // Observe disk full during recording
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("DiskFullDuringRecording"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let error = notification.object as? Error

            Task { @MainActor [weak self] in
                guard let self = self, let error = error else { return }

                if self.timeline.isRecording,
                   let trackIndex = self.recorder.currentRecordingTrackIndex {

                    self.stopRecording(onTrack: trackIndex)

                    self.showAlert(
                        title: "Disk Full",
                        message: error.localizedDescription + " Recording has been stopped and saved."
                    )
                }
            }
        }

        // Observe audio interruptions (phone calls, Siri, etc)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioInterruptionBegan"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.timeline.isRecording,
                   let trackIndex = self.recorder.currentRecordingTrackIndex {
                    self.stopRecording(onTrack: trackIndex)
                    self.showAlert(
                        title: "Recording Interrupted",
                        message: "Recording was stopped due to interruption (call, Siri, etc). Your recording has been saved."
                    )
                } else if self.timeline.isPlaying {
                    self.stopPlayback(resetPlayhead: false)
                }
            }
        }

        // Observe recording reaching max duration (360 seconds)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RecordingReachedMaxDuration"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if self.timeline.isRecording,
                   let trackIndex = self.recorder.currentRecordingTrackIndex {
                    self.stopRecording(onTrack: trackIndex)
                    self.showAlert(
                        title: "Recording Complete",
                        message: "Maximum session length (8 minutes) reached. Your recording has been saved."
                    )
                }
            }
        }

    }

    // MARK: - Alert Helper

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    private func autoSaveSession() {
        autoSaveTask?.cancel()

        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            guard !Task.isCancelled else { return }

            do {
                try FileStore.saveSession(session)
            } catch {
                print("⚠️ AudioRuntime: Auto-save session failed: \(error)")
            }
        }
    }

    func startPlayback() async {
        do {
            try await player.play(session: session, timeline: timeline)
        }
        catch {
            print("⚠️ AudioRuntime: Playback failed: \(error)")
        }
    }
    
    /// Stop playback and optionally reset playhead
    /// - Parameter resetPlayhead: If true, resets playhead to 0. If false, preserves current position.
    func stopPlayback(resetPlayhead: Bool = true) {
        player.stop()
        timeline.isPlaying = false

        // Reset effects to clear delay/reverb tails
        engine.resetAllEffects()

        if resetPlayhead {
            timeline.playhead = 0
        }

        objectWillChange.send()
    }
    
    func startRecording(onTrack index: Int) async -> Bool {

        if timeline.isLoopMode {
            timeline.isLoopMode = false
        }

        if !HeadphoneDetector.areHeadphonesConnected() {
            showAlert(
                title: "Headphones Required",
                message: "Please connect headphones to record. This prevents feedback and allows you to hear playback while recording."
            )
            return false
        }

        do {
            // CRITICAL: Tell player to exclude this track from playback during recording
            // This prevents file access conflicts (player reading while recorder writing)
            player.setRecordingTrack(index)

            // Check if there's existing audio on OTHER tracks (not the one being recorded)
            // This determines if we need output latency compensation for overdubbing
            let hasExistingAudio = session.tracks.enumerated().contains { (trackIndex, track) in
                trackIndex != index && !track.regions.isEmpty
            }

            if !timeline.isPlaying {
                try await player.play(session: session, timeline: timeline)
            }

            session = try await recorder.startRecording(session: session, timeline: timeline, trackIndex: index, needsLatencyCompensation: hasExistingAudio)

            objectWillChange.send()
            return true
        }
        catch {
            return false
        }
    }

    func stopRecording(onTrack index: Int) {
        isProcessing = true
        processingMessage = "Processing Recording"
        objectWillChange.send()

        let startTime = Date()

        let recordingStartPosition = recorder.activeRecording?.startTime ?? timeline.playhead

        recorder.stopRecording(session: &session, trackIndex: index, timeline: timeline)

        player.setRecordingTrack(nil)

        player.stop()
        timeline.isPlaying = false

        timeline.seek(to: recordingStartPosition)

        Task {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 3.0 {
                try? await Task.sleep(nanoseconds: UInt64((3.0 - elapsed) * 1_000_000_000))
            }

            await MainActor.run {
                isProcessing = false
                processingMessage = ""
                objectWillChange.send()
            }
        }
    }

    /// Update a region's position on the timeline
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region within the track
    ///   - newStartTime: New start time in seconds
    func updateRegionPosition(trackIndex: Int, regionIndex: Int, newStartTime: TimeInterval) {
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            return
        }

        // Don't allow moving regions while recording
        guard !timeline.isRecording else {
            return
        }

        // Clamp start time to valid range (0 to maxDuration - region.duration)
        let region = session.tracks[trackIndex].regions[regionIndex]
        let maxStartTime = session.maxDuration - region.duration
        let clampedStartTime = max(0, min(newStartTime, maxStartTime))

        // Update the region's start time
        session.tracks[trackIndex].regions[regionIndex].startTime = clampedStartTime


        // If playback is active, restart it to reflect the new position
        if timeline.isPlaying {
            Task {
                stopPlayback(resetPlayhead: false)
                await startPlayback()
            }
        }

        // Force SwiftUI to update
        objectWillChange.send()
    }

    /// Cut a region at the current playhead position, creating two separate regions
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region within the track to cut
    /// - Returns: Success status and optional error message
    @discardableResult
    func cutRegion(trackIndex: Int, regionIndex: Int) -> (success: Bool, errorMessage: String?) {
        // Validate indices
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            return (false, nil)
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            return (false, nil)
        }

        // Don't allow cutting while recording or playing
        guard !timeline.isRecording && !timeline.isPlaying else {
            return (false, nil)
        }

        let region = session.tracks[trackIndex].regions[regionIndex]
        let cutPosition = timeline.playhead

        // Validate that playhead is within this region
        let regionEnd = region.startTime + region.duration
        guard cutPosition > region.startTime && cutPosition < regionEnd else {
            return (false, "Move the playhead where you want to cut the region")
        }

        // Check if playhead is at least 0.25s from start or end
        let minDistanceFromEdge: TimeInterval = 0.25
        guard cutPosition >= (region.startTime + minDistanceFromEdge) &&
              cutPosition <= (regionEnd - minDistanceFromEdge) else {
            return (false, "Move the playhead where you want to cut the region")
        }

        // Calculate split point relative to region start
        let splitOffset = cutPosition - region.startTime

        // Create first region (left side of cut)
        let firstRegion = Region(
            sourceURL: region.sourceURL,
            startTime: region.startTime,
            duration: splitOffset,
            fileStartOffset: region.fileStartOffset,
            fileDuration: region.fileDuration,
            reversed: region.reversed,
            fadeIn: region.fadeIn,
            fadeOut: nil, // Remove fade out from first region
            gainDB: region.gainDB
        )

        // Create second region (right side of cut)
        let secondRegion = Region(
            sourceURL: region.sourceURL,
            startTime: cutPosition,
            duration: region.duration - splitOffset,
            fileStartOffset: region.fileStartOffset + splitOffset,
            fileDuration: region.fileDuration,
            reversed: region.reversed,
            fadeIn: nil, // Remove fade in from second region
            fadeOut: region.fadeOut,
            gainDB: region.gainDB
        )

        // Replace the original region with the two new regions
        session.tracks[trackIndex].regions.remove(at: regionIndex)
        session.tracks[trackIndex].regions.insert(firstRegion, at: regionIndex)
        session.tracks[trackIndex].regions.insert(secondRegion, at: regionIndex + 1)

        // Clear selection
        timeline.selectedRegion = nil


        // Force SwiftUI to update
        objectWillChange.send()

        return (true, nil)
    }

    /// Delete a region from a track
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region within the track to delete
    func deleteRegion(trackIndex: Int, regionIndex: Int) {
        // Validate indices
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            return
        }

        // Don't allow deleting regions while recording
        guard !timeline.isRecording else {
            return
        }

        // Clear selection state if this region is selected
        if let selected = timeline.selectedRegion,
           selected.trackIndex == trackIndex && selected.regionIndex == regionIndex {
            timeline.selectedRegion = nil
        }

        // Remove region from session
        session.tracks[trackIndex].regions.remove(at: regionIndex)

        // Optionally delete the audio file (commented out for safety)
        // To enable file deletion, uncomment the following lines:
        /*
        do {
            try FileManager.default.removeItem(at: region.sourceURL)
        } catch {
        }
        */

        // If playback is active, restart it to reflect the deletion
        if timeline.isPlaying {
            Task {
                stopPlayback(resetPlayhead: false)
                await startPlayback()
            }
        }

        // Force SwiftUI to update
        objectWillChange.send()
    }

    /// Duplicate a region and place it after the original
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region to duplicate
    func duplicateRegion(trackIndex: Int, regionIndex: Int) {
        // Validate indices
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            return
        }

        // Don't allow duplicating regions while recording
        guard !timeline.isRecording else {
            return
        }

        let originalRegion = session.tracks[trackIndex].regions[regionIndex]

        // Create duplicate with new ID and positioned after original
        let newStartTime = originalRegion.startTime + originalRegion.duration

        // Ensure duplicate doesn't exceed max duration
        guard newStartTime + originalRegion.duration <= session.maxDuration else {
            return
        }

        let duplicate = Region(
            sourceURL: originalRegion.sourceURL,
            startTime: newStartTime,
            duration: originalRegion.duration,
            fileStartOffset: originalRegion.fileStartOffset,
            fileDuration: originalRegion.fileDuration,
            reversed: originalRegion.reversed,
            fadeIn: originalRegion.fadeIn,
            fadeOut: originalRegion.fadeOut,
            gainDB: originalRegion.gainDB
        )

        // Insert duplicate after original
        session.tracks[trackIndex].regions.insert(duplicate, at: regionIndex + 1)

        // Move playhead to the start of the duplicated region
        timeline.playhead = newStartTime

    }

    /// Move a region from one track to another
    /// - Parameters:
    ///   - fromTrackIndex: Index of the source track (0-based)
    ///   - regionIndex: Index of the region to move
    ///   - toTrackIndex: Index of the destination track (0-based)
    func moveRegionToTrack(fromTrackIndex: Int, regionIndex: Int, toTrackIndex: Int) {
        // Validate source track index
        guard fromTrackIndex >= 0 && fromTrackIndex < session.tracks.count else {
            return
        }

        // Validate destination track index
        guard toTrackIndex >= 0 && toTrackIndex < session.tracks.count else {
            return
        }

        // Validate region index
        guard regionIndex >= 0 && regionIndex < session.tracks[fromTrackIndex].regions.count else {
            return
        }

        // Don't allow moving if same track
        guard fromTrackIndex != toTrackIndex else {
            return
        }

        // Don't allow moving regions while recording or playing
        guard !timeline.isRecording && !timeline.isPlaying else {
            return
        }

        // Get the region
        let region = session.tracks[fromTrackIndex].regions[regionIndex]

        // Remove from source track
        session.tracks[fromTrackIndex].regions.remove(at: regionIndex)

        // Add to destination track
        session.tracks[toTrackIndex].regions.append(region)

        // Clear selection since the region has moved
        timeline.selectedRegion = nil


        // If playback is active, restart it to reflect the duplication
        if timeline.isPlaying {
            Task {
                stopPlayback(resetPlayhead: false)
                await startPlayback()
            }
        }

        // Force SwiftUI to update
        objectWillChange.send()
    }

    /// Toggle reversed playback for a region
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region to reverse
    func toggleReverse(trackIndex: Int, regionIndex: Int) {
        // Validate indices
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            return
        }

        // Don't allow reversing regions while recording
        guard !timeline.isRecording else {
            return
        }

        // Toggle reversed state
        session.tracks[trackIndex].regions[regionIndex].reversed.toggle()

        // If playback is active, restart it to reflect the change
        if timeline.isPlaying {
            Task {
                stopPlayback(resetPlayhead: false)
                await startPlayback()
            }
        }

        // Force SwiftUI to update
        objectWillChange.send()
    }


    // MARK: - External Playback Support

    /// Suspend audio engine and monitoring for external playback (e.g., PlayerView)
    func suspendForExternalPlayback() {

        // Stop any ongoing playback or recording
        if timeline.isPlaying {
            stopPlayback(resetPlayhead: false)
        }

        // Stop engine
        engine.stop()

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("⚠️ AudioRuntime: Audio session deactivation failed: \(error)")
        }
    }

    /// Resume audio engine after external playback
    func resumeAfterExternalPlayback() {

        // Reconfigure audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("⚠️ AudioRuntime: Audio session resume failed: \(error)")
        }

        // Restart engine
        do {
            try engine.start()
        } catch {
            print("⚠️ AudioRuntime: Engine restart failed: \(error)")
        }

    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
