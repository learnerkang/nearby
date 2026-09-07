import CoreLocation
import Foundation

/// Venue identity and region-slot budgeting, kept free of app dependencies so
/// the geometry can be reasoned about - and tested - on its own.
enum VenueSelection {

    // MARK: - Identity

    /// Regions are keyed by rounded coordinates so that the same venue spelled
    /// differently by two sources still maps to one slot. Five decimal places
    /// is about one metre.
    ///
    /// The coordinates are recoverable from the string on purpose: iOS hands
    /// back only a region identifier when the user arrives, and a background
    /// relaunch has no state to look it up in.
    static func venueKey(lat: Double, lon: Double) -> String {
        String(format: "venue.%.5f,%.5f", lat, lon)
    }

    static func coordinate(fromVenueKey key: String) -> CLLocationCoordinate2D? {
        guard key.hasPrefix("venue.") else { return nil }
        let parts = key.dropFirst("venue.".count).split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Budgeting

    /// Take the nearest `limit` candidates, skipping any that sit within
    /// `clusterRadius` of one already taken.
    ///
    /// Rounded coordinates collapse a venue that two sources spell
    /// differently, but only when they agree on the position to the metre.
    /// They frequently do not: Ticketmaster lists the Eldorado casino twice,
    /// 48 m apart, and "Alpine" and "The Alpine" 41 m apart. Those are one
    /// building, and spending two of nineteen slots on it is two slots that a
    /// venue across town does not get. Downtown Reno alone claimed 22 slots
    /// for 11 buildings, so venues were being dropped for want of room.
    ///
    /// Candidates must already be sorted nearest-first; the first of a cluster
    /// wins, which keeps the region centred on the closest member.
    static func suppressingNearDuplicates<T>(
        _ candidates: [T],
        limit: Int,
        clusterRadius: CLLocationDistance,
        coordinate: (T) -> CLLocationCoordinate2D
    ) -> [T] {
        var kept: [T] = []
        var keptLocations: [CLLocation] = []

        for candidate in candidates {
            if kept.count >= limit { break }
            let c = coordinate(candidate)
            let location = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if keptLocations.contains(where: { $0.distance(from: location) <= clusterRadius }) {
                continue
            }
            kept.append(candidate)
            keptLocations.append(location)
        }
        return kept
    }

    /// Whether an event belongs to the region identified by `key`.
    ///
    /// Distance rather than string equality, because a region now stands for
    /// every venue within `clusterRadius` of it, not just the one whose
    /// coordinates named it. Standing at a suppressed venue puts the user well
    /// inside the surviving region - it is 350 m wide and they are within 150 m
    /// of its centre - so the arrival has to resolve to that venue's events.
    static func event(at coordinate: CLLocationCoordinate2D,
                      matchesKey key: String,
                      clusterRadius: CLLocationDistance) -> Bool {
        guard let centre = Self.coordinate(fromVenueKey: key) else { return false }
        let a = CLLocation(latitude: centre.latitude, longitude: centre.longitude)
        let b = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return a.distance(from: b) <= clusterRadius
    }
}
