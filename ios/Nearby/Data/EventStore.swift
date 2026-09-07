import CoreLocation
import Foundation
import OSLog
import SwiftUI

@MainActor
final class EventStore: ObservableObject {
    private let log = Logger(subsystem: "com.example.nearby", category: "store")
    private let client: SnapshotClient

    @Published private(set) var events: [Event] = []
    @Published private(set) var generatedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    /// False until the on-disk cache has been consulted, so the UI can tell
    /// "no events near you" apart from "we have not looked yet".
    @Published private(set) var hasLoaded = false

    init(client: SnapshotClient = .shared) {
        self.client = client
    }

    // MARK: - Loading

    func loadCache() async {
        do {
            let snapshot = try await client.loadCached()
            apply(snapshot)
        } catch {
            log.debug("no cached snapshot yet")
        }
        hasLoaded = true
    }

    /// Pull a new snapshot if the server has one. Safe to call often - it
    /// costs a ~200 byte manifest request when nothing has changed.
    func refresh(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            if let snapshot = try await client.fetchIfChanged() {
                apply(snapshot)
            } else if force {
                // Nothing new, but the user explicitly pulled to refresh -
                // let them see that we did check.
                log.debug("forced refresh: already up to date")
            }
            hasLoaded = true
        } catch {
            lastError = error.localizedDescription
            log.error("refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func apply(_ snapshot: Snapshot) {
        // Events that ended while the app was closed should not reappear.
        events = snapshot.events.filter { !$0.isOver() }
        generatedAt = snapshot.generatedAt
    }

    // MARK: - Queries

    /// Events the user should see, honouring their browse radius and muted
    /// categories, sorted by start time.
    func visibleEvents(from location: CLLocation?,
                       settings: UserSettings,
                       now: Date = .now) -> [Event] {
        let radiusMetres = settings.browseRadiusMiles * 1609.344
        return events
            .filter { !$0.isOver(asOf: now) }
            .filter { !settings.isMuted($0.category) }
            .filter { event in
                guard let location else { return true }
                return event.distance(from: location) <= radiusMetres
            }
            .sorted { $0.start < $1.start }
    }

    /// Everything on tonight, for the "what is on right now" section.
    func tonight(from location: CLLocation?,
                 settings: UserSettings,
                 now: Date = .now) -> [Event] {
        visibleEvents(from: location, settings: settings, now: now)
            .filter { $0.isActive(within: AppConfig.notificationLookahead, asOf: now) }
    }

    func event(withID id: String) -> Event? {
        events.first { $0.id == id }
    }
}
