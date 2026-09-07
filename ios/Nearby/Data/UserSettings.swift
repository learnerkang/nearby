import Foundation
import SwiftUI

/// User preferences, persisted in UserDefaults.
///
/// These are read from a background launch (a geofence can wake the app with
/// no UI at all), so this is a plain observable object backed by UserDefaults
/// rather than a pile of `@AppStorage` properties trapped inside a View.
final class UserSettings: ObservableObject {
    static let shared = UserSettings()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.arrivalAlertsEnabled = defaults.object(forKey: Keys.arrivalAlerts) as? Bool ?? true
        self.browseRadiusMiles = defaults.object(forKey: Keys.radius) as? Double ?? 25
        self.lookaheadHours = defaults.object(forKey: Keys.lookahead) as? Double ?? 6
        self.quietHoursEnabled = defaults.object(forKey: Keys.quietEnabled) as? Bool ?? true
        self.quietStartHour = defaults.object(forKey: Keys.quietStart) as? Int ?? 23
        self.quietEndHour = defaults.object(forKey: Keys.quietEnd) as? Int ?? 9

        if let raw = defaults.array(forKey: Keys.categories) as? [String] {
            self.mutedCategories = Set(raw.compactMap(EventCategory.init(rawValue:)))
        } else {
            self.mutedCategories = []
        }
    }

    private enum Keys {
        static let arrivalAlerts = "settings.arrivalAlerts"
        static let radius = "settings.browseRadiusMiles"
        static let lookahead = "settings.lookaheadHours"
        static let quietEnabled = "settings.quietHoursEnabled"
        static let quietStart = "settings.quietStartHour"
        static let quietEnd = "settings.quietEndHour"
        static let categories = "settings.mutedCategories"
    }

    @Published var arrivalAlertsEnabled: Bool {
        didSet { defaults.set(arrivalAlertsEnabled, forKey: Keys.arrivalAlerts) }
    }

    /// Browsing radius only. The snapshot always covers the full 100 miles;
    /// this narrows what the map and list show.
    @Published var browseRadiusMiles: Double {
        didSet { defaults.set(browseRadiusMiles, forKey: Keys.radius) }
    }

    /// How far ahead an event counts as "starting soon" for an arrival alert.
    @Published var lookaheadHours: Double {
        didSet { defaults.set(lookaheadHours, forKey: Keys.lookahead) }
    }

    @Published var quietHoursEnabled: Bool {
        didSet { defaults.set(quietHoursEnabled, forKey: Keys.quietEnabled) }
    }

    @Published var quietStartHour: Int {
        didSet { defaults.set(quietStartHour, forKey: Keys.quietStart) }
    }

    @Published var quietEndHour: Int {
        didSet { defaults.set(quietEndHour, forKey: Keys.quietEnd) }
    }

    @Published var mutedCategories: Set<EventCategory> {
        didSet {
            defaults.set(mutedCategories.map(\.rawValue), forKey: Keys.categories)
        }
    }

    var lookahead: TimeInterval { lookaheadHours * 3600 }

    func isMuted(_ category: EventCategory) -> Bool { mutedCategories.contains(category) }

    func toggle(_ category: EventCategory) {
        if mutedCategories.contains(category) {
            mutedCategories.remove(category)
        } else {
            mutedCategories.insert(category)
        }
    }

    /// Quiet hours wrap midnight (23:00-09:00 by default), so the comparison
    /// differs depending on whether the window crosses into the next day.
    func isQuiet(at date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard quietHoursEnabled else { return false }
        let hour = calendar.component(.hour, from: date)
        if quietStartHour == quietEndHour { return false }
        if quietStartHour < quietEndHour {
            return hour >= quietStartHour && hour < quietEndHour
        }
        return hour >= quietStartHour || hour < quietEndHour
    }
}
