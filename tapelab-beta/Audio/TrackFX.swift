//
//  TrackFX.swift
//  tapelab
//  Single source of truth for FX models
//
import Foundation

// MARK: - EQ Band
public struct EQBand: Codable, Hashable {
    public var frequency: Double   // Hz
    public var gainDB: Double      // dB
    public var q: Double           // Q factor
    public init(frequency: Double, gainDB: Double = 0.0, q: Double = 1.0) {
        self.frequency = frequency
        self.gainDB = gainDB
        self.q = q
    }
}

// MARK: - Reverb FX
public struct ReverbFX: Codable, Hashable {
    public var wetMix: Float       // 0–100
    public var roomSize: Bool      // true = large hall (always use large hall)
    public var preDelay: Double    // seconds
    public static let neutral = ReverbFX(wetMix: 0, roomSize: true, preDelay: 0)
}

// MARK: - Delay FX
public struct DelayFX: Codable, Hashable {
    public var wetMix: Float       // 0–100
    public var time: TimeInterval  // seconds
    public var feedback: Float     // 0–100
    public var lowPassCutoff: Float // Hz
    public static let neutral = DelayFX(wetMix: 0, time: 0.3, feedback: 0, lowPassCutoff: 18000)
}

// MARK: - Saturation FX
public struct SaturationFX: Codable, Hashable {
    public var wetMix: Float       // 0–100
    public var preGain: Float      // -40 … +40 dB
    public static let neutral = SaturationFX(wetMix: 0, preGain: 0)
}

// MARK: - Track FX Container
public struct TrackFX: Codable, Hashable {
    // Base mix controls
    public var volumeDB: Double = 0.0     // overall gain
    public var pan: Float = 0.0           // -1.0 (L) to 1.0 (R)

    // EQ
    public var eqBands: [EQBand] = [
        EQBand(frequency: 100),
        EQBand(frequency: 500),
        EQBand(frequency: 2000),
        EQBand(frequency: 8000)
    ]

    // Effects
    public var reverb: ReverbFX = .neutral
    public var delay: DelayFX = .neutral
    public var saturation: SaturationFX = .neutral

    public init(volumeDB: Double = 0.0,
                pan: Float = 0.0,
                eqBands: [EQBand] = [
                    EQBand(frequency: 100),
                    EQBand(frequency: 500),
                    EQBand(frequency: 2000),
                    EQBand(frequency: 8000)
                ],
                reverb: ReverbFX = .neutral,
                delay: DelayFX = .neutral,
                saturation: SaturationFX = .neutral) {
        self.volumeDB = volumeDB
        self.pan = pan
        self.eqBands = eqBands
        self.reverb = reverb
        self.delay = delay
        self.saturation = saturation
    }

    // MARK: - Helper Methods

    /// Check if FX parameters (reverb, delay, saturation) are modified from defaults
    public func hasFXModified() -> Bool {
        return reverb.wetMix > 0 || delay.wetMix > 0 || saturation.wetMix > 0
    }

    /// Check if volume/EQ parameters are modified from defaults
    public func hasVolumeModified() -> Bool {
        // Check volume and pan
        let volumeChanged = abs(volumeDB) > 0.01
        let panChanged = abs(pan) > 0.01

        // Check if any EQ band has non-zero gain
        let eqChanged = eqBands.contains { abs($0.gainDB) > 0.01 }

        return volumeChanged || panChanged || eqChanged
    }

    /// Reset FX to defaults (reverb, delay, saturation)
    public mutating func resetFX() {
        reverb = .neutral
        delay = .neutral
        saturation = .neutral
    }

    /// Reset volume and EQ to defaults
    public mutating func resetVolume() {
        volumeDB = 0.0
        pan = 0.0
        eqBands = [
            EQBand(frequency: 100),
            EQBand(frequency: 500),
            EQBand(frequency: 2000),
            EQBand(frequency: 8000)
        ]
    }
}
