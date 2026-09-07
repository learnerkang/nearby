import CoreLocation
import MapKit
import SwiftUI

struct MapScreen: View {
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var settings: UserSettings
    @EnvironmentObject private var locationManager: LocationManager

    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: Event?
    @State private var now = Date.now

    private var location: CLLocation? { locationManager.currentLocation }

    private var events: [Event] {
        store.visibleEvents(from: location, settings: settings, now: now)
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera) {
                UserAnnotation()

                ForEach(events) { event in
                    Annotation(
                        event.venue.name,
                        coordinate: event.coordinate,
                        anchor: .bottom
                    ) {
                        pin(for: event)
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { CategoryFilterMenu() }
            }
            .sheet(item: $selected) { event in
                NavigationStack { EventDetailView(event: event) }
                    .presentationDetents([.medium, .large])
            }
            .onAppear(perform: frameCamera)
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) {
                now = $0
            }
            .overlay(alignment: .bottom) {
                if events.isEmpty && store.hasLoaded {
                    Text("No events within \(Int(settings.browseRadiusMiles)) miles")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 24)
                }
            }
        }
    }

    /// A pin that reads as "what and when" at a glance: category colour, plus
    /// a red ring for anything happening right now.
    private func pin(for event: Event) -> some View {
        let isNow = event.isHappeningNow(asOf: now)
        return Button {
            selected = event
        } label: {
            Image(systemName: event.category.symbolName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(event.category.tint, in: Circle())
                .overlay(Circle().strokeBorder(isNow ? .red : .white, lineWidth: isNow ? 3 : 2))
                .shadow(radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title) at \(event.venue.name)")
    }

    /// Start framed on the user if we have a fix, otherwise on the region the
    /// snapshot covers - never on a default that shows the wrong continent.
    private func frameCamera() {
        if let location {
            camera = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 20_000,
                longitudinalMeters: 20_000
            ))
        } else {
            camera = .region(MKCoordinateRegion(
                center: AppConfig.fallbackCenter,
                latitudinalMeters: 30_000,
                longitudinalMeters: 30_000
            ))
        }
    }
}
