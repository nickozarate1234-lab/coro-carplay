import XCTest
@testable import LyricsCore

final class LyricsCoreTests: XCTestCase {
    func testFractionsAndRepeatedTimestamps() {
        let lines = LRCParser.parse("[ar:Test]\n[00:01.5][00:03.125]Uno\n[00:02.50]Dos")
        XCTAssertEqual(lines.map(\.time), [1.5, 2.5, 3.125])
        XCTAssertEqual(lines.map(\.text), ["Uno", "Dos", "Uno"])
    }
    func testPositiveOffsetAdvancesLyrics() {
        XCTAssertEqual(LRCParser.parse("[offset:500]\n[00:02.00]Hola").first?.time, 1.5)
    }
    func testNegativeOffsetDelaysLyrics() {
        XCTAssertEqual(LRCParser.parse("[offset:-500]\n[00:02.00]Hola").first?.time, 2.5)
    }
    func testEmptyLineMarksInstrumentalBreak() {
        let lines = LRCParser.parse("[00:01]Voz\n[00:04]\n[00:06]Otra voz")
        XCTAssertEqual(lines[LRCParser.index(at: 5, in: lines)!].text, "")
    }
    func testInvalidTimestampIgnored() {
        XCTAssertEqual(LRCParser.parse("[00:72]Mal\n[ar:Una banda]\nSin tiempos"), [])
    }
    func testDuplicateAndSimultaneousLines() {
        let lines = LRCParser.parse("[00:01]Uno\n[00:01]Uno\n[00:01]Dos")
        XCTAssertEqual(lines, [LyricLine(time: 1, text: "Uno · Dos")])
    }
    func testSeekAndExactBoundary() {
        let lines = LRCParser.parse("[00:02]A\n[00:05]B\n[00:08]C")
        XCTAssertNil(LRCParser.index(at: 1.9, in: lines))
        XCTAssertEqual(LRCParser.index(at: 8, in: lines), 2)
        XCTAssertEqual(LRCParser.index(at: 3, in: lines), 0)
        XCTAssertEqual(LRCParser.index(at: 5, in: lines), 1)
        XCTAssertNil(LRCParser.index(at: .nan, in: lines))
    }
    func testPausedPlaybackDoesNotAdvance() {
        let anchor = PlaybackAnchor(position: 12, duration: 30, observedAt: 100, isPlaying: false)
        XCTAssertEqual(anchor.position(at: 110), 12)
    }
    func testPlaybackClampsAtEnd() {
        let anchor = PlaybackAnchor(position: 29, duration: 30, observedAt: 100, isPlaying: true)
        XCTAssertEqual(anchor.position(at: 120), 30)
    }
    func testStalePlaybackIsNotTreatedAsLive() {
        let anchor = PlaybackAnchor(position: 10, duration: 30, observedAt: 100, isPlaying: true)
        XCTAssertTrue(anchor.isFresh(at: 120))
        XCTAssertFalse(anchor.isFresh(at: 120.1))
        XCTAssertFalse(anchor.isFresh(at: 99))
    }
    func testNegativePositionClamped() {
        XCTAssertEqual(PlaybackAnchor(position: -5, duration: 20, observedAt: 10, isPlaying: false).position(at: 12), 0)
    }
    func testMatchingRejectsAnotherVersionAndArtist() {
        let track = Track(id: "demo", title: "Canción", artists: ["Autor"], album: "Álbum", duration: 180, spotifyURL: nil)
        let wrong = [
            LyricsRecord(id: 1, trackName: "Canción (Live)", artistName: "Autor", duration: 180, instrumental: false),
            LyricsRecord(id: 2, trackName: "Canción", artistName: "Otro", duration: 180, instrumental: false),
            LyricsRecord(id: 3, trackName: "Canción", artistName: "Autor", duration: 190, instrumental: false)
        ]
        XCTAssertNil(LyricsMatcher.best(in: wrong, for: track))
        let match = LyricsRecord(id: 4, trackName: "cancion", artistName: "AUTOR", duration: 181, instrumental: false, syncedLyrics: "[00:01]Sí")
        XCTAssertEqual(LyricsMatcher.best(in: wrong + [match], for: track)?.id, 4)
    }
    func testSyncedVersionPreferred() {
        let track = Track(id: "a", title: "A", artists: ["B"], album: "C", duration: 180, spotifyURL: nil)
        let plain = LyricsRecord(id: 1, trackName: "A", artistName: "B", duration: 180, instrumental: false, plainLyrics: "A")
        let timed = LyricsRecord(id: 2, trackName: "A", artistName: "B", duration: 181, instrumental: false, syncedLyrics: "[00:01]A")
        XCTAssertEqual(LyricsMatcher.best(in: [plain, timed], for: track)?.id, 2)
    }
    func testRetryAfterSecondsAndDate() {
        XCTAssertEqual(RetryDelay.seconds(from: "120"), 120)
        XCTAssertEqual(RetryDelay.seconds(from: "-1"), 1)
        XCTAssertEqual(RetryDelay.seconds(from: nil), 30)
        XCTAssertEqual(RetryDelay.seconds(from: "n/a"), 30)
        XCTAssertEqual(RetryDelay.seconds(from: "Thu, 01 Jan 1970 00:01:00 GMT", now: Date(timeIntervalSince1970: 0)), 60)
    }
}
