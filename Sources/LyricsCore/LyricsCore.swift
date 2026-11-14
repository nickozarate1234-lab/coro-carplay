import Foundation

public struct LyricLine: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let text: String
    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public enum LRCParser {
    /// Preserves timed empty lines: they mark instrumental breaks.
    /// LRC offsets are milliseconds. Positive offsets advance the text.
    public static func parse(_ input: String) -> [LyricLine] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]"#)
        let offsetPattern = try! NSRegularExpression(pattern: #"(?im)^\s*\[offset:([+-]?\d+)\]\s*$"#)
        let whole = input as NSString
        var offset: Double = 0
        if let match = offsetPattern.matches(in: input, range: NSRange(location: 0, length: whole.length)).last {
            offset = (Double(whole.substring(with: match.range(at: 1))) ?? 0) / 1000
        }
        var entries: [(line: LyricLine, order: Int)] = []
        for raw in input.components(separatedBy: .newlines) {
            let source = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let ns = source as NSString
            let matches = stamp.matches(in: source, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last, matches.first?.range.location == 0 else { continue }
            let text = ns.substring(from: NSMaxRange(last.range)).trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minute = Double(ns.substring(with: match.range(at: 1))),
                      let second = Double(ns.substring(with: match.range(at: 2))), second < 60 else { continue }
                let fractionRange = match.range(at: 3)
                let fraction = fractionRange.location == NSNotFound ? 0 :
                    (Double("0." + ns.substring(with: fractionRange)) ?? 0)
                let time = max(0, minute * 60 + second + fraction - offset)
                entries.append((LyricLine(time: time, text: text), entries.count))
            }
        }
        entries.sort { $0.line.time == $1.line.time ? $0.order < $1.order : $0.line.time < $1.line.time }
        var result: [LyricLine] = []
        for entry in entries {
            if let previous = result.last, abs(previous.time - entry.line.time) < 0.00001 {
                if previous.text == entry.line.text { continue }
                // Two simultaneous voices / translations stay on the same line.
                let combined = [previous.text, entry.line.text].filter { !$0.isEmpty }.joined(separator: " · ")
                result[result.count - 1] = LyricLine(time: previous.time, text: combined)
            } else {
                result.append(entry.line)
            }
        }
        return result
    }

    public static func index(at position: TimeInterval, in lines: [LyricLine]) -> Int? {
        guard position.isFinite, let first = lines.first, position >= first.time else { return nil }
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= position { low = middle + 1 } else { high = middle }
        }
        return low - 1
    }
}

public struct PlaybackAnchor: Sendable {
    public let position: TimeInterval
    public let duration: TimeInterval
    public let observedAt: TimeInterval
    public let isPlaying: Bool
    public init(position: TimeInterval, duration: TimeInterval, observedAt: TimeInterval, isPlaying: Bool) {
        self.position = position
        self.duration = duration
        self.observedAt = observedAt
        self.isPlaying = isPlaying
    }
    public func position(at uptime: TimeInterval) -> TimeInterval {
        let elapsed = isPlaying ? max(0, uptime - observedAt) : 0
        return min(max(0, duration), max(0, position + elapsed))
    }
    public func isFresh(at uptime: TimeInterval, lifetime: TimeInterval = 20) -> Bool {
        uptime >= observedAt && uptime - observedAt <= lifetime
    }
}

public struct Track: Equatable, Sendable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String
    public let duration: TimeInterval
    public let spotifyURL: URL?
    public init(id: String, title: String, artists: [String], album: String, duration: TimeInterval, spotifyURL: URL?) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.duration = duration
        self.spotifyURL = spotifyURL
    }
}

public struct LyricsRecord: Decodable, Sendable {
    public let id: Int
    public let trackName: String
    public let artistName: String
    public let duration: Double
    public let instrumental: Bool
    public let plainLyrics: String?
    public let syncedLyrics: String?
    public init(id: Int, trackName: String, artistName: String, duration: Double, instrumental: Bool,
                plainLyrics: String? = nil, syncedLyrics: String? = nil) {
        self.id = id; self.trackName = trackName; self.artistName = artistName
        self.duration = duration; self.instrumental = instrumental
        self.plainLyrics = plainLyrics; self.syncedLyrics = syncedLyrics
    }
}

public enum LyricsMatcher {
    public static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    public static func best(in records: [LyricsRecord], for track: Track) -> LyricsRecord? {
        let candidates = records.filter { record in
            abs(record.duration - track.duration) <= 2 && normalized(record.trackName) == normalized(track.title) &&
            track.artists.contains { normalized($0) == normalized(record.artistName) }
        }
        return candidates.sorted {
            let leftSynced = !($0.syncedLyrics ?? "").isEmpty
            let rightSynced = !($1.syncedLyrics ?? "").isEmpty
            if leftSynced != rightSynced { return leftSynced }
            return abs($0.duration - track.duration) < abs($1.duration - track.duration)
        }.first
    }
}

public enum RetryDelay {
    public static func seconds(from value: String?, now: Date = Date()) -> TimeInterval {
        guard let value else { return 30 }
        if let seconds = Double(value), seconds.isFinite { return max(1, seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: value) { return max(1, date.timeIntervalSince(now)) }
        return 30
    }
}
