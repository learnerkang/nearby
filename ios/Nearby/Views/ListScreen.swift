import CoreLocation
import SwiftUI

struct ListScreen: View {
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var locationManager: LocationManager

    @State private var now = Date.now

    private var location: CLLocation? { locationManager.currentLocation }

    private var events: [Event] {
        store.visibleEvents(from: location, settings: settings, now: now)
    }

    private var onNow: [Event] { events.filter { $0.isHappeningNow(asOf: now) } }

    private var soon: [Event] {
        events.filter {
            !$0.isHappeningNow(asOf: now)
                && $0.start <= now.addingTimeInterval(AppConfig.notificationLookahead)
        }
    }

    private var later: [Event] {
        let cutoff = now.addingTimeInterval(AppConfig.notificationLookahead)
        return events.filter { $0.start > cutoff }
    }

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Nearby")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { CategoryFilterMenu() }
            }
            .refreshable { await store.refresh(force: true) }
            // Section membership is time-dependent, so re-evaluate on a timer
            // rather than letting "On now" go stale while the app sits open.
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) {
                now = $0
            }
        }
    }

    private var list: some View {
        List {
            if !onNow.isEmpty {
                Section("On now") {
                    ForEach(onNow) { row(for: $0) }
                }
            }
            if !soon.isEmpty {
                Section("Starting soon") {
                    ForEach(soon) { row(for: $0) }
                }
            }
            if !later.isEmpty {
                Section("Coming up") {
                    ForEach(later) { row(for: $0) }
                }
            }
            if let generatedAt = store.generatedAt {
                Section {
                    HStack {
                        Text("Events updated")
                        Spacer()
                        Text(generatedAt, style: .relative) + Text(" ago")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
        // Declared once for the whole stack. Attaching this inside the row
        // builder would re-register it for every visible row, which SwiftUI
        // warns about and which makes the destination non-deterministic.
        .navigationDestination(for: Event.self) { EventDetailView(event: $0) }
    }

    private func row(for event: Event) -> some View {
        NavigationLink(value: event) {
            EventRow(event: event, location: location, now: now)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !store.hasLoaded {
            ProgressView("Loading events")
        } else if let error = store.lastError {
            ContentUnavailableView {
                Label("Could not load events", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { Task { await store.refresh(force: true) } }
            }
        } else if !settings.mutedCategories.isEmpty {
            ContentUnavailableView {
                Label("Nothing matches your filters", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("You have muted \(settings.mutedCategories.count) categories.")
            } actions: {
                Button("Show all categories") { settings.mutedCategories = [] }
            }
        } else {
            ContentUnavailableView {
                Label("No events within \(Int(settings.browseRadiusMiles)) miles",
                      systemImage: "mappin.slash")
            } description: {
                Text("Try widening the radius in Settings.")
            }
        }
    }
}

// MARK: - Row

struct EventRow: View {
    let event: Event
    let location: CLLocation?
    var now: Date = .now

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: event.category.symbolName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(event.category.tint, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                if event.isHappeningNow(asOf: now) {
                    Text("NOW")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                } else {
                    Text(Formatters.time(event.start, estimated: event.startIsEstimated))
                        .font(.caption.weight(.medium))
                        .monospacedDigit()
                }
                if let location {
                    Text(Formatters.distance(event.distance(from: location)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [event.venue.name]
        if !event.isHappeningNow(asOf: now) {
            parts.insert(Formatters.day(event.start, now: now), at: 0)
        }
        if let price = event.priceLabel { parts.append(price) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Filters

struct CategoryFilterMenu: View {
    @EnvironmentObject private var settings: UserSettings

    var body: some View {
        Menu {
            ForEach(EventCategory.allCases) { category in
                Button {
                    settings.toggle(category)
                } label: {
                    Label(category.label,
                          systemImage: settings.isMuted(category) ? "circle" : "checkmark.circle.fill")
                }
            }
            if !settings.mutedCategories.isEmpty {
                Divider()
                Button("Show all") { settings.mutedCategories = [] }
            }
        } label: {
            Image(systemName: settings.mutedCategories.isEmpty
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }
}
