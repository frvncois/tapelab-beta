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


        // 4. CRITICAL: Enable manual rendering mode BEFORE attaching any nodes
        do {
            try engine.enableManualRenderingMode(
                .offline,
                format: stereoFormat,
                maximumFrameCount: frameCapacity
            )
        } catch {
            throw BounceError.engineConfigurationFailed
        }

        // 5. Build audio graph (attach and connect nodes)
        // Returns track/player pairs for later scheduling
        let trackPlayers: [(track: Track, player: AVAudioPlayerNode)]
        do {
            trackPlayers = try buildRenderingGraph(engine: engine, stereoFormat: stereoFormat)
        } catch {
            throw BounceError.engineConfigurationFailed
        }

        // 6. Start engine in manual rendering mode
        do {
            try engine.start()
        } catch {
            throw BounceError.engineConfigurationFailed
        }

        // 7. Preload and pre-render regions with effects
        preloadRegions(sampleRate: stereoFormat.sampleRate)

        preRenderAllRegions(sampleRate: stereoFormat.sampleRate)

        // 8. NOW schedule pre-rendered buffers (engine is running in manual mode)
        for (track, player) in trackPlayers {
            schedulePreRenderedRegions(track: track, player: player, sampleRate: stereoFormat.sampleRate)
        }

        // 9. Write rendered audio - use explicit scope to ensure file closure
        var framesRendered: AVAudioFramePosition = 0
        do {
            // Create output file in Int16 interleaved format - the gold standard for WAV compatibility
            let outputFile: AVAudioFile

            // Validate Int16 interleaved format - the most compatible WAV format
            guard AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: sampleRate,
                channels: 2,
                interleaved: true  // CRITICAL: must be interleaved
            ) != nil else {
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


                // Verify file format details
                let _ = outputFile.fileFormat.streamDescription.pointee
            } catch {
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


            // Check if we need format conversion
            let needsConversion = engine.manualRenderingFormat != writeFormat

            var converter: AVAudioConverter?
            var convertBuffer: AVAudioPCMBuffer?

            if needsConversion {
                converter = AVAudioConverter(from: engine.manualRenderingFormat, to: writeFormat)
                convertBuffer = AVAudioPCMBuffer(
                    pcmFormat: writeFormat,
                    frameCapacity: engine.manualRenderingMaximumFrameCount
                )
            } else {
            }

            framesRendered = 0

            while framesRendered < totalFrames {

                // Check for cancellation
                if isCancelled {
                    engine.stop()
                    try? FileManager.default.removeItem(at: outputURL)
                    throw BounceError.renderingFailed(NSError(domain: "SessionBouncer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cancelled by user"]))
                }

                let framesToRender = min(AVAudioFrameCount(totalFrames - framesRendered), renderBuffer.frameCapacity)

                // Render frames from engine
                do {
                    let status = try engine.renderOffline(framesToRender, to: renderBuffer)

                    guard status == .success else {
                        throw BounceError.renderingFailed(NSError(domain: "SessionBouncer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Render status: \(status)"]))
                    }
                } catch {
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
                            throw BounceError.renderingFailed(conversionError)
                        }

                        guard conversionStatus != .error else {
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


        } // CRITICAL: outputFile goes out of scope here, forcing file closure and buffer flush

        // 10. Cleanup
        engine.stop()

        // Wait briefly to ensure file system has completed write operations
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // 11. Verify the output file is valid
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            let fileSize = attributes[.size] as? Int ?? 0

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

            if header != "RIFF" {
            }

            // Try to load with AVAudioFile to verify
            let _ = try AVAudioFile(forReading: outputURL)

        } catch {
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

    /// Creates an audio processing bus for a single track with full FX chain
    private func createTrackBus(
        engine: AVAudioEngine,
        track: Track,
        trackIndex: Int,
        stereoFormat: AVAudioFormat
    ) throws -> (player: AVAudioPlayerNode, mixer: AVAudioMixerNode) {

        // Create full FX chain: Player → EQ → Delay → Reverb → Distortion → Mixer
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 4)
        let delay = AVAudioUnitDelay()
        let reverb = AVAudioUnitReverb()
        let dist = AVAudioUnitDistortion()
        let mixer = AVAudioMixerNode()

        // Attach all nodes
        engine.attach(player)
        engine.attach(eq)
        engine.attach(delay)
        engine.attach(reverb)
        engine.attach(dist)
        engine.attach(mixer)

        // Mono processing format for audio files
        guard let monoFormat = AVAudioFormat(
            standardFormatWithSampleRate: stereoFormat.sampleRate,
            channels: 1
        ) else {
            throw BounceError.invalidAudioFormat
        }

        // Connect full signal chain: Player → EQ → Delay → Reverb → Dist → Mixer
        engine.connect(player, to: eq, format: monoFormat)
        engine.connect(eq, to: delay, format: monoFormat)
        engine.connect(delay, to: reverb, format: monoFormat)
        engine.connect(reverb, to: dist, format: monoFormat)
        engine.connect(dist, to: mixer, format: monoFormat)

        // Apply FX settings from track
        applyFXToNodes(track: track, eq: eq, delay: delay, reverb: reverb, dist: dist, mixer: mixer)

        return (player, mixer)
    }

    /// Apply FX settings to audio nodes (same logic as TrackBus.applyFX)
    private func applyFXToNodes(
        track: Track,
        eq: AVAudioUnitEQ,
        delay: AVAudioUnitDelay,
        reverb: AVAudioUnitReverb,
        dist: AVAudioUnitDistortion,
        mixer: AVAudioMixerNode
    ) {
        let fx = track.fx

        // Volume / Pan
        let linearGain = pow(10.0, fx.volumeDB / 20.0)
        mixer.outputVolume = Float(linearGain)
        mixer.pan = fx.pan

        // EQ
        for (i, model) in fx.eqBands.enumerated() {
            guard i < eq.bands.count else { break }
            let band = eq.bands[i]
            band.bypass = false
            band.filterType = .parametric
            band.frequency = Float(model.frequency)
            band.gain = Float(model.gainDB)
            band.bandwidth = Float(model.q)
        }
        // Bypass remaining bands
        if fx.eqBands.count < eq.bands.count {
            for j in fx.eqBands.count..<eq.bands.count {
                eq.bands[j].bypass = true
            }
        }
        eq.bypass = fx.eqBands.isEmpty

        // Reverb - always use plate (spring-like sound)
        reverb.wetDryMix = fx.reverb.wetMix
        reverb.loadFactoryPreset(.plate)

        // Delay
        delay.wetDryMix = fx.delay.wetMix
        delay.delayTime = fx.delay.time
        delay.feedback = fx.delay.feedback
        delay.lowPassCutoff = fx.delay.lowPassCutoff

        // Saturation/Distortion
        dist.loadFactoryPreset(.multiBrokenSpeaker)
        dist.wetDryMix = fx.saturation.wetMix
        dist.preGain = fx.saturation.preGain
    }

    /// Schedules pre-rendered regions for OFFLINE rendering
    private func schedulePreRenderedRegions(track: Track, player: AVAudioPlayerNode, sampleRate: Double) {

        guard let trackIndex = session.tracks.firstIndex(where: { $0.id == track.id }) else {
            return
        }

        for region in track.regions {
            // Get the pre-rendered buffer (already has all effects applied!)
            let regionKey = "\(trackIndex)-\(region.id.id)"
            guard let preRenderedBuffer = preRenderedRegions[regionKey] else {
                continue
            }

            // Calculate schedule time in samples
            let startSample = AVAudioFramePosition(region.startTime * sampleRate)
            let scheduledTime = AVAudioTime(sampleTime: startSample, atRate: sampleRate)

            // Schedule the pre-rendered buffer (not the raw file!)
            player.scheduleBuffer(preRenderedBuffer, at: scheduledTime, options: [], completionHandler: nil)

        }

        // CRITICAL: START THE PLAYER NODE!
        // Without this, offline rendering won't pull any audio from scheduled buffers
        player.play()
    }

    /// Applies gain in dB to a buffer
    private func applyGain(buffer: AVAudioPCMBuffer, gainDB: Double) {
        let linearGain = pow(10, Float(gainDB) / 20.0)

        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)

        for channel in 0..<Int(buffer.format.channelCount) {
            let data = channelData[channel]
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
            for region in track.regions {
                do {
                    let file = try AVAudioFile(forReading: region.sourceURL)
                    let sr = file.processingFormat.sampleRate
                    let startFrame = AVAudioFramePosition(region.fileStartOffset * sr)
                    let frames = AVAudioFrameCount(region.duration * sr)
                    guard frames > 0 else {
                        continue
                    }
                    file.framePosition = startFrame
                    let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                               frameCapacity: frames)!
                    try file.read(into: buf, frameCount: frames)
                    buf.frameLength = frames
                    if let mono = convertToMonoIfNeeded(buffer: buf, targetSampleRate: sampleRate) {
                        regionBuffers[i][region.id.id] = mono
                    }
                } catch {
                    print("⚠️ SessionBouncer: Failed to load region \(region.id.id): \(error)")
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
