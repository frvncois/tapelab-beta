import Foundation

/// Represents a bounced stereo mix from a session
struct Mix: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let sessionId: UUID
    let sessionName: String
    let createdAt: Date
    let duration: TimeInterval
    let fileURL: URL

    init(id: UUID = UUID(),
         name: String,
         sessionId: UUID,
         sessionName: String,
         createdAt: Date = Date(),
         duration: TimeInterval,
         fileURL: URL) {
        self.id = id
        self.name = name
        self.sessionId = sessionId
        self.sessionName = sessionName
        self.createdAt = createdAt
        self.duration = duration
        self.fileURL = fileURL
    }
}

/// Lightweight metadata for Mix (used in list views)
struct MixMetadata: Identifiable, Codable {
    let id: UUID
    let name: String
    let sessionId: UUID
    let sessionName: String
    let createdAt: Date
    let duration: TimeInterval

    init(from mix: Mix) {
        self.id = mix.id
        self.name = mix.name
        self.sessionId = mix.sessionId
        self.sessionName = mix.sessionName
        self.createdAt = mix.createdAt
        self.duration = mix.duration
    }
}
