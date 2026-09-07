import CoreLocation
import Foundation
import OSLog

/// Thin wrapper over CLLocationManager.
///
/// Deliberately not `@MainActor`: region-entry callbacks arrive when iOS
/// relaunches the app in the background with no UI, and the delegate methods
/// need to run then. CLLocationManager delivers callbacks on the queue it was
/// created on, which is main here, so the `@Published` writes are safe.
final class LocationManager: NSObject, ObservableObject {
    private let log = Logger(subsystem: "com.example.nearby", category: "location")
    private let manager = CLLocationManager()

    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?

    /// Called with the identifier of a venue region the user just entered.
    var onRegionEntry: ((String) -> Void)?
    /// Called when the user has moved far enough that the monitored set of
    /// venues should be recalculated.
    var onSignificantMove: ((CLLocation) -> Void)?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Region monitoring survives app termination; this makes iOS relaunch
        // us for a boundary crossing instead of dropping the alert.
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
        currentLocation = manager.location
    }

    var hasAnyAuthorization: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var hasAlwaysAuthorization: Bool { authorizationStatus == .authorizedAlways }

    // MARK: - Permissions

    /// Step one of the two-step prompt. Asking for "Always" up front gets a
    /// much lower grant rate (and reads as pushy), so we ask for it later,
    /// only once the user has turned arrival alerts on.
    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func requestAlways() {
        guard authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Updates

    func requestOneShotLocation() {
        guard hasAnyAuthorization else { return }
        manager.requestLocation()
    }

    /// Cheap, coarse wake-ups (roughly every 500m-1km) used to re-pick which
    /// venues we monitor. Far less battery than continuous updates.
    func startMonitoringSignificantChanges() {
        guard hasAlwaysAuthorization,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopMonitoringSignificantChanges() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.allowsBackgroundLocationUpdates = false
    }

    // MARK: - Regions

    var monitoredRegions: Set<CLRegion> { manager.monitoredRegions }

    func startMonitoring(_ region: CLCircularRegion) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        manager.startMonitoring(for: region)
    }

    func stopMonitoring(_ region: CLRegion) {
        manager.stopMonitoring(for: region)
    }

    func stopMonitoringAll() {
        for region in manager.monitoredRegions {
            manager.stopMonitoring(for: region)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        log.info("authorization -> \(manager.authorizationStatus.rawValue, privacy: .public)")
        if hasAnyAuthorization { manager.requestLocation() }
        if hasAlwaysAuthorization { startMonitoringSignificantChanges() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        currentLocation = latest
        onSignificantMove?(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient .locationUnknown is normal indoors; nothing to do but
        // wait for the next fix.
        log.error("location failed: \(error.localizedDescription, privacy: .public)")
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        log.info("entered region \(region.identifier, privacy: .public)")
        if region.identifier == AppConfig.recomputeRegionID { return }
        onRegionEntry?(region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // Leaving the recompute bubble means the previously chosen venues may
        // no longer be the nearest ones.
        guard region.identifier == AppConfig.recomputeRegionID else { return }
        log.info("left recompute region; re-selecting venues")
        if let location = manager.location ?? currentLocation {
            onSignificantMove?(location)
        } else {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager,
                         monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        log.error("""
            region monitoring failed for \(region?.identifier ?? "nil", privacy: .public): \
            \(error.localizedDescription, privacy: .public)
            """)
    }
}
