import SwiftUI

@main
struct NearbyApp: App {
    // The one shared environment - see AppEnvironment for why it is a
    // singleton rather than something the scene owns.
    @StateObject private var environment = AppEnvironment.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Registered from App.init so that a background launch (geofence
        // crossing or scheduled refresh) still finds a handler. Registering
        // inside a View body would be too late.
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(environment.store)
                .environmentObject(environment.settings)
                .environmentObject(environment.locationManager)
                .environmentObject(environment.notifications)
                .environmentObject(NotificationRouter.shared)
                .task { await environment.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await environment.store.refresh() }
            case .background:
                BackgroundRefresh.schedule()
            default:
                break
            }
        }
    }
}
