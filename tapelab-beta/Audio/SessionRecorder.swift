//
//  SessionRecorder.swift
//  tapelab
//

import AVFAudio
import Foundation
import Combine
import QuartzCore

enum RecordingError: LocalizedError {
    case diskSpaceCheckFailed
    case insufficientDiskSpace(availableMB: Int64)
    case audioInputNotAvailable

    var errorDescription: String? {
        switch self {
        case .diskSpaceCheckFailed:
            return "Could not check available disk space"
        case .insufficientDiskSpace(let mb):
            return "Insufficient disk space: \(mb)MB available. Need at least 100MB to record."
        case .audioInputNotAvailable:
            return "Audio input not available"
        }
    }
}

@MainActor
public final class SessionRecorder: ObservableObject {
    weak var engineController: AudioEngineController?
    @Published var inputLevel: Float = 0
    @Published var recordingDuration: TimeInterval = 0
    @Published var monitorVolume: Float = 0.8 // User-adjustable input monitoring level

    /// Temporary state for active recording - used for UI feedback only
    /// This is updated from audio thread safely via @Published (MainActor protection)
    @Published var activeRecording: ActiveRecording? = nil

    struct ActiveRecording {
        let trackIndex: Int
        let regionID: RegionID
        let startTime: TimeInterval
        var duration: TimeInterval
        let fileURL: URL
    }

    private var recordingFile: AVAudioFile?
    private var isRecording = false
    private var monitorMixer: AVAudioMixerNode?
    private var recordingStartPlayhead: TimeInterval = 0  // Playhead when recording started
    private var recordingOutputLatency: TimeInterval = 0  // Output latency for overdub compensation
    private var wasOverdubbing: Bool = false              // True if playback was active when recording started
    private var currentRecordingRegionID: RegionID?  // Track the region being recorded
    private(set) var currentRecordingTrackIndex: Int?  // Track index being recorded (internal access for emergency stop)

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
                return
            }

            // Ensure engine is running
            if !engine.isRunning {
                do {
                    try engine.start()
                } catch {
                    return
                }
            }

            let input = engine.inputNode
            let inputFormat = input.outputFormat(forBus: 0)

            // Install a tap just for metering and tuner
            // Use 4096 frames (~85ms @ 48kHz) for good balance between update rate and pitch accuracy
            var tapCallCount = 0
            input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
                guard let self = self,
                      let channelData = buffer.floatChannelData else { return }

                tapCallCount += 1

                let frameCount = Int(buffer.frameLength)
                let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

                // Calculate RMS level
                var sum: Float = 0
                for sample in samples {
                    sum += sample * sample
                }
                let rms = sqrtf(sum / Float(frameCount))

                // Update input level on main thread
                Task { @MainActor in
                    self.inputLevel = rms
                }
            }

            self.meterTapInstalled = true
        }
    }

    /// Measure output latency for overdub alignment compensation
    private func measureOutputLatency() -> TimeInterval {
        return AVAudioSession.sharedInstance().outputLatency
    }

    /// Trim frames from the start of an audio file for latency compensation
    /// Used when overdubbing at 0:00 where we can't shift to negative time
    private func trimAudioFile(sourceURL: URL, trimSeconds: TimeInterval, format: AVAudioFormat) throws -> (url: URL, duration: TimeInterval) {
        let sourceFile = try AVAudioFile(forReading: sourceURL)
        let sampleRate = format.sampleRate
        let trimFrames = Int64(trimSeconds * sampleRate)
        let totalFrames = sourceFile.length

        // If trim is longer than file, return minimal file
        guard trimFrames < totalFrames else {
            return (sourceURL, 0)
        }

        let trimmedFrames = totalFrames - trimFrames
        let trimmedDuration = Double(trimmedFrames) / sampleRate

        // Create trimmed file
        let trimmedURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("trimmed_\(sourceURL.lastPathComponent)")

        let outputFile = try AVAudioFile(forWriting: trimmedURL, settings: format.settings)

        // Seek past the trim portion
        sourceFile.framePosition = trimFrames

        // Copy remaining audio in chunks
        let bufferSize: AVAudioFrameCount = 4096
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!

        var framesRemaining = trimmedFrames
        while framesRemaining > 0 {
            let framesToRead = min(AVAudioFrameCount(framesRemaining), bufferSize)
            try sourceFile.read(into: buffer, frameCount: framesToRead)
            try outputFile.write(from: buffer)
            framesRemaining -= Int64(buffer.frameLength)
        }

        // Replace original with trimmed file
        try FileManager.default.removeItem(at: sourceURL)
        try FileManager.default.moveItem(at: trimmedURL, to: sourceURL)

        return (sourceURL, trimmedDuration)
    }

    /// Check if sufficient disk space available for recording
    /// Requires at least 100MB free space
    nonisolated private func checkDiskSpace() throws {
        guard let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            throw RecordingError.diskSpaceCheckFailed
        }

        do {
            let values = try documentsPath.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let capacity = values.volumeAvailableCapacityForImportantUsage else {
                return // Don't block recording on check failure
            }

            let requiredBytes: Int64 = 100 * 1024 * 1024  // 100 MB minimum
            let availableMB = capacity / 1_048_576

            if capacity < requiredBytes {
                throw RecordingError.insufficientDiskSpace(availableMB: availableMB)
            }

        } catch let error as RecordingError {
            throw error
        } catch {
            // Don't block recording on check failure
        }
    }

    func startRecording(session: Session, timeline: TimelineState, trackIndex: Int, needsLatencyCompensation: Bool) async throws -> Session {
        let mutableSession = session

        // CHECK DISK SPACE FIRST
        try checkDiskSpace()

        guard let engine = engineController?.engine else { return mutableSession }

        // Remove the continuous monitoring tap before installing recording tap
        // (only one tap allowed per node at a time)
        let input = engine.inputNode
        if meterTapInstalled {
            input.removeTap(onBus: 0)
            meterTapInstalled = false
        }

        // CRITICAL: Disconnect input mixer before installing tap
        // The input mixer connection may interfere with tap callbacks on Bluetooth devices
        if let inputMixer = engineController?.inputMixer {
            engine.disconnectNodeInput(inputMixer)
        }

        // Ensure engine is running
        try engineController?.start()

        let inputFormat = input.outputFormat(forBus: 0)


        guard inputFormat.sampleRate > 0 else {
            throw NSError(domain: "TapelabRecorder", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Audio input not available - format shows \(inputFormat.sampleRate)Hz"])
        }

        
        // CRITICAL: Capture playhead position NOW, before installing tap
        // The audio file will contain audio starting from this moment, not from when
        // the first buffer callback fires (which can be 100-150ms later)
        recordingStartPlayhead = timeline.playhead

        // Detect if we need output latency compensation
        // This is true when overdubbing (recording over existing audio on other tracks)
        // The user plays along with playback, which is delayed by output latency
        wasOverdubbing = needsLatencyCompensation

        // Capture output latency NOW at recording start (for overdub compensation)
        // AVAudioSession latency values can change during recording (especially with Bluetooth)
        recordingOutputLatency = measureOutputLatency()

        // Create recording file
        let fileURL = FileStore.newRegionURL(session: mutableSession, track: trackIndex)
        let file = try AVAudioFile(forWriting: fileURL, settings: inputFormat.settings)
        recordingFile = file
        isRecording = true
        recordingDuration = 0

        // Create recording metadata for UI (no session modification)
        let recordingRegionID = RegionID()
        currentRecordingRegionID = recordingRegionID
        currentRecordingTrackIndex = trackIndex


        // Detect if output is Bluetooth (which forces input buffers to match for sync)
        let audioSession = AVAudioSession.sharedInstance()
        let isBluetoothOutput = audioSession.currentRoute.outputs.contains { output in
            output.portType == .bluetoothA2DP ||
            output.portType == .bluetoothHFP ||
            output.portType == .bluetoothLE
        }

        // Match buffer size to iOS's actual behavior based on output route
        // Bluetooth forces large buffers even for built-in mic input
        let bufferSize: AVAudioFrameCount = isBluetoothOutput ? 4800 : 512
        let _ = Double(bufferSize) / inputFormat.sampleRate * 1000


        var tapCallCount = 0
        var lastTapTime = CACurrentMediaTime()
        var lastBufferSize: AVAudioFrameCount = 0

        input.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
            tapCallCount += 1

            // Detect when iOS changes buffer size on us (common with Bluetooth)
            if buffer.frameLength != lastBufferSize {
                if lastBufferSize > 0 {
                }
                lastBufferSize = buffer.frameLength
            }

            // Detect dropped buffers by monitoring tap callback interval
            let currentTime = CACurrentMediaTime()
            let timeSinceLastTap = currentTime - lastTapTime
            lastTapTime = currentTime

            // Expected interval: 512 / 48000 ≈ 10.7ms
            // If interval is > 50ms, we likely dropped buffers
            let expectedInterval = Double(buffer.frameLength) / buffer.format.sampleRate
            let warningThreshold = expectedInterval * 2.0

            if tapCallCount > 1 && timeSinceLastTap > warningThreshold {
            }

            // Log first few callbacks with detailed info
            // Log first few callbacks with detailed info
            if tapCallCount <= 5 {
                let expectedMs = (Double(buffer.frameLength) / buffer.format.sampleRate) * 1000
                let _ = abs(timeSinceLastTap * 1000 - expectedMs) < 10 ? "✅" : "⚠️"
            }

            // Log every 100th callback after initial 5 to monitor long-term stability
            if tapCallCount > 5 && tapCallCount % 100 == 0 {
            }

            guard let self, let file = self.recordingFile else { return }

            // Initialize activeRecording state for UI on first buffer (NO session access)
            if tapCallCount == 1 {
                if let regionID = self.currentRecordingRegionID,
                   let trackIdx = self.currentRecordingTrackIndex {
                    Task { @MainActor in
                        self.activeRecording = ActiveRecording(
                            trackIndex: trackIdx,
                            regionID: regionID,
                            startTime: self.recordingStartPlayhead,
                            duration: 0,
                            fileURL: file.url
                        )
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
                    let currentDuration = frames / sampleRate

                    // Periodic disk space check (every 5 seconds)
                    // ~93 Hz tap rate @ 512 frames, so ~465 calls = ~5 seconds
                    if tapCallCount % 500 == 0 {
                        do {
                            try self.checkDiskSpace()
                        } catch {
                            // Stop recording on main thread
                            DispatchQueue.main.async {
                                // Trigger emergency stop
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("DiskFullDuringRecording"),
                                    object: error
                                )
                            }
                            return  // Stop processing this buffer
                        }
                    }

                    // Reduce logging frequency to avoid console spam
                    if tapCallCount <= 100 || tapCallCount % 100 == 0 {
                    }

                    // Update UI state on main thread (NO session access)
                    // Use MainActor.run for better timing precision than DispatchQueue.main.async
                    Task { @MainActor in
                        self.recordingDuration = currentDuration

                        // Update input level for meter display during recording
                        self.inputLevel = level

                        // Update activeRecording duration for UI
                        if self.activeRecording?.regionID == self.currentRecordingRegionID {
                            self.activeRecording?.duration = currentDuration
                        }
                    }
                } catch {
                    // TODO: Add error handling in Phase 2
                }
            }
        }


        // Update timeline state to show recording in UI - must be on main thread
        await MainActor.run {
            timeline.isRecording = true

            // Start timeline for playhead updates during recording
            // Don't start if already playing (overdubbing scenario)
            if !timeline.isPlaying {
                timeline.startTimelineForRecording()
            }

        }


        return mutableSession
    }

    func stopRecording(session: inout Session, trackIndex: Int, timeline: TimelineState) {
        guard let file = recordingFile else { return }

        // Remove tap
        if let engine = engineController?.engine {
            engine.inputNode.removeTap(onBus: 0)

            // CRITICAL: Reconnect input mixer after tap is removed
            // This keeps the input node initialized for future recordings
            if let inputMixer = engineController?.inputMixer {
                engine.connect(engine.inputNode, to: inputMixer, format: nil)
                inputMixer.outputVolume = 0
            }

            // Restart continuous monitoring tap
            startInputLevelMonitoring()
        }

        // Clean up recording state
        recordingFile = nil
        isRecording = false
        recordingDuration = 0
        currentRecordingRegionID = nil
        currentRecordingTrackIndex = nil

        // Clear UI recording state
        activeRecording = nil

        // Update timeline state to hide recording in UI
        timeline.isRecording = false

        // Stop timeline if playback is not active
        if !timeline.isPlaying {
            timeline.stopTimeline()
        }

        let sampleRate = file.processingFormat.sampleRate
        var fileDuration = Double(file.length) / sampleRate
        var sourceURL = file.url

        // LATENCY COMPENSATION LOGIC:
        //
        // Case 1: First recording (no playback active) - wasOverdubbing = false
        //   - No compensation needed
        //   - The recorded audio aligns with the playhead position when recording started
        //   - Region starts at recordingStartPlayhead
        //
        // Case 2: Overdubbing (recording while playing back) - wasOverdubbing = true
        //   - Need to compensate for OUTPUT latency
        //   - When playhead shows position X, the audio coming out of headphones
        //     is actually from position (X - outputLatency) due to buffering/processing
        //   - User plays along with what they HEAR (which is delayed)
        //   - So their performance corresponds to earlier audio
        //   - We shift the recording EARLIER by outputLatency to align
        //
        // Case 2b: Overdubbing near 0:00 (compensated time would be negative)
        //   - We can't place a region at negative time
        //   - Instead, TRIM the audio file to remove the latency portion
        //   - This aligns the audio content with timeline position 0:00

        let latencyCompensation = wasOverdubbing ? recordingOutputLatency : 0
        let compensatedStartTime = recordingStartPlayhead - latencyCompensation

        let actualStartTime: TimeInterval
        let fileStartOffset: TimeInterval
        let playableDuration: TimeInterval

        if compensatedStartTime < 0 {
            // Case 2b: Overdub near 0:00 - trim the audio file
            let trimAmount = -compensatedStartTime  // How much to trim (positive value)

            do {
                let (trimmedURL, trimmedDuration) = try trimAudioFile(
                    sourceURL: sourceURL,
                    trimSeconds: trimAmount,
                    format: file.processingFormat
                )
                sourceURL = trimmedURL
                fileDuration = trimmedDuration
                actualStartTime = 0
                fileStartOffset = 0
                playableDuration = trimmedDuration

            } catch {
                // Fallback: use fileStartOffset approach
                actualStartTime = 0
                fileStartOffset = -compensatedStartTime
                playableDuration = fileDuration - fileStartOffset
            }
        } else {
            // Normal case: shift region earlier (or no shift for non-overdub)
            actualStartTime = compensatedStartTime
            fileStartOffset = 0
            playableDuration = fileDuration
        }

        // Create region with latency-compensated positioning
        let region = Region(
            sourceURL: sourceURL,
            startTime: actualStartTime,
            duration: playableDuration,
            fileStartOffset: fileStartOffset,
            fileDuration: fileDuration
        )
        session.tracks[trackIndex].regions.append(region)
    }
    
    // MARK: - Input Monitoring
    
    private func setupInputMonitoring(input: AVAudioInputNode, engine: AVAudioEngine) {
        // CRITICAL: Use the ACTUAL input format from the input node
        // Don't assume format - get it directly from the node
        let actualInputFormat = input.outputFormat(forBus: 0)


        // Clean up any existing monitoring setup first
        if let existingMonitor = monitorMixer {
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

    }
    
    /// Adjust input monitoring volume (0.0 = muted, 1.0 = full volume)
    func setMonitorVolume(_ volume: Float) {
        monitorVolume = max(0, min(1, volume))
        monitorMixer?.outputVolume = monitorVolume
    }
}
