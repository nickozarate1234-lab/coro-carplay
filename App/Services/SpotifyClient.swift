import Foundation
import LyricsCore

struct SpotifySnapshot {
    let track: Track
    let anchor: PlaybackAnchor
    let confirmedAt: Date
}

@MainActor
final class SpotifyClient {
    let auth: SpotifyAuth
    init(auth: SpotifyAuth) { self.auth = auth }

    func current() async throws -> SpotifySnapshot? {
        var token = try await auth.accessToken()
        for attempt in 0..<2 {
            let start = ProcessInfo.processInfo.systemUptime
            var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await Network.request(request)
            let end = ProcessInfo.processInfo.systemUptime
            if response.statusCode == 401, attempt == 0 {
                token = try await auth.accessToken(forceRefresh: true)
                continue
            }
            if response.statusCode == 204 { return nil }
            if response.statusCode == 401 { throw CoroError.unauthorized }
            if response.statusCode == 403 {
                throw CoroError.message("Spotify denegó el acceso. Revisa Premium, el Client ID y los usuarios autorizados de tu app.")
            }
            guard response.statusCode == 200 else {
                throw CoroError.message("Spotify no responde por ahora (\(response.statusCode)).")
            }
            let value = try JSONDecoder().decode(PlaybackResponse.self, from: data)
            guard value.currently_playing_type == "track", let song = value.item,
                  song.type == "track", song.is_local != true, let id = song.id,
                  let progress = value.progress_ms else { return nil }
            let track = Track(id: id, title: song.name, artists: song.artists.map(\.name),
                              album: song.album.name, duration: Double(song.duration_ms) / 1000,
                              spotifyURL: song.external_urls?["spotify"].flatMap { URL(string: $0) })
            // The Web API's timestamp is not a continuously updated playback clock.
            // Anchor the returned progress to the request midpoint, then use monotonic time.
            return SpotifySnapshot(track: track,
                                   anchor: PlaybackAnchor(position: Double(progress) / 1000, duration: track.duration,
                                                          observedAt: (start + end) / 2, isPlaying: value.is_playing),
                                   confirmedAt: Date())
        }
        throw CoroError.unauthorized
    }

    private struct PlaybackResponse: Decodable {
        let is_playing: Bool
        let progress_ms: Int?
        let currently_playing_type: String
        let item: Item?
        private enum CodingKeys: String, CodingKey { case is_playing, progress_ms, currently_playing_type, item }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            is_playing = try values.decode(Bool.self, forKey: .is_playing)
            progress_ms = try values.decodeIfPresent(Int.self, forKey: .progress_ms)
            currently_playing_type = try values.decode(String.self, forKey: .currently_playing_type)
            if currently_playing_type == "track" {
                item = try values.decodeIfPresent(Item.self, forKey: .item)
            } else {
                item = nil
            }
        }
    }
    private struct Item: Decodable {
        let id: String?
        let type: String
        let name: String
        let duration_ms: Int
        let is_local: Bool?
        let artists: [Artist]
        let album: Album
        let external_urls: [String: String]?
    }
    private struct Artist: Decodable { let name: String }
    private struct Album: Decodable { let name: String }
}
