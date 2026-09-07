import Foundation

/// The tiny file we poll to decide whether a full download is worth it.
/// Roughly 200 bytes, versus ~70 KB for the events payload.
struct SnapshotManifest: Codable, Sendable {
    let schema: Int
    let etag: String
    let generatedAt: Date
    let count: Int
    let region: String

    enum CodingKeys: String, CodingKey {
        case schema, etag, count, region
        case generatedAt = "generated_at"
    }
}

struct SnapshotCenter: Codable, Sendable {
    let lat: Double
    let lon: Double
}

struct Snapshot: Codable, Sendable {
    let schema: Int
    let region: String
    let generatedAt: Date
    let center: SnapshotCenter
    let radiusMiles: Double
    let horizonDays: Int
    let count: Int
    let etag: String
    let events: [Event]

    enum CodingKeys: String, CodingKey {
        case schema, region, center, count, etag, events
        case generatedAt = "generated_at"
        case radiusMiles = "radius_miles"
        case horizonDays = "horizon_days"
    }

    /// The schema the app was written against. If the pipeline ever ships a
    /// breaking change it bumps this, and old apps keep their cached copy
    /// rather than misreading the new shape.
    static let supportedSchema = 1
}
