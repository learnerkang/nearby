import Foundation

enum Formatters {
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f
    }()

    private static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f
    }()

    /// A leading "~" marks a time the pipeline inferred from the venue's usual
    /// door time rather than one the source actually published.
    static func time(_ date: Date, estimated: Bool = false) -> String {
        (estimated ? "~" : "") + timeFormatter.string(from: date)
    }

    /// "Tonight", "Tomorrow", "Sat" or "Sat 14 Feb" depending on how far out.
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            let hour = calendar.component(.hour, from: date)
            return hour >= 17 ? "Tonight" : "Today"
        }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }

        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return days < 7 ? weekdayFormatter.string(from: date)
                        : dayMonthFormatter.string(from: date)
    }

    static func dayAndTime(_ event: Event, now: Date = .now) -> String {
        "\(day(event.start, now: now)) at \(time(event.start, estimated: event.startIsEstimated))"
    }

    /// Distances are for deciding "can I get there", so precision below a
    /// tenth of a mile is noise.
    static func distance(_ metres: Double) -> String {
        let miles = metres / 1609.344
        if miles < 0.1 { return "here" }
        if miles < 10 { return String(format: "%.1f mi", miles) }
        return String(format: "%.0f mi", miles)
    }
}
