//
//  SessionRecorder.swift
//  tapelab
//

import AVFAudio
import Foundation
import Combine
import QuartzCore

// Debug logging flag - set to false for production
private let enableDebugLogs = false

public final class SessionRecorder: ObservableObject {
    weak var engineController: AudioEngineController?
    @Published var inputLevel: Float = 0
    @Published var recordingDuration: TimeInterval = 0
    @Published var monitorVolume: Float = 0.8 // User-adjustable input monitoring level

    private var recordingFile: AVAudioFile?
    private var isRecording = false
    private var monitorMixer: AVAudioMixerNode?
    private var recordingStartPlayhead: TimeInterval = 0  // Playhead when recording started
    private var currentRecordingRegionID: RegionID?  // Track the region being recorded
    private var currentRecordingTrackIndex: Int?  // Track index being recorded

    // Real-time level monitoring (always active, independent of recording)
    private var meterUpdateTimer: Timer?
    private var meterTapInstalled = false

    // Background queue for file I/O (NEVER block the audio thread!)
    private let fileIOQueue = DispatchQueue(label: "com.tapelab.fileIO", qos: .userInitiated)

    // Callback to update session from audio thread
    var onSessionUpdate: ((Session) -> Void)?

    public init() {
        // Start continuous input level monitoring
        startInputLevelMonitoring()
    }

    /// Start continuous monitoring of input level (independent of recording)
    private func startInputLevelMonitoring() {
        guard !meterTapInstalled else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self,
                  let engine = self.engineController?.engine else {
                print("⚠️ Cannot start monitoring: engine not available")
                return
            }

            // Ensure engine is running
            if !engine.isRunning {
                do {
                    try engine.start()
                    print("🎚️ Started engine for monitoring")
                } catch {
                    print("⚠️ Failed to start engine for monitoring: \(error)")
                    return
                }
            }

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)

            // Install a tap just for metering (small buffer for fast updates)
            input.installTap(onBus: 0, bufferSize: 256, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
                guard let self = self,
                      let channelData = buffer.floatChannelData else { return }

                let frameCount = Int(buffer.frameLength)
                let samples = UnsafeBufferPointer(start: channelData[0], count: frameCount)

                // Calculate RMS level
                var sum: Float = 0
                for sample in samples {
                    sum += sample * sample
                }
                let rms = sqrtf(sum / Float(frameCount))

                // Update on main thread
                DispatchQueue.main.async {
                    self.inputLevel = rms
                    self.objectWillChange.send()
                }
            }

            self.meterTapInstalled = true
            print("🎚️ Continuous input level monitoring started (engine running: \(engine.isRunning))")
        }
    }

    /// Trim latency frames from the start of an audio file
    /// Returns the URL of the trimmed file
    private func trimLatencyFromFile(sourceURL: URL, latencyFrames: Int64, format: AVAudioFormat) throws -> URL {
        // If latency is negligible, skip trimming
        guard latencyFrames > 0 else {
            if enableDebugLogs {
                print("⚠️ Latency is 0 frames, skipping trim")
            }
            return sourceURL
        }

        // Read source file
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let totalFrames = sourceFile.length

        // If latency is longer than the file, return empty file or error
        guard latencyFrames < totalFrames else {
            if enableDebugLogs {
                print("⚠️ Latency (\(latencyFrames) frames) >= file length (\(totalFrames) frames), keeping original")
            }
            return sourceURL
        }

        // Calculate trimmed length
        let trimmedFrames = totalFrames - latencyFrames
        if enableDebugLogs {
            print("✂️ Trimming: removing \(latencyFrames) frames, keeping \(trimmedFrames) frames")
        }

        // Create trimmed file URL (replace original)
        let trimmedURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("trimmed_\(sourceURL.lastPathComponent)")

        // Create output file
        let outputFile = try AVAudioFile(forWriting: trimmedURL, settings: format.settings)

        // Read from source starting at latency offset
        sourceFile.framePosition = latencyFrames

        // Read and write in chunks
        let bufferSize: AVAudioFrameCount = 4096
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!

        var framesRemaining = trimmedFrames
        while framesRemaining > 0 {
            let framesToRead = min(AVAudioFrameCount(framesRemaining), bufferSize)
            try sourceFile.read(into: buffer, frameCount: framesToRead)
            try outputFile.write(from: buffer)
            framesRemaining -= Int64(buffer.frameLength)
        }

        // Delete original file
        try FileManager.default.removeItem(at: sourceURL)
        if enableDebugLogs {
            print("🗑️ Deleted original file: \(sourceURL.lastPathComponent)")
        }

        // Rename trimmed file to original name
        let finalURL = sourceURL
        try FileManager.default.moveItem(at: trimmedURL, to: finalURL)
        if enableDebugLogs {
            print("✅ Renamed trimmed file to: \(finalURL.lastPathComponent)")
        }

        return finalURL
    }

    /// Measure the round-trip audio latency for latency compensation
    private func measureLatency() -> TimeInterval {
        let audioSession = AVAudioSession.sharedInstance()

        // Input latency: Time for audio to travel from mic to audio engine
        let inputLatency = audioSession.inputLatency

        // Output latency: Time for audio to travel from engine to speakers/headphones
        let outputLatency = audioSession.outputLatency

        // Buffer latency: Time spent in processing buffers
        let bufferDuration = audioSession.ioBufferDuration

        // Total round-trip latency (what user hears vs what gets recorded)
        let totalLatency = inputLatency + outputLatency + bufferDuration

        if enableDebugLogs {
            print("🔊 Latency measurements:")
            print("   - Input latency: \(String(format: "%.1f", inputLatency * 1000))ms")
            print("   - Output latency: \(String(format: "%.1f", outputLatency * 1000))ms")
            print("   - Buffer duration: \(String(format: "%.1f", bufferDuration * 1000))ms")
            print("   - Total round-trip: \(String(format: "%.1f", totalLatency * 1000))ms")
        }

        return totalLatency
    }

    func startRecording(session: Session, timeline: TimelineState, trackIndex: Int) async throws -> Session {
        var mutableSession = session
        guard let engine = engineController?.engine else { return mutableSession }

        // Remove the continuous monitoring tap before installing recording tap
        // (only one tap allowed per node at a time)
        let input = engine.inputNode
        if meterTapInstalled {
            input.removeTap(onBus: 0)
            meterTapInstalled = false
            print("🔍 Removed continuous monitoring tap")
        }

        // CRITICAL: Disconnect input mixer before installing tap
        // The input mixer connection may interfere with tap callbacks on Bluetooth devices
        if let inputMixer = engineController?.inputMixer {
            engine.disconnectNodeInput(inputMixer)
            print("🔍 Disconnected input mixer before tap installation")
        }

        // Ensure engine is running
        try engineController?.start()

        let inputFormat = input.outputFormat(forBus: 0)

        print("🔍 Input node format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) ch")

        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "TapelabRecorder", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Audio input not available - format shows \(inputFormat.sampleRate)Hz"])
        }

        print("🔍 Recording with format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount) ch")
        
        // Create recording file
        let fileURL = FileStore.newRegionURL(session: mutableSession, track: trackIndex)
        let file = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
        recordingFile = file
        isRecording = true
        recordingDuration = 0
        recordingStartPlayhead = -1  // Will be set when first buffer arrives
        print("🎬 Recording armed, waiting for first audio buffer...")
        
        // Create temporary region for live display
        let tempFileURL = fileURL
        let tempRegionID = RegionID()
        let tempRegion = Region(
            id: tempRegionID,
            sourceURL: tempFileURL,
            startTime: timeline.playhead,  // Will be updated when first buffer arrives
            duration: 0,  // Will grow during recording
            fileStartOffset: 0
        )

        // Add temporary region to session immediately
        currentRecordingRegionID = tempRegionID
        currentRecordingTrackIndex = trackIndex
        mutableSession.tracks[trackIndex].regions.append(tempRegion)
        print("📍 Added temporary recording region at playhead: \(String(format: "%.3f", timeline.playhead))s")

        // Notify runtime of session update
        await MainActor.run {
            self.onSessionUpdate?(mutableSession)
        }

        // Install tap - use nil format to match input node's format automatically
        // Request 512 frames @ 48kHz (~11ms), but iOS may ignore this for Bluetooth
        print("🔍 Installing tap on input node (requesting 512 frame buffers)...")
        var tapCallCount = 0
        var lastTapTime = CACurrentMediaTime()
        var lastBufferSize: AVAudioFrameCount = 0

        input.installTap(onBus: 0, bufferSize: 512, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
            tapCallCount += 1

            // Detect when iOS changes buffer size on us (common with Bluetooth)
            if buffer.frameLength != lastBufferSize {
                if lastBufferSize > 0 {
                    print("⚠️ BUFFER SIZE CHANGED: \(lastBufferSize) → \(buffer.frameLength) frames")
                }
                lastBufferSize = buffer.frameLength
            }

            // Detect dropped buffers by monitoring tap callback interval
            let currentTime = CACurrentMediaTime()
            let timeSinceLastTap = currentTime - lastTapTime
            lastTapTime = currentTime

            // Expected interval: 512 / 48000 ≈ 10.7ms
            // If interval is > 50ms, we likely dropped buffers
            if tapCallCount > 1 && timeSinceLastTap > 0.05 {
                print("⚠️ TAP CALLBACK GAP DETECTED: \(String(format: "%.1f", timeSinceLastTap * 1000))ms since last callback (expected ~11ms)")
            }

            // Log first few callbacks with detailed info
            if tapCallCount <= 5 {
                let expectedMs = (Double(buffer.frameLength) / buffer.format.sampleRate) * 1000
                print("🔍 Tap callback #\(tapCallCount): \(buffer.frameLength) frames (expected ~\(String(format: "%.1f", expectedMs))ms), actual interval: \(String(format: "%.1f", timeSinceLastTap * 1000))ms")
            }

            // Log every 100th callback after initial 5 to monitor long-term stability
            if tapCallCount > 5 && tapCallCount % 100 == 0 {
                print("🔍 Tap callback #\(tapCallCount): \(buffer.frameLength) frames, interval: \(String(format: "%.1f", timeSinceLastTap * 1000))ms")
            }

            guard let self, let file = self.recordingFile else { return }

            // CRITICAL: Capture playhead position when FIRST buffer arrives
            // This is the actual recording start time
            if self.recordingStartPlayhead < 0 {
                self.recordingStartPlayhead = timeline.playhead
                print("🎬 First buffer arrived! Recording started at playhead: \(String(format: "%.3f", self.recordingStartPlayhead))s")

                // Update the temporary region's start time
                if let regionID = self.currentRecordingRegionID,
                   let trackIdx = self.currentRecordingTrackIndex,
                   let idx = mutableSession.tracks[trackIdx].regions.firstIndex(where: { $0.id == regionID }) {
                    mutableSession.tracks[trackIdx].regions[idx].startTime = self.recordingStartPlayhead
                    Task { @MainActor in
                        self.onSessionUpdate?(mutableSession)
                    }
                }
            }

            // CRITICAL: Calculate level on audio thread (fast), then offload file I/O to background
            let level = buffer.peakLevel()
            let sampleRate = buffer.format.sampleRate

            // Offload file I/O to background queue - NEVER block the audio thread!
            self.fileIOQueue.async { [weak self] in
                guard let self else { return }

                do {
                    try file.write(from: buffer)
                    let frames = Double(file.length)

                    // Reduce logging frequency to avoid console spam
                    if tapCallCount <= 100 || tapCallCount % 100 == 0 {
                        print("🎤 Buffer: \(buffer.frameLength) frames, Level: \(String(format: "%.3f", level)) (\(String(format: "%.1f", 20 * log10(max(0.0001, level)))) dB), File: \(frames) frames")
                    }

                    let currentDuration = frames / sampleRate

                    // Update UI on main thread (but don't wait for it)
                    DispatchQueue.main.async {
                        self.recordingDuration = currentDuration

                        // Update the temporary region's duration in real-time
                        if let regionID = self.currentRecordingRegionID,
                           let trackIdx = self.currentRecordingTrackIndex,
                           let idx = mutableSession.tracks[trackIdx].regions.firstIndex(where: { $0.id == regionID }) {
                            mutableSession.tracks[trackIdx].regions[idx].duration = currentDuration

                            // Only trigger session update every 10 buffers to reduce overhead
                            if tapCallCount % 10 == 0 {
                                Task { @MainActor in
                                    self.onSessionUpdate?(mutableSession)
                                }
                            }
                        }

                        // Explicitly trigger objectWillChange for immediate UI update
                        self.objectWillChange.send()
                    }
                } catch {
                    print("⚠️ Error writing buffer: \(error)")
                }
            }
        }

        print("✅ Tap installed successfully")

        // Update timeline state to show recording in UI - must be on main thread
        await MainActor.run {
            timeline.isRecording = true

            // Start timeline for playhead updates during recording
            // Don't start if already playing (overdubbing scenario)
            if !timeline.isPlaying {
                timeline.startTimelineForRecording()
            }

            print("🔍 Timeline isRecording set to: \(timeline.isRecording)")
        }

        print("🎙️ Recording started on track \(trackIndex + 1)")

        return mutableSession
    }

    func stopRecording(session: inout Session, trackIndex: Int, timeline: TimelineState) {
        guard let file = recordingFile else { return }

        // Remove tap
        if let engine = engineController?.engine {
            engine.inputNode.removeTap(onBus: 0)
            print("🔍 Input tap removed")

            // CRITICAL: Reconnect input mixer after tap is removed
            // This keeps the input node initialized for future recordings
            if let inputMixer = engineController?.inputMixer {
                engine.connect(engine.inputNode, to: inputMixer, format: nil)
                inputMixer.outputVolume = 0
                print("🔍 Reconnected input mixer (volume=0)")
            }

            // Restart continuous monitoring tap
            startInputLevelMonitoring()
        }

        // Remove the temporary recording region
        if let regionID = currentRecordingRegionID {
            if let idx = session.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionID }) {
                session.tracks[trackIndex].regions.remove(at: idx)
                print("🗑️ Removed temporary recording region")
            }
        }

        // No monitoring to clean up anymore

        recordingFile = nil
        isRecording = false
        recordingDuration = 0
        currentRecordingRegionID = nil
        currentRecordingTrackIndex = nil

        // Update timeline state to hide recording in UI
        timeline.isRecording = false

        // Stop timeline if playback is not active
        if !timeline.isPlaying {
            timeline.stopTimeline()
        }

        // Measure latency BEFORE processing file
        let url = file.url
        let latency = measureLatency()
        let sampleRate = file.processingFormat.sampleRate
        let latencyFrames = Int64(latency * sampleRate)

        print("📊 Original recorded file stats:")
        print("   - Path: \(url.lastPathComponent)")
        print("   - Frames: \(file.length)")
        print("   - Duration: \(String(format: "%.2f", Double(file.length) / sampleRate))s")
        print("   - Sample Rate: \(sampleRate)Hz")
        print("   - Latency to remove: \(String(format: "%.3f", latency))s (\(latencyFrames) frames)")

        // Trim latency from the start of the audio file
        do {
            let trimmedURL = try trimLatencyFromFile(sourceURL: file.url,
                                                       latencyFrames: latencyFrames,
                                                       format: file.processingFormat)

            // Read trimmed file stats
            let trimmedFile = try AVAudioFile(forReading: trimmedURL)
            let trimmedDuration = Double(trimmedFile.length) / sampleRate
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: trimmedURL.path)[.size] as? Int64) ?? 0

            print("📊 Trimmed file stats:")
            print("   - Path: \(trimmedURL.lastPathComponent)")
            print("   - Frames: \(trimmedFile.length)")
            print("   - Duration: \(String(format: "%.2f", trimmedDuration))s")
            print("   - File Size: \(fileSize) bytes")

            // CRITICAL: Move the region backward by the amount we trimmed
            // If we trimmed 170ms from the start, the audio now starts 170ms earlier
            let compensatedStartTime = max(0, recordingStartPlayhead - latency)

            print("🎯 Timeline position compensation:")
            print("   - Recording started at: \(String(format: "%.3f", recordingStartPlayhead))s")
            print("   - Trimmed amount: \(String(format: "%.3f", latency))s")
            print("   - New start position: \(String(format: "%.3f", compensatedStartTime))s")

            let region = Region(
                sourceURL: trimmedURL,
                startTime: compensatedStartTime,  // Move backward by trimmed amount
                duration: trimmedDuration,
                fileStartOffset: 0,
                fileDuration: trimmedDuration
            )
            session.tracks[trackIndex].regions.append(region)

            print("✅ Trimmed region saved to session: \(trimmedURL.lastPathComponent)")
        } catch {
            print("⚠️ Failed to trim audio file: \(error)")
            print("⚠️ Using original file without trimming")

            // Fallback: use original file without trimming
            let originalDuration = Double(file.length) / sampleRate
            let region = Region(
                sourceURL: file.url,
                startTime: recordingStartPlayhead,
                duration: originalDuration,
                fileStartOffset: 0,
                fileDuration: originalDuration
            )
            session.tracks[trackIndex].regions.append(region)
            print("✅ Original (untrimmed) region saved to session: \(file.url.lastPathComponent)")
        }
    }
    
    // MARK: - Input Monitoring
    
    private func setupInputMonitoring(input: AVAudioInputNode, engine: AVAudioEngine) {
        // CRITICAL: Use the ACTUAL input format from the input node
        // Don't assume format - get it directly from the node
        let actualInputFormat = input.outputFormat(forBus: 0)

        print("🔍 Setting up monitoring: \(actualInputFormat.sampleRate)Hz, \(actualInputFormat.channelCount) channels")

        // Clean up any existing monitoring setup first
        if let existingMonitor = monitorMixer {
            print("🔍 Cleaning up existing monitor mixer")
            engine.disconnectNodeInput(existingMonitor)
            engine.disconnectNodeOutput(existingMonitor)
            engine.detach(existingMonitor)
            monitorMixer = nil
        }

        // Create fresh monitor mixer
        let monitor = AVAudioMixerNode()
        engine.attach(monitor)
        monitorMixer = monitor

        // Connect input → monitor mixer (use actual input format)
        engine.connect(input, to: monitor, format: actualInputFormat)

        // Connect monitor → main mixer (use nil for auto format conversion)
        engine.connect(monitor, to: engine.mainMixerNode, format: nil)

        // Set monitoring volume
        monitor.outputVolume = monitorVolume

        print("✅ Input monitoring connected")
    }
    
    /// Adjust input monitoring volume (0.0 = muted, 1.0 = full volume)
    func setMonitorVolume(_ volume: Float) {
        monitorVolume = max(0, min(1, volume))
        monitorMixer?.outputVolume = monitorVolume
    }
}
