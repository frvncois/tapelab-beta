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
    let metronome = Metronome()

    private var autoSaveTask: Task<Void, Never>?

    init() {
        player.engineController = engine
        recorder.engineController = engine

        // Set up recorder callback to update session in real-time
        recorder.onSessionUpdate = { [weak self] updatedSession in
            guard let self = self else { return }
            self.session = updatedSession
            self.objectWillChange.send()
        }

        print("🎛️ Audio runtime initialized (4-track engine)")
    }

    /// Auto-save session with debouncing to avoid excessive writes
    private func autoSaveSession() {
        // Cancel any pending save
        autoSaveTask?.cancel()

        // Debounce: wait 500ms before saving
        autoSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            guard !Task.isCancelled else { return }

            do {
                try FileStore.saveSession(session)
            } catch {
                print("⚠️ Failed to auto-save session: \(error)")
            }
        }
    }
    
    func startPlayback() async {
        do {
            // Show processing indicator
            isProcessing = true
            processingMessage = "Processing track..."
            objectWillChange.send()

            try await player.play(session: session, timeline: timeline)

            // Hide processing indicator
            isProcessing = false
            processingMessage = ""
            // Force SwiftUI to update
            objectWillChange.send()
        }
        catch {
            print("⚠️ Playback failed: \(error)")
            isProcessing = false
            processingMessage = ""
            objectWillChange.send()
        }
    }
    
    /// Stop playback and optionally reset playhead
    /// - Parameter resetPlayhead: If true, resets playhead to 0. If false, preserves current position.
    func stopPlayback(resetPlayhead: Bool = true) {
        player.stop()
        timeline.isPlaying = false
        
        if resetPlayhead {
            timeline.playhead = 0
            print("⏹️ Stopped playback, reset playhead to 0")
        } else {
            print("⏹️ Stopped playback, preserved playhead at \(String(format: "%.2f", timeline.playhead))s")
        }
        
        // Force SwiftUI to update
        objectWillChange.send()
    }
    
    func startRecording(onTrack index: Int) async {
        print("🔍 AudioRuntime.startRecording called for track \(index + 1)")
        print("🔍 Timeline isRecording BEFORE: \(timeline.isRecording)")

        do {
            // CRITICAL: Tell player to exclude this track from playback during recording
            // This prevents file access conflicts (player reading while recorder writing)
            player.setRecordingTrack(index)

            // Start playback of existing tracks for overdubbing
            if !timeline.isPlaying {
                print("🎧 Starting playback for overdubbing...")
                try await player.play(session: session, timeline: timeline)
            }

            // Start recording IMMEDIATELY (captures count-in clicks)
            session = try await recorder.startRecording(session: session, timeline: timeline, trackIndex: index)
            print("🔍 Timeline isRecording AFTER: \(timeline.isRecording)")

            // NOW play the count-in metronome (it gets recorded)
            if session.metronomeCountIn {
                let beatsPerMeasure = session.timeSignature.beatsPerMeasure
                print("🥁 Starting \(beatsPerMeasure)-count metronome (recording already started)...")
                metronome.bpm = session.bpm
                metronome.timeSignature = session.timeSignature

                // Start metronome for count-in
                await metronome.play()

                // Calculate count-in duration (full measure based on time signature)
                let beatDuration = 60.0 / session.bpm
                let countInDuration = beatDuration * Double(beatsPerMeasure)

                // Wait for one full measure
                try await Task.sleep(nanoseconds: UInt64(countInDuration * 1_000_000_000))

                // Stop metronome after count-in if not playing during recording
                if !session.metronomeWhileRecording {
                    metronome.stop()
                    print("🥁 Count-in complete, metronome stopped")
                } else {
                    print("🥁 Count-in complete, metronome continues")
                }
            } else if session.metronomeWhileRecording {
                // No count-in but play metronome during recording
                print("🥁 Starting metronome for recording...")
                metronome.bpm = session.bpm
                metronome.timeSignature = session.timeSignature
                await metronome.play()
            }

            // Force SwiftUI to update by triggering objectWillChange
            objectWillChange.send()
        }
        catch {
            print("⚠️ Recording failed: \(error)")
            // Stop metronome on error
            if metronome.isPlaying {
                metronome.stop()
            }
        }
    }
    
    func stopRecording(onTrack index: Int) {
        // Show processing indicator
        isProcessing = true
        processingMessage = "Processing recording..."
        objectWillChange.send()

        recorder.stopRecording(session: &session, trackIndex: index, timeline: timeline)

        // Stop metronome if playing
        if metronome.isPlaying {
            metronome.stop()
            print("🥁 Metronome stopped")
        }

        // CRITICAL: Clear the recording track exclusion so it can be played back
        player.setRecordingTrack(nil)

        // CRITICAL: Stop playback when recording stops
        // This ensures pressing "stop record" also stops playback
        player.stop()
        timeline.isPlaying = false
        // Keep playhead at current position
        print("⏹️ Stopped recording AND playback, playhead at \(String(format: "%.2f", timeline.playhead))s")

        // Hide processing indicator
        isProcessing = false
        processingMessage = ""
        // Force SwiftUI to update
        objectWillChange.send()
    }

    /// Update a region's position on the timeline
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region within the track
    ///   - newStartTime: New start time in seconds
    func updateRegionPosition(trackIndex: Int, regionIndex: Int, newStartTime: TimeInterval) {
        // Validate indices
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            print("⚠️ Invalid track index: \(trackIndex)")
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            print("⚠️ Invalid region index: \(regionIndex)")
            return
        }

        // Don't allow moving regions while recording
        guard !timeline.isRecording else {
            print("⚠️ Cannot move regions while recording")
            return
        }

        // Clamp start time to valid range (0 to maxDuration - region.duration)
        let region = session.tracks[trackIndex].regions[regionIndex]
        let maxStartTime = session.maxDuration - region.duration
        let clampedStartTime = max(0, min(newStartTime, maxStartTime))

        // Update the region's start time
        session.tracks[trackIndex].regions[regionIndex].startTime = clampedStartTime

        print("📍 Moved region \(regionIndex) on track \(trackIndex + 1) to \(String(format: "%.2f", clampedStartTime))s")

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

    /// Update a region's trim (duration and file start offset)
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region within the track
    ///   - newDuration: New duration after trimming
    ///   - newFileStartOffset: New file start offset (where to start reading from source file)
    func updateRegionTrim(trackIndex: Int, regionIndex: Int, newDuration: TimeInterval, newFileStartOffset: TimeInterval) {
        // Validate indices
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            print("⚠️ Invalid track index: \(trackIndex)")
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            print("⚠️ Invalid region index: \(regionIndex)")
            return
        }

        // Don't allow trimming regions while recording
        guard !timeline.isRecording else {
            print("⚠️ Cannot trim regions while recording")
            return
        }

        let region = session.tracks[trackIndex].regions[regionIndex]

        // Validate trim parameters
        guard let fileDuration = region.fileDuration else {
            print("⚠️ Cannot trim region without fileDuration")
            return
        }

        // Ensure we don't exceed the source file duration
        let maxDuration = fileDuration - newFileStartOffset
        let clampedDuration = max(0.1, min(newDuration, maxDuration))
        let clampedFileStartOffset = max(0, min(newFileStartOffset, fileDuration - 0.1))

        // Update the region's duration and file start offset
        session.tracks[trackIndex].regions[regionIndex].duration = clampedDuration
        session.tracks[trackIndex].regions[regionIndex].fileStartOffset = clampedFileStartOffset

        print("✂️ Trimmed region \(regionIndex) on track \(trackIndex + 1): duration=\(String(format: "%.2f", clampedDuration))s, offset=\(String(format: "%.2f", clampedFileStartOffset))s")

        // If playback is active, restart it to reflect the new trim
        if timeline.isPlaying {
            Task {
                stopPlayback(resetPlayhead: false)
                await startPlayback()
            }
        }

        // Force SwiftUI to update
        objectWillChange.send()
    }

    /// Delete a region from a track
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region within the track to delete
    func deleteRegion(trackIndex: Int, regionIndex: Int) {
        // Validate indices
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            print("⚠️ Invalid track index: \(trackIndex)")
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            print("⚠️ Invalid region index: \(regionIndex)")
            return
        }

        // Don't allow deleting regions while recording
        guard !timeline.isRecording else {
            print("⚠️ Cannot delete regions while recording")
            return
        }

        let region = session.tracks[trackIndex].regions[regionIndex]
        print("🗑️ Deleting region \(regionIndex) on track \(trackIndex + 1): \(region.sourceURL.lastPathComponent)")

        // Remove region from session
        session.tracks[trackIndex].regions.remove(at: regionIndex)

        // Optionally delete the audio file (commented out for safety)
        // To enable file deletion, uncomment the following lines:
        /*
        do {
            try FileManager.default.removeItem(at: region.sourceURL)
            print("🗑️ Deleted audio file: \(region.sourceURL.lastPathComponent)")
        } catch {
            print("⚠️ Failed to delete audio file: \(error)")
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
            print("⚠️ Invalid track index: \(trackIndex)")
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            print("⚠️ Invalid region index: \(regionIndex)")
            return
        }

        // Don't allow duplicating regions while recording
        guard !timeline.isRecording else {
            print("⚠️ Cannot duplicate regions while recording")
            return
        }

        let originalRegion = session.tracks[trackIndex].regions[regionIndex]

        // Create duplicate with new ID and positioned after original
        let newStartTime = originalRegion.startTime + originalRegion.duration

        // Ensure duplicate doesn't exceed max duration
        guard newStartTime + originalRegion.duration <= session.maxDuration else {
            print("⚠️ Cannot duplicate region: would exceed max duration")
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

        print("📋 Duplicated region \(regionIndex) on track \(trackIndex + 1) at \(String(format: "%.2f", newStartTime))s")

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
            print("⚠️ Invalid track index: \(trackIndex)")
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            print("⚠️ Invalid region index: \(regionIndex)")
            return
        }

        // Don't allow reversing regions while recording
        guard !timeline.isRecording else {
            print("⚠️ Cannot reverse regions while recording")
            return
        }

        // Toggle reversed state
        session.tracks[trackIndex].regions[regionIndex].reversed.toggle()
        let isReversed = session.tracks[trackIndex].regions[regionIndex].reversed

        print("🔄 Toggled reverse for region \(regionIndex) on track \(trackIndex + 1): \(isReversed ? "ON" : "OFF")")

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

    /// Enter trim mode for a region
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region to trim
    func enterTrimMode(trackIndex: Int, regionIndex: Int) {
        // Set trim mode for this specific region
        timeline.trimModeRegion = (trackIndex: trackIndex, regionIndex: regionIndex)
        print("✂️ Entering trim mode for region \(regionIndex) on track \(trackIndex + 1)")

        // The trim handles will appear in RegionView via the isTrimMode computed property
        // Edit buttons remain visible because selectedRegion is still set
    }

    // MARK: - External Playback Support

    /// Suspend audio engine and monitoring for external playback (e.g., PlayerView)
    func suspendForExternalPlayback() {
        print("🎵 Suspending engine for external playback")

        // Stop any ongoing playback or recording
        if timeline.isPlaying {
            stopPlayback(resetPlayhead: false)
        }

        // Stop engine
        engine.stop()

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("✅ Audio session released")
        } catch {
            print("⚠️ Failed to release audio session: \(error)")
        }
    }

    /// Resume audio engine after external playback
    func resumeAfterExternalPlayback() {
        print("🎵 Resuming engine after external playback")

        // Reconfigure audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
            print("✅ Audio session restored to playAndRecord")
        } catch {
            print("⚠️ Failed to restore audio session: \(error)")
        }

        // Restart engine
        do {
            try engine.start()
            print("✅ Engine restarted")
        } catch {
            print("⚠️ Failed to restart engine: \(error)")
        }

        print("✅ Engine and audio session resumed")
    }
}
