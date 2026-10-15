import XCTest
@testable import Dartiqo

final class BotEngineTests: XCTestCase {
    func testEveryBedResolvesToItself() {
        for segment in 1...20 {
            for multiplier in 1...3 {
                let point = DartboardGeometry.aim(segment: segment, multiplier: multiplier)
                let hit = DartboardGeometry.hit(x: point.x, y: point.y)
                XCTAssertEqual(hit, Dart(segment, multiplier), "\(Dart(segment, multiplier).label) se trefilo jako \(hit.label)")
            }
        }
        XCTAssertEqual(DartboardGeometry.hit(x: 0, y: 0), Dart(25, 2))
        let outer = DartboardGeometry.aim(segment: 25, multiplier: 1)
        XCTAssertEqual(DartboardGeometry.hit(x: outer.x, y: outer.y), Dart(25))
        XCTAssertEqual(DartboardGeometry.hit(x: 0, y: 1.2).segment, 0)
        XCTAssertEqual(DartboardGeometry.segmentOrder.count, 20)
        XCTAssertEqual(DartboardGeometry.segmentOrder.first, 20)
        let neighbors = DartboardGeometry.neighbors(of: 20)
        XCTAssertEqual(neighbors?.clockwise, 1)
        XCTAssertEqual(neighbors?.counterClockwise, 5)
    }

    func testScoresMatchSegmentTimesMultiplier() {
        for segment in 1...20 {
            for multiplier in 1...3 {
                let dart = Dart(segment, multiplier)
                XCTAssertEqual(dart.score, segment * multiplier)
                XCTAssertTrue(dart.isValid)
            }
        }
        XCTAssertEqual(Dart(25, 2).score, 50)
        XCTAssertEqual(Dart.miss.score, 0)
    }

    func testCheckoutAimChangesAfterEachDart() {
        var game = x01()
        game.players[0].botLevel = 14
        game.states[0].remaining = 80
        let onEighty = Bot.target(in: game, dartsLeft: 3)
        XCTAssertLessThan(onEighty.score, 80)
        XCTAssertGreaterThanOrEqual(onEighty.score, 32)
        XCTAssertFalse(ScoringRules.isBust(remaining: 80, dart: onEighty, rule: .double))
        game.states[0].remaining = 60
        let onSixty = Bot.target(in: game, dartsLeft: 2)
        XCTAssertNotEqual(onSixty, onEighty)
        XCTAssertLessThan(onSixty.score, 60)
        game.states[0].remaining = 32
        XCTAssertEqual(Bot.target(in: game, dartsLeft: 1), Dart(16, 2))
        game.states[0].remaining = 16
        XCTAssertEqual(Bot.target(in: game, dartsLeft: 1), Dart(8, 2))
    }

    func testOutRulesAndBustStayLegal() throws {
        for rule in OutRule.allCases {
            var game = x01(rule: rule)
            game.players[0].botLevel = 12
            game.players[1].botLevel = 12
            var rng = BotRNG(seed: rule == .double ? 91 : rule == .straight ? 92 : 93)
            for _ in 0..<40 {
                if game.finished { break }
                let darts = Bot.visit(in: game, using: &rng)
                XCTAssertFalse(darts.isEmpty)
                XCTAssertLessThanOrEqual(darts.count, 3)
                XCTAssertTrue(darts.allSatisfy(\.isValid))
                XCTAssertTrue(darts.allSatisfy { (0...60).contains($0.score) || $0.score == 50 || $0.score == 25 })
                try game.submit(darts)
                if let visit = game.visits.last, visit.checkout {
                    XCTAssertTrue(rule.allows(visit.darts.last ?? .miss))
                    XCTAssertEqual(game.states[visit.player].remaining, 0)
                }
                if game.legWinner != nil && !game.finished { game.nextLeg() }
            }
        }

        var stuck = x01()
        stuck.states[0].remaining = 2
        XCTAssertEqual(Bot.target(in: stuck, dartsLeft: 3).multiplier, 2)
        try stuck.submit([Dart(20, 3)])
        XCTAssertTrue(stuck.visits.last?.bust == true)
        XCTAssertEqual(stuck.states[0].remaining, 2)
        XCTAssertNil(stuck.legWinner)

        var one = x01()
        one.states[0].remaining = 1
        XCTAssertEqual(Bot.target(in: one, dartsLeft: 1), Dart(1, 2))
        try one.submit([Dart(1)])
        XCTAssertTrue(one.visits.last?.bust == true)
        XCTAssertNil(one.legWinner)
    }

    func testStraightAndMasterCanFinish() throws {
        var straight = x01(rule: .straight)
        straight.states[0].remaining = 20
        let straightAim = Bot.target(in: straight, dartsLeft: 1)
        XCTAssertEqual(straightAim.score, 20)
        try straight.submit([straightAim])
        XCTAssertEqual(straight.legWinner, 0)

        var master = x01(rule: .master)
        master.states[0].remaining = 60
        XCTAssertEqual(Bot.target(in: master, dartsLeft: 1), Dart(20, 3))
        try master.submit([Dart(20, 3)])
        XCTAssertEqual(master.legWinner, 0)
    }

    func testVisitNeverExceedsThreeAndIsDeterministic() {
        var game = x01()
        game.players[0].botLevel = 8
        var first = BotRNG(seed: 42)
        var second = BotRNG(seed: 42)
        let a = Bot.visit(in: game, using: &first)
        let b = Bot.visit(in: game, using: &second)
        XCTAssertEqual(a, b)
        XCTAssertLessThanOrEqual(a.count, 3)
        XCTAssertFalse(a.isEmpty)
    }

    func testStatisticsUseRealVisitsOnce() throws {
        var game = Match(
            config: GameConfig(mode: .x01, startingScore: 501, outRule: .double, legsToWin: 1),
            players: [Player(name: "A")]
        )
        try game.submit([Dart(20, 3), Dart(20, 3), Dart(20, 3)])
        try game.submit([Dart(20, 3), Dart(20, 3), Dart(20, 3)])
        try game.submit([Dart(20, 3), Dart(19, 3), Dart(12, 2)])
        let stats = BotStatistics.make(from: game, player: 0)
        XCTAssertEqual(stats.darts, 9)
        XCTAssertEqual(stats.count180, 2)
        XCTAssertEqual(stats.busts, 0)
        XCTAssertEqual(stats.legsWon, 1)
        XCTAssertEqual(stats.bestLegDarts, 9)
        XCTAssertEqual(stats.threeDartAverage, game.average(for: 0), accuracy: 0.001)
        XCTAssertEqual(stats.checkoutAttempts, 1)
        XCTAssertEqual(stats.highestCheckout, 141)
        let again = BotStatistics.make(from: game, player: 0)
        XCTAssertEqual(again.darts, stats.darts)
        XCTAssertEqual(again.checkoutAttempts, stats.checkoutAttempts)
    }

    func testHigherLevelsScoreMoreOnTreble20() {
        var averages: [Double] = []
        for level in [1, 5, 10, 15, 20] {
            var rng = BotRNG(seed: UInt64(level) &* 17)
            var sum = 0
            for _ in 0..<2_000 {
                let dart = Bot.throwDart(at: Dart(20, 3), level: level, using: &rng)
                XCTAssertTrue(dart.isValid)
                XCTAssertLessThanOrEqual(dart.score, 60)
                sum += dart.score
            }
            averages.append(Double(sum) / 2_000)
        }
        for index in averages.indices.dropFirst() {
            XCTAssertLessThan(averages[index - 1], averages[index], "Úroveň \(index) nemá vyšší zásah než předchozí: \(averages)")
        }
    }

    func testDoubleHitRisesWithLevel() {
        let low = BotCalibrationEngine.doubleHitRate(level: 1, attempts: 2_500, seed: 11)
        let mid = BotCalibrationEngine.doubleHitRate(level: 10, attempts: 2_500, seed: 11)
        let high = BotCalibrationEngine.doubleHitRate(level: 20, attempts: 2_500, seed: 11)
        XCTAssertLessThan(low, mid)
        XCTAssertLessThan(mid, high)
        XCTAssertLessThan(low, 0.08)
        XCTAssertGreaterThan(high, 0.35)
    }

    func testReferenceLevelsApproachTargets() {
        for level in 1...BotDifficulty.count {
            let isolated = BotCalibrationEngine.doubleHitRate(level: level, attempts: 2_500, seed: 7)
            let targetDouble = BotDifficulty.level(level).targetDoubleHit
            XCTAssertEqual(isolated, targetDouble, accuracy: 0.05, "Level \(level) double \(isolated) mimo \(targetDouble)")
        }
        for level in [1, 5, 10, 15, 20] {
            let report = BotCalibrationEngine.simulate(level: level, legs: 24, seed: 21)
            XCTAssertEqual(report.threeDartAverage, report.targetAverage, accuracy: 10, "Level \(level) průměr \(report.threeDartAverage)")
            XCTAssertGreaterThan(report.dartsPerLeg, 8)
            XCTAssertLessThan(report.dartsPerLeg, 160)
        }
    }

    func testStylesAreNotIdentical() {
        let scoring = BotProfile.reference(level: 12, style: .scoringSpecialist)
        let finish = BotProfile.reference(level: 12, style: .checkoutSpecialist)
        let wild = BotProfile.reference(level: 12, style: .unpredictable)
        let calm = BotProfile.reference(level: 12, style: .consistent)
        XCTAssertLessThan(scoring.tripleSigma, finish.tripleSigma)
        XCTAssertLessThan(finish.doubleSigma, scoring.doubleSigma)
        XCTAssertLessThan(wild.consistency, calm.consistency)
        let left = BotProfile.make(level: 12, identity: 3)
        let right = BotProfile.make(level: 12, identity: 9)
        XCTAssertNotEqual(left.tripleSigma, right.tripleSigma)
    }

    func testAdaptiveMapsAveragesAndDoesNotScriptAWin() {
        XCTAssertEqual(AdaptiveBotEngine.level(forThreeDartAverage: 17.5), 1)
        XCTAssertEqual(AdaptiveBotEngine.level(forThreeDartAverage: 62.5), 10)
        XCTAssertEqual(AdaptiveBotEngine.level(forThreeDartAverage: 112.5), 20)
        XCTAssertEqual(AdaptiveBotEngine.level(forThreeDartAverage: 200), 20)
        XCTAssertEqual(AdaptiveBotEngine.challenge(base: 10, recentWinRate: 0.8, unstable: false), 11)
        XCTAssertEqual(AdaptiveBotEngine.challenge(base: 10, recentWinRate: 0.2, unstable: false), 9)
        XCTAssertEqual(AdaptiveBotEngine.challenge(base: 10, recentWinRate: 0.9, unstable: true), 10)
        XCTAssertEqual(AdaptiveBotEngine.recommendedLevel(matches: [], playerID: UUID()), AdaptiveBotEngine.fallbackLevel)
    }

    func testBotFinishes501WithoutIllegalCheckout() throws {
        var game = x01()
        game.players[0].botLevel = 15
        game.players[1].botLevel = 6
        var rng = BotRNG(seed: 404)
        for _ in 0..<2_000 {
            if game.finished { break }
            let before = game.visits.count
            let darts = Bot.visit(in: game, using: &rng)
            XCTAssertLessThanOrEqual(darts.count, 3)
            try game.submit(darts)
            XCTAssertEqual(game.visits.count, before + 1)
            if game.legWinner != nil && !game.finished { game.nextLeg() }
        }
        XCTAssertTrue(game.finished)
        for visit in game.visits where visit.checkout {
            let rule = game.config.outRule(for: visit.player)
            XCTAssertTrue(rule.allows(visit.darts.last ?? .miss))
            XCTAssertLessThanOrEqual(visit.darts.count, 3)
        }
    }

    private func x01(rule: OutRule = .double, legs: Int = 2) -> Match {
        Match(config: GameConfig(mode: .x01, outRule: rule, legsToWin: legs), players: [Player(name: "A"), Player(name: "B")])
    }
}
