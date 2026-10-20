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

    func testSideStatsSplitBothPlayers() {
        var game = match(opponent: Player(id: friend, name: "Pepa"), winner: 0)
        game.visits = [
            Visit(
                player: 0,
                leg: 1,
                darts: [Dart(20, 3, x: 0.1, y: 0.2), Dart(20, 3, x: 0.11, y: 0.2), Dart(20, 3, x: 0.12, y: 0.2)],
                credited: 180,
                bust: false,
                checkout: false,
                remaining: 321
            ),
            Visit(
                player: 1,
                leg: 1,
                darts: [Dart(1, x: 0.4, y: 0.1)],
                credited: 1,
                bust: false,
                checkout: false,
                remaining: 500
            )
        ]
        game.states[0].legs = 1
        let series = HeadToHead.series(from: [game], me: me, key: RivalKey(kind: .person(friend)))
        let mine = series?.side(me: me, mine: true)
        let theirs = series?.side(me: me, mine: false)
        XCTAssertEqual(mine?.oneEighties, 1)
        XCTAssertEqual(mine?.tons, 1)
        XCTAssertEqual(mine?.darts, 3)
        XCTAssertEqual(mine?.positioned.count, 3)
        XCTAssertEqual(mine?.legsWon, 1)
        XCTAssertEqual(theirs?.darts, 1)
        XCTAssertEqual(theirs?.oneEighties, 0)
        XCTAssertEqual(theirs?.positioned.count, 1)
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
