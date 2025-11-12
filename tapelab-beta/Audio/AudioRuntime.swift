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

    // Alert state
    @Published var alertTitle: String = ""
    @Published var alertMessage: String = ""
    @Published var showAlert: Bool = false

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

        // Observe audio route disconnections
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AudioDeviceDisconnected"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }

            if self.timeline.isRecording,
               let trackIndex = self.recorder.currentRecordingTrackIndex {
                print("⚠️ Audio device disconnected during recording - stopping")

                // Stop recording immediately
                Task { @MainActor in
                    self.stopRecording(onTrack: trackIndex)

                    // Alert user
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
            guard let self = self,
                  let error = notification.object as? Error else { return }

            if self.timeline.isRecording,
               let trackIndex = self.recorder.currentRecordingTrackIndex {
                print("⚠️ Disk full during recording - emergency stop")

                Task { @MainActor in
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

            if self.timeline.isRecording,
               let trackIndex = self.recorder.currentRecordingTrackIndex {
                print("⚠️ Interruption during recording - stopping")
                Task { @MainActor in
                    self.stopRecording(onTrack: trackIndex)
                    self.showAlert(
                        title: "Recording Interrupted",
                        message: "Recording was stopped due to interruption (call, Siri, etc). Your recording has been saved."
                    )
                }
            } else if self.timeline.isPlaying {
                self.stopPlayback(resetPlayhead: false)
            }
        }

        print("🎛️ Audio runtime initialized (4-track engine)")
    }

    // MARK: - Alert Helper

    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
        print("📢 ALERT: \(title) - \(message)")
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
            try await player.play(session: session, timeline: timeline)
        }
        catch {
            print("⚠️ Playback failed: \(error)")
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
            // Only play metronome if BPM is set
            if let bpm = session.bpm {
                if session.metronomeCountIn {
                    let beatsPerMeasure = session.timeSignature.beatsPerMeasure
                    print("🥁 Starting \(beatsPerMeasure)-count metronome (recording already started)...")
                    metronome.bpm = bpm
                    metronome.timeSignature = session.timeSignature

                    // Start metronome for count-in
                    await metronome.play()

                    // Calculate count-in duration (full measure based on time signature)
                    let beatDuration = 60.0 / bpm
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
                    metronome.bpm = bpm
                    metronome.timeSignature = session.timeSignature
                    await metronome.play()
                }
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
        processingMessage = "Processing Recording"
        objectWillChange.send()

        let startTime = Date()

        // Capture the recording start position before stopping
        let recordingStartPosition = recorder.activeRecording?.startTime ?? timeline.playhead

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

        // Move playhead back to the beginning of the recorded section
        timeline.seek(to: recordingStartPosition)
        print("⏹️ Stopped recording AND playback, moved playhead back to \(String(format: "%.2f", recordingStartPosition))s")

        // Ensure minimum 3 second display time
        Task {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < 3.0 {
                try? await Task.sleep(nanoseconds: UInt64((3.0 - elapsed) * 1_000_000_000))
            }

            // Hide processing indicator
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

    /// Cut a region at the current playhead position, creating two separate regions
    /// - Parameters:
    ///   - trackIndex: Index of the track containing the region (0-based)
    ///   - regionIndex: Index of the region within the track to cut
    func cutRegion(trackIndex: Int, regionIndex: Int) {
        // Validate indices
        guard trackIndex >= 0 && trackIndex < session.tracks.count else {
            print("⚠️ Invalid track index: \(trackIndex)")
            return
        }

        guard regionIndex >= 0 && regionIndex < session.tracks[trackIndex].regions.count else {
            print("⚠️ Invalid region index: \(regionIndex)")
            return
        }

        // Don't allow cutting while recording or playing
        guard !timeline.isRecording && !timeline.isPlaying else {
            print("⚠️ Cannot cut regions while recording or playing")
            return
        }

        let region = session.tracks[trackIndex].regions[regionIndex]
        let cutPosition = timeline.playhead

        // Validate that playhead is within this region
        let regionEnd = region.startTime + region.duration
        guard cutPosition > region.startTime && cutPosition < regionEnd else {
            print("⚠️ Playhead is not within region bounds")
            return
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

        print("✂️ Cut region at \(String(format: "%.2f", cutPosition))s on track \(trackIndex + 1)")
        print("   First region: \(String(format: "%.2f", firstRegion.duration))s")
        print("   Second region: \(String(format: "%.2f", secondRegion.duration))s")

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
    }

    /// Move a region from one track to another
    /// - Parameters:
    ///   - fromTrackIndex: Index of the source track (0-based)
    ///   - regionIndex: Index of the region to move
    ///   - toTrackIndex: Index of the destination track (0-based)
    func moveRegionToTrack(fromTrackIndex: Int, regionIndex: Int, toTrackIndex: Int) {
        // Validate source track index
        guard fromTrackIndex >= 0 && fromTrackIndex < session.tracks.count else {
            print("⚠️ Invalid source track index: \(fromTrackIndex)")
            return
        }

        // Validate destination track index
        guard toTrackIndex >= 0 && toTrackIndex < session.tracks.count else {
            print("⚠️ Invalid destination track index: \(toTrackIndex)")
            return
        }

        // Validate region index
        guard regionIndex >= 0 && regionIndex < session.tracks[fromTrackIndex].regions.count else {
            print("⚠️ Invalid region index: \(regionIndex)")
            return
        }

        // Don't allow moving if same track
        guard fromTrackIndex != toTrackIndex else {
            print("⚠️ Cannot move region to the same track")
            return
        }

        // Don't allow moving regions while recording or playing
        guard !timeline.isRecording && !timeline.isPlaying else {
            print("⚠️ Cannot move regions while recording or playing")
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

        print("🔄 Moved region \(regionIndex) from track \(fromTrackIndex + 1) to track \(toTrackIndex + 1)")

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
