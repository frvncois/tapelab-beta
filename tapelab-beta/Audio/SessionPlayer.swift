//
//  SessionPlayer.swift
//  tapelab
//

import AVFAudio
import Accelerate
import Foundation
import QuartzCore

@MainActor
public final class SessionPlayer {
    // Debug logging flag - set to false for production
    private nonisolated static let enableDebugLogs = false
    // DEBUG FLAG - Set to true to enable detailed scheduling gap logging
    static let LOG_SCHEDULING_GAPS = false
    
    public weak var engineController: AudioEngineController?

    private var regionBuffers: [[UUID: AVAudioPCMBuffer]] = []

    // CRITICAL: Pre-rendered COMPLETE regions cache (entire region with all effects applied)
    // Key format: "trackIndex-regionID"
    private var preRenderedRegions: [String: AVAudioPCMBuffer] = [:]

    private var session: Session?
    private var timeline: TimelineState?

    private var basePlayerSampleTime: AVAudioFramePosition = 0
    private var baseWallTime: TimeInterval = 0
    private var basePlayhead: TimeInterval = 0

    private var loopObserverTask: Task<Void, Never>?
    private var isPlaying = false

    // Track last scheduled time per track for gap detection
    private var lastScheduledEndTime: [TimeInterval] = [0, 0, 0, 0]

    // Track the furthest point we've scheduled for each track to prevent overlaps
    private var maxScheduledTime: [TimeInterval] = [0, 0, 0, 0]

    // Track last scheduled player sample position per track for contiguous scheduling
    private var lastScheduledPlayerSample: [AVAudioFramePosition] = [0, 0, 0, 0]

    // Track index currently being recorded (nil if no recording in progress)
    // Used to exclude recording track from playback to avoid file access conflicts
    private var recordingTrackIndex: Int?

    public init() {}

    /// Set which track is currently recording (to exclude from playback)
    public func setRecordingTrack(_ trackIndex: Int?) {
        recordingTrackIndex = trackIndex
        if let _ = trackIndex {
        } else {
        }
    }

    public func play(session: Session, timeline: TimelineState) async throws {
        guard let ec = engineController else { return }
        self.session = session
        self.timeline = timeline

        try ec.start()

        // Apply FX
        for (i, track) in session.tracks.enumerated() where i < ec.trackBuses.count {
            ec.trackBuses[i].applyFX(track.fx)
        }

        preloadRegions(session)

        // CRITICAL: Pre-render ENTIRE regions with all effects applied
        // This eliminates real-time processing during playback
        let renderStart = CACurrentMediaTime()
        await preRenderAllRegions(session: session, sampleRate: ec.sampleRate)
        let _ = CACurrentMediaTime() - renderStart

        // Diagnostic: Check audio engine and output state BEFORE reset
        if let _ = ec.engine.outputNode.engine {
        }

        // Start players & anchor clock
        // CRITICAL: NEVER call .reset() - it breaks Bluetooth A2DP audio routing on iOS
        // Simply stop/play is sufficient to reschedule new buffers
        for (_, bus) in ec.trackBuses.enumerated() {
            bus.player.stop()
            bus.player.play()
        }

        // Diagnostic: Check audio engine and output state AFTER reset
        if let _ = ec.engine.outputNode.engine {
        }

        // Verify all connections are still valid
        for (_, bus) in ec.trackBuses.enumerated() {
            if let _ = bus.player.engine {
            } else {
            }
            // Check volume levels
        }

        // Check main mixer and output routing

        // Give the player a moment to stabilize before getting render time
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        if let nodeTime = ec.trackBuses.first?.player.lastRenderTime,
           let playerTime = ec.trackBuses.first?.player.playerTime(forNodeTime: nodeTime) {
            basePlayerSampleTime = playerTime.sampleTime
        } else {
            basePlayerSampleTime = 0
        }
        baseWallTime = CACurrentMediaTime()
        basePlayhead = timeline.playhead

        // Reset scheduling tracking for new playback session
        maxScheduledTime = [0, 0, 0, 0]
        lastScheduledEndTime = [0, 0, 0, 0]
        lastScheduledPlayerSample = [0, 0, 0, 0]

        isPlaying = true
        scheduleWindow()

        timeline.startTimeline(session: session)

        loopObserverTask?.cancel()
        loopObserverTask = Task { [weak self] in
            guard let self else { return }
            var lastScheduleTime = CACurrentMediaTime()
            var schedulingInProgress = false

            while self.isPlaying {
                try? await Task.sleep(nanoseconds: 20_000_000)
                guard let tl = self.timeline else { continue }

                // Loop mode detection
                if tl.isLoopMode, tl.playhead >= tl.loopEnd - 0.002 {
                    if SessionPlayer.enableDebugLogs {
                    }
                    self.resetClockForNextLoopPass()
                    // CRITICAL: Offload to detached task to avoid blocking this loop
                    if !schedulingInProgress {
                        schedulingInProgress = true
                        Task.detached(priority: .userInitiated) { [weak self] in
                            await self?.scheduleWindow()
                            await MainActor.run { schedulingInProgress = false }
                        }
                    }
                    lastScheduleTime = CACurrentMediaTime()
                }

                // Periodic scheduling: reschedule buffers every 1.0s for better gap coverage
                // CRITICAL: Use detached task to prevent blocking the recording tap
                // Reduced frequency from 0.3s to 1.0s to reduce CPU load
                let now = CACurrentMediaTime()
                if now - lastScheduleTime >= 1.0 {
                    // Only schedule if not already in progress (skip if previous call is still running)
                    if !schedulingInProgress {
                        schedulingInProgress = true
                        let scheduleStartTime = CACurrentMediaTime()
                        Task.detached(priority: .userInitiated) { [weak self] in
                            await self?.scheduleWindow()
                            let scheduleEndTime = CACurrentMediaTime()
                            let scheduleDuration = scheduleEndTime - scheduleStartTime
                            // Log if scheduling takes longer than expected
                            if SessionPlayer.enableDebugLogs && scheduleDuration > 0.05 {
                            }
                            await MainActor.run { schedulingInProgress = false }
                        }
                        lastScheduleTime = now
                    } else {
                        if SessionPlayer.enableDebugLogs {
                        }
                    }
                }
            }
        }
    }

    public func stop() {
        isPlaying = false
        loopObserverTask?.cancel()
        loopObserverTask = nil
        engineController?.trackBuses.forEach { $0.player.stop() }

        // Reset scheduling tracking
        maxScheduledTime = [0, 0, 0, 0]
        lastScheduledEndTime = [0, 0, 0, 0]
        lastScheduledPlayerSample = [0, 0, 0, 0]

        // Clear buffer caches to free memory
        regionBuffers.removeAll()
        preRenderedRegions.removeAll()

        timeline?.stopTimeline()
    }

    /// Get the audio buffer for a specific region (for waveform visualization)
    /// - Parameters:
    ///   - trackIndex: Index of the track (0-based)
    ///   - regionID: UUID of the region
    ///   - session: The session containing the region
    /// - Returns: The audio buffer if available, nil otherwise
    public func getRegionBuffer(trackIndex: Int, regionID: UUID, session: Session) -> AVAudioPCMBuffer? {
        // Initialize regionBuffers if empty
        if regionBuffers.isEmpty {
            regionBuffers = Array(repeating: [:], count: session.tracks.count)
        }

        guard trackIndex >= 0 && trackIndex < regionBuffers.count else {
            return nil
        }

        // Check if buffer is already loaded
        if let buffer = regionBuffers[trackIndex][regionID] {
            return buffer
        }

        // Buffer not loaded - load it on-demand for waveform display
        guard trackIndex < session.tracks.count else {
            return nil
        }

        // Find the region
        guard let region = session.tracks[trackIndex].regions.first(where: { $0.id.id == regionID }) else {
            return nil
        }


        do {
            let file = try AVAudioFile(forReading: region.sourceURL)

            // Read entire file (not just the region portion) for full waveform
            let totalFrames = AVAudioFrameCount(file.length)
            guard totalFrames > 0 else {
                return nil
            }

            let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: totalFrames)!
            try file.read(into: buf, frameCount: totalFrames)
            buf.frameLength = totalFrames

            // Convert to mono if needed
            if let mono = convertToMonoIfNeeded(buffer: buf, targetSampleRate: engineController?.sampleRate ?? 48000) {
                // Cache it for future use
                regionBuffers[trackIndex][regionID] = mono
                return mono
            } else {
                return nil
            }
        } catch {
            return nil
        }
    }

    // MARK: - Pre-rendering

    /// Pre-render ENTIRE regions with all effects applied
    /// This is much simpler than chunking and eliminates all complexity
    private func preRenderAllRegions(session: Session, sampleRate: Double) async {
        preRenderedRegions.removeAll()

        for (tIndex, track) in session.tracks.enumerated() {
            // Skip recording track
            if let recordingIdx = recordingTrackIndex, tIndex == recordingIdx {
                continue
            }

            for region in track.regions {
                // Get source buffer (already loaded in preloadRegions)
                guard let sourceBuffer = regionBuffers[tIndex][region.id.id] else {
                    continue
                }

                // Render the ENTIRE region with all effects applied at once
                // No chunks, no complexity, just the whole thing
                // NOTE: sourceBuffer already has fileStartOffset applied from preloadRegions,
                // so we pass offsetSeconds: 0 here to avoid double-skipping
                if let renderedRegion = makeSegment(
                    from: sourceBuffer,
                    sampleRate: sampleRate,
                    offsetSeconds: 0,  // Already applied in preloadRegions
                    durationSeconds: region.duration,
                    reversed: region.reversed,
                    fadeIn: region.fadeIn ?? 0,
                    fadeOut: region.fadeOut ?? 0,
                    gainDB: region.gainDB ?? 0
                ) {
                    // Cache the entire pre-rendered region with simple key
                    let key = "\(tIndex)-\(region.id.id)"
                    preRenderedRegions[key] = renderedRegion

                    if tIndex == 0 || tIndex == 1 { // Only log first two tracks to reduce spam
                    }
                }
            }
        }
    }

    // MARK: - Scheduling
    private func scheduleWindow() {
        guard let ec = engineController, let session, let tl = timeline else {
            return
        }
        let sr = ec.sampleRate

        // CRITICAL FIX: Only schedule a lookahead window to prevent overlaps
        // Previously scheduled entire session (up to 6 minutes!) causing massive overlaps
        // 20 seconds provides safe buffer - with 1.0s scheduling interval, this gives
        // 19s of buffered audio to prevent starvation (increased from 12s to reduce scheduling frequency)
        let lookaheadDuration: TimeInterval = 20.0  // Schedule 20 seconds ahead (was 12.0)

        let windowStart: TimeInterval
        let windowEnd: TimeInterval

        if tl.isLoopMode {
            // In loop mode, schedule the entire loop region
            windowStart = tl.loopStart
            windowEnd = tl.loopEnd
        } else {
            // In normal mode, only schedule lookahead window from current playhead
            windowStart = tl.playhead
            windowEnd = min(tl.playhead + lookaheadDuration, session.maxDuration)
        }


        let scheduleLead: TimeInterval = 0.08
        let anchorNow = CACurrentMediaTime()
        let elapsed   = anchorNow - baseWallTime
        let playerSampleNow = basePlayerSampleTime + AVAudioFramePosition(elapsed * sr)

        for (tIndex, track) in session.tracks.enumerated() where tIndex < ec.trackBuses.count {
            // Skip scheduling the track that's currently being recorded
            if let recordingIdx = recordingTrackIndex, tIndex == recordingIdx {
                continue
            }

            let bus = ec.trackBuses[tIndex]


            for region in track.regions {
                let rStart = region.startTime
                let rEnd   = region.startTime + region.duration
                if rEnd <= windowStart || rStart >= windowEnd {
                    continue
                }

                // CRITICAL: Skip if this segment has already been scheduled
                // This prevents overlaps when scheduleWindow() is called repeatedly
                let maxScheduled = maxScheduledTime[tIndex]
                if rEnd <= maxScheduled {
                    continue
                }

                // If region partially scheduled, only schedule the unscheduled portion
                let effectiveStart = max(rStart, maxScheduled)

                let segStart = max(effectiveStart, windowStart)
                let segEnd   = min(rEnd,   windowEnd)
                let segDur   = max(0, segEnd - segStart)
                guard segDur > 0 else {
                    continue
                }

                // Calculate offset into the pre-rendered region
                let offsetIntoRegion = segStart - rStart
                

                // Get the pre-rendered ENTIRE region (already has all effects applied)
                let regionKey = "\(tIndex)-\(region.id.id)"
                guard let preRenderedRegion = preRenderedRegions[regionKey] else {
                    continue
                }

                // Extract the specific portion we need from the pre-rendered region
                let frameOffset = Int(offsetIntoRegion * sr)
                let frameCount = Int(segDur * sr)
                
                guard let slice = extractFrames(from: preRenderedRegion, offset: frameOffset, count: frameCount) else {
                    continue
                }
                

                // CRITICAL FIX: Use contiguous scheduling to eliminate gaps between buffers
                // If we've already scheduled a buffer on this track in this window,
                // schedule the next buffer immediately after the previous one
                let scheduleAtPlayerSamples: AVAudioFramePosition
                if lastScheduledPlayerSample[tIndex] > 0 {
                    // Schedule immediately after the previous buffer
                    scheduleAtPlayerSamples = lastScheduledPlayerSample[tIndex]
                } else {
                    // First buffer in this window - use calculated time with lead
                    let deltaFromPlayhead = segStart - tl.playhead
                    scheduleAtPlayerSamples = playerSampleNow
                        + AVAudioFramePosition((scheduleLead + deltaFromPlayhead) * sr)
                }

                let atTime = AVAudioTime(sampleTime: scheduleAtPlayerSamples, atRate: sr)

                // Check buffer audio level before scheduling
                let _ = slice.peakLevel()

                // The buffer format must match the player's input connection format (mono processingFormat)
                // The audio graph handles mono->stereo conversion at the mixer nodes automatically
                bus.player.scheduleBuffer(slice, at: atTime, options: [])

                // Update last scheduled player sample for contiguous scheduling
                lastScheduledPlayerSample[tIndex] = scheduleAtPlayerSamples + AVAudioFramePosition(slice.frameLength)

                // Update max scheduled time for this track to prevent future overlaps
                maxScheduledTime[tIndex] = max(maxScheduledTime[tIndex], segEnd)

                // Gap detection logging
                if Self.LOG_SCHEDULING_GAPS {
                    let previousEnd = lastScheduledEndTime[tIndex]
                    if previousEnd > 0 {
                        let gap = segStart - previousEnd
                        if abs(gap) > 0.001 { // More than 1ms difference
                            if gap > 0 {
                            } else {
                            }
                        }
                    }
                    lastScheduledEndTime[tIndex] = segEnd
                }
            }
        }
    }

    private func resetClockForNextLoopPass() {
        guard let ec = engineController, let tl = timeline else { return }
        let sr = ec.sampleRate
        basePlayhead = tl.loopStart
        baseWallTime = CACurrentMediaTime()
        if let nodeTime = ec.trackBuses.first?.player.lastRenderTime,
           let playerTime = ec.trackBuses.first?.player.playerTime(forNodeTime: nodeTime) {
            basePlayerSampleTime = playerTime.sampleTime + AVAudioFramePosition(0.02 * sr)
        } else {
            basePlayerSampleTime += AVAudioFramePosition((tl.loopEnd - tl.loopStart) * sr)
        }

        // Reset scheduling tracking for loop (allow rescheduling of loop region)
        maxScheduledTime = [tl.loopStart, tl.loopStart, tl.loopStart, tl.loopStart]
        lastScheduledEndTime = [tl.loopStart, tl.loopStart, tl.loopStart, tl.loopStart]
        lastScheduledPlayerSample = [0, 0, 0, 0]

        // Update timeline's playhead to loop start
        tl.seek(to: tl.loopStart)
    }

    // MARK: - Preload
    private func preloadRegions(_ session: Session) {
        guard let ec = engineController else { return }
        regionBuffers = Array(repeating: [:], count: session.tracks.count)

        for (i, track) in session.tracks.enumerated() {
            // Skip preloading the track that's currently being recorded
            if let recordingIdx = recordingTrackIndex, i == recordingIdx {
                continue
            }
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
                    if let mono = convertToMonoIfNeeded(buffer: buf, targetSampleRate: ec.sampleRate) {
                        regionBuffers[i][region.id.id] = mono
                    } else {
                        print("⚠️ SessionPlayer: Failed to convert buffer to mono for region \(region.id.id)")
                    }
                } catch {
                    print("⚠️ SessionPlayer: Failed to load region \(region.id.id): \(error)")
                }
            }
        }
    }

    // MARK: - Buffer utilities

    /// Extract a specific range of frames from a pre-rendered buffer
    private func extractFrames(from source: AVAudioPCMBuffer, offset: Int, count: Int) -> AVAudioPCMBuffer? {
        // Clamp to valid range
        let actualOffset = max(0, min(offset, Int(source.frameLength)))
        let maxCount = Int(source.frameLength) - actualOffset
        let actualCount = max(0, min(count, maxCount))

        guard actualCount > 0 else { return nil }

        // Create output buffer
        guard let out = AVAudioPCMBuffer(pcmFormat: source.format,
                                         frameCapacity: AVAudioFrameCount(actualCount)) else { return nil }
        out.frameLength = AVAudioFrameCount(actualCount)

        guard let src = source.floatChannelData?.pointee,
              let dst = out.floatChannelData?.pointee
        else { return nil }

        // Simple copy - no processing needed since it's already pre-rendered
        src.advanced(by: actualOffset).withMemoryRebound(to: Float.self, capacity: actualCount) { srcPtr in
            dst.update(from: srcPtr, count: actualCount)
        }

        return out
    }

    private func makeSegment(
        from source: AVAudioPCMBuffer,
        sampleRate sr: Double,
        offsetSeconds: TimeInterval,
        durationSeconds: TimeInterval,
        reversed: Bool,
        fadeIn: TimeInterval,
        fadeOut: TimeInterval,
        gainDB: Double
    ) -> AVAudioPCMBuffer? {
        let start = max(0, Int(offsetSeconds * sr))
        let frames = max(0, Int(durationSeconds * sr))
        guard frames > 0, start < source.frameLength else { return nil }
        let clampedFrames = min(frames, Int(source.frameLength) - start)
        guard clampedFrames > 0 else { return nil }

        guard let out = AVAudioPCMBuffer(pcmFormat: source.format,
                                         frameCapacity: AVAudioFrameCount(clampedFrames)) else { return nil }
        out.frameLength = AVAudioFrameCount(clampedFrames)

        guard
            let s = source.floatChannelData?.pointee,
            let d = out.floatChannelData?.pointee
        else { return nil }

        // Copy window
        s.advanced(by: start).withMemoryRebound(to: Float.self, capacity: clampedFrames) { src in
            d.update(from: src, count: clampedFrames)
        }

        if reversed { reverseInPlace(d, count: clampedFrames) }

        if gainDB != 0 {
            let g = powf(10, Float(gainDB) / 20)
            vDSP_vsmul(d, 1, [g], d, 1, vDSP_Length(clampedFrames))
        }

        if fadeIn > 0 || fadeOut > 0 {
            applyFades(samples: d,
                       totalFrames: clampedFrames,
                       sampleRate: sr,
                       fadeInSec: fadeIn,
                       fadeOutSec: fadeOut)
        }
        return out
    }

    private func reverseInPlace(_ ptr: UnsafeMutablePointer<Float>, count: Int) {
        var i = 0, j = count - 1
        while i < j {
            let tmp = ptr[i]; ptr[i] = ptr[j]; ptr[j] = tmp
            i += 1; j -= 1
        }
    }

    private func applyFades(samples: UnsafeMutablePointer<Float>,
                            totalFrames: Int,
                            sampleRate sr: Double,
                            fadeInSec: TimeInterval,
                            fadeOutSec: TimeInterval) {
        let fi = min(totalFrames, Int(max(0, fadeInSec) * sr))
        let fo = min(totalFrames, Int(max(0, fadeOutSec) * sr))
        if fi > 0 {
            for i in 0..<fi {
                let t = Float(i) / Float(max(1, fi)); samples[i] *= t
            }
        }
        if fo > 0 {
            for i in 0..<fo {
                let t = 1.0 - Float(i) / Float(max(1, fo))
                samples[totalFrames - 1 - i] *= t
            }
        }
    }

    private func convertToMonoIfNeeded(buffer: AVAudioPCMBuffer, targetSampleRate: Double) -> AVAudioPCMBuffer? {
        if buffer.format.channelCount == 1 && buffer.format.sampleRate == targetSampleRate { return buffer }
        guard let monoFmt = AVAudioFormat(standardFormatWithSampleRate: targetSampleRate, channels: 1),
              let out = AVAudioPCMBuffer(pcmFormat: monoFmt, frameCapacity: buffer.frameLength) else {
            return nil
        }
        out.frameLength = buffer.frameLength
        let frames = Int(buffer.frameLength)
        guard let dst = out.floatChannelData?.pointee else { return nil }
        if let src0 = buffer.floatChannelData?.pointee {
            if buffer.format.channelCount == 1 {
                dst.update(from: src0, count: frames)
            } else if buffer.format.channelCount >= 2,
                      let src1 = buffer.floatChannelData?.advanced(by: 1).pointee {
                for i in 0..<frames { dst[i] = 0.5 * (src0[i] + src1[i]) }
            }
        } else {
            return nil
        }
        return out
    }

    /// Convert mono buffer to stereo (duplicate mono signal to both L/R channels)
    private func convertMonoToStereo(_ monoBuffer: AVAudioPCMBuffer, sampleRate: Double) -> AVAudioPCMBuffer? {
        guard monoBuffer.format.channelCount == 1 else {
            // Already stereo or multichannel
            return monoBuffer
        }

        guard let stereoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let stereoBuffer = AVAudioPCMBuffer(pcmFormat: stereoFormat, frameCapacity: monoBuffer.frameLength) else {
            return nil
        }

        stereoBuffer.frameLength = monoBuffer.frameLength
        let frameCount = Int(monoBuffer.frameLength)

        guard let monoData = monoBuffer.floatChannelData?.pointee,
              let leftData = stereoBuffer.floatChannelData?.pointee,
              let rightData = stereoBuffer.floatChannelData?.advanced(by: 1).pointee else {
            return nil
        }

        // Copy mono to both L and R channels
        leftData.update(from: monoData, count: frameCount)
        rightData.update(from: monoData, count: frameCount)

        return stereoBuffer
    }
}
