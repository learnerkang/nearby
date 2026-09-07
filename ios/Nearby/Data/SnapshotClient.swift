import Foundation
import OSLog

enum SnapshotError: LocalizedError {
    case badStatus(Int)
    case unsupportedSchema(Int)
    case noCachedData

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            "The event server returned an error (\(code))."
        case .unsupportedSchema(let schema):
            "This snapshot needs a newer version of the app (format \(schema))."
        case .noCachedData:
            "No events have been downloaded yet."
        }
    }
}

/// Downloads and caches the event snapshot.
///
/// The flow is deliberately two-step: fetch the ~200 byte manifest, and only
/// pull the ~70 KB payload when its etag differs from what is already on disk.
/// A background refresh that finds nothing new costs almost no data or battery.
actor SnapshotClient {
    static let shared = SnapshotClient()

    private let log = Logger(subsystem: "com.example.nearby", category: "snapshot")
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.waitsForConnectivity = true
            config.timeoutIntervalForRequest = 30
            // We do our own etag check against the manifest, and a stale
            // URLCache hit would defeat it.
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Disk cache

    private var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                           in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("snapshot.json")
    }

    func loadCached() throws -> Snapshot {
        guard let data = try? Data(contentsOf: cacheURL) else {
            throw SnapshotError.noCachedData
        }
        return try JSONDecoder.nearby().decode(Snapshot.self, from: data)
    }

    var cachedETag: String? {
        try? loadCached().etag
    }

    // MARK: - Network

    /// Returns a fresh snapshot, or `nil` when the server's copy matches what
    /// is already cached.
    func fetchIfChanged() async throws -> Snapshot? {
        let manifest = try await fetchManifest()

        guard manifest.schema <= Snapshot.supportedSchema else {
            throw SnapshotError.unsupportedSchema(manifest.schema)
        }
        if let cached = cachedETag, cached == manifest.etag {
            log.debug("snapshot unchanged (etag \(manifest.etag, privacy: .public))")
            return nil
        }

        let snapshot = try await fetchFullSnapshot()
        try persist(snapshot)
        log.info("snapshot updated: \(snapshot.count, privacy: .public) events")
        return snapshot
    }

    private func fetchManifest() async throws -> SnapshotManifest {
        let data = try await get(AppConfig.manifestURL)
        return try JSONDecoder.nearby().decode(SnapshotManifest.self, from: data)
    }

    private func fetchFullSnapshot() async throws -> Snapshot {
        let data = try await get(AppConfig.eventsURL)
        return try JSONDecoder.nearby().decode(Snapshot.self, from: data)
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw SnapshotError.badStatus(http.statusCode)
        }
        return data
    }

    private func persist(_ snapshot: Snapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // Atomic so a crash mid-write cannot leave a half-file that fails to
        // decode on next launch.
        try encoder.encode(snapshot).write(to: cacheURL, options: .atomic)
    }
}
