//
//  AudioEngineController.swift
//  tapelab
//

import AVFAudio
import Foundation
import Combine

@MainActor
public final class AudioEngineController: ObservableObject {
    // DEBUG FLAGS - Set these to test different configurations
    static let DISABLE_LIMITER = true        // CHANGED: Test without limiter
    static let USE_SINGLE_TRACK_ONLY = false

    let engine = AVAudioEngine()
    let mainMixer: AVAudioMixerNode
    let limiter: AVAudioUnitEffect
    let inputMixer: AVAudioMixerNode
    let sampleRate: Double
    let processingFormat: AVAudioFormat
    let stereoFormat: AVAudioFormat
    private(set) var trackBuses: [TrackBus] = []

    // Audio route change observer
    private var routeChangeObserver: NSObjectProtocol?

    init(trackCount: Int = 4) {
        // Configure audio session FIRST before reading formats
        Self.configureAudioSession()

        // Initialize all stored properties
        mainMixer = engine.mainMixerNode
        inputMixer = AVAudioMixerNode()
        let outputFormat = engine.outputNode.outputFormat(forBus: 0)
        var detectedSampleRate = outputFormat.sampleRate


        // CRITICAL: Handle case where output format is invalid (0Hz)
        if detectedSampleRate <= 0 || detectedSampleRate > 192000 {

            do {
                try engine.start()
                engine.stop()

                let retryFormat = engine.outputNode.outputFormat(forBus: 0)
                detectedSampleRate = retryFormat.sampleRate
            } catch {
            }

            if detectedSampleRate <= 0 || detectedSampleRate > 192000 {
                detectedSampleRate = 48000
            }
        }

        // Ensure we have a valid sample rate for format creation
        let validatedRate = (detectedSampleRate > 0 && detectedSampleRate <= 192000) ? detectedSampleRate : 48000
        sampleRate = validatedRate

        // Create audio formats with validated sample rate
        // AVAudioFormat with standard format and valid rate should always succeed
        processingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
            ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
            ?? AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!


        let limiterDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        limiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)

        engine.attach(limiter)
        engine.attach(inputMixer)

        // CRITICAL: Connect input node to input mixer to force initialization
        inputMixer.outputVolume = 0
        engine.connect(engine.inputNode, to: inputMixer, format: nil)

        let actualTrackCount = Self.USE_SINGLE_TRACK_ONLY ? 1 : trackCount
        setupTracks(count: actualTrackCount)

        if Self.DISABLE_LIMITER {
            engine.connect(mainMixer, to: engine.outputNode, format: stereoFormat)
        } else {
            engine.connect(mainMixer, to: limiter, format: stereoFormat)
            engine.connect(limiter, to: engine.outputNode, format: stereoFormat)
        }

        if Self.USE_SINGLE_TRACK_ONLY {
        }

        setupAudioObservers()
    }

    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            var categorySet = false

            do {
                try session.setCategory(.playAndRecord, mode: .default,
                                       options: [.allowBluetoothA2DP])
                categorySet = true
            } catch {
                try session.setCategory(.playback, mode: .default,
                                       options: [.allowBluetoothA2DP])
                categorySet = true
            }

            guard categorySet else {
                return
            }

            // CRITICAL: Set sample rate BEFORE activation
            try session.setPreferredSampleRate(48000)

            // CRITICAL: Force iPhone built-in microphone at startup
            if session.category == .playAndRecord {
                let availableInputs = session.availableInputs ?? []
                if let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic }) {
                    try session.setPreferredInput(builtInMic)
                } else {
                }
            }

            // Detect Bluetooth
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

            // CHANGED: More aggressive buffer size for Bluetooth to prevent dropouts
            let bufferDuration: TimeInterval
            if isBluetoothAny {
                bufferDuration = 0.100  // CHANGED: 100ms for Bluetooth (was 50ms)
                if isBluetoothInput {
                }
            } else {
                bufferDuration = 0.020  // CHANGED: 20ms for wired (was 10ms)
            }
            try session.setPreferredIOBufferDuration(bufferDuration)

            // Verify what we actually got
            let actualBufferDuration = session.ioBufferDuration
            if abs(actualBufferDuration - bufferDuration) > 0.005 {
            }

            // Activate the session
            try session.setActive(true)

        } catch {
        }
    }
    
    private func setupTracks(count: Int) {
        for _ in 0..<count {
            let bus = TrackBus()
            engine.attach(bus.player)
            engine.attach(bus.eq)
            engine.attach(bus.delay)
            engine.attach(bus.reverb)
            engine.attach(bus.dist)
            engine.attach(bus.mixer)

            engine.connect(bus.player, to: bus.eq, format: processingFormat)
            engine.connect(bus.eq, to: bus.delay, format: processingFormat)
            engine.connect(bus.delay, to: bus.reverb, format: processingFormat)
            engine.connect(bus.reverb, to: bus.dist, format: processingFormat)
            engine.connect(bus.dist, to: bus.mixer, format: processingFormat)

            engine.connect(bus.mixer, to: mainMixer, format: processingFormat)

            trackBuses.append(bus)
        }
    }

    func start() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    func reactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setActive(true)
        } catch {
        }
    }
    
    func stop() {
        engine.stop()
    }

    func diagnoseAudioIssues() {
        // Debug function - no-op in production
    }

    // MARK: - Audio Route Change Handling

    private func setupAudioObservers() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Extract data needed from userInfo to avoid Sendable warning
            guard let userInfo = notification.userInfo,
                  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt else {
                return
            }

            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.handleRouteChangeWithReason(reasonValue)
            }
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                return
            }

            switch type {
            case .began:
                NotificationCenter.default.post(
                    name: NSNotification.Name("AudioInterruptionBegan"),
                    object: nil
                )

            case .ended:
                guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                    return
                }
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("AudioInterruptionEnded"),
                        object: options
                    )
                }

            @unknown default:
                break
            }
        }

    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt else {
            return
        }
        handleRouteChangeWithReason(reasonValue)
    }

    private func handleRouteChangeWithReason(_ reasonValue: UInt) {
        guard let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:

            NotificationCenter.default.post(
                name: NSNotification.Name("AudioDeviceDisconnected"),
                object: nil
            )

        case .newDeviceAvailable:
            break
        case .categoryChange:
            break
        default:
            break
        }
    }

    deinit {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
