import XCTest
@testable import Dartiqo

final class MatchUploadTests: XCTestCase {
    /// X01 101 na dva legy proti botovi: první leg zavře hráč, ve druhém bot přehodí.
    private func playedMatch(owner: UUID) throws -> Match {
        var config = GameConfig(startingScore: 101, legsToWin: 2)
        config.options = MatchOptions()
        var match = Match(config: config, players: [Player(id: owner, name: "Já"), Player(name: "Robin", botLevel: 7, botStyle: .balanced, adaptiveBot: true)])
        try match.submit([Dart(20, 3), Dart(20), Dart(1)])
        try match.submit([Dart(20), Dart(20), Dart(20)])
        try match.submit([Dart(5, 2), Dart(5, 2)])
        match.nextLeg()
        try match.submit([Dart(20, 3), Dart(20, 3)])
        try match.submit([Dart(19, 3), Dart(19), Dart.miss])
        try match.submit([Dart(20), Dart(20), Dart(20)])
        try match.submit([Dart(9), Dart(8, 2)])
        return match
    }

    @MainActor
    func testEncodesPlayersVisitsAndRawMatch() throws {
        let owner = UUID()
        let match = try playedMatch(owner: owner)
        XCTAssertTrue(match.finished)
        XCTAssertEqual(match.winner, 0)

        let friend = Friend(owner: owner, name: "Petr", username: "petr")
        let upload = MatchUpload(match: match, owner: owner, friends: [friend], profiles: [])
        XCTAssertEqual(upload.status, "finished")
        XCTAssertEqual(upload.players.map(\.kind), ["owner", "bot"])
        XCTAssertEqual(upload.players[1].bot?.level, 7)
        XCTAssertEqual(upload.players[1].bot?.adaptive, true)
        XCTAssertEqual(upload.visits.count, 7)
        XCTAssertEqual(upload.visits[3].bust, true)
        XCTAssertEqual(upload.visits.filter(\.checkout).count, 2)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(upload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((json["config"] as? [String: Any])?["mode"] as? String, "x01")
        XCTAssertNotNil(json["match"] as? [String: Any])
        if let path = ProcessInfo.processInfo.environment["DARTIQO_UPLOAD_SAMPLE"] {
            try data.write(to: URL(fileURLWithPath: path))
        }
    }

    @MainActor
    func testFriendAndGuestKinds() throws {
        let owner = UUID()
        let friendID = UUID()
        let match = Match(config: GameConfig(), players: [Player(id: owner, name: "Já"), Player(id: friendID, name: "Petr"), Player(name: "Host")])
        let upload = MatchUpload(match: match, owner: owner, friends: [Friend(id: friendID, owner: owner, name: "Petr", username: "petr")], profiles: [])
        XCTAssertEqual(upload.players.map(\.kind), ["owner", "friend", "guest"])
        XCTAssertEqual(upload.players[1].username, "petr")
        XCTAssertEqual(upload.status, "abandoned")
    }
}
