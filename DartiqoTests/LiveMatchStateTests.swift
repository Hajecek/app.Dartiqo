import XCTest
@testable import Dartiqo

final class LiveMatchStateTests: XCTestCase {
    @MainActor
    func testPendingDartsShowInScoreAndCheckout() throws {
        var match = Match(config: GameConfig(startingScore: 301), players: [Player(name: "Já"), Player(name: "Bot", botLevel: 4)])
        try match.submit([Dart(20, 3), Dart(20, 3), Dart(20, 3)])
        try match.submit([Dart(1), Dart(5), Dart(20)])
        try match.recordDart(Dart(20, 3))

        let state = LiveMatchState(match: match)
        XCTAssertEqual(state.status, "live")
        XCTAssertEqual(state.mode, "x01")
        XCTAssertEqual(state.active, 0)
        XCTAssertEqual(state.players[0].score, "61")
        XCTAssertEqual(state.players[1].score, "275")
        XCTAssertTrue(state.players[1].bot)
        XCTAssertEqual(state.currentDarts, ["T20"])
        XCTAssertFalse(state.players[0].checkout.isEmpty)
        XCTAssertEqual(state.players[1].checkout, "")
        XCTAssertEqual(state.visits.map(\.score), [180, 26])
        XCTAssertEqual(state.visits[0].darts, ["T20", "T20", "T20"])
        XCTAssertEqual(state.visits.map(\.leg), [1, 1])
        XCTAssertEqual(state.visits.map(\.set), [1, 1])
    }

    @MainActor
    func testEncodesFieldsTheServerExpects() throws {
        var match = Match(config: GameConfig(), players: [Player(name: "Já")])
        try match.submit([Dart(25, 2), Dart(25), Dart.miss])
        var state = LiveMatchState(match: match)
        state.seq = 7
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(state)) as? [String: Any])

        XCTAssertEqual(json["seq"] as? Int, 7)
        XCTAssertNotNil(json["startedAt"] as? String)
        XCTAssertNil(json["winner"])
        let players = try XCTUnwrap(json["players"] as? [[String: Any]])
        XCTAssertEqual(players.first?["score"] as? String, "426")
        let visits = try XCTUnwrap(json["visits"] as? [[String: Any]])
        XCTAssertEqual(visits.first?["darts"] as? [String], ["BULL", "25", "MISS"])
    }
}
