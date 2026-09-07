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
/// `@MainActor`-isolated. It is reached first from `NearbyApp`'s `@StateObject`
/// initialiser, and SwiftUI's `App` is itself main-actor-isolated, so this is
/// where construction already happens; `EventStore` is `@MainActor` too and
/// cannot be built anywhere else. `LocationManager` stays deliberately
/// nonisolated - see its own note - because region callbacks arrive off the
/// main actor during a background relaunch. Background callers reach this type
/// through an explicit main-actor hop.
@MainActor
final class AppEnvironment: ObservableObject {
    static let shared = AppEnvironment()

    private let log = Logger(subsystem: "com.learnerkang.nearby", category: "environment")

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
        var events = store.events
        if events.isEmpty {
            await store.loadCache()
            events = store.events
        }
        geofences.handleArrival(atVenueKey: venueKey, in: events)
    }

    func refreshGeofences(at location: CLLocation) async {
        guard settings.arrivalAlertsEnabled, locationManager.hasAlwaysAuthorization else {
            return
        }
        var events = store.events
        if events.isEmpty {
            await store.loadCache()
            events = store.events
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
