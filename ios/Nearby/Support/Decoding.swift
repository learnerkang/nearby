import Foundation

/// The pipeline emits two shapes of ISO-8601 instant: event times are whole
/// seconds ("2026-09-05T17:00:00Z") while `generated_at` carries microseconds
/// ("2026-09-06T23:37:05.910683Z"). `.iso8601` handles only the first, so a
/// snapshot would fail to decode on the manifest alone. Try both.
enum ISO8601 {
    static func date(from string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: string) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}

extension JSONDecoder {
    /// The decoder to use for anything coming from the snapshot.
    static func nearby() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not an ISO-8601 instant: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}
