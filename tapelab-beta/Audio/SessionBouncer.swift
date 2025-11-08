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

        // 4. Build audio graph FIRST (before manual rendering mode)
        do {
            try buildRenderingGraph(engine: engine, stereoFormat: stereoFormat)
        } catch {
            print("⚠️ Failed to build rendering graph: \(error)")
            throw BounceError.engineConfigurationFailed
        }

        // 5. CRITICAL: Start engine to initialize player nodes
        do {
            if !engine.isRunning {
                try engine.start()
                print("✅ Engine started for node initialization")
            }

            // Let engine warm up briefly
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms

            // Stop engine before enabling manual rendering
            engine.stop()
            print("✅ Engine stopped, ready for manual rendering")

        } catch {
            print("⚠️ Failed to initialize engine: \(error)")
            throw BounceError.engineConfigurationFailed
        }

        // 6. Enable manual rendering mode with stereo format
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

        // 7. Create output file in Int16 interleaved format - the gold standard for WAV compatibility
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

        // 8. Start engine in manual rendering mode
        do {
            try engine.start()
            print("✅ Engine started in manual rendering mode")
        } catch {
            print("⚠️ Failed to start engine: \(error)")
            throw BounceError.engineConfigurationFailed
        }

        // 9. Render audio in chunks
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

        var framesRendered: AVAudioFramePosition = 0

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

        // 10. Cleanup
        engine.stop()

        print("✅ Bounce complete: \(framesRendered) frames rendered")

        // 11. CRITICAL: Verify the output file is valid
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

    /// Builds the audio processing graph for offline rendering
    private func buildRenderingGraph(engine: AVAudioEngine, stereoFormat: AVAudioFormat) throws {

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

        // Create track buses and schedule regions
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

            // Connect track mixer to main mixer in stereo
            engine.connect(trackBus.mixer, to: mainMixer, format: stereoFormat)

            // Schedule all regions for this track
            scheduleRegions(track: track, player: trackBus.player, sampleRate: stereoFormat.sampleRate)
        }

        engine.prepare()
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

        // Connect player (mono) to mixer, which will output stereo
        engine.connect(player, to: mixer, format: monoFormat)

        // Apply track volume and pan
        mixer.volume = pow(10, Float(track.fx.volumeDB) / 20.0)
        mixer.pan = Float(track.fx.pan)

        print("✅ Track \(trackIndex + 1): player(mono) → mixer(stereo), vol=\(track.fx.volumeDB)dB, pan=\(track.fx.pan)")

        return (player, mixer)
    }

    /// Schedules all regions for playback on a player node
    private func scheduleRegions(track: Track, player: AVAudioPlayerNode, sampleRate: Double) {

        for region in track.regions {

            guard let audioFile = try? AVAudioFile(forReading: region.sourceURL) else {
                print("⚠️ Failed to load region file: \(region.sourceURL)")
                continue
            }

            // Calculate schedule time in samples
            let startSample = AVAudioFramePosition(region.startTime * sampleRate)
            let scheduledTime = AVAudioTime(sampleTime: startSample, atRate: sampleRate)

            // Load entire region into buffer
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: AVAudioFrameCount(audioFile.length)
            ) else {
                print("⚠️ Failed to create buffer for region")
                continue
            }

            do {
                try audioFile.read(into: buffer)
            } catch {
                print("⚠️ Failed to read region file: \(error)")
                continue
            }

            // Apply region gain if present
            if let gainDB = region.gainDB {
                applyGain(buffer: buffer, gainDB: gainDB)
            }

            // Schedule buffer
            player.scheduleBuffer(buffer, at: scheduledTime, options: [], completionHandler: nil)
        }

        player.play()
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
}
