import CoreLocation
import Foundation
import OSLog

/// Decides which venues are worth watching, and reacts when the user arrives.
///
/// The constraint that shapes this whole file: **iOS gives an app 20 monitored
/// regions, total.** Reno has far more than 20 venues, so the set has to be
/// chosen, and re-chosen as the user moves.
///
/// The scheme:
///  - one region per *venue*, not per event, so a venue with three shows
///    tonight costs one slot rather than three;
///  - 19 nearest venues with something on soon;
///  - the 20th slot is a large "recompute" bubble around the user. Leaving it
///    means the nearest-19 list is probably stale, which triggers a reselect.
final class GeofenceCoordinator {
    private let log = Logger(subsystem: "com.example.nearby", category: "geofence")
    private let locationManager: LocationManager
    private let notifications: NotificationManager
    private let settings: UserSettings

    /// Only events starting inside this window are worth a geofence slot at
    /// all - wider than the notification lookahead so that a venue does not
    /// get dropped an hour before it becomes relevant.
    private let candidateWindow: TimeInterval = 24 * 3600

    init(locationManager: LocationManager,
         notifications: NotificationManager = .shared,
         settings: UserSettings = .shared) {
        self.locationManager = locationManager
        self.notifications = notifications
        self.settings = settings
    }

    // MARK: - Venue identity

    /// Regions are keyed by rounded coordinates so that the same venue spelled
    /// differently by two sources still maps to one slot. Five decimal places
    /// is about one metre.
    static func venueKey(lat: Double, lon: Double) -> String {
        String(format: "venue.%.5f,%.5f", lat, lon)
    }

    static func venueKey(for event: Event) -> String {
        venueKey(lat: event.venue.lat, lon: event.venue.lon)
    }

    // MARK: - Selection

    /// Pick the venues to monitor: nearest first, only those with an event
    /// inside the candidate window and in a category the user has not muted.
    func selectVenues(from events: [Event],
                      near location: CLLocation,
                      now: Date = .now) -> [(key: String, coordinate: CLLocationCoordinate2D)] {
        var bestByVenue: [String: (event: Event, distance: CLLocationDistance)] = [:]

        for event in events {
            guard event.isActive(within: candidateWindow, asOf: now) else { continue }
            guard !settings.isMuted(event.category) else { continue }
            let key = Self.venueKey(for: event)
            let distance = event.distance(from: location)
            // Keep the soonest event per venue; distance is identical anyway.
            if let existing = bestByVenue[key], existing.event.start <= event.start { continue }
            bestByVenue[key] = (event, distance)
        }

        return bestByVenue
            .sorted { $0.value.distance < $1.value.distance }
            .prefix(AppConfig.maxVenueRegions)
            .map { ($0.key, $0.value.event.coordinate) }
    }

    /// Reconcile the monitored set with the desired set.
    ///
    /// Diffing rather than clearing-and-re-adding matters: `startMonitoring`
    /// re-arms a region, so a user already standing inside one would get a
    /// fresh entry callback every refresh.
    func updateRegions(for events: [Event], location: CLLocation, now: Date = .now) {
        let desired = selectVenues(from: events, near: location, now: now)
        var desiredIDs = Set(desired.map(\.key))
        desiredIDs.insert(AppConfig.recomputeRegionID)

        let monitored = locationManager.monitoredRegions
        let monitoredIDs = Set(monitored.map(\.identifier))

        for region in monitored where !desiredIDs.contains(region.identifier) {
            locationManager.stopMonitoring(region)
        }

        for venue in desired where !monitoredIDs.contains(venue.key) {
            let region = CLCircularRegion(
                center: venue.coordinate,
                radius: AppConfig.venueRegionRadius,
                identifier: venue.key
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            locationManager.startMonitoring(region)
        }

        refreshRecomputeRegion(around: location, monitored: monitored)

        log.info("""
            monitoring \(desired.count, privacy: .public) venues \
            (of \(events.count, privacy: .public) events)
            """)
    }

    /// The recompute bubble follows the user. Re-centre it whenever they have
    /// drifted more than half its radius from where it currently sits.
    private func refreshRecomputeRegion(around location: CLLocation, monitored: Set<CLRegion>) {
        let existing = monitored
            .compactMap { $0 as? CLCircularRegion }
            .first { $0.identifier == AppConfig.recomputeRegionID }

        if let existing {
            let centre = CLLocation(latitude: existing.center.latitude,
                                    longitude: existing.center.longitude)
            if centre.distance(from: location) < AppConfig.recomputeRegionRadius / 2 {
                return
            }
            locationManager.stopMonitoring(existing)
        }

        let region = CLCircularRegion(
            center: location.coordinate,
            radius: AppConfig.recomputeRegionRadius,
            identifier: AppConfig.recomputeRegionID
        )
        region.notifyOnEntry = false
        region.notifyOnExit = true
        locationManager.startMonitoring(region)
    }

    // MARK: - Arrival

    /// The user just crossed into a venue's radius. A geofence knows where
    /// they are but nothing about timing, so pick the most relevant event at
    /// that venue and let NotificationManager decide whether it is worth a
    /// buzz.
    @discardableResult
    func handleArrival(atVenueKey key: String, in events: [Event], now: Date = .now) -> Event? {
        let candidates = events
            .filter { Self.venueKey(for: $0) == key }
            .filter { $0.isActive(within: settings.lookahead, asOf: now) }
            .sorted { $0.start < $1.start }

        guard let event = candidates.first else {
            log.debug("arrival at \(key, privacy: .public) with nothing on")
            return nil
        }
        return notifications.notifyArrival(for: event, settings: settings, now: now)
            ? event : nil
    }

    func stopAll() {
        locationManager.stopMonitoringAll()
    }
}
