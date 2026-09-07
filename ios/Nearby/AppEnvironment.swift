import CoreLocation
import Foundation
import OSLog
import SwiftUI

/// Owns the long-lived objects and wires them together.
///
/// There is exactly one of these (`AppEnvironment.shared`). That is not
/// decoration: iOS relaunches the app in the background for a geofence
/// crossing, and both the background task handler and the SwiftUI scene must
/// talk to the *same* LocationManager. Two instances would each register their
/// own regions and quietly fight over the 20-region budget.
///
/// Not `@MainActor`-isolated, because it is constructed from `App.init`, which
/// is nonisolated. The pieces that need the main actor (`EventStore`) are
/// isolated themselves and awaited here.
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    private let log = Logger(subsystem: "com.example.nearby", category: "environment")

    let store: EventStore
    let settings: UserSettings
    let locationManager: LocationManager
    let notifications: NotificationManager
    let geofences: GeofenceCoordinator

    private init() {
        let settings = UserSettings.shared
        let locationManager = LocationManager()
        let notifications = NotificationManager.shared

        self.settings = settings
        self.locationManager = locationManager
        self.notifications = notifications
        self.store = EventStore()
        self.geofences = GeofenceCoordinator(
            locationManager: locationManager,
            notifications: notifications,
            settings: settings
        )

        locationManager.onRegionEntry = { [weak self] identifier in
            Task { await self?.handleArrival(identifier) }
        }
        locationManager.onSignificantMove = { [weak self] location in
            Task { await self?.refreshGeofences(at: location) }
        }
    }

    /// Called on launch, on foreground, and from the background refresh task.
    func start() async {
        await store.loadCache()
        await notifications.refreshStatus()
        await store.refresh()

        if let location = locationManager.currentLocation {
            await refreshGeofences(at: location)
        } else {
            locationManager.requestOneShotLocation()
        }
    }

    private func handleArrival(_ venueKey: String) async {
        // A background relaunch has no warm state, so make sure the cached
        // snapshot is loaded before trying to resolve the venue.
        var events = await store.events
        if events.isEmpty {
            await store.loadCache()
            events = await store.events
        }
        geofences.handleArrival(atVenueKey: venueKey, in: events)
    }

    func refreshGeofences(at location: CLLocation) async {
        guard settings.arrivalAlertsEnabled, locationManager.hasAlwaysAuthorization else {
            return
        }
        var events = await store.events
        if events.isEmpty {
            await store.loadCache()
            events = await store.events
        }
        geofences.updateRegions(for: events, location: location)
    }

    /// Turning arrival alerts off should actually stop the battery cost, not
    /// merely suppress the banners.
    func applyAlertPreference() async {
        if settings.arrivalAlertsEnabled {
            locationManager.startMonitoringSignificantChanges()
            if let location = locationManager.currentLocation {
                await refreshGeofences(at: location)
            }
        } else {
            geofences.stopAll()
            locationManager.stopMonitoringSignificantChanges()
        }
    }
}
