//
//  Metronome.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import Foundation
import AVFAudio
import Combine
import Accelerate

@MainActor
public final class Metronome: ObservableObject {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let mainMixer: AVAudioMixerNode

    @Published var isPlaying: Bool = false
    @Published var bpm: Double = 120.0 {
        didSet {
            if isPlaying {
                // Restart with new BPM if already playing
                stop()
                Task { await play() }
            }
        }
    }
    @Published var timeSignature: TimeSignature = .fourFour {
        didSet {
            if isPlaying {
                // Restart with new time signature if already playing
                stop()
                Task { await play() }
            }
        }
    }

    private var clickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private let sampleRate: Double = 48000.0
    private var currentBeat: Int = 0
    private var timer: Timer?

    init() {
        mainMixer = engine.mainMixerNode

        // DON'T configure audio session - use the main app's session configuration
        // The main AudioEngineController already configured it for playAndRecord

        // Set up audio graph
        setupAudioGraph()

        // Generate click sounds
        generateClickSounds()

        print("🥁 Metronome initialized")
    }

    deinit {
        // Note: Engine cleanup is automatic
    }

    // MARK: - Audio Session Configuration

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("🎧 Metronome audio session configured")
        } catch {
            print("⚠️ Failed to configure metronome audio session: \(error)")
        }
    }

    // MARK: - Audio Graph Setup

    private func setupAudioGraph() {
        // Attach player node
        engine.attach(player)

        // Create stereo format
        let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!

        // Connect player -> main mixer -> output
        engine.connect(player, to: mainMixer, format: stereoFormat)
        engine.connect(mainMixer, to: engine.outputNode, format: stereoFormat)

        // Prepare and start engine
        engine.prepare()
        do {
            try engine.start()
            print("🥁 Metronome engine started")
        } catch {
            print("⚠️ Failed to start metronome engine: \(error)")
        }
    }

    // MARK: - Click Sound Generation

    private func generateClickSounds() {
        // Generate accent click (downbeat - higher pitch, 1000Hz)
        accentBuffer = generateClick(frequency: 1000, duration: 0.05)

        // Generate regular click (800Hz)
        clickBuffer = generateClick(frequency: 800, duration: 0.05)

        print("🥁 Click sounds generated")
    }

    private func generateClick(frequency: Double, duration: TimeInterval) -> AVAudioPCMBuffer? {
        let stereoFormat = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 2
        )!

        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        guard let leftChannel = buffer.floatChannelData?[0],
              let rightChannel = buffer.floatChannelData?[1] else {
            return nil
        }

        // Generate sine wave with envelope
        for frame in 0..<Int(frameCount) {
            let phase = 2.0 * Double.pi * frequency * Double(frame) / sampleRate
            let envelope = 1.0 - (Double(frame) / Double(frameCount)) // Linear decay
            let sample = Float(sin(phase) * envelope * 0.5) // 0.5 to avoid clipping

            leftChannel[frame] = sample
            rightChannel[frame] = sample
        }

        return buffer
    }

    // MARK: - Playback Control

    func play() async {
        guard !isPlaying else { return }

        isPlaying = true
        currentBeat = 0

        // Start player node
        player.play()

        // Schedule first click immediately
        scheduleClick()

        // Calculate interval in seconds
        let interval = 60.0 / bpm

        // Schedule repeating timer for subsequent clicks
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleClick()
            }
        }

        print("🥁 Metronome playing at \(Int(bpm)) BPM")
    }

    func stop() {
        guard isPlaying else { return }

        isPlaying = false
        currentBeat = 0

        // Stop timer
        timer?.invalidate()
        timer = nil

        // Stop player
        player.stop()

        print("🥁 Metronome stopped")
    }

    private func scheduleClick() {
        // Use accent on beat 1 (downbeat), regular click on other beats
        // The downbeat occurs when currentBeat % beatsPerMeasure == 0
        let beatsPerMeasure = timeSignature.beatsPerMeasure
        let buffer = (currentBeat % beatsPerMeasure == 0) ? accentBuffer : clickBuffer

        guard let buffer = buffer else { return }

        // Schedule buffer for immediate playback
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)

        // Increment beat counter
        currentBeat += 1
    }

    // MARK: - BPM Tap Tempo

    private var tapTimes: [Date] = []
    private let maxTapInterval: TimeInterval = 2.0 // Reset if more than 2 seconds between taps

    func tap() {
        let now = Date()

        // Remove old taps (more than maxTapInterval old)
        tapTimes = tapTimes.filter { now.timeIntervalSince($0) < maxTapInterval }

        // Add new tap
        tapTimes.append(now)

        // Need at least 2 taps to calculate BPM
        guard tapTimes.count >= 2 else { return }

        // Calculate average interval between taps
        var totalInterval: TimeInterval = 0
        for i in 1..<tapTimes.count {
            totalInterval += tapTimes[i].timeIntervalSince(tapTimes[i-1])
        }
        let avgInterval = totalInterval / Double(tapTimes.count - 1)

        // Convert to BPM (60 seconds / interval = beats per minute)
        let newBPM = 60.0 / avgInterval

        // Clamp to reasonable range (40-240 BPM)
        bpm = max(40, min(240, newBPM))

        print("🥁 Tap tempo: \(Int(bpm)) BPM (from \(tapTimes.count) taps)")
    }

    func resetTaps() {
        tapTimes.removeAll()
        print("🥁 Tap tempo reset")
    }
}
