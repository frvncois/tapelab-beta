//
//  SessionModels.swift
//  tapelab
//
import Foundation
import Combine
import QuartzCore

// Debug logging flag - set to false for production
private let enableDebugLogs = false

// MARK: - RegionID
public struct RegionID: Codable, Hashable, Identifiable {
    public let id: UUID
    public init(_ id: UUID = UUID()) { self.id = id }
}

// MARK: - Region
public struct Region: Codable, Hashable, Identifiable {
    public let id: RegionID
    public var sourceURL: URL
    public var startTime: TimeInterval       // timeline position (s)
    public var duration: TimeInterval        // visible length (s)
    public var fileStartOffset: TimeInterval // start offset inside source file (s)
    public var fileDuration: TimeInterval?   // full source length (s)
    public var reversed: Bool                // reversed playback
    public var fadeIn: TimeInterval?         // seconds
    public var fadeOut: TimeInterval?        // seconds
    public var gainDB: Double?               // dB gain adjustment
    
    public init(id: RegionID = RegionID(),
                sourceURL: URL,
                startTime: TimeInterval,
                duration: TimeInterval,
                fileStartOffset: TimeInterval,
                fileDuration: TimeInterval? = nil,
                reversed: Bool = false,
                fadeIn: TimeInterval? = nil,
                fadeOut: TimeInterval? = nil,
                gainDB: Double? = nil) {
        self.id = id
        self.sourceURL = sourceURL
        self.startTime = startTime
        self.duration = duration
        self.fileStartOffset = fileStartOffset
        self.fileDuration = fileDuration
        self.reversed = reversed
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.gainDB = gainDB
    }
}

// MARK: - Track (depends on TrackFX from TrackFX.swift)
public struct Track: Codable, Hashable, Identifiable {
    public let id: UUID
    public var number: Int
    public var regions: [Region]
    public var fx: TrackFX
    public var isArmed: Bool
    
    public init(id: UUID = UUID(),
                number: Int,
                regions: [Region] = [],
                fx: TrackFX = TrackFX(),
                isArmed: Bool = false) {
        self.id = id
        self.number = number
        self.regions = regions
        self.fx = fx
        self.isArmed = isArmed
    }
}

// MARK: - Session
// MARK: - SessionMetadata (lightweight for list view)
public struct SessionMetadata: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var trackCount: Int
    public var totalRegions: Int
    public var duration: TimeInterval  // Total duration of longest track

    public init(id: UUID, name: String, createdAt: Date, trackCount: Int = 4, totalRegions: Int = 0, duration: TimeInterval = 0) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.trackCount = trackCount
        self.totalRegions = totalRegions
        self.duration = duration
    }

    // Create metadata from full session
    public init(from session: Session) {
        self.id = session.id
        self.name = session.name
        self.createdAt = session.createdAt
        self.trackCount = session.tracks.count
        self.totalRegions = session.tracks.reduce(0) { $0 + $1.regions.count }
        self.duration = session.tracks.map { track in
            track.regions.map { $0.startTime + $0.duration }.max() ?? 0
        }.max() ?? 0
    }
}

public struct Session: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var tracks: [Track]

    // Non-codable constant - not stored in JSON
    public let maxDuration: TimeInterval = 6 * 60 // 6 minutes cap

    // Exclude maxDuration from encoding/decoding
    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, tracks
    }

    public init(id: UUID = UUID(),
                name: String,
                createdAt: Date = Date(),
                tracks: [Track] = (1...4).map { Track(number: $0, isArmed: $0 == 1) }) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.tracks = tracks
    }
}

// MARK: - TimelineState (runtime UI/controller state)
@MainActor
public final class TimelineState: ObservableObject {
    @Published public var playhead: TimeInterval = 0
    @Published public var isPlaying: Bool = false
    @Published public var isRecording: Bool = false
    @Published public var currentRegionID: RegionID? = nil
    @Published public var session: Session? = nil

    @Published public var isLoopMode: Bool = false
    @Published public var loopStart: TimeInterval = 0
    @Published public var loopEnd: TimeInterval = 10.0  // Default 10 second loop
    public let gridStep: TimeInterval = 0.25

    // Region selection state for edit mode
    @Published public var selectedRegion: (trackIndex: Int, regionIndex: Int)? = nil

    // Drag-to-delete state - shows trash icon when dragging region to delete
    @Published public var isDraggingToDelete: Bool = false

    private var displayLink: CADisplayLink?
    private var lastUpdateTime: TimeInterval = 0
    private var playbackStartTime: TimeInterval = 0
    private var playbackStartPlayhead: TimeInterval = 0

    public init() {}

    public func startTimeline(session: Session) {
        self.session = session
        isPlaying = true
        
        // Store initial state
        playbackStartTime = CACurrentMediaTime()
        playbackStartPlayhead = playhead
        lastUpdateTime = playbackStartTime
        
        // Create and configure display link for smooth 60fps updates
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(updatePlayhead))
        displayLink?.add(to: .main, forMode: .common)
        
    }

    public func stopTimeline() {
        displayLink?.invalidate()
        displayLink = nil
        isPlaying = false
    }

    /// Start timeline for recording-only mode (no playback)
    public func startTimelineForRecording() {
        // Start CADisplayLink for playhead updates during recording
        playbackStartTime = CACurrentMediaTime()
        playbackStartPlayhead = playhead
        lastUpdateTime = playbackStartTime

        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(updatePlayhead))
        displayLink?.add(to: .main, forMode: .common)

    }
    
    @objc private func updatePlayhead() {
        // Update playhead during both playback AND recording
        guard isPlaying || isRecording else {
            if enableDebugLogs {
            }
            return
        }

        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - playbackStartTime

        // Calculate new playhead position
        let newPlayhead = playbackStartPlayhead + elapsed

        // Debug: Log first few updates (disabled for performance)
        if enableDebugLogs && (lastUpdateTime == 0 || Int(playhead * 10) != Int(newPlayhead * 10)) {
        }

        playhead = newPlayhead

        // Handle loop mode (only during playback, not recording)
        // NOTE: We do NOT jump the playhead here anymore
        // The SessionPlayer handles audio looping and will update the playhead
        // This prevents the playhead from jumping before audio is rescheduled

        lastUpdateTime = currentTime
    }
    
    /// Seek to a specific position (useful for scrubbing)
    public func seek(to position: TimeInterval) {
        playhead = position
        playbackStartTime = CACurrentMediaTime()
        playbackStartPlayhead = playhead
        // Force SwiftUI to update immediately
        objectWillChange.send()
    }
}
