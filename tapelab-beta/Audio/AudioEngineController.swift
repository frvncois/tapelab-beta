//
//  AudioEngineController.swift
//  tapelab
//

import AVFAudio
import Foundation
import Combine

// Debug logging flag - set to false for production
private let enableDebugLogs = false

@MainActor
public final class AudioEngineController: ObservableObject {
    // DEBUG FLAGS - Set these to test different configurations
    static let DISABLE_LIMITER = false       // Set to true to bypass limiter (test for limiter-induced clicks)
    static let USE_SINGLE_TRACK_ONLY = false // Set to true to test with only Track 1 (test format conversion issues)

    let engine = AVAudioEngine()
    let mainMixer: AVAudioMixerNode
    let limiter: AVAudioUnitEffect // Master limiter to prevent clipping
    let inputMixer: AVAudioMixerNode // Mixer for input node (keeps it initialized)
    let sampleRate: Double
    let processingFormat: AVAudioFormat
    let stereoFormat: AVAudioFormat
    private(set) var trackBuses: [TrackBus] = []

    init(trackCount: Int = 4) {
        // Configure audio session FIRST before reading formats
        Self.configureAudioSession()

        // Initialize all stored properties
        mainMixer = engine.mainMixerNode
        inputMixer = AVAudioMixerNode()
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        var detectedSampleRate = outputFormat.sampleRate

        print("🔍 Output node format: \(detectedSampleRate)Hz, \(outputFormat.channelCount) channels")

        // CRITICAL: Handle case where output format is invalid (0Hz)
        // This can happen if audio session configuration failed
        if detectedSampleRate <= 0 || detectedSampleRate > 192000 {
            print("⚠️ Invalid output format detected (\(detectedSampleRate)Hz)")
            print("⚠️ Attempting to start engine to initialize output node...")

            // Try starting the engine which may initialize the output node
            do {
                try engine.start()
                engine.stop()

                // Re-read output format
                let retryFormat = engine.outputNode.outputFormat(forBus: 0)
                detectedSampleRate = retryFormat.sampleRate
                print("🔍 After engine start: \(detectedSampleRate)Hz, \(retryFormat.channelCount) channels")
            } catch {
                print("⚠️ Could not start engine: \(error)")
            }

            // If still invalid, use fallback
            if detectedSampleRate <= 0 || detectedSampleRate > 192000 {
                detectedSampleRate = 48000  // Fallback to 48kHz
                print("⚠️ Using fallback sample rate: \(detectedSampleRate)Hz")
            }
        }

        sampleRate = detectedSampleRate

        guard sampleRate > 0 && sampleRate <= 192000 else {
            fatalError("⚠️ Invalid sample rate: \(sampleRate)Hz - audio system initialization failed")
        }

        processingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

        print("🔍 Processing format: \(processingFormat.sampleRate)Hz, \(processingFormat.channelCount) channels")
        print("🔍 Stereo format: \(stereoFormat.sampleRate)Hz, \(stereoFormat.channelCount) channels")

        // Create limiter (inline to avoid method call before init)
        let limiterDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        limiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)

        // Attach limiter and input mixer
        engine.attach(limiter)
        engine.attach(inputMixer)

        // CRITICAL: Connect input node to input mixer to force initialization
        // This keeps the input node initialized and ready for recording
        // Set volume to 0 so we don't hear the input during playback
        inputMixer.outputVolume = 0
        engine.connect(engine.inputNode, to: inputMixer, format: nil)
        print("🔍 Connected input node to input mixer (volume=0) to force initialization")

        // Respect single track debug flag
        let actualTrackCount = Self.USE_SINGLE_TRACK_ONLY ? 1 : trackCount
        setupTracks(count: actualTrackCount)

        // Connect main mixer to output - optionally bypass limiter for testing
        if Self.DISABLE_LIMITER {
            engine.connect(mainMixer, to: engine.outputNode, format: stereoFormat)
            print("⚠️  LIMITER DISABLED (DEBUG MODE)")
            print("🎧 AudioEngine ready @ \(sampleRate)Hz WITHOUT limiter")
        } else {
            engine.connect(mainMixer, to: limiter, format: stereoFormat)
            engine.connect(limiter, to: engine.outputNode, format: stereoFormat)
            print("🎧 AudioEngine ready @ \(sampleRate)Hz with master limiter")
        }

        if Self.USE_SINGLE_TRACK_ONLY {
            print("⚠️  SINGLE TRACK MODE (DEBUG) - Only Track 1 active")
        }
    }

    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // CRITICAL: Try playback-only category first if playAndRecord fails
            // This handles cases where microphone permissions aren't granted yet
            var categorySet = false

            // Try playAndRecord first (for recording capability)
            do {
                try session.setCategory(.playAndRecord, mode: .default,
                                       options: [.allowBluetoothA2DP])
                categorySet = true
                print("✅ Audio session category: playAndRecord")
            } catch {
                print("⚠️ Could not set playAndRecord category: \(error)")
                print("   Falling back to playback-only mode...")
                // Fallback to playback-only
                try session.setCategory(.playback, mode: .default,
                                       options: [.allowBluetoothA2DP])
                categorySet = true
                print("✅ Audio session category: playback (recording will not be available)")
            }

            guard categorySet else {
                print("⚠️ Failed to set any audio session category")
                return
            }

            // CRITICAL: Set sample rate BEFORE activation
            try session.setPreferredSampleRate(48000)

            // CRITICAL: Force iPhone built-in microphone at startup (only for playAndRecord)
            // This must be done BEFORE activating the session
            if session.category == .playAndRecord {
                let availableInputs = session.availableInputs ?? []
                if let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic }) {
                    try session.setPreferredInput(builtInMic)
                    print("✅ Forced iPhone built-in microphone at startup")
                } else {
                    print("⚠️ Built-in mic not found, using default input")
                }
            }

            // Detect if output OR input is Bluetooth before activation
            let currentRoute = session.currentRoute
            let isBluetoothOutput = currentRoute.outputs.contains { output in
                output.portType == .bluetoothA2DP ||
                output.portType == .bluetoothHFP ||
                output.portType == .bluetoothLE
            }
            let isBluetoothInput = currentRoute.inputs.contains { input in
                input.portType == .bluetoothHFP ||
                input.portType == .bluetoothLE
            }
            let isBluetoothAny = isBluetoothOutput || isBluetoothInput

            // Set preferred buffer duration - adjust for Bluetooth
            // Bluetooth needs MUCH larger buffer due to compression and variable latency
            let bufferDuration: TimeInterval
            if isBluetoothAny {
                bufferDuration = 0.050  // 50ms for Bluetooth (up from 20ms)
                print("🔵 Bluetooth detected - requesting 50ms buffer for stability")
                if isBluetoothInput {
                    print("⚠️ WARNING: Bluetooth microphone detected - input tap may be unreliable")
                }
            } else {
                bufferDuration = 0.010  // 10ms for wired
                print("🔌 Wired audio - requesting 10ms buffer")
            }
            try session.setPreferredIOBufferDuration(bufferDuration)

            // Verify what we actually got - iOS may not honor our request
            let actualBufferDuration = session.ioBufferDuration
            if abs(actualBufferDuration - bufferDuration) > 0.005 {
                print("⚠️ Buffer duration mismatch: requested \(String(format: "%.1f", bufferDuration * 1000))ms, got \(String(format: "%.1f", actualBufferDuration * 1000))ms")
            }

            // Activate the session
            try session.setActive(true)

            print("🎚️ Audio session configured: \(session.sampleRate)Hz, \(session.ioBufferDuration)s buffer")
            print("🔍 Requested: 48000Hz, Got: \(session.sampleRate)Hz")
            print("🔍 Input route: \(session.currentRoute.inputs.first?.portName ?? "unknown")")
            print("🔍 Output route: \(session.currentRoute.outputs.first?.portName ?? "unknown")")
        } catch {
            print("⚠️ Could not configure audio session: \(error)")
            print("⚠️ Audio will use default system configuration")
        }
    }
    
    private func setupTracks(count: Int) {
        for i in 0..<count {
            let bus = TrackBus()
            engine.attach(bus.player)
            engine.attach(bus.eq)
            engine.attach(bus.delay)
            engine.attach(bus.reverb)
            engine.attach(bus.dist)
            engine.attach(bus.mixer)

            print("🔍 Track \(i+1): Connecting with mono format \(processingFormat.sampleRate)Hz")

            // Audio graph: Player → EQ → Delay → Reverb → Dist → Mixer → MainMixer
            engine.connect(bus.player, to: bus.eq, format: processingFormat)
            engine.connect(bus.eq, to: bus.delay, format: processingFormat)
            engine.connect(bus.delay, to: bus.reverb, format: processingFormat)
            engine.connect(bus.reverb, to: bus.dist, format: processingFormat)
            engine.connect(bus.dist, to: bus.mixer, format: processingFormat)

            print("🔍 Track \(i+1): Connecting mixer to mainMixer with mono format (will be converted to stereo by mainMixer)")
            engine.connect(bus.mixer, to: mainMixer, format: processingFormat)

            trackBuses.append(bus)
            print("🎛️ Track \(i+1) initialized")
        }
    }

    func start() throws {
        if !engine.isRunning {
            try engine.start()
            print("▶️ Audio engine started")
        }
    }

    /// Force reactivate audio session to fix Bluetooth A2DP routing issues
    /// Call this after stopping/restarting the engine during playback modifications
    func reactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Deactivate and immediately reactivate to force iOS to reconnect Bluetooth output
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setActive(true)
            print("🔄 Audio session reactivated")
            print("   Output: \(session.currentRoute.outputs.first?.portName ?? "unknown")")
        } catch {
            print("⚠️ Failed to reactivate audio session: \(error)")
        }
    }
    
    func stop() {
        engine.stop()
        print("⏸️ Audio engine stopped")
    }

    /// Diagnostic function to identify audio issues (clicks, pops, dropouts)
    /// Call this periodically during playback to monitor audio health
    func diagnoseAudioIssues() {
        guard enableDebugLogs else { return }

        let session = AVAudioSession.sharedInstance()

        print("🔍 ═══════════════════════════════════════")
        print("🔍 AUDIO DIAGNOSTICS")
        print("🔍 ═══════════════════════════════════════")
        print("🔍 Audio Session:")
        print("  📊 Buffer duration: \(String(format: "%.1f", session.ioBufferDuration * 1000))ms")
        print("  📊 Sample rate: \(session.sampleRate)Hz")
        print("  📊 Preferred rate: \(session.preferredSampleRate)Hz")
        print("  📊 Output latency: \(String(format: "%.1f", session.outputLatency * 1000))ms")
        print("  📊 Input latency: \(String(format: "%.1f", session.inputLatency * 1000))ms")
        print("  📊 Output route: \(session.currentRoute.outputs.first?.portName ?? "unknown")")
        print("  📊 Output type: \(session.currentRoute.outputs.first?.portType.rawValue ?? "unknown")")

        print("🔍 Engine:")
        print("  📊 Running: \(engine.isRunning)")
        print("  📊 Main mixer volume: \(mainMixer.volume)")
        print("  📊 Main mixer output: \(mainMixer.outputVolume)")

        print("🔍 Track Buses:")
        for (i, bus) in trackBuses.enumerated() {
            let lastRender = bus.player.lastRenderTime?.sampleTime ?? -1
            print("  📊 Track \(i+1):")
            print("     - Player playing: \(bus.player.isPlaying)")
            print("     - Last render: \(lastRender)")
            print("     - Mixer volume: \(bus.mixer.volume)")
            print("     - Mixer pan: \(bus.mixer.pan)")
        }

        // Check for common issues
        let bufferMs = session.ioBufferDuration * 1000
        if bufferMs < 8 {
            print("⚠️  WARNING: Buffer size (\(String(format: "%.1f", bufferMs))ms) is very small - may cause clicks!")
            print("   Recommendation: Increase to 10-20ms")
        }

        if session.sampleRate != session.preferredSampleRate {
            print("⚠️  WARNING: Sample rate mismatch!")
            print("   Requested: \(session.preferredSampleRate)Hz, Got: \(session.sampleRate)Hz")
            print("   This causes resampling which can add artifacts")
        }

        let outputType = session.currentRoute.outputs.first?.portType
        if outputType == .bluetoothA2DP || outputType == .bluetoothHFP || outputType == .bluetoothLE {
            print("ℹ️  INFO: Using Bluetooth audio")
            print("   Bluetooth adds ~150-200ms latency and may have compression artifacts")
            print("   Try wired headphones or speaker for testing")
        }

        print("🔍 ═══════════════════════════════════════")
    }
}
