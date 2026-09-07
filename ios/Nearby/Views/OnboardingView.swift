import SwiftUI

/// First-run explainer.
///
/// The order matters for App Review and for grant rates: explain the benefit
/// in our own UI *before* triggering the system prompt, and ask only for
/// "When In Use" here. The upgrade to "Always" is requested later, from
/// Settings, once the user has actively turned arrival alerts on - asking for
/// background location on first launch reads as a grab and gets denied.
struct OnboardingView: View {
    @EnvironmentObject private var locationManager: LocationManager
    @EnvironmentObject private var notifications: NotificationManager

    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            VStack(spacing: 10) {
                Text("What's on around you")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)

                Text("Shows, games and nights out within 100 miles of Reno — out to Tahoe, Carson City and Truckee.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 18) {
                point(icon: "map", title: "See it on a map",
                      detail: "Every event nearby, colour-coded by what it is.")
                point(icon: "bell.badge", title: "Get a nudge when you're close",
                      detail: "Walk near a venue with something on tonight and Nearby tells you.")
                point(icon: "lock.shield", title: "Your location stays here",
                      detail: "Matching happens on your phone. Nothing is uploaded.")
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await requestAndFinish() }
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)

                Button("Not now", action: onFinish)
                    .font(.subheadline)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
    }

    private func point(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func requestAndFinish() async {
        locationManager.requestWhenInUse()
        await notifications.requestAuthorization()
        onFinish()
    }
}
