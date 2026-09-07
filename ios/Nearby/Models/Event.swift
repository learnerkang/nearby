import CoreLocation
import Foundation
import SwiftUI

// MARK: - Category

/// Mirrors `CATEGORIES` in pipeline/nearby/models.py. Decoding is lenient:
/// a category added to the pipeline before the app ships an update must not
/// break the whole snapshot, so unknown values fall back to `.other`.
enum EventCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case music, nightlife, sports, arts, comedy, food, community, outdoors, family, other

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EventCategory(rawValue: raw) ?? .other
    }

    var label: String {
        switch self {
        case .music: "Music"
        case .nightlife: "Nightlife"
        case .sports: "Sports"
        case .arts: "Arts"
        case .comedy: "Comedy"
        case .food: "Food & Drink"
        case .community: "Community"
        case .outdoors: "Outdoors"
        case .family: "Family"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .music: "music.note"
        case .nightlife: "moon.stars.fill"
        case .sports: "sportscourt.fill"
        case .arts: "theatermasks.fill"
        case .comedy: "face.smiling.fill"
        case .food: "fork.knife"
        case .community: "person.3.fill"
        case .outdoors: "mountain.2.fill"
        case .family: "figure.2.and.child.holdinghands"
        case .other: "star.fill"
        }
    }

    var tint: Color {
        switch self {
        case .music: .pink
        case .nightlife: .purple
        case .sports: .green
        case .arts: .orange
        case .comedy: .yellow
        case .food: .red
        case .community: .teal
        case .outdoors: .mint
        case .family: .cyan
        case .other: .gray
        }
    }
}

// MARK: - Venue

struct Venue: Codable, Hashable, Sendable {
    let name: String
    let lat: Double
    let lon: Double
    let address: String?
    let city: String?
    let state: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// "140 Vesta St, Reno" - whichever parts the source actually gave us.
    var shortAddress: String {
        [address, city].compactMap { $0 }.joined(separator: ", ")
    }
}

// MARK: - Event

struct Event: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let source: String
    let title: String
    let start: Date
    let end: Date?
    let venue: Venue
    let category: EventCategory
    let description: String?
    let url: URL?
    let imageURL: URL?
    let priceMin: Double?
    let priceMax: Double?
    let isFree: Bool
    /// The source published a date but no time, so `start` is the venue's
    /// usual door time rather than a fact. The UI marks these with "~".
    let startIsEstimated: Bool
    let performers: [String]

    enum CodingKeys: String, CodingKey {
        case id, source, title, start, end, venue, category, description, url
        case imageURL = "image_url"
        case priceMin = "price_min"
        case priceMax = "price_max"
        case isFree = "is_free"
        case startIsEstimated = "start_is_estimated"
        case performers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? "unknown"
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decodeIfPresent(Date.self, forKey: .end)
        venue = try c.decode(Venue.self, forKey: .venue)
        category = try c.decodeIfPresent(EventCategory.self, forKey: .category) ?? .other
        description = try c.decodeIfPresent(String.self, forKey: .description)
        // The pipeline omits falsey/empty fields entirely to save bytes, so
        // every optional here is genuinely optional.
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        imageURL = try c.decodeIfPresent(URL.self, forKey: .imageURL)
        priceMin = try c.decodeIfPresent(Double.self, forKey: .priceMin)
        priceMax = try c.decodeIfPresent(Double.self, forKey: .priceMax)
        isFree = try c.decodeIfPresent(Bool.self, forKey: .isFree) ?? false
        startIsEstimated = try c.decodeIfPresent(Bool.self, forKey: .startIsEstimated) ?? false
        performers = try c.decodeIfPresent([String].self, forKey: .performers) ?? []
    }

    var coordinate: CLLocationCoordinate2D { venue.coordinate }

    /// Sources frequently omit an end time. Four hours is long enough to cover
    /// a concert and short enough that a matinee stops alerting by dinner.
    static let assumedDuration: TimeInterval = 4 * 3600

    var endOrAssumed: Date { end ?? start.addingTimeInterval(Self.assumedDuration) }

    func isOver(asOf now: Date = .now) -> Bool { endOrAssumed < now }

    func isHappeningNow(asOf now: Date = .now) -> Bool {
        start <= now && now <= endOrAssumed
    }

    /// True if the event is running now or starts within `window`.
    func isActive(within window: TimeInterval, asOf now: Date = .now) -> Bool {
        !isOver(asOf: now) && start <= now.addingTimeInterval(window)
    }

    func distance(from location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: venue.lat, longitude: venue.lon).distance(from: location)
    }

    var priceLabel: String? {
        if isFree { return "Free" }
        guard let min = priceMin else { return nil }
        if let max = priceMax, max > min {
            return "$\(Int(min.rounded()))-\(Int(max.rounded()))"
        }
        return "$\(Int(min.rounded()))"
    }
}
