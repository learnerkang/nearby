import Foundation
import OSLog
import UserNotifications

/// Local notifications only. Nothing here talks to a push server, and no
/// location ever leaves the device - the matching happens on-device against
/// the downloaded snapshot.
final class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()

    private let log = Logger(subsystem: "com.example.nearby", category: "notifications")
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private static let lastNotifiedKey = "notifications.lastNotified"

    override init() {
        super.init()
        center.delegate = self
    }

    // MARK: - Permission

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshStatus()
            return granted
        } catch {
            log.error("auth request failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        await MainActor.run { self.authorizationStatus = settings.authorizationStatus }
    }

    // MARK: - Arrival alerts

    /// Fire an alert for an event the user has just walked or driven up to.
    ///
    /// Returns false (and sends nothing) when the event is not actually
    /// relevant right now - which is the common case, because a geofence only
    /// knows *where* the user is, not *when* the show is.
    @discardableResult
    func notifyArrival(for event: Event, settings: UserSettings, now: Date = .now) -> Bool {
        guard settings.arrivalAlertsEnabled else { return false }
        guard !settings.isMuted(event.category) else { return false }
        guard event.isActive(within: settings.lookahead, asOf: now) else {
            log.debug("skipping \(event.id, privacy: .public): not starting soon")
            return false
        }
        guard !settings.isQuiet(at: now) else {
            log.debug("skipping \(event.id, privacy: .public): quiet hours")
            return false
        }
        guard !wasRecentlyNotified(event.id, now: now) else { return false }

        let content = UNMutableNotificationContent()
        content.title = event.isHappeningNow(asOf: now)
            ? "Happening now nearby"
            : "Starting soon nearby"
        content.body = body(for: event, now: now)
        content.sound = .default
        content.userInfo = ["eventID": event.id]
        content.interruptionLevel = .timeSensitive

        // nil trigger = deliver immediately. We are already inside the
        // geofence callback, so "now" is the right moment.
        let request = UNNotificationRequest(
            identifier: "arrival.\(event.id)",
            content: content,
            trigger: nil
        )
        center.add(request) { [log] error in
            if let error {
                log.error("failed to post: \(error.localizedDescription, privacy: .public)")
            }
        }
        markNotified(event.id, now: now)
        log.info("notified for \(event.id, privacy: .public)")
        return true
    }

    private func body(for event: Event, now: Date) -> String {
        var parts: [String] = [event.title]
        if event.isHappeningNow(asOf: now) {
            parts.append("on now at \(event.venue.name)")
        } else {
            let time = Formatters.time(event.start, estimated: event.startIsEstimated)
            parts.append("\(time) at \(event.venue.name)")
        }
        if let price = event.priceLabel { parts.append(price) }
        return parts.joined(separator: " - ")
    }

    // MARK: - Repeat suppression

    private var lastNotified: [String: Double] {
        get { defaults.dictionary(forKey: Self.lastNotifiedKey) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: Self.lastNotifiedKey) }
    }

    private func wasRecentlyNotified(_ id: String, now: Date) -> Bool {
        guard let stamp = lastNotified[id] else { return false }
        return now.timeIntervalSince1970 - stamp < AppConfig.notificationCooldown
    }

    private func markNotified(_ id: String, now: Date) {
        var map = lastNotified
        map[id] = now.timeIntervalSince1970
        // Walking in and out of a geofence all week would grow this forever.
        let cutoff = now.timeIntervalSince1970 - AppConfig.notificationCooldown * 4
        lastNotified = map.filter { $0.value > cutoff }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show the banner even when the app happens to be open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo["eventID"] as? String
        await MainActor.run {
            NotificationRouter.shared.pendingEventID = id
        }
    }
}

/// Carries a tapped notification through to the UI once it is on screen.
@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    @Published var pendingEventID: String?
}
