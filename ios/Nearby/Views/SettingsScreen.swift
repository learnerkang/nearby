import CoreLocation
import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        NavigationStack {
            Form {
                alertsSection
                if settings.arrivalAlertsEnabled {
                    timingSection
                    quietHoursSection
                }
                browsingSection
                categoriesSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
        }
    }

    // MARK: Alerts

    private var alertsSection: some View {
        Section {
            Toggle("Alert me when I'm near an event", isOn: $settings.arrivalAlertsEnabled)
                .onChange(of: settings.arrivalAlertsEnabled) { _, enabled in
                    Task {
                        if enabled { await requestPermissionsForAlerts() }
                        await environment.applyAlertPreference()
                    }
                }

            if settings.arrivalAlertsEnabled {
                permissionRows
            }
        } header: {
            Text("Arrival alerts")
        } footer: {
            Text("""
                Your location is matched against the event list entirely on this \
                device. Nothing about where you are is uploaded or shared.
                """)
        }
    }

    @ViewBuilder
    private var permissionRows: some View {
        // "Always" is what makes an alert possible when the app is closed, so
        // say plainly what is missing rather than failing silently.
        if !locationManager.hasAlwaysAuthorization {
            permissionRow(
                title: "Background location",
                detail: locationManager.hasAnyAuthorization
                    ? "Set Location to \"Always\" so alerts work with the app closed."
                    : "Nearby needs location access to know when you're close to a venue.",
                action: locationManager.hasAnyAuthorization ? "Open Settings" : "Allow",
                isSystemSettings: locationManager.hasAnyAuthorization
            ) {
                if locationManager.hasAnyAuthorization {
                    locationManager.requestAlways()
                } else {
                    locationManager.requestWhenInUse()
                }
            }
        }

        if notifications.authorizationStatus == .denied {
            permissionRow(
                title: "Notifications are off",
                detail: "Turn them on in iOS Settings to receive alerts.",
                action: "Open Settings",
                isSystemSettings: true
            ) {}
        }
    }

    private func permissionRow(title: String,
                               detail: String,
                               action: String,
                               isSystemSettings: Bool,
                               perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Button(action) {
                if isSystemSettings {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } else {
                    perform()
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 4)
    }

    private func requestPermissionsForAlerts() async {
        await notifications.requestAuthorization()
        if locationManager.hasAnyAuthorization {
            locationManager.requestAlways()
        } else {
            locationManager.requestWhenInUse()
        }
    }

    // MARK: Timing

    private var timingSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Alert me about events starting within")
                    Spacer()
                    Text("\(Int(settings.lookaheadHours))h").foregroundStyle(.secondary)
                }
                Slider(value: $settings.lookaheadHours, in: 1...12, step: 1)
            }
        } footer: {
            Text("""
                Walking past a venue at 2pm for a show that starts at 8pm is \
                usually not worth a buzz. Six hours is a good default.
                """)
        }
    }

    private var quietHoursSection: some View {
        Section("Quiet hours") {
            Toggle("Don't alert me overnight", isOn: $settings.quietHoursEnabled)
            if settings.quietHoursEnabled {
                Picker("From", selection: $settings.quietStartHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
                Picker("Until", selection: $settings.quietEndHour) {
                    ForEach(0..<24, id: \.self) { Text(hourLabel($0)).tag($0) }
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Browsing

    private var browsingSection: some View {
        Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Show events within")
                    Spacer()
                    Text("\(Int(settings.browseRadiusMiles)) mi").foregroundStyle(.secondary)
                }
                Slider(value: $settings.browseRadiusMiles, in: 5...100, step: 5)
            }
        } header: {
            Text("Browsing")
        } footer: {
            Text("""
                The download always covers 100 miles - Reno out to Tahoe, Carson \
                City and Truckee. This only changes what the list and map show.
                """)
        }
    }

    private var categoriesSection: some View {
        Section("Categories") {
            ForEach(EventCategory.allCases) { category in
                Toggle(isOn: Binding(
                    get: { !settings.isMuted(category) },
                    set: { _ in settings.toggle(category) }
                )) {
                    Label(category.label, systemImage: category.symbolName)
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: Data

    private var dataSection: some View {
        Section("Events") {
            HStack {
                Text("Loaded")
                Spacer()
                Text("\(store.events.count)").foregroundStyle(.secondary)
            }
            if let generatedAt = store.generatedAt {
                HStack {
                    Text("Updated")
                    Spacer()
                    Text(generatedAt.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                HStack {
                    Text("Refresh now")
                    Spacer()
                    if store.isRefreshing { ProgressView() }
                }
            }
            .disabled(store.isRefreshing)

            if let error = store.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var aboutSection: some View {
        Section {
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
