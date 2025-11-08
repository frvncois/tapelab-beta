//
//  AudioExtensions.swift
//  tapelab
//
import AVFAudio

public extension AVAudioPCMBuffer {
    /// Returns the peak (absolute max) amplitude value across all channels.
    func peakLevel() -> Float {
        guard let data = floatChannelData else { return 0 }
        let frames = Int(frameLength)
        var peak: Float = 0
        for ch in 0..<Int(format.channelCount) {
            for i in 0..<frames {
                peak = max(peak, abs(data[ch][i]))
            }
        }
        return peak
    }
}
