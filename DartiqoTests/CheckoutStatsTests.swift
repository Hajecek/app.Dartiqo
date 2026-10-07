import XCTest
@testable import Dartiqo

final class CheckoutStatsTests: XCTestCase {
    private func match(start: Int = 101, out: OutRule = .double, legs: Int = 2) -> Match {
        Match(config: GameConfig(mode: .x01, startingScore: start, outRule: out, legsToWin: legs), players: [Player(name: "A")])
    }

    func testCountsDartsAtDoubleAndHits() throws {
        var game = match()
        // 101 → 41 → 40, poslední šipka S20 je pokus na D20.
        try game.submit([Dart(20, 3), Dart(1), Dart(20)])
        // 20: D10 netrefí (S10 → 10), pak D5 trefí.
        try game.submit([Dart(10, 2)], allowPartial: true)

        let stats = CheckoutStats.make(from: game, player: 0)
        XCTAssertEqual(stats.attempts, 2)
        XCTAssertEqual(stats.hits, 1)
        XCTAssertEqual(stats.doubles[20]?.attempts, 1)
        XCTAssertEqual(stats.doubles[20]?.hits, 0)
        XCTAssertEqual(stats.doubles[10]?.attempts, 1)
        XCTAssertEqual(stats.doubles[10]?.hits, 1)
        XCTAssertEqual(stats.checkouts, [20])
        XCTAssertEqual(stats.percentage ?? 0, 50, accuracy: 0.001)
    }

    func testBustStopsCountingAndFiftyIsBull() throws {
        var game = match()
        try game.submit([Dart(17, 3), Dart(0), Dart(0)])   // 101 → 50
        try game.submit([Dart(20, 3)], allowPartial: true)  // pokus na bull, přehoz
        let stats = CheckoutStats.make(from: game, player: 0)
        XCTAssertEqual(stats.doubles[25]?.attempts, 1)
        XCTAssertEqual(stats.attempts, 1)
        XCTAssertEqual(stats.hits, 0)
        XCTAssertTrue(stats.checkouts.isEmpty)
    }

    func testFilterByLegAndStraightOutIsEmpty() throws {
        var game = match()
        try game.submit([Dart(20, 3), Dart(1), Dart(20, 2)])  // 101 → 0 zavřeno na D20
        game.nextLeg()
        try game.submit([Dart(20, 3), Dart(1), Dart(0)])      // leg 2: 40, pokus na D20
        XCTAssertEqual(CheckoutStats.make(from: game, player: 0, leg: 1).hits, 1)
        XCTAssertEqual(CheckoutStats.make(from: game, player: 0, leg: 2).attempts, 1)
        XCTAssertEqual(CheckoutStats.make(from: game, player: 0, leg: 2).hits, 0)

        var straight = match(out: .straight)
        try straight.submit([Dart(20, 3), Dart(1), Dart(20)])
        XCTAssertFalse(CheckoutStats.make(from: straight, player: 0).hasData)
    }
}
