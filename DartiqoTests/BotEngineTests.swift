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

    func testScore126OpensOnNineteenBecauseSingleEighteenCannotFinish() {
        let strong = BotProfile.reference(level: 16)
        let aim = BotCheckoutEngine.planned(
            remaining: 126,
            dartsLeft: 3,
            rule: .double,
            opened: true,
            profile: strong
        )
        XCTAssertEqual(aim, Dart(19, 3))
        XCTAssertNil(Checkout.route(for: 108, darts: 2))
        XCTAssertEqual(Checkout.route(for: 107, darts: 2), [Dart(19, 3), Dart(25, 2)])
        let afterSingleNineteen = BotCheckoutEngine.planned(
            remaining: 107,
            dartsLeft: 2,
            rule: .double,
            opened: true,
            profile: strong
        )
        XCTAssertEqual(afterSingleNineteen, Dart(19, 3))
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

    func testLiveVisitAimsNextTrebleAfterCover() throws {
        var game = x01()
        game.players[0].botLevel = 16
        game.states[0].remaining = 501
        // pending šipka v návštěvě — liveProjection ji „spotřebuje“, thrown musí jít zvlášť
        try game.recordDart(Dart(20, 3))
        XCTAssertEqual(game.currentDarts.count, 1)
        XCTAssertTrue(game.liveProjection.currentDarts.isEmpty)
        let planned = BotTargetSelector.deterministicAim(
            in: game.liveProjection,
            dartsLeft: 2,
            thrown: game.currentDarts
        )
        XCTAssertEqual(planned, Dart(20, 3))
        var stayed = 0
        for seed in 1...40 {
            var rng = BotRNG(seed: UInt64(seed))
            let shot = BotGameController.simulateDart(in: game, using: &rng)
            if shot.aim == Dart(20, 3) { stayed += 1 }
        }
        XCTAssertGreaterThan(stayed, 25, "Po T20 má bot zůstat na T20, zůstal jen \(stayed)/40")
    }

    func testScoringSetupFollowsHandbook() {
        let strong = BotProfile.reference(level: 14)
        func aim(_ score: Int, darts: Int = 3) -> Dart? {
            ScoringSetup.aim(remaining: score, dartsLeft: darts, rule: .double, profile: strong)
        }
        // 273: T19, T19, S19 → 140
        XCTAssertEqual(aim(273), Dart(19, 3))
        XCTAssertEqual(aim(216, darts: 2), Dart(19, 3))
        XCTAssertEqual(aim(159, darts: 1), Dart(19))
        // 305 a 308 začínají na 18; po S18 se přechází na T20
        XCTAssertEqual(aim(305), Dart(18, 3))
        XCTAssertEqual(aim(287, darts: 2), Dart(20, 3))
        XCTAssertEqual(aim(308), Dart(18, 3))
        XCTAssertEqual(aim(309), Dart(19, 3))
        XCTAssertEqual(aim(303), Dart(19, 3))
        XCTAssertEqual(aim(302), Dart(18, 3))
        XCTAssertEqual(aim(300), Dart(20, 3))
        XCTAssertEqual(aim(310), Dart(20, 3))
        XCTAssertEqual(aim(250), Dart(20, 3))
        // 265 začíná na 19. Po T19 se dál míří na T19, single není plán.
        XCTAssertEqual(aim(265), Dart(19, 3))
        XCTAssertEqual(aim(246, darts: 2), Dart(19, 3))
        XCTAssertEqual(aim(208, darts: 2), Dart(19, 3))
        XCTAssertEqual(aim(189, darts: 1), Dart(19))
        XCTAssertEqual(aim(262), Dart(19, 3))
        XCTAssertEqual(aim(259), Dart(19, 3))
        // Poslední šipka se dopočítá na nejlepší nechání: 227 − T19 = 170.
        XCTAssertEqual(aim(227, darts: 1), Dart(19, 3))
        XCTAssertEqual(aim(230, darts: 1), Dart(20, 3))
        XCTAssertEqual(aim(221, darts: 1), Dart(17, 3))
        XCTAssertEqual(aim(187, darts: 1), Dart(17))
        // 158 − T20 = 98, dvoušipkové zavření na 20 a 19.
        XCTAssertEqual(aim(158, darts: 1), Dart(20, 3))
        XCTAssertEqual(Checkout.route(for: 98, darts: 2), [Dart(20, 3), Dart(19, 2)])
        // Vysoké skóre: 501 jen skóruje (nil → rotace), 489/488 nezačínají na 20.
        XCTAssertNil(aim(501))
        XCTAssertEqual(aim(489), Dart(19, 3))
        XCTAssertEqual(aim(488), Dart(18, 3))
        XCTAssertEqual(
            BotCheckoutEngine.scoringAim(remaining: 273, rule: .double, profile: strong),
            Dart(19, 3)
        )
        XCTAssertEqual(
            BotCheckoutEngine.scoringAim(remaining: 501, rule: .double, profile: strong),
            Dart(20, 3)
        )
        let weak = BotProfile.reference(level: 2)
        XCTAssertNil(ScoringSetup.aim(remaining: 273, dartsLeft: 3, rule: .double, profile: weak))
        XCTAssertEqual(aim(275), Dart(20, 3))
        XCTAssertEqual(aim(255, darts: 2), Dart(25, 2))
    }

    func testShapedCheckouts() {
        let strong = BotProfile.reference(level: 16)
        func planned(_ score: Int, darts: Int = 3, thrown: [Dart] = []) -> Dart {
            BotCheckoutEngine.planned(
                remaining: score,
                dartsLeft: darts,
                rule: .double,
                opened: true,
                profile: strong,
                thrown: thrown
            )
        }
        XCTAssertEqual(Checkout.route(for: 119)?.first, Dart(19, 3))
        XCTAssertEqual(planned(119), Dart(19, 3))
        XCTAssertEqual(Checkout.route(for: 135)?.first, Dart(25, 2))
        XCTAssertEqual(planned(135), Dart(25, 2))
        XCTAssertEqual(Checkout.route(for: 110, darts: 2), [Dart(20, 3), Dart(25, 2)])
        XCTAssertEqual(Checkout.route(for: 96, darts: 2)?.first, Dart(20, 3))
        XCTAssertEqual(Checkout.route(for: 101, darts: 2), [Dart(17, 3), Dart(25, 2)])
        XCTAssertEqual(planned(121), Dart(25, 2))
        var bulls = 0
        var twenties = 0
        for seed in 1...80 {
            var rng = BotRNG(seed: UInt64(seed))
            let shot = BotCheckoutEngine.aim(
                remaining: 121,
                dartsLeft: 3,
                rule: .double,
                opened: true,
                profile: strong,
                using: &rng
            )
            if shot == Dart(25, 2) { bulls += 1 }
            if shot == Dart(20, 3) { twenties += 1 }
        }
        XCTAssertGreaterThan(bulls, 20, "Střed vyšel jen \(bulls)/80")
        XCTAssertGreaterThan(twenties, 20, "Dvacítka vyšla jen \(twenties)/80")
        XCTAssertEqual(planned(116, darts: 1), Dart(20, 3))
        XCTAssertEqual(planned(116, darts: 1, thrown: packedTreble(segment: 20)), Dart(19, 3))
        XCTAssertEqual(planned(179, darts: 1), Dart(20, 3))
        XCTAssertEqual(planned(210, darts: 1), Dart(20, 3))
        var awkward = 0
        var plain = 0
        for seed in 1...80 {
            var above = BotRNG(seed: UInt64(seed))
            var onFinish = BotRNG(seed: UInt64(seed))
            let chase = BotCheckoutEngine.aim(
                remaining: 179,
                dartsLeft: 1,
                rule: .double,
                opened: true,
                profile: strong,
                opponentAboveCheckout: true,
                using: &above
            )
            let score = BotCheckoutEngine.aim(
                remaining: 179,
                dartsLeft: 1,
                rule: .double,
                opened: true,
                profile: strong,
                opponentAboveCheckout: false,
                using: &onFinish
            )
            if chase == Dart(9) { awkward += 1 }
            if score == Dart(9) { plain += 1 }
            XCTAssertEqual(score.multiplier, 3)
            XCTAssertTrue((18...20).contains(score.segment))
        }
        XCTAssertEqual(plain, 0)
        XCTAssertGreaterThan(awkward, 4, "Single na 170 vyšel jen \(awkward)/80")
        XCTAssertLessThan(awkward, 50, "Single na 170 vyšel \(awkward)/80, má být jen občas")
    }

    func testScoringAimMovesDownTreblesAfterCover() {
        let strong = BotProfile.reference(level: 16)
        let ladder = BotCheckoutEngine.scoringLadder(for: strong)
        XCTAssertEqual(ladder.prefix(3).map { $0 }, [20, 19, 18])
        XCTAssertEqual(BotCheckoutEngine.scoringBedIndex(thrown: [], ladder: ladder, profile: strong), 0)
        // Jedna T20 ve středu treble pořád nechá místo — bot zůstává.
        XCTAssertTrue(BotCheckoutEngine.trebleHasRoom(segment: 20, occupied: [Dart(20, 3)], profile: strong))
        XCTAssertEqual(
            BotCheckoutEngine.scoringBedIndex(thrown: [Dart(20, 3)], ladder: ladder, profile: strong),
            0
        )
        // Podhoz do 19 bez treble přeskakuje na 18. Trefená T19 se na 19 nechá.
        XCTAssertEqual(
            BotCheckoutEngine.scoringBedIndex(thrown: [Dart(19)], ladder: ladder, profile: strong),
            2
        )
        XCTAssertEqual(
            BotCheckoutEngine.scoringBedIndex(thrown: [Dart(20, 3), Dart(19)], ladder: ladder, profile: strong),
            2
        )
        XCTAssertEqual(
            BotCheckoutEngine.scoringBedIndex(thrown: [Dart(20, 3), Dart(19, 3)], ladder: ladder, profile: strong),
            1
        )
        // Zakrytá dvacítka a minutý treble (S20 po T20) schází na 19.
        XCTAssertEqual(
            BotCheckoutEngine.scoringBedIndex(thrown: [Dart(20, 3), Dart(20)], ladder: ladder, profile: strong),
            1
        )
        // Vedlejší segment (1 nebo 5) sám o sobě z T20 nesestěhuje.
        XCTAssertEqual(
            BotCheckoutEngine.scoringBedIndex(thrown: [Dart(1)], ladder: ladder, profile: strong),
            0
        )
        XCTAssertEqual(
            BotCheckoutEngine.scoringAim(remaining: 501, rule: .double, profile: strong, thrown: [Dart(1)]),
            Dart(20, 3)
        )
        let afterCover = BotCheckoutEngine.scoringAim(
            remaining: 441,
            rule: .double,
            profile: strong,
            thrown: [Dart(20, 3)]
        )
        XCTAssertEqual(afterCover, Dart(20, 3))
        XCTAssertFalse(BotCheckoutEngine.trebleHasRoom(segment: 20, occupied: packedTreble(segment: 20), profile: strong))
        let weak = BotProfile.reference(level: 2)
        let weakLadder = BotCheckoutEngine.scoringLadder(for: weak)
        // Slabý bot po zásahu / sousedovi často zůstane na stejné terci (deterministicky pod prahem).
        XCTAssertEqual(
            BotCheckoutEngine.scoringBedIndex(thrown: [Dart(20, 3)], ladder: weakLadder, profile: weak),
            0
        )
        XCTAssertEqual(
            BotCheckoutEngine.scoringBedIndex(thrown: [Dart(1)], ladder: weakLadder, profile: weak),
            0
        )
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

    func testCustomBotKeepsRequestedAverageAndCheckout() {
        let level = BotDifficulty.level(10)
        let matched = BotProfile.custom(average: level.targetAverage, checkout: level.targetDoubleHit)
        XCTAssertEqual(matched.tripleSigma, level.tripleSigma, accuracy: 0.0001)
        XCTAssertEqual(matched.doubleSigma, level.doubleSigma, accuracy: 0.0001)
        XCTAssertEqual(BotDifficulty.nearestLevel(forAverage: 17.5), 1)
        XCTAssertEqual(BotDifficulty.nearestLevel(forAverage: 112.5), 20)

        let soft = BotProfile.custom(average: 40, checkout: 0.10)
        let hard = BotProfile.custom(average: 90, checkout: 0.40)
        XCTAssertEqual(soft.targetAverage, 40, accuracy: 0.01)
        XCTAssertEqual(soft.targetDoubleHit, 0.10, accuracy: 0.001)
        XCTAssertLessThan(hard.tripleSigma, soft.tripleSigma)
        XCTAssertLessThan(hard.doubleSigma, soft.doubleSigma)

        let plain = BotProfile.custom(average: 70, checkout: 0.25, style: .balanced)
        let finisher = BotProfile.custom(average: 70, checkout: 0.25, style: .checkoutSpecialist)
        let calm = BotProfile.custom(average: 70, checkout: 0.25, style: .consistent)
        let wild = BotProfile.custom(average: 70, checkout: 0.25, style: .unpredictable)
        XCTAssertEqual(finisher.tripleSigma, plain.tripleSigma, accuracy: 0.0001)
        XCTAssertEqual(finisher.doubleSigma, plain.doubleSigma, accuracy: 0.0001)
        XCTAssertGreaterThan(finisher.checkoutIntelligence, plain.checkoutIntelligence)
        XCTAssertNotEqual(finisher.preferredDoubles, plain.preferredDoubles)
        XCTAssertGreaterThan(calm.consistency, wild.consistency)

        let player = Player(name: "Karel", botLevel: 8, botStyle: .tactical, botAverage: 55, botCheckout: 0.2)
        let fromPlayer = BotProfile.from(player: player)
        XCTAssertEqual(fromPlayer.targetAverage, 55, accuracy: 0.01)
        XCTAssertEqual(fromPlayer.targetDoubleHit, 0.2, accuracy: 0.001)
        XCTAssertEqual(fromPlayer.style, .tactical)
        XCTAssertEqual(fromPlayer.name, "Karel")

        let mortal = BotProfile.custom(average: 80, checkout: 0.52)
        let closer = BotProfile.custom(average: 80, checkout: 1, consistency: 0.95, pressure: 0.1, intelligence: 0.2)
        XCTAssertLessThan(closer.doubleSigma, mortal.doubleSigma)
        XCTAssertLessThan(closer.doubleSigma, 0.006)
        XCTAssertEqual(closer.consistency, 0.95, accuracy: 0.001)
        XCTAssertEqual(closer.pressureResistance, 0.1, accuracy: 0.001)
        XCTAssertEqual(closer.checkoutIntelligence, 0.2, accuracy: 0.001)
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

    private func packedTreble(segment: Int) -> [Dart] {
        guard let index = BoardGeometry.sectors.firstIndex(of: segment) else { return [Dart(segment, 3)] }
        let center = -Double.pi / 2 + Double(index) * .pi / 10
        let radius = (BoardGeometry.tripleInner + BoardGeometry.tripleOuter) / 2
        return stride(from: -0.14, through: 0.14, by: 0.028).map { offset in
            let angle = center + offset
            return Dart(segment, 3, x: cos(angle) * radius, y: sin(angle) * radius)
        }
    }

    private func x01(rule: OutRule = .double, legs: Int = 2) -> Match {
        Match(config: GameConfig(mode: .x01, outRule: rule, legsToWin: legs), players: [Player(name: "A"), Player(name: "B")])
    }
}
