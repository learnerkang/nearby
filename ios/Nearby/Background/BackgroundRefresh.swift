import BackgroundTasks
import Foundation
import OSLog

/// Keeps the cached snapshot reasonably fresh without the user opening the app.
///
/// iOS decides when - and whether - these actually run; the schedule below is
/// a request, not a guarantee. That is acceptable here: the geofence set is
/// rebuilt from whatever snapshot is on disk, and an event list a few hours
/// stale is still useful. Foreground launches refresh normally regardless.
enum BackgroundRefresh {
    private static let log = Logger(subsystem: "com.learnerkang.nearby", category: "background")

    /// Must run before the app finishes launching, so it is called from
    /// `NearbyApp.init`.
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppConfig.backgroundRefreshTaskID,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: AppConfig.backgroundRefreshTaskID)
        // The pipeline publishes every 3 hours; asking for anything sooner
        // spends the app's background budget for no new data.
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
            log.debug("background refresh scheduled")
        } catch {
            // Expected on the simulator, which has no background scheduler.
            log.error("could not schedule: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Queue the next one first: if this run is killed we still want
        // another attempt later.
        schedule()

        // Hops to the main actor explicitly: AppEnvironment and EventStore are
        // both main-actor-isolated, and this handler is called by iOS from a
        // nonisolated context during a background relaunch.
        let work = Task { @MainActor in
            let env = AppEnvironment.shared
            await env.store.refresh()
            if let location = env.locationManager.currentLocation {
                await env.refreshGeofences(at: location)
            }
            task.setTaskCompleted(success: !Task.isCancelled)
        }

        task.expirationHandler = {
            log.info("background refresh expired before finishing")
            work.cancel()
        }
    }
}
