import XCTest
@testable import Dartiqo

final class GameEngineTests: XCTestCase {
    func game(mode: GameMode = .x01, out: OutRule = .double, doubleIn: Bool = false, players: Int = 2, legs: Int = 1) -> Match {
        Match(config: GameConfig(mode: mode, outRule: out, doubleIn: doubleIn, legsToWin: legs), players: (1...players).map { Player(name: "P\($0)") })
    }
    func test180AndRotation() throws {
        var m = game(); try m.submit([Dart(20,3),Dart(20,3),Dart(20,3)])
        XCTAssertEqual(m.states[0].remaining,321); XCTAssertEqual(m.active,1); XCTAssertEqual(m.average(for:0),180)
    }
    func testRewindRestoresStateBeforeChosenVisit() throws {
        var m = game(legs: 2)
        try m.submit([Dart(20,3),Dart(20,3),Dart(20,3)])
        try m.submit([Dart(20),Dart(20),Dart(20)])
        let target = m.visits[1].id
        try m.submit([Dart(19,3),Dart(19,3),Dart(19,3)])
        XCTAssertTrue(m.rewind(before: target))
        XCTAssertEqual(m.visits.count, 1)
        XCTAssertEqual(m.active, 1)
        XCTAssertEqual(m.states[0].remaining, 321)
        XCTAssertEqual(m.states[1].remaining, 501)
        XCTAssertFalse(m.rewind(before: UUID()))
    }
    func testRewindCrossesLegBoundary() throws {
        var m = game(legs: 2); m.states[0].remaining = 40
        try m.submit([Dart(20,2)])
        let winning = m.visits[0].id
        m.nextLeg()
        try m.submit([Dart(20),Dart(20),Dart(20)])
        XCTAssertTrue(m.rewind(before: winning))
        XCTAssertEqual(m.leg, 1); XCTAssertNil(m.legWinner)
        XCTAssertEqual(m.states[0].remaining, 40); XCTAssertEqual(m.states[0].legs, 0)
        XCTAssertEqual(m.active, 0); XCTAssertTrue(m.visits.isEmpty)
    }
    func testBustRestoresEntireVisitAndCountsUsedDarts() throws {
        var m = game(); m.states[0].remaining = 50
        try m.submit([Dart(20),Dart(20,2)])
        XCTAssertEqual(m.states[0].remaining,50); XCTAssertTrue(m.visits[0].bust); XCTAssertEqual(m.visits[0].credited,0)
        XCTAssertEqual(m.visits[0].darts.count,2)
    }
    func testRemainingOneIsBustInDoubleOut() throws {
        var m = game(); m.states[0].remaining = 21
        try m.submit([Dart(20)])
        XCTAssertTrue(m.visits[0].bust); XCTAssertEqual(m.states[0].remaining,21)
    }
    func testWrongFinishingDartBusts() throws {
        var m = game(); m.states[0].remaining = 20
        try m.submit([Dart(20)])
        XCTAssertFalse(m.finished); XCTAssertTrue(m.visits[0].bust)
    }
    func testDoubleBullCheckoutStopsUnusedDarts() throws {
        var m = game(); m.states[0].remaining = 50
        try m.submit([Dart(25,2),Dart(20,3),Dart(20,3)])
        XCTAssertTrue(m.finished); XCTAssertEqual(m.winner,0); XCTAssertEqual(m.visits[0].darts.count,1)
    }
    func testMasterOutAllowsTripleAndStraightAllowsOne() throws {
        var m = game(out:.master); m.states[0].remaining = 60
        try m.submit([Dart(20,3)]); XCTAssertTrue(m.finished)
        var n = game(out:.straight); n.states[0].remaining = 1
        try n.submit([Dart(1)]); XCTAssertTrue(n.finished)
    }
    func testHandicapStartAndRulesPerPlayer() throws {
        var config = GameConfig(mode: .x01, outRule: .double, legsToWin: 2)
        config.handicaps = [Handicap(startingScore: 301, outRule: .straight), Handicap(doubleIn: true)]
        var m = Match(config: config, players: [Player(name: "A"), Player(name: "B")])
        XCTAssertEqual(m.states[0].remaining, 301); XCTAssertTrue(m.states[0].opened)
        XCTAssertEqual(m.states[1].remaining, 501); XCTAssertFalse(m.states[1].opened)
        XCTAssertTrue(m.config.hasHandicap)
        try m.submit([Dart(20), Dart(20), Dart(20)])
        try m.submit([Dart(20), Dart(20), Dart(20)])
        XCTAssertEqual(m.states[1].remaining, 501)
        m.states[0].remaining = 1
        try m.submit([Dart(1)])
        XCTAssertEqual(m.legWinner, 0)
        m.nextLeg()
        XCTAssertEqual(m.states[0].remaining, 301); XCTAssertEqual(m.states[1].remaining, 501)
        XCTAssertFalse(m.states[1].opened)
    }
    func testHandicapDecodesMissingFieldAndRoundTrips() throws {
        var config = GameConfig(mode: .x01)
        XCTAssertFalse(config.hasHandicap)
        config.handicaps = [Handicap(), Handicap(startingScore: 701)]
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(GameConfig.self, from: data)
        XCTAssertEqual(decoded.startingScore(for: 1), 701)
        XCTAssertEqual(decoded.startingScore(for: 0), decoded.startingScore)
        XCTAssertEqual(decoded.outRule(for: 5), decoded.outRule)
    }
    func testDoubleInAndBustResetOpening() throws {
        var m = game(doubleIn:true)
        try m.submit([Dart(20,3),Dart(20,2),Dart(20)])
        XCTAssertEqual(m.states[0].remaining,441); XCTAssertTrue(m.states[0].opened)
        var n = game(doubleIn:true); n.states[0].remaining = 50
        try n.submit([Dart(20,2),Dart(20)])
        XCTAssertFalse(n.states[0].opened); XCTAssertEqual(n.states[0].remaining,50)
    }
    func testRejectInvalidDartAndIncompleteVisitWithoutMutation() throws {
        var m = game(); let before = m.snapshot
        XCTAssertThrowsError(try m.submit([Dart(25,3),.miss,.miss]))
        XCTAssertEqual(m.snapshot,before)
        XCTAssertThrowsError(try m.submit([Dart(20)])); XCTAssertEqual(m.snapshot,before); XCTAssertTrue(m.visits.isEmpty)
    }
    func testUndoLegAcrossBoundaryAndStarterRotation() throws {
        var m = game(legs:2); m.states[0].remaining = 40
        try m.submit([Dart(20,2)]); XCTAssertEqual(m.legWinner,0); XCTAssertFalse(m.finished)
        m.nextLeg(); XCTAssertEqual(m.active,1); XCTAssertEqual(m.leg,2)
        m.undo(); XCTAssertEqual(m.leg,1); XCTAssertEqual(m.active,0); XCTAssertEqual(m.states[0].remaining,40); XCTAssertEqual(m.states[0].legs,0)
    }
    func testUndoBotReplyReturnsHumanTurn() throws {
        var m = game(); m.players[1].botLevel = 3
        try m.submit([Dart(20),Dart(20),Dart(20)])
        try m.submit([Dart(20),Dart(20),Dart(20)])
        m.undoHumanTurn(); XCTAssertEqual(m.active,0); XCTAssertEqual(m.states[0].remaining,501); XCTAssertTrue(m.visits.isEmpty)
    }
    func testCricketExcessAndClosedOpponent() throws {
        var m = game(mode:.cricket)
        try m.submit([Dart(20,3),Dart(20,3),.miss]); XCTAssertEqual(m.states[0].marks[20],3); XCTAssertEqual(m.states[0].points,60)
        try m.submit([Dart(20,3),Dart(20,3),.miss]); XCTAssertEqual(m.states[1].points,0)
    }
    func testCricketNeedsNotLowerScoreToWin() throws {
        var m = game(mode:.cricket)
        for n in [15,16,17,18,19,20] { m.states[0].marks[n] = 3 }
        m.states[0].marks[25] = 2; m.states[1].points = 50
        try m.submit([Dart(25),.miss,.miss]); XCTAssertFalse(m.finished)
        try m.submit([.miss,.miss,.miss])
        try m.submit([Dart(25,2)]); XCTAssertTrue(m.finished); XCTAssertEqual(m.states[0].points,50)
    }
    func testCricketBullTwoMarks() throws {
        var m = game(mode:.cricket)
        try m.submit([Dart(25,2),.miss,.miss]); XCTAssertEqual(m.states[0].marks[25],2)
    }
    func testClockProgressesWithinVisitAndEndsOnBull() throws {
        var m = game(mode:.aroundClock)
        try m.submit([Dart(1,3),Dart(2,2),Dart(3)]); XCTAssertEqual(m.states[0].clockTarget,4)
        m.active = 0; m.states[0].clockTarget = 20
        try m.submit([Dart(20),Dart(25)]); XCTAssertTrue(m.finished); XCTAssertEqual(m.visits.last?.darts.count,2)
    }
    func testCountUpExactlyTenRoundsAndTie() throws {
        var m = game(mode:.countUp)
        for _ in 0..<19 { try m.submit([Dart(20),Dart(20),Dart(20)]); XCTAssertFalse(m.finished) }
        try m.submit([Dart(20),Dart(20),Dart(20)])
        XCTAssertTrue(m.finished); XCTAssertNil(m.winner); XCTAssertEqual(m.states[0].points,600)
    }
    func testCountUpFinalBotVisitStillHasThreeDarts() throws {
        var m = game(mode:.countUp); m.players[1].botLevel = 5
        for _ in 0..<19 { try m.submit([Dart(20),Dart(20),Dart(20)]) }
        var rng = SeededGenerator(seed:42); let darts = Bot.visit(in:m,using:&rng)
        XCTAssertEqual(darts.count,3); try m.submit(darts); XCTAssertTrue(m.finished)
    }
    func testAllCheckoutRoutesAreLegalAndImpossibleFinishesAbsent() {
        for rule in OutRule.allCases {
            for score in 1...180 {
                if let route = Checkout.route(for:score,rule:rule) {
                    XCTAssertTrue(route.allSatisfy(\.isValid)); XCTAssertLessThanOrEqual(route.count,3)
                    XCTAssertEqual(route.reduce(0) { $0 + $1.score },score); XCTAssertTrue(rule.allows(route.last!))
                }
            }
        }
        for score in [169,168,166,165,163,162,159] { XCTAssertNil(Checkout.route(for:score)) }
        XCTAssertEqual(Checkout.route(for:170),[Dart(20,3),Dart(20,3),Dart(25,2)])
        // Human-style low finishes — not obscure trebles like T3.
        XCTAssertEqual(Checkout.route(for:15),[Dart(7),Dart(4,2)])
        XCTAssertEqual(Checkout.route(for:32),[Dart(16,2)])
        XCTAssertEqual(Checkout.route(for:40),[Dart(20,2)])
        XCTAssertEqual(Checkout.route(for:36),[Dart(18,2)])
        XCTAssertEqual(Checkout.route(for:3),[Dart(1),Dart(1,2)])
    }
    func testSetupLeavesAFinishWhenCheckoutIsImpossible() {
        for rule in OutRule.allCases {
            for darts in 1...3 {
                for score in 2...170 where Checkout.route(for: score, rule: rule, darts: darts) == nil {
                    guard let setup = Checkout.setup(for: score, rule: rule, darts: darts) else {
                        XCTFail("Chybí sehrávka pro \(score) / \(darts) / \(rule.rawValue)")
                        continue
                    }
                    XCTAssertFalse(setup.darts.isEmpty)
                    XCTAssertLessThanOrEqual(setup.darts.count, darts)
                    XCTAssertTrue(setup.darts.allSatisfy(\.isValid))
                    var left = score
                    let floor = rule == .straight ? 1 : 2
                    for dart in setup.darts {
                        let next = left - dart.score
                        XCTAssertGreaterThanOrEqual(next, floor, "Sehrávka \(setup.darts.map(\.label)) z \(score) bustuje")
                        left = next
                    }
                    XCTAssertEqual(left, setup.leaves)
                    XCTAssertNotNil(Checkout.route(for: left, rule: rule, darts: 3))
                    XCTAssertNil(Checkout.route(for: score, rule: rule, darts: darts))
                }
            }
        }
        for score in [169, 168, 166, 165, 163, 162, 159] {
            let setup = Checkout.setup(for: score, darts: 3)
            XCTAssertEqual(setup?.leaves, 40, "\(score) má sehrát na D20")
            XCTAssertEqual(setup?.leaveLabel, "D20")
            XCTAssertEqual(setup?.darts.first, Dart(20, 3))
        }
        let ontoForty = Checkout.setup(for: 100, darts: 1)
        XCTAssertEqual(ontoForty?.darts, [Dart(20, 3)])
        XCTAssertEqual(ontoForty?.leaveLabel, "D20")
        let ontoBull = Checkout.setup(for: 170, darts: 2)
        XCTAssertEqual(ontoBull?.darts, [Dart(20, 3), Dart(20, 3)])
        XCTAssertEqual(ontoBull?.leaveLabel, "Bull")
        XCTAssertNil(Checkout.setup(for: 40, darts: 1))
    }
    func testBotDartsAreLegalAndStrengthIncreases() {
        var averages: [Double] = []
        for level in [1,5,10] {
            var rng = SeededGenerator(seed:UInt64(level)); var sum = 0
            for _ in 0..<10000 { let d = Bot.throwDart(at:Dart(20,3),level:level,using:&rng); XCTAssertTrue(d.isValid); sum += d.score }
            averages.append(Double(sum) / 10000)
        }
        XCTAssertLessThan(averages[0],averages[1]); XCTAssertLessThan(averages[1],averages[2])
    }
    func testBotsFinishAllModesWithoutInvalidVisits() throws {
        for mode in GameMode.allCases {
            var m = game(mode:mode)
            m.players[0].botLevel = 7; m.players[1].botLevel = 8
            var rng = SeededGenerator(seed:123)
            for _ in 0..<3000 {
                if m.finished { break }
                try m.submit(Bot.visit(in:m,using:&rng))
                if m.legWinner != nil && !m.finished { m.nextLeg() }
            }
            XCTAssertTrue(m.finished,"Bot stalled in \(mode)")
        }
    }
    func testPersistenceRoundTripAndUndo() throws {
        var m = game(); try m.submit([Dart(20,3),Dart(5),.miss])
        var decoded = try JSONDecoder().decode(Match.self,from:JSONEncoder().encode(m))
        XCTAssertTrue(decoded.isSane); XCTAssertEqual(decoded.visits,m.visits)
        decoded.undo(); XCTAssertEqual(decoded.states[0].remaining,501)
    }
    func testTotalEntryScoresAndLabelsHistory() throws {
        var m = game(); try m.submitTotal(100)
        XCTAssertEqual(m.states[0].remaining,401); XCTAssertEqual(m.visits[0].darts.count,3)
        XCTAssertEqual(m.visits[0].enteredAsTotal,true); XCTAssertEqual(m.visits[0].credited,100)
        XCTAssertFalse(m.visits[0].inputDescription.contains("T20"))
    }
    func testImpossibleTotalIsAtomic() throws {
        var m = game(); let before = m.snapshot
        for score in [179,178,176,175,173,172,169] {
            XCTAssertThrowsError(try m.submitTotal(score)); XCTAssertEqual(m.snapshot,before)
        }
    }
    func testZeroTotalAndCheckoutDartCount() throws {
        var m = game(); try m.submitTotal(0); XCTAssertEqual(m.visits[0].darts.count,3)
        m.active = 0; m.states[0].remaining = 40
        try m.submitTotal(40, checkoutDarts:3)
        XCTAssertTrue(m.finished); XCTAssertEqual(m.visits.last?.darts.count,3)
    }
    func testTotalCheckoutRequiresPossibleDarts() throws {
        var m = game(); m.states[0].remaining = 170
        XCTAssertThrowsError(try m.submitTotal(170, checkoutDarts:2))
        XCTAssertTrue(m.visits.isEmpty)
        try m.submitTotal(170,checkoutDarts:3); XCTAssertTrue(m.finished)
    }
    func testTotalEntryUnavailableForDoubleIn() {
        var m = game(doubleIn:true)
        XCTAssertThrowsError(try m.submitTotal(60)); XCTAssertTrue(m.visits.isEmpty)
    }
    func testExplicitBustPreservesScoreAndUndo() throws {
        var m = game(); m.states[0].remaining = 40
        try m.recordBust(darts:2)
        XCTAssertEqual(m.states[0].remaining,40); XCTAssertEqual(m.visits[0].darts.count,2)
        XCTAssertTrue(m.visits[0].bust); XCTAssertEqual(m.active,1)
        m.undo(); XCTAssertTrue(m.visits.isEmpty); XCTAssertEqual(m.active,0)
    }
    func testImpossibleBustRejected() {
        var m = game(); XCTAssertThrowsError(try m.recordBust(darts:3)); XCTAssertTrue(m.visits.isEmpty)
    }
    func testNoScoreCricketNeverAddsPoints() throws {
        var m = game(mode:.cricket); var options = MatchOptions(); options.cricketNoScore = true; m.config.options = options
        try m.submit([Dart(20,3),Dart(20,3),.miss]); XCTAssertEqual(m.states[0].points,0)
        m.active = 0
        for n in [15,16,17,18,19,20] { m.states[0].marks[n] = 3 }
        m.states[0].marks[25] = 2
        try m.submit([Dart(25)]); XCTAssertTrue(m.finished)
    }
    func testClockDoubleTrainingRejectsSingle() throws {
        var m = game(mode:.aroundClock); var options = MatchOptions(); options.clockStyle = .doubles; m.config.options = options
        try m.submit([Dart(1),Dart(1,2),Dart(2,3)])
        XCTAssertEqual(m.states[0].clockTarget,2)
    }
    func testClockTripleTrainingRequiresInnerBull() throws {
        var m = game(mode:.aroundClock); var options = MatchOptions(); options.clockStyle = .triples; m.config.options = options
        m.states[0].clockTarget = 20
        try m.submit([Dart(20,3),Dart(25),Dart(25,2)])
        XCTAssertTrue(m.finished); XCTAssertEqual(m.visits.last?.darts.count,3)
    }
    func testClockBotRespectsTrainingTarget() {
        var m = game(mode:.aroundClock); var options = MatchOptions(); options.clockStyle = .triples; m.config.options = options
        XCTAssertEqual(Bot.target(in:m,dartsLeft:3),Dart(1,3))
        m.states[0].clockTarget = 21; XCTAssertEqual(Bot.target(in:m,dartsLeft:3),Dart(25,2))
    }
    func testCountUpCustomLengthAndFourPlayers() throws {
        var m = game(mode:.countUp,players:4); var options = MatchOptions(); options.countUpRounds = 5; m.config.options = options
        for _ in 0..<19 { try m.submit([Dart(20),Dart(20),Dart(20)]); XCTAssertFalse(m.finished) }
        try m.submit([Dart(20,3),Dart(20,3),Dart(20,3)])
        XCTAssertTrue(m.finished); XCTAssertEqual(m.winner,3); XCTAssertEqual(m.states[3].points,420)
    }
    func testLegacyConfigurationDecodesWithDefaults() throws {
        let json = #"{"mode":"x01","startingScore":501,"outRule":"double","doubleIn":false,"legsToWin":2}"#
        let config = try JSONDecoder().decode(GameConfig.self,from:Data(json.utf8))
        XCTAssertNil(config.options); XCTAssertEqual(config.settings.countUpRounds,10)
        XCTAssertEqual(config.setsToWin,1); XCTAssertEqual(config.format,.firstTo)
    }
    func testLegacyVisitsDecodeWithoutEntryFlag() throws {
        var m = game(); try m.submit([Dart(20),Dart(20),Dart(20)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(m.visits[0])) as? [String:Any])
        object.removeValue(forKey:"enteredAsTotal")
        let visit = try JSONDecoder().decode(Visit.self,from:JSONSerialization.data(withJSONObject:object))
        XCTAssertNil(visit.enteredAsTotal); XCTAssertTrue(visit.inputDescription.contains("S20"))
    }

    func testImmediateDartAndAutomaticRotation() throws {
        var m = game()
        try m.recordDart(Dart(20,3))
        XCTAssertEqual(m.liveProjection.states[0].remaining,441)
        XCTAssertEqual(m.active,0); XCTAssertTrue(m.visits.isEmpty)
        try m.recordDart(Dart(20,3)); try m.recordDart(Dart(20,3))
        XCTAssertEqual(m.states[0].remaining,321); XCTAssertEqual(m.active,1)
        XCTAssertEqual(m.visits.count,1); XCTAssertTrue(m.currentDarts.isEmpty)
    }
    func testUndoReopensCompletedVisit() throws {
        var m = game()
        for _ in 0..<3 { try m.recordDart(Dart(20)) }
        m.undoLastInput()
        XCTAssertEqual(m.currentDarts.count,2); XCTAssertEqual(m.active,0)
        XCTAssertEqual(m.liveProjection.states[0].remaining,461)
        try m.recordDart(Dart(5)); XCTAssertEqual(m.states[0].remaining,456)
    }
    func testImmediateBustRestoresVisitAndCanUndo() throws {
        var m = game(); m.states[0].remaining = 50
        try m.recordDart(Dart(20)); XCTAssertEqual(m.liveProjection.states[0].remaining,30)
        try m.recordDart(Dart(20,2)); XCTAssertEqual(m.states[0].remaining,50)
        XCTAssertTrue(m.visits[0].bust)
        m.undoLastInput(); XCTAssertEqual(m.liveProjection.states[0].remaining,30)
    }
    func testImmediateCheckoutBlocksFurtherDarts() throws {
        var m = game(); m.states[0].remaining = 40
        try m.recordDart(Dart(20,2)); XCTAssertTrue(m.finished)
        XCTAssertThrowsError(try m.recordDart(Dart(20)))
        m.undoLastInput(); XCTAssertFalse(m.finished); XCTAssertEqual(m.states[0].remaining,40)
    }
    func testPendingDartsPersistWithoutDuplicateHistory() throws {
        var m = game(); try m.recordDart(Dart(20,3)); try m.recordDart(.miss)
        var restored = try JSONDecoder().decode(Match.self,from:JSONEncoder().encode(m))
        XCTAssertTrue(restored.isSane); XCTAssertEqual(restored.liveProjection.states[0].remaining,441)
        try restored.recordDart(Dart(20)); XCTAssertEqual(restored.states[0].remaining,421)
        XCTAssertEqual(restored.visits.count,1); XCTAssertEqual(restored.visits[0].darts.count,3)
    }
    func testFinalCountUpRoundWaitsForThirdDart() throws {
        var m = game(mode:.countUp,players:1)
        var options = m.config.settings; options.countUpRounds = 1; m.config.options = options
        try m.recordDart(Dart(20)); try m.recordDart(Dart(20))
        XCTAssertFalse(m.liveProjection.finished); XCTAssertTrue(m.isSane)
        XCTAssertEqual(m.liveProjection.states[0].points,40)
        try m.recordDart(Dart(20)); XCTAssertTrue(m.finished); XCTAssertEqual(m.states[0].points,60)
    }
    func testBoardHitTestingEverySegmentAndRing() {
        for (index,segment) in BoardGeometry.sectors.enumerated() {
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 10
            for (radius,multiplier) in [(0.8,1),(0.6,3),(0.98,2)] {
                XCTAssertEqual(BoardGeometry.hit(x:cos(angle)*radius,y:sin(angle)*radius),Dart(segment,multiplier))
            }
        }
        XCTAssertEqual(BoardGeometry.hit(x:0,y:0),Dart(25,2))
        XCTAssertEqual(BoardGeometry.hit(x:0,y:0.07),Dart(25))
        XCTAssertEqual(BoardGeometry.hit(x:2,y:0),.miss)
        XCTAssertEqual(BoardGeometry.hit(x:Double.nan,y:0),.miss)
    }
    func testCustomScoreStaysSaneAndBestOfIsMajority() {
        var config = GameConfig(startingScore: 420)
        config.apply(format: .bestOf, setsShown: 3, legsShown: 5)
        let match = Match(config: config, players: [Player(name: "A"), Player(name: "B")])
        XCTAssertTrue(match.isSane)
        XCTAssertEqual(config.legsToWin, 3)
        XCTAssertEqual(config.setsToWin, 2)
        XCTAssertEqual(config.shownLegs, 5)
        XCTAssertEqual(config.shownSets, 3)
        XCTAssertEqual(config.lengthLine, "Best of 3 sety · Best of 5 legů v setu")
    }

    func testSetClosesBeforeTheMatchDoes() throws {
        var match = Match(config: GameConfig(legsToWin: 1, setsToWin: 2), players: [Player(name: "A"), Player(name: "B")])
        match.states[0].remaining = 40
        try match.submit([Dart(20, 2)])
        XCTAssertEqual(match.legWinner, 0)
        XCTAssertEqual(match.states[0].sets, 1)
        XCTAssertFalse(match.finished)
        match.nextLeg()
        XCTAssertEqual(match.states[0].legs, 0)
        XCTAssertEqual(match.states[0].sets, 1)
        XCTAssertEqual(match.states[0].remaining, 501)
        XCTAssertEqual(match.active, 1)
        try match.submit([Dart(1), Dart(1), Dart(1)])
        match.states[0].remaining = 40
        try match.submit([Dart(20, 2)])
        XCTAssertTrue(match.finished)
        XCTAssertEqual(match.winner, 0)
        XCTAssertEqual(match.states[0].sets, 2)
    }

    func testBoardMarkersRoundTrip() {
        for dart in Dart.targets {
            if let point = BoardGeometry.marker(for:dart) {
                XCTAssertEqual(BoardGeometry.hit(x:point.x,y:point.y),dart)
            }
        }
    }
}
struct SeededGenerator: RandomNumberGenerator {
    var seed: UInt64
    mutating func next() -> UInt64 { seed = 2862933555777941757 &* seed &+ 3037000493; return seed }
}
