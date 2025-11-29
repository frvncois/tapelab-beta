//
//  TrackBus.swift
//  tapelab
//

import AVFAudio
import Foundation

/// Represents a single track’s full audio processing chain.
/// Graph: Player → EQ → Delay → Reverb → Distortion → Mixer
public final class TrackBus {
    public let player = AVAudioPlayerNode()
    public let eq = AVAudioUnitEQ(numberOfBands: 2)
    public let delay = AVAudioUnitDelay()
    public let reverb = AVAudioUnitReverb()
    public let dist = AVAudioUnitDistortion()
    public let mixer = AVAudioMixerNode()

    public init() { configureDefaults() }

    private func configureDefaults() {
        // EQ defaults
        for band in eq.bands {
            band.filterType = .parametric
            band.bypass = true
            band.frequency = 1000
            band.gain = 0
            band.bandwidth = 1.0
        }
        // Delay defaults
        delay.wetDryMix = 0
        delay.delayTime = 0.3
        delay.feedback = 0.0
        delay.lowPassCutoff = 18000
        // Reverb defaults - plate sounds more like spring reverb
        reverb.loadFactoryPreset(.plate)
        reverb.wetDryMix = 0
        // Distortion as saturation
        dist.loadFactoryPreset(.multiBrokenSpeaker)
        dist.wetDryMix = 0
        dist.preGain = 0
        // Mixer defaults
        mixer.pan = 0.0
        mixer.outputVolume = 1.0
    }

    /// Reset effects to clear delay/reverb tails
    public func resetEffects() {
        // Reset audio units to clear their internal buffers
        delay.reset()
        reverb.reset()
    }

    /// Apply full FX graph settings from TrackFX
    public func applyFX(_ fx: TrackFX) {
        // Volume / Pan
        let linearGain = pow(10.0, fx.volumeDB / 20.0)
        mixer.outputVolume = Float(linearGain)
        mixer.pan = fx.pan

        // EQ
        for (i, model) in fx.eqBands.enumerated() {
            guard i < eq.bands.count else { break }
            let b = eq.bands[i]
            b.bypass = false
            b.filterType = .parametric
            b.frequency = Float(model.frequency)
            b.gain = Float(model.gainDB)
            b.bandwidth = Float(model.q)
        }
        // Bypass remaining bands
        if fx.eqBands.count < eq.bands.count {
            for j in fx.eqBands.count..<eq.bands.count { eq.bands[j].bypass = true }
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

        // Saturation
        dist.wetDryMix = fx.saturation.wetMix
        dist.preGain = fx.saturation.preGain
    }
}
