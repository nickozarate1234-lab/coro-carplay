import Foundation
import LyricsCore

struct LyricsResult: Sendable {
    let lines: [LyricLine]
    let notice: String
}

actor LyricsClient {
    private var cache: [String: LyricsResult] = [:]
    private var cacheOrder: [String] = []
    private var allowedAfter = Date.distantPast

    func get(for track: Track) async throws -> LyricsResult {
        if let stored = cache[track.id] { return stored }
        guard track.duration > 0, track.duration <= 3600 else {
            return LyricsResult(lines: [], notice: "No hay letra disponible para esta pista.")
        }
        let artist = track.artists.first ?? ""
        let query: [URLQueryItem] = [
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: artist),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(Int(track.duration.rounded())))
        ]
        var result: LyricsRecord?
        if let data = try await fetch(path: "/api/get", items: query) {
            result = try JSONDecoder().decode(LyricsRecord.self, from: data)
        }
        // If the exact signature has no synchronized version, consider only
        // matching title, artist and duration. Never invent timing for plain text.
        if result?.syncedLyrics == nil, result?.instrumental != true {
            try await Task.sleep(nanoseconds: 300_000_000)
            if let data = try await fetch(path: "/api/search", items: [
                .init(name: "track_name", value: track.title), .init(name: "artist_name", value: artist)
            ]) {
                let records = try JSONDecoder().decode([LyricsRecord].self, from: data)
                if let alternative = LyricsMatcher.best(in: records, for: track) { result = alternative }
            }
        }
        try Task.checkCancellation()
        let lines = LRCParser.parse(result?.syncedLyrics ?? "")
        let notice: String
        if result?.instrumental == true { notice = "Pista instrumental" }
        else if lines.isEmpty { notice = "Esta canción no tiene letra sincronizada en LRCLIB." }
        else { notice = "" }
        let resolved = LyricsResult(lines: lines, notice: notice)
        cache[track.id] = resolved
        cacheOrder.removeAll { $0 == track.id }
        cacheOrder.append(track.id)
        while cacheOrder.count > 80 { cache.removeValue(forKey: cacheOrder.removeFirst()) }
        return resolved
    }

    private func fetch(path: String, items: [URLQueryItem]) async throws -> Data? {
        if allowedAfter > Date() {
            try await Task.sleep(nanoseconds: UInt64(min(allowedAfter.timeIntervalSinceNow, 3600) * 1_000_000_000))
            if allowedAfter > Date() { throw CoroError.rateLimited(allowedAfter.timeIntervalSinceNow) }
        }
        try Task.checkCancellation()
        var url = URLComponents(string: "https://lrclib.net" + path)!
        url.queryItems = items
        var request = URLRequest(url: url.url!)
        let projectURL = Bundle.main.object(forInfoDictionaryKey: "CoroProjectURL") as? String ?? ""
        let identification = projectURL.isEmpty ? "Coro/0.1 personal lyrics companion" : "Coro/0.1 (\(projectURL))"
        request.setValue(identification, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await Network.request(request)
            if response.statusCode == 404 { return nil }
            guard response.statusCode == 200, data.count <= 2_000_000 else {
                throw CoroError.message("No se pudo consultar la letra (\(response.statusCode)).")
            }
            return data
        } catch CoroError.rateLimited(let seconds) {
            let wait = seconds + Double.random(in: 0...max(0.1, min(5, seconds * 0.2)))
            allowedAfter = Date().addingTimeInterval(wait)
            throw CoroError.rateLimited(wait)
        }
    }

    func clear() { cache.removeAll(); cacheOrder.removeAll() }
}
