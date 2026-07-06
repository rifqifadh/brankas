import Foundation

/// Fetches global time from an HTTP Date header and computes offset from system clock.
/// Offset is applied via `TOTPService.timeOffset` so all TOTP generation uses network time.
struct TimeSyncService {
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case synced(offset: TimeInterval)
        case failed(String)
    }

    /// Current sync status — read by UI to show indicator
    private(set) static var status: SyncStatus = .idle

    /// Cached time offset (server - system) in seconds
    private static var cachedOffset: TimeInterval = 0
    /// Last successful sync timestamp
    private static var lastSynced: Date = .distantPast
    /// Minimum interval between syncs
    private static let minSyncInterval: TimeInterval = 300 // 5 minutes

    /// Synced offset, or 0 if never synced / expired
    static var offset: TimeInterval {
        let elapsed = Date().timeIntervalSince(lastSynced)
        guard elapsed < minSyncInterval else { return 0 }
        return cachedOffset
    }

    /// Fetch server time and update offset. Non-blocking — caller should `await`.
    /// On failure, offset stays at previous value (or 0).
    static func sync() async {
        let now = Date()
        // Throttle: don't re-sync if recently done
        guard now.timeIntervalSince(lastSynced) > minSyncInterval else { return }

        status = .syncing

        guard let serverDate = await fetchServerDate() else {
            status = .failed("Could not reach time server")
            return
        }

        cachedOffset = serverDate.timeIntervalSince1970 - now.timeIntervalSince1970
        lastSynced = now
        TOTPService.timeOffset = cachedOffset

        let absDrift = abs(cachedOffset)
        if absDrift < 1 {
            status = .synced(offset: 0)
        } else {
            status = .synced(offset: cachedOffset)
        }
    }

    /// Try multiple endpoints until one succeeds.
    private static func fetchServerDate() async -> Date? {
        let endpoints = [
            "https://www.apple.com",
            "https://www.google.com",
            "https://api.github.com",
            "https://www.cloudflare.com",
        ]
        for endpoint in endpoints {
            if let date = await fetchDate(from: endpoint) {
                return date
            }
        }
        return nil
    }

    /// Make HEAD request to a single endpoint, parse Date header.
    private static func fetchDate(from urlString: String) async -> Date? {
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5

        guard let response = try? await URLSession.shared.data(for: request).1 as? HTTPURLResponse,
              let dateString = response.allHeaderFields["Date"] as? String
        else { return nil }

        return parseHTTPDate(dateString)
    }

    /// Parse HTTP-date format: `EEE, dd MMM yyyy HH:mm:ss zzz`
    private static func parseHTTPDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        formatter.dateFormat = "E, dd MMM yyyy HH:mm:ss z"
        return formatter.date(from: string)
    }
}
