import ActivityKit
import Foundation

struct CoroAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var line: String
        var nextLine: String
        var notice: String
        var isPlaying: Bool
        var isDemo: Bool
    }
    var sessionID: UUID
}
