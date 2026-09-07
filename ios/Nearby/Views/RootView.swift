import CoreLocation
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var router: NotificationRouter

    @AppStorage("onboarding.complete") private var onboardingComplete = false
    @State private var selectedTab = Tab.tonight
    @State private var deepLinkedEvent: Event?

    enum Tab: Hashable { case tonight, map, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            ListScreen()
                .tabItem { Label("Tonight", systemImage: "list.bullet") }
                .tag(Tab.tonight)

            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(Tab.map)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .fullScreenCover(isPresented: .constant(!onboardingComplete)) {
            OnboardingView { onboardingComplete = true }
        }
        .sheet(item: $deepLinkedEvent) { event in
            NavigationStack { EventDetailView(event: event) }
        }
        // A tapped notification should land on the event it was about.
        .onChange(of: router.pendingEventID) { _, id in
            guard let id, let event = store.event(withID: id) else { return }
            deepLinkedEvent = event
            router.pendingEventID = nil
        }
    }
}
