import XCTest
@testable import Dartiqo

final class CommentaryCueTests: XCTestCase {
    func testScoresCoverOneThroughOneEighty() {
        XCTAssertEqual(CommentaryCue.scores.count, 180)
        XCTAssertEqual(CommentaryCue.scores.first?.id, "score-1")
        XCTAssertEqual(CommentaryCue.scores.last?.id, "score-180")
    }

    func testCelebrationIsSeparateFromScore() {
        XCTAssertEqual(CommentaryCue.celebration180.id, "celebration-180")
        XCTAssertNotEqual(CommentaryCue.celebration180.id, CommentaryCue.score(180).id)
        XCTAssertTrue(CommentaryCue.specials.contains(.celebration180))
    }

    func testOneEightyPrefersCelebrationThenScore() {
        let order = CommentaryCue.playbackOrder(score: 180, spoken: nil, checkout: false, matchWon: false)
        XCTAssertEqual(order.map(\.id), ["celebration-180", "score-180"])
    }

    func testWinningCheckoutPrefersWinThenCheckoutThenScore() {
        let order = CommentaryCue.playbackOrder(score: 40, spoken: nil, checkout: true, matchWon: true)
        XCTAssertEqual(order.map(\.id), ["match-win", "checkout", "score-40"])
    }

    func testBustIgnoresTheNumber() {
        let order = CommentaryCue.playbackOrder(score: 26, spoken: "Přehoz", checkout: false, matchWon: false)
        XCTAssertEqual(order.map(\.id), ["bust"])
    }

    func testZeroAndPlainScore() {
        XCTAssertEqual(CommentaryCue.playbackOrder(score: 0, spoken: nil, checkout: false, matchWon: false).map(\.id), ["zero"])
        XCTAssertEqual(CommentaryCue.playbackOrder(score: 26, spoken: nil, checkout: false, matchWon: false).map(\.id), ["score-26"])
    }

    func testLegacyStoreDecodesWithoutCommentator() throws {
        let json = #"{"version":1,"profiles":[],"matches":[],"activeMatches":{},"haptics":true,"voice":false,"appearance":"dark","biometricLock":false}"#
        let stored = try JSONDecoder().decode(StoredData.self, from: Data(json.utf8))
        XCTAssertNil(stored.commentators)
    }

    func testSaveReplacesClipForTheSameSituation() async throws {
        let owner = UUID()
        let cue = CommentaryCue.score(100)
        let first = FileManager.default.temporaryDirectory.appendingPathComponent("cue-\(UUID().uuidString).m4a")
        let second = FileManager.default.temporaryDirectory.appendingPathComponent("cue-\(UUID().uuidString).m4a")
        try Data("prvni".utf8).write(to: first)
        try Data("druha-nahravka".utf8).write(to: second)
        try await MainActor.run {
            let library = CommentaryLibrary()
            defer { library.deleteAll(owner: owner) }
            try library.save(owner: owner, cue: cue, from: first)
            try library.save(owner: owner, cue: cue, from: second)
            XCTAssertEqual(library.count(owner: owner), 1)
            let stored = try Data(contentsOf: library.fileURL(owner: owner, cue: cue))
            XCTAssertEqual(stored, Data("druha-nahravka".utf8))
            library.delete(owner: owner, cue: cue)
            XCTAssertFalse(library.exists(owner: owner, cue: cue))
        }
    }
}
