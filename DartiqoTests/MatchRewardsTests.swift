import XCTest
@testable import Dartiqo

final class MatchRewardsTests: XCTestCase {
    func testWinAndLossBands() {
        var win = Match(config: GameConfig(), players: [Player(name: "Já"), Player(name: "Soupeř")])
        win.finished = true
        win.winner = 0
        win.states[0].legs = 2
        win.visits = [
            Visit(player: 0, leg: 1, darts: [Dart(20, 1), Dart(20, 1), Dart(20, 1)], credited: 60, bust: false, checkout: false, remaining: 441)
        ]
        let winXP = MatchRewards.award(match: win, playerID: win.players[0].id)
        XCTAssertEqual(winXP.lines.first { $0.id == "finish" }?.amount, 40)
        XCTAssertEqual(winXP.lines.first { $0.id == "win" }?.amount, 50)
        XCTAssertNil(winXP.lines.first { $0.id == "loss" })

        var loss = win
        loss.winner = 1
        let lossXP = MatchRewards.award(match: loss, playerID: loss.players[0].id)
        XCTAssertEqual(lossXP.lines.first { $0.id == "loss" }?.amount, -25)
        XCTAssertNil(lossXP.lines.first { $0.id == "win" })
    }

    func testAverageBandIsRangeNotPerPoint() {
        var match = Match(config: GameConfig(), players: [Player(name: "Já")])
        // average 60 → pásmo 60–69 = 35 XP
        match.visits = [
            Visit(player: 0, leg: 1, darts: [Dart(20, 1), Dart(20, 1), Dart(20, 1)], credited: 60, bust: false, checkout: false, remaining: 441)
        ]
        match.finished = true
        let xp = MatchRewards.award(match: match, playerID: match.players[0].id)
        XCTAssertEqual(xp.lines.first { $0.id == "average" }?.amount, 35)
        XCTAssertTrue(xp.lines.first { $0.id == "average" }?.detail.contains("60–69") == true)
    }

    func testCheckoutScoreBands() {
        var match = Match(config: GameConfig(), players: [Player(name: "Já")])
        match.visits = [
            Visit(player: 0, leg: 1, darts: [Dart(20, 2)], credited: 40, bust: false, checkout: true, remaining: 0),
            Visit(player: 0, leg: 2, darts: [Dart(20, 3), Dart(19, 3), Dart(25, 2)], credited: 170, bust: false, checkout: true, remaining: 0)
        ]
        match.finished = true
        match.states[0].legs = 2
        let xp = MatchRewards.award(match: match, playerID: match.players[0].id)
        let checkouts = xp.lines.filter { $0.id.hasPrefix("checkout-") }
        XCTAssertEqual(checkouts.count, 2)
        XCTAssertTrue(checkouts.contains { $0.amount == 8 })
        XCTAssertTrue(checkouts.contains { $0.amount == 55 })
    }

    func testCheckoutRateBand() {
        XCTAssertEqual(MatchRewards.checkoutRateBands.first { $0.contains(24) }?.xp, 12)
        XCTAssertEqual(MatchRewards.checkoutRateBands.first { $0.contains(24) }?.label, "20–29")
        XCTAssertEqual(MatchRewards.averageBands.first { $0.contains(55.2) }?.label, "50–59")
        XCTAssertEqual(MatchRewards.checkoutScoreBands.first { $0.contains(121) }?.xp, 28)
    }

    func testNoDartsMeansNoXP() {
        let match = Match(config: GameConfig(), players: [Player(name: "Já"), Player(name: "Bot", botLevel: 3)])
        let xp = MatchRewards.award(match: match, playerID: match.players[0].id)
        XCTAssertEqual(xp.total, 0)
        XCTAssertTrue(xp.lines.isEmpty)
    }

    func testSoloSkipsWinAndLoss() {
        var match = Match(config: GameConfig(), players: [Player(name: "Já")])
        match.finished = true
        match.winner = 0
        match.visits = [
            Visit(player: 0, leg: 1, darts: [Dart(20, 1)], credited: 20, bust: false, checkout: false, remaining: 481)
        ]
        let xp = MatchRewards.award(match: match, playerID: match.players[0].id)
        XCTAssertNil(xp.lines.first { $0.id == "win" })
        XCTAssertNil(xp.lines.first { $0.id == "loss" })
        XCTAssertEqual(xp.lines.first { $0.id == "finish" }?.amount, 40)
    }
}
