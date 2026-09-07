import CoreLocation
import Foundation

enum AppConfig {
    // ------------------------------------------------------------------
    // CHANGE THIS after you enable GitHub Pages (docs/SETUP.md step 4).
    // It is the only line that ties the app to your data.
    // ------------------------------------------------------------------
    static let snapshotBaseURL = URL(string: "https://learnerkang.github.io/nearby")!

    static var manifestURL: URL { snapshotBaseURL.appendingPathComponent("manifest.json") }
    /// Plain JSON, not the .gz: GitHub Pages applies gzip transfer encoding
    /// and URLSession decompresses it transparently, so we get the small
    /// download without hand-rolling gunzip.
    static var eventsURL: URL { snapshotBaseURL.appendingPathComponent("events.json") }

    static let backgroundRefreshTaskID = "com.learnerkang.nearby.refresh"

    /// Fallback map centre before the first location fix: downtown Reno.
    static let fallbackCenter = CLLocationCoordinate2D(latitude: 39.5296, longitude: -119.8138)

    // MARK: Geofencing

    /// iOS allows an app 20 monitored regions, total. We spend 19 on venues
    /// and reserve one as a "you have moved meaningfully, recompute" region
    /// centred on the user - otherwise a drive across town leaves the app
    /// watching venues that are now the wrong ones.
    static let maxVenueRegions = 19
    static let venueRegionRadius: CLLocationDistance = 350      // metres
    static let recomputeRegionRadius: CLLocationDistance = 5_000
    static let recomputeRegionID = "nearby.recompute"

    /// How far ahead an event counts as "tonight" for an arrival alert.
    static let notificationLookahead: TimeInterval = 6 * 3600

    /// Never alert twice for the same event.
    static let notificationCooldown: TimeInterval = 12 * 3600
}
