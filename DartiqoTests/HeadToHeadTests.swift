import XCTest
@testable import Dartiqo

final class HeadToHeadTests: XCTestCase {
    private let me = UUID()
    private let friend = UUID()

    private func match(
        opponent: Player,
        winner: Int?,
        completed: Date = Date(),
        ghostKind: GhostKind? = nil
    ) -> Match {
        var game = Match(
            config: GameConfig(mode: .x01, startingScore: 501, outRule: .double, legsToWin: 1),
            players: [Player(id: me, name: "Já"), opponent]
        )
        game.finished = true
        game.completedAt = completed
        game.winner = winner
        if winner == 0 { game.states[0].legs = 1 }
        if winner == 1 { game.states[1].legs = 1 }
        if let ghostKind {
            game.ghostKind = ghostKind
            game.ghostPlayerIndex = 1
        }
        return game
    }

    func testBotLevelAggregatesAcrossFreshUUIDs() {
        let a = match(opponent: Player(name: "Bot A", botLevel: 10), winner: 0, completed: Date().addingTimeInterval(-100))
        let b = match(opponent: Player(name: "Bot B", botLevel: 10), winner: 1, completed: Date())
        let rivals = HeadToHead.rivals(from: [a, b], me: me)
        XCTAssertEqual(rivals.count, 1)
        XCTAssertEqual(rivals[0].myWins, 1)
        XCTAssertEqual(rivals[0].theirWins, 1)
        XCTAssertEqual(rivals[0].played, 2)
        XCTAssertEqual(rivals[0].opponentBotLevel, 10)
    }

    func testFriendUUIDKeepsSeries() {
        let win = match(opponent: Player(id: friend, name: "Pepa"), winner: 0)
        let loss = match(opponent: Player(id: friend, name: "Pepa"), winner: 1)
        let draw = match(opponent: Player(id: friend, name: "Pepa"), winner: nil)
        let series = HeadToHead.series(from: [win, loss, draw], me: me, key: RivalKey(kind: .person(friend)))
        XCTAssertEqual(series?.myWins, 1)
        XCTAssertEqual(series?.theirWins, 1)
        XCTAssertEqual(series?.draws, 1)
    }

    func testDifferentBotLevelsAreSeparateRivals() {
        let low = match(opponent: Player(name: "Easy", botLevel: 2), winner: 0)
        let high = match(opponent: Player(name: "Hard", botLevel: 9), winner: 1)
        let rivals = HeadToHead.rivals(from: [low, high], me: me)
        XCTAssertEqual(rivals.count, 2)
    }

    func testGhostKindIsSeparateKey() {
        let ghost = match(
            opponent: Player(name: "Ghost · 90"),
            winner: 0,
            ghostKind: .best
        )
        let rivals = HeadToHead.rivals(from: [ghost], me: me)
        XCTAssertEqual(rivals.count, 1)
        XCTAssertTrue(rivals[0].isGhost)
        XCTAssertEqual(rivals[0].key, RivalKey(kind: .ghost(GhostKind.best.rawValue)))
    }
}
