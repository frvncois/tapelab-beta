//
//  FileStore.swift
//  tapelab
//
//  Handles local file management for session audio regions
//

import Foundation
import UIKit

public enum FileStore {
    // MARK: - Directory setup

    /// Documents directory - always available on iOS
    private static var documentsURL: URL {
        // FileManager.default.urls always returns at least one URL for .documentDirectory on iOS
        // but we use nil coalescing for defensive coding
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
    }

    /// Base directory in Documents/Tapelab/Sessions
    public static var sessionsBaseURL: URL {
        let base = documentsURL.appendingPathComponent("Tapelab/Sessions", isDirectory: true)
        createDirectoryIfNeeded(at: base)
        return base
    }

    /// Base directory in Documents/Tapelab/Mixes
    public static var mixesBaseURL: URL {
        let base = documentsURL.appendingPathComponent("Tapelab/Mixes", isDirectory: true)
        createDirectoryIfNeeded(at: base)
        return base
    }

    /// Directory for a specific session
    public static func sessionDirectory(for session: Session) -> URL {
        let dir = sessionsBaseURL.appendingPathComponent(session.id.uuidString, isDirectory: true)
        createDirectoryIfNeeded(at: dir)
        return dir
    }

    /// Directory for a specific track within a session
    public static func trackDirectory(session: Session, track: Int) -> URL {
        let dir = sessionDirectory(for: session)
            .appendingPathComponent("Track_\(track + 1)", isDirectory: true)
        createDirectoryIfNeeded(at: dir)
        return dir
    }

    /// Cover image URL for a session
    public static func sessionCoverURL(_ sessionID: UUID) -> URL {
        let sessionDir = sessionsBaseURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        return sessionDir.appendingPathComponent("cover.jpg")
    }

    /// Load cover image for a session if it exists
    public static func loadSessionCover(_ sessionID: UUID) -> UIImage? {
        let coverURL = sessionCoverURL(sessionID)
        guard FileManager.default.fileExists(atPath: coverURL.path),
              let imageData = try? Data(contentsOf: coverURL),
              let image = UIImage(data: imageData) else {
            return nil
        }
        return image
    }

    /// Cover image URL for a mix
    public static func mixCoverURL(_ mixID: UUID) -> URL {
        return mixesBaseURL.appendingPathComponent("\(mixID.uuidString)-cover.jpg")
    }

    /// Load cover image for a mix if it exists
    public static func loadMixCover(_ mixID: UUID) -> UIImage? {
        let coverURL = mixCoverURL(mixID)
        guard FileManager.default.fileExists(atPath: coverURL.path),
              let imageData = try? Data(contentsOf: coverURL),
              let image = UIImage(data: imageData) else {
            return nil
        }
        return image
    }

    /// Save cover image for a mix
    public static func saveMixCover(_ image: UIImage, for mixID: UUID) throws {
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "FileStore", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to convert image to JPEG"
            ])
        }

        let coverURL = mixCoverURL(mixID)
        try jpegData.write(to: coverURL)
    }

    // MARK: - Region File Management

    /// Generates a new unique file URL for a recording region
    public static func newRegionURL(session: Session, track: Int) -> URL {
        let dir = trackDirectory(session: session, track: track)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return dir.appendingPathComponent("region_\(timestamp).caf")
    }

    /// Returns all region URLs for a given session
    public static func allRegionFiles(for session: Session) -> [URL] {
        let dir = sessionDirectory(for: session)
        var urls: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension.lowercased() == "caf" {
                    urls.append(fileURL)
                }
            }
        }
        return urls
    }

    /// Deletes all files for a given session
    public static func clearSessionFiles(for session: Session) {
        let dir = sessionDirectory(for: session)
        try? FileManager.default.removeItem(at: dir)
        createDirectoryIfNeeded(at: dir)
    }

    // MARK: - Session Persistence

    /// Save session metadata and structure (not audio files)
    public static func saveSession(_ session: Session) throws {
        let dir = sessionDirectory(for: session)
        let sessionFile = dir.appendingPathComponent("session.json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(session)
        try data.write(to: sessionFile, options: .atomic)

    }

    /// Load a specific session by ID
    public static func loadSession(_ sessionID: UUID) throws -> Session {
        let sessionDir = sessionsBaseURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        let sessionFile = sessionDir.appendingPathComponent("session.json")

        guard FileManager.default.fileExists(atPath: sessionFile.path) else {
            throw NSError(domain: "FileStore", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Session not found: \(sessionID)"
            ])
        }

        let data = try Data(contentsOf: sessionFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let session = try decoder.decode(Session.self, from: data)
        return session
    }

    /// Load all session metadata (lightweight, for list view)
    public static func loadAllSessionMetadata() throws -> [SessionMetadata] {
        let baseDir = sessionsBaseURL

        guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var metadata: [SessionMetadata] = []

        for sessionDir in sessionDirs {
            let sessionFile = sessionDir.appendingPathComponent("session.json")

            guard FileManager.default.fileExists(atPath: sessionFile.path) else {
                continue
            }

            do {
                let data = try Data(contentsOf: sessionFile)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let session = try decoder.decode(Session.self, from: data)
                metadata.append(SessionMetadata(from: session))
            } catch {
            }
        }

        // Sort by creation date, newest first
        metadata.sort { $0.createdAt > $1.createdAt }

        return metadata
    }

    /// Delete a session and all its files
    public static func deleteSession(_ sessionID: UUID) throws {
        let sessionDir = sessionsBaseURL.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try FileManager.default.removeItem(at: sessionDir)
    }

    // MARK: - Mix Persistence

    /// Generates a new unique file URL for a bounced mix
    static func newMixURL(sessionName: String) -> URL {
        let dir = mixesBaseURL
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let safeName = sessionName.replacingOccurrences(of: "/", with: "-")
        return dir.appendingPathComponent("\(safeName)-\(timestamp).wav")
    }

    /// Save mix metadata
    static func saveMix(_ mix: Mix) throws {
        let metadataFile = mixesBaseURL.appendingPathComponent("\(mix.id.uuidString).json")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(mix)
        try data.write(to: metadataFile, options: .atomic)

    }

    /// Load a specific mix by ID
    static func loadMix(_ mixID: UUID) throws -> Mix {
        let metadataFile = mixesBaseURL.appendingPathComponent("\(mixID.uuidString).json")

        guard FileManager.default.fileExists(atPath: metadataFile.path) else {
            throw NSError(domain: "FileStore", code: 404, userInfo: [
                NSLocalizedDescriptionKey: "Mix not found: \(mixID)"
            ])
        }

        let data = try Data(contentsOf: metadataFile)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let mix = try decoder.decode(Mix.self, from: data)
        return mix
    }

    /// Load all mix metadata (lightweight, for list view)
    static func loadAllMixMetadata() throws -> [MixMetadata] {
        let baseDir = mixesBaseURL

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: baseDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var metadata: [MixMetadata] = []

        for file in files {
            guard file.pathExtension == "json" else { continue }

            do {
                let data = try Data(contentsOf: file)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601

                let mix = try decoder.decode(Mix.self, from: data)
                metadata.append(MixMetadata(from: mix))
            } catch {
            }
        }

        // Sort by creation date, newest first
        metadata.sort { $0.createdAt > $1.createdAt }

        return metadata
    }

    /// Delete a mix and its audio file
    static func deleteMix(_ mixID: UUID) throws {
        // Load mix to get file URL
        let mix = try loadMix(mixID)

        // Delete audio file
        if FileManager.default.fileExists(atPath: mix.fileURL.path) {
            try FileManager.default.removeItem(at: mix.fileURL)
        }

        // Delete cover image if it exists
        let coverURL = mixCoverURL(mixID)
        if FileManager.default.fileExists(atPath: coverURL.path) {
            try? FileManager.default.removeItem(at: coverURL)
        }

        // Delete metadata file
        let metadataFile = mixesBaseURL.appendingPathComponent("\(mixID.uuidString).json")
        try FileManager.default.removeItem(at: metadataFile)

    }

    // MARK: - Private Helpers

    private static func createDirectoryIfNeeded(at url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}
