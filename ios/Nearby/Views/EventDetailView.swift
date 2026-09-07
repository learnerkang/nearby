import CoreLocation
import MapKit
import SwiftUI

struct EventDetailView: View {
    let event: Event

    @EnvironmentObject private var locationManager: LocationManager
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                poster
                header
                Divider()
                venueBlock
                if let description = event.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if !event.performers.isEmpty {
                    lineup
                }
                actions
                sourceFootnote
            }
            .padding()
        }
        .navigationTitle(event.venue.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var poster: some View {
        if let url = event.imageURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .empty:
                    Rectangle().fill(.quaternary).overlay(ProgressView())
                case .failure:
                    // A dead poster URL should not leave a broken-image hole.
                    EmptyView()
                @unknown default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(event.category.label, systemImage: event.category.symbolName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(event.category.tint)
                if event.isHappeningNow() {
                    Text("ON NOW")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.red, in: Capsule())
                }
            }

            Text(event.title)
                .font(.title2.bold())

            Text(Formatters.dayAndTime(event))
                .font(.subheadline)

            if event.startIsEstimated {
                // Be honest about precision rather than inventing a door time.
                Label("Start time is approximate", systemImage: "clock.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let price = event.priceLabel {
                Text(price)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(event.isFree ? .green : .primary)
            }
        }
    }

    private var venueBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.venue.name).font(.headline)
            if !event.venue.shortAddress.isEmpty {
                Text(event.venue.shortAddress)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let location = locationManager.currentLocation {
                Text("\(Formatters.distance(event.distance(from: location))) away")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lineup: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Line-up").font(.headline)
            Text(event.performers.joined(separator: ", "))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let url = event.url {
                Button {
                    openURL(url)
                } label: {
                    Label("Tickets & details", systemImage: "ticket")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            Button {
                openInMaps()
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 4)
    }

    private var sourceFootnote: some View {
        Text("Listed by \(event.source.replacingOccurrences(of: "_", with: " "))")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func openInMaps() {
        let placemark = MKPlacemark(coordinate: event.coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = event.venue.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
}
