import Foundation
import AVFAudio
import Combine

/// Handles offline rendering of session tracks into a stereo mix file
@MainActor
class SessionBouncer {

    // MARK: - Types

    struct BounceProgress {
        let percentage: Int  // 0-100
        let framesProcessed: AVAudioFramePosition
        let totalFrames: AVAudioFramePosition
    }

    enum BounceError: LocalizedError {
        case emptySession
        case invalidAudioFormat
        case insufficientDiskSpace
        case engineConfigurationFailed
        case renderingFailed(Error)
        case fileWriteFailed(Error)

        var errorDescription: String? {
            switch self {
            case .emptySession:
                return "Session is empty. Add some audio before exporting."
            case .invalidAudioFormat:
                return "Invalid audio format configuration."
            case .insufficientDiskSpace:
                return "Insufficient disk space to create mix file."
            case .engineConfigurationFailed:
                return "Failed to configure audio engine for bouncing."
            case .renderingFailed(let error):
                return "Rendering failed: \(error.localizedDescription)"
            case .fileWriteFailed(let error):
                return "Failed to write mix file: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Properties

    private let session: Session
    private let audioController: AudioEngineController
    private var isCancelled = false

    // Buffer caching for pre-rendering
    private var regionBuffers: [[UUID: AVAudioPCMBuffer]] = []
    private var preRenderedRegions: [String: AVAudioPCMBuffer] = [:]

    // MARK: - Initialization

    init(session: Session, audioController: AudioEngineController) {
        self.session = session
        self.audioController = audioController
    }

    // MARK: - Public API

    /// Bounces the session to a stereo WAV file
    /// - Parameters:
    ///   - outputURL: Destination file URL for the bounced mix
    ///   - progressHandler: Closure called with progress updates (0-100%)
    /// - Returns: Mix object representing the bounced file
    /// - Throws: BounceError if bouncing fails
    func bounce(to outputURL: URL, progressHandler: @escaping (BounceProgress) -> Void) async throws -> Mix {

        // 1. Validate session has audio
        let totalDuration = calculateSessionDuration()
        guard totalDuration > 0 else {
            throw BounceError.emptySession
        }

        print("🎛️ Starting bounce: \(session.name), duration: \(totalDuration)s")

        // 2. Create offline rendering engine
        let engine = AVAudioEngine()
        let sampleRate = audioController.sampleRate
        let totalFrames = AVAudioFramePosition(totalDuration * sampleRate)
        let frameCapacity: AVAudioFrameCount = 4096

        // 3. Configure stereo output format (this is what we'll render AND write)
        guard let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        ) else {
            throw BounceError.invalidAudioFormat
        }

        print("🔍 Stereo format: \(stereoFormat)")

        // 4. CRITICAL: Enable manual rendering mode BEFORE attaching any nodes
        do {
            try engine.enableManualRenderingMode(
                .offline,
                format: stereoFormat,
                maximumFrameCount: frameCapacity
            )
            print("✅ Manual rendering enabled with format: \(engine.manualRenderingFormat)")
        } catch {
            print("⚠️ Failed to enable manual rendering: \(error)")
            throw BounceError.engineConfigurationFailed
        }

        // 5. Build audio graph (attach and connect nodes)
        // Returns track/player pairs for later scheduling
        let trackPlayers: [(track: Track, player: AVAudioPlayerNode)]
        do {
            trackPlayers = try buildRenderingGraph(engine: engine, stereoFormat: stereoFormat)
        } catch {
            print("⚠️ Failed to build rendering graph: \(error)")
            throw BounceError.engineConfigurationFailed
        }

        // 6. Start engine in manual rendering mode
        do {
            try engine.start()
            print("✅ Engine started in manual rendering mode")
        } catch {
            print("⚠️ Failed to start engine: \(error)")
            throw BounceError.engineConfigurationFailed
        }

        // 7. Preload and pre-render regions with effects
        print("🎵 Preloading region buffers...")
        preloadRegions(sampleRate: stereoFormat.sampleRate)
        print("✅ Preloaded \(regionBuffers.flatMap { $0.values }.count) region buffers")

        print("🎵 Pre-rendering regions with effects...")
        preRenderAllRegions(sampleRate: stereoFormat.sampleRate)
        print("✅ Pre-rendered \(preRenderedRegions.count) regions")

        // 8. NOW schedule pre-rendered buffers (engine is running in manual mode)
        print("🎵 Scheduling regions for offline rendering...")
        for (track, player) in trackPlayers {
            schedulePreRenderedRegions(track: track, player: player, sampleRate: stereoFormat.sampleRate)
        }
        print("✅ All regions scheduled for offline rendering")

        // 9. Write rendered audio - use explicit scope to ensure file closure
        var framesRendered: AVAudioFramePosition = 0
        do {
            // Create output file in Int16 interleaved format - the gold standard for WAV compatibility
            let outputFile: AVAudioFile

            // Create Int16 interleaved format - the most compatible WAV format
            guard let int16Format = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: true  // CRITICAL: must be interleaved
            ) else {
                throw BounceError.invalidAudioFormat
            }

            do {
                // Create output file with Int16 interleaved settings
                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,           // Int16, not Float
                    AVLinearPCMIsNonInterleaved: false,      // MUST be false (interleaved)
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: 2
                ]

                outputFile = try AVAudioFile(forWriting: outputURL, settings: settings)

                print("🔍 Engine rendering format: \(engine.manualRenderingFormat)")
                print("🔍 Target format: \(int16Format)")
                print("🔍 Output file format: \(outputFile.fileFormat)")
                print("🔍 Output file processing format: \(outputFile.processingFormat)")

                // Verify file format details
                let desc = outputFile.fileFormat.streamDescription.pointee
                print("📋 File format verification:")
                print("  - Format ID: \(desc.mFormatID == kAudioFormatLinearPCM ? "PCM" : "other")")
                print("  - Bits per channel: \(desc.mBitsPerChannel)")
                print("  - Is float: \(desc.mFormatFlags & kAudioFormatFlagIsFloat != 0)")
                print("  - Is interleaved: \(desc.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0)")
            } catch {
                print("⚠️ Failed to create output file: \(error)")
                throw BounceError.fileWriteFailed(error)
            }

            // Render audio in chunks
            // CRITICAL: We must write in processingFormat, NOT fileFormat!
            // AVAudioFile converts from processingFormat to fileFormat automatically
            let renderBuffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: engine.manualRenderingMaximumFrameCount
            )!

            let writeFormat = outputFile.processingFormat

            print("🔍 Render format: \(renderBuffer.format)")
            print("🔍 Write format (processingFormat): \(writeFormat)")
            print("🎯 AVAudioFile will convert \(writeFormat) → \(outputFile.fileFormat) on disk")

            // Check if we need format conversion
            let needsConversion = engine.manualRenderingFormat != writeFormat

            var converter: AVAudioConverter?
            var convertBuffer: AVAudioPCMBuffer?

            if needsConversion {
                print("⚠️ Format conversion needed")
                converter = AVAudioConverter(from: engine.manualRenderingFormat, to: writeFormat)
                convertBuffer = AVAudioPCMBuffer(
                    pcmFormat: writeFormat,
                    frameCapacity: engine.manualRenderingMaximumFrameCount
                )
                print("✅ Converter created: \(engine.manualRenderingFormat) → \(writeFormat)")
            } else {
                print("✅ Formats match - no conversion needed")
            }

            framesRendered = 0

            while framesRendered < totalFrames {

                // Check for cancellation
                if isCancelled {
                    engine.stop()
                    try? FileManager.default.removeItem(at: outputURL)
                    print("🛑 Bounce cancelled")
                    throw BounceError.renderingFailed(NSError(domain: "SessionBouncer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cancelled by user"]))
                }

                let framesToRender = min(AVAudioFrameCount(totalFrames - framesRendered), renderBuffer.frameCapacity)

                // Render frames from engine
                do {
                    let status = try engine.renderOffline(framesToRender, to: renderBuffer)

                    guard status == .success else {
                        print("⚠️ Render failed with status: \(status)")
                        throw BounceError.renderingFailed(NSError(domain: "SessionBouncer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Render status: \(status)"]))
                    }
                } catch {
                    print("⚠️ Rendering error: \(error)")
                    throw BounceError.renderingFailed(error)
                }

                // CRITICAL: Set the actual frame length on the render buffer
                renderBuffer.frameLength = framesToRender

                // Write to file in processingFormat
                // AVAudioFile will convert to fileFormat (Int16 interleaved) automatically
                do {
                    if needsConversion, let converter = converter, let convertBuffer = convertBuffer {
                        // Convert to processingFormat first
                        var conversionError: NSError?
                        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                            outStatus.pointee = .haveData
                            return renderBuffer
                        }

                        let conversionStatus = converter.convert(to: convertBuffer, error: &conversionError, withInputFrom: inputBlock)

                        if let conversionError = conversionError {
                            print("⚠️ Conversion error: \(conversionError)")
                            throw BounceError.renderingFailed(conversionError)
                        }

                        guard conversionStatus != .error else {
                            print("⚠️ Conversion failed with status: \(conversionStatus)")
                            throw BounceError.renderingFailed(NSError(domain: "SessionBouncer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Conversion failed"]))
                        }

                        // Write converted buffer in processingFormat
                        try outputFile.write(from: convertBuffer)
                    } else {
                        // Formats match - write directly in processingFormat
                        // AVAudioFile converts to Int16 interleaved on disk
                        try outputFile.write(from: renderBuffer)
                    }
                } catch {
                    print("⚠️ Write error: \(error)")
                    throw BounceError.fileWriteFailed(error)
                }

                framesRendered += AVAudioFramePosition(framesToRender)

                // Report progress
                let percentage = Int((Double(framesRendered) / Double(totalFrames)) * 100)
                let progress = BounceProgress(
                    percentage: percentage,
                    framesProcessed: framesRendered,
                    totalFrames: totalFrames
                )
                progressHandler(progress)
            }

            print("✅ Bounce complete: \(framesRendered) frames rendered")
            print("💾 Closing output file and flushing buffers to disk...")

        } // CRITICAL: outputFile goes out of scope here, forcing file closure and buffer flush

        // 10. Cleanup
        engine.stop()

        // Wait briefly to ensure file system has completed write operations
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // 11. Verify the output file is valid
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes[.size] as? Int ?? 0
            print("📊 Output file size: \(fileSize) bytes")

            guard fileSize > 0 else {
                throw BounceError.fileWriteFailed(NSError(
                    domain: "SessionBouncer",
                    code: -4,
                    userInfo: [NSLocalizedDescriptionKey: "Output file is empty"]
                ))
            }

            // Try to read the file header
            let data = try Data(contentsOf: outputURL)
            let header = String(data: data.prefix(4), encoding: .ascii) ?? ""
            print("📊 File header: '\(header)'")

            if header != "RIFF" {
                print("⚠️ WARNING: File header is '\(header)', expected 'RIFF'")
                print("   This may not be a valid WAV file!")
            }

            // Try to load with AVAudioFile to verify
            let verifyFile = try AVAudioFile(forReading: outputURL)
            print("✅ File verified with AVAudioFile:")
            print("   Frames: \(verifyFile.length)")
            print("   Sample rate: \(verifyFile.fileFormat.sampleRate)Hz")
            print("   Channels: \(verifyFile.fileFormat.channelCount)")
            print("   Format: \(verifyFile.fileFormat)")

        } catch {
            print("⚠️ File verification failed: \(error)")
            throw BounceError.fileWriteFailed(error)
        }

        // 12. Create Mix object
        let mix = Mix(
            name: session.name,
            sessionId: session.id,
            sessionName: session.name,
            createdAt: Date(),
            duration: totalDuration,
            fileURL: outputURL
        )

        return mix
    }

    /// Cancels an in-progress bounce operation
    func cancel() {
        isCancelled = true
    }

    // MARK: - Private Helpers

    /// Calculates the total duration of the session (end time of last region)
    private func calculateSessionDuration() -> TimeInterval {
        var maxEndTime: TimeInterval = 0

        for track in session.tracks {
            for region in track.regions {
                let endTime = region.startTime + region.duration
                if endTime > maxEndTime {
                    maxEndTime = endTime
                }
            }
        }

        return maxEndTime
    }

    /// Builds the audio processing graph for offline rendering WITHOUT scheduling
    /// Returns array of (track, player) pairs for later scheduling
    private func buildRenderingGraph(engine: AVAudioEngine, stereoFormat: AVAudioFormat) throws -> [(track: Track, player: AVAudioPlayerNode)] {

        // Create main mixer and limiter
        let mainMixer = AVAudioMixerNode()
        let limiter = AVAudioUnitEffect(
            audioComponentDescription: AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_PeakLimiter,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
        )

        engine.attach(mainMixer)
        engine.attach(limiter)

        // Connect in stereo: mainMixer → limiter → output
        engine.connect(mainMixer, to: limiter, format: stereoFormat)
        engine.connect(limiter, to: engine.mainMixerNode, format: stereoFormat)

        print("✅ Graph: mainMixer → limiter → output (stereo)")

        var trackPlayers: [(track: Track, player: AVAudioPlayerNode)] = []

        // Create track buses (DO NOT schedule regions yet)
        for (trackIndex, track) in session.tracks.enumerated() {

            // Skip tracks with no regions
            guard !track.regions.isEmpty else { continue }

            // Create track bus (player + mixer for mono→stereo)
            let trackBus = try createTrackBus(
                engine: engine,
                track: track,
                trackIndex: trackIndex,
                stereoFormat: stereoFormat
            )

            // Mono format for track output
            guard let monoFormat = AVAudioFormat(
                standardFormatWithSampleRate: stereoFormat.sampleRate,
                channels: 1
            ) else {
                throw BounceError.invalidAudioFormat
            }

            // Connect track mixer to main mixer in MONO (mainMixer converts to stereo)
            engine.connect(trackBus.mixer, to: mainMixer, format: monoFormat)

            // Store for later scheduling (AFTER manual rendering is enabled)
            trackPlayers.append((track: track, player: trackBus.player))
        }

        engine.prepare()

        return trackPlayers
    }

    /// Creates an audio processing bus for a single track
    private func createTrackBus(
        engine: AVAudioEngine,
        track: Track,
        trackIndex: Int,
        stereoFormat: AVAudioFormat
    ) throws -> (player: AVAudioPlayerNode, mixer: AVAudioMixerNode) {

        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()

        engine.attach(player)
        engine.attach(mixer)

        // Mono processing format for audio files
        guard let monoFormat = AVAudioFormat(
            standardFormatWithSampleRate: stereoFormat.sampleRate,
            channels: 1
        ) else {
            throw BounceError.invalidAudioFormat
        }

        // Connect player (mono) to mixer in mono format
        engine.connect(player, to: mixer, format: monoFormat)

        // Apply track volume and pan
        mixer.volume = pow(10, Float(track.fx.volumeDB) / 20.0)
        mixer.pan = Float(track.fx.pan)

        print("✅ Track \(trackIndex + 1): player(mono) → mixer(mono), vol=\(track.fx.volumeDB)dB, pan=\(track.fx.pan)")

        return (player, mixer)
    }

    /// Schedules pre-rendered regions for OFFLINE rendering
    private func schedulePreRenderedRegions(track: Track, player: AVAudioPlayerNode, sampleRate: Double) {

        guard let trackIndex = session.tracks.firstIndex(where: { $0.id == track.id }) else {
            print("   ⚠️ Could not find track index")
            return
        }

        for region in track.regions {
            // Get the pre-rendered buffer (already has all effects applied!)
            let regionKey = "\(trackIndex)-\(region.id.id)"
            guard let preRenderedBuffer = preRenderedRegions[regionKey] else {
                print("   ⚠️ No pre-rendered buffer for region \(region.id.id)")
                continue
            }

            // Calculate schedule time in samples
            let startSample = AVAudioFramePosition(region.startTime * sampleRate)
            let scheduledTime = AVAudioTime(sampleTime: startSample, atRate: sampleRate)

            // Schedule the pre-rendered buffer (not the raw file!)
            player.scheduleBuffer(preRenderedBuffer, at: scheduledTime, options: [], completionHandler: nil)

            print("   📍 Scheduled PRE-RENDERED: \(region.sourceURL.lastPathComponent) at \(String(format: "%.2f", region.startTime))s, \(preRenderedBuffer.frameLength) frames")
        }

        // CRITICAL: START THE PLAYER NODE!
        // Without this, offline rendering won't pull any audio from scheduled buffers
        player.play()
        print("   ✅ Track ready (\(track.regions.count) pre-rendered regions scheduled) - PLAYER STARTED")
    }

    /// Applies gain in dB to a buffer
    private func applyGain(buffer: AVAudioPCMBuffer, gainDB: Double) {
        let linearGain = pow(10, Float(gainDB) / 20.0)

        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)

        for channel in 0..<Int(buffer.format.channelCount) {
            var data = channelData[channel]
            for frame in 0..<frameCount {
                data[frame] *= linearGain
            }
        }
    }

    // MARK: - Pre-rendering (from SessionPlayer)

    /// Preload all region buffers into memory
    private func preloadRegions(sampleRate: Double) {
        regionBuffers = Array(repeating: [:], count: session.tracks.count)

        for (i, track) in session.tracks.enumerated() {
            print("   🎚️ Track \(i + 1): \(track.regions.count) regions to load")
            for region in track.regions {
                print("      📁 Loading: \(region.sourceURL.lastPathComponent)")
                do {
                    let file = try AVAudioFile(forReading: region.sourceURL)
                    let sr = file.processingFormat.sampleRate
                    let startFrame = AVAudioFramePosition(region.fileStartOffset * sr)
                    let frames = AVAudioFrameCount(region.duration * sr)
                    guard frames > 0 else {
                        print("      ⚠️ Skipped (0 frames)")
                        continue
                    }
                    file.framePosition = startFrame
                    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                               frameCapacity: frames)!
                    try file.read(into: buf, frameCount: frames)
                    buf.frameLength = frames
                    if let mono = convertToMonoIfNeeded(buffer: buf, targetSampleRate: sampleRate) {
                        regionBuffers[i][region.id.id] = mono
                        print("      ✅ Loaded: \(mono.frameLength) frames")
                    }
                } catch {
                    print("      ⚠️ Preload failed: \(error)")
                }
            }
        }
    }

    /// Pre-render ENTIRE regions with all effects applied
    private func preRenderAllRegions(sampleRate: Double) {
        preRenderedRegions.removeAll()

        for (tIndex, track) in session.tracks.enumerated() {
            for region in track.regions {
                // Get source buffer (already loaded in preloadRegions)
                guard let sourceBuffer = regionBuffers[tIndex][region.id.id] else {
                    print("      ⚠️ No buffer for region \(region.id.id)")
                    continue
                }

                // Render the ENTIRE region with all effects applied
                if let renderedRegion = makeSegment(
                    from: sourceBuffer,
                    sampleRate: sampleRate,
                    offsetSeconds: region.fileStartOffset,
                    durationSeconds: region.duration,
                    reversed: region.reversed,
                    fadeIn: region.fadeIn ?? 0,
                    fadeOut: region.fadeOut ?? 0,
                    gainDB: region.gainDB ?? 0
                ) {
                    let key = "\(tIndex)-\(region.id.id)"
                    preRenderedRegions[key] = renderedRegion
                    print("      ✅ Pre-rendered: \(region.sourceURL.lastPathComponent), \(renderedRegion.frameLength) frames")
                }
            }
        }
    }

    /// Convert buffer to mono if needed
    private func convertToMonoIfNeeded(buffer: AVAudioPCMBuffer, targetSampleRate: Double) -> AVAudioPCMBuffer? {
        let format = buffer.format
        let channelCount = Int(format.channelCount)

        // Already mono and correct sample rate
        if channelCount == 1 && format.sampleRate == targetSampleRate {
            return buffer
        }

        // Create mono format at target sample rate
        guard let monoFormat = AVAudioFormat(
            standardFormatWithSampleRate: targetSampleRate,
            channels: 1
        ) else {
            return nil
        }

        // Convert if needed
        guard let converter = AVAudioConverter(from: format, to: monoFormat) else {
            return nil
        }

        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * (targetSampleRate / format.sampleRate))
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: outputFrameCapacity
        ) else {
            return nil
        }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        return error == nil ? outputBuffer : nil
    }

    /// Apply effects to a segment (fades, gain, reverse)
    private func makeSegment(
        from sourceBuffer: AVAudioPCMBuffer,
        sampleRate: Double,
        offsetSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        reversed: Bool,
        fadeIn: TimeInterval,
        fadeOut: TimeInterval,
        gainDB: Double
    ) -> AVAudioPCMBuffer? {

        let frameOffset = Int(offsetSeconds * sampleRate)
        let frameCount = Int(durationSeconds * sampleRate)

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceBuffer.format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ),
        let sourceData = sourceBuffer.floatChannelData,
        let outputData = outputBuffer.floatChannelData else {
            return nil
        }

        outputBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Copy data
        let sourcePtr = sourceData[0].advanced(by: frameOffset)
        let outputPtr = outputData[0]
        memcpy(outputPtr, sourcePtr, frameCount * MemoryLayout<Float>.size)

        // Apply reverse
        if reversed {
            var samples = Array(UnsafeBufferPointer(start: outputPtr, count: frameCount))
            samples.reverse()
            outputPtr.update(from: samples, count: frameCount)
        }

        // Apply fades
        if fadeIn > 0 {
            let fadeInFrames = Int(fadeIn * sampleRate)
            for i in 0..<min(fadeInFrames, frameCount) {
                let gain = Float(i) / Float(fadeInFrames)
                outputPtr[i] *= gain
            }
        }

        if fadeOut > 0 {
            let fadeOutFrames = Int(fadeOut * sampleRate)
            let fadeStart = max(0, frameCount - fadeOutFrames)
            for i in fadeStart..<frameCount {
                let gain = Float(frameCount - i) / Float(fadeOutFrames)
                outputPtr[i] *= gain
            }
        }

        // Apply gain
        if gainDB != 0 {
            let linearGain = pow(10.0, Float(gainDB) / 20.0)
            for i in 0..<frameCount {
                outputPtr[i] *= linearGain
            }
        }

        return outputBuffer
    }
}
