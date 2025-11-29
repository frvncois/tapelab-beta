//
//  WaveformGenerator.swift
//  tapelab-beta
//
//  Created by Claude Code
//

import Foundation
import AVFAudio
import Accelerate

public struct WaveformGenerator {
    // Debug logging flag - set to false for production
    private nonisolated static let enableDebugLogs = false

    /// Generate waveform data from an audio buffer using RMS downsampling
    /// - Parameters:
    ///   - buffer: Audio buffer to analyze (mono Float32 PCM)
    ///   - targetPoints: Number of data points to generate (default 500)
    /// - Returns: Array of normalized amplitude values (0.0-1.0)
    public nonisolated static func generateWaveformData(from buffer: AVAudioPCMBuffer, targetPoints: Int = 500) -> [Float] {
        guard let floatData = buffer.floatChannelData else {
            if WaveformGenerator.enableDebugLogs {
            }
            return []
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            if WaveformGenerator.enableDebugLogs {
            }
            return []
        }

        // Access first channel (mono audio)
        let _ = UnsafeBufferPointer(start: floatData[0], count: frameCount)

        // Calculate samples per point
        let samplesPerPoint = max(1, frameCount / targetPoints)
        let actualPoints = frameCount / samplesPerPoint

        var waveformData: [Float] = []
        waveformData.reserveCapacity(actualPoints)

        // Process each segment using RMS (root mean square) for better visual representation
        for i in 0..<actualPoints {
            let startIndex = i * samplesPerPoint
            let endIndex = min(startIndex + samplesPerPoint, frameCount)
            let segmentLength = endIndex - startIndex

            guard segmentLength > 0 else { continue }

            // Get pointer to segment
            let segmentPointer = floatData[0].advanced(by: startIndex)

            // Calculate RMS using vDSP for efficiency
            var rms: Float = 0.0
            vDSP_rmsqv(segmentPointer, 1, &rms, vDSP_Length(segmentLength))

            // Normalize: typical speech/music peaks around 0.3-0.7 RMS
            // Apply slight compression for better visual appearance
            let normalized = min(1.0, rms * 1.5)

            waveformData.append(normalized)
        }

        // If we got no data, return empty array
        if waveformData.isEmpty {
            if WaveformGenerator.enableDebugLogs {
            }
            return []
        }

        if WaveformGenerator.enableDebugLogs {
        }

        return waveformData
    }

    /// Generate waveform data using peak detection (alternative method)
    /// - Parameters:
    ///   - buffer: Audio buffer to analyze (mono Float32 PCM)
    ///   - targetPoints: Number of data points to generate
    /// - Returns: Array of normalized amplitude values (0.0-1.0)
    public nonisolated static func generateWaveformDataWithPeaks(from buffer: AVAudioPCMBuffer, targetPoints: Int = 500) -> [Float] {
        guard let floatData = buffer.floatChannelData else {
            return []
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return [] }

        let _ = UnsafeBufferPointer(start: floatData[0], count: frameCount)
        let samplesPerPoint = max(1, frameCount / targetPoints)
        let actualPoints = frameCount / samplesPerPoint

        var waveformData: [Float] = []
        waveformData.reserveCapacity(actualPoints)

        // Process each segment using peak detection
        for i in 0..<actualPoints {
            let startIndex = i * samplesPerPoint
            let endIndex = min(startIndex + samplesPerPoint, frameCount)
            let segmentLength = endIndex - startIndex

            guard segmentLength > 0 else { continue }

            // Find peak amplitude in segment
            var peak: Float = 0.0

            let segmentPointer = floatData[0].advanced(by: startIndex)
            vDSP_maxmgv(segmentPointer, 1, &peak, vDSP_Length(segmentLength))

            // Normalize
            let normalized = min(1.0, peak * 1.2)
            waveformData.append(normalized)
        }

        return waveformData
    }
}
