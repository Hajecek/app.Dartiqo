import XCTest
@testable import Dartiqo

final class TrainingEngineTests: XCTestCase {
    func testCatalogHasEightyPlayableGames() {
        XCTAssertEqual(TrainingCatalog.all.count, 80)
        XCTAssertEqual(Set(TrainingCatalog.all.map(\.id)).count, 80)
        XCTAssertEqual(Set(TrainingCatalog.all.map(\.number)), Set(1...80))
        for definition in TrainingCatalog.all {
            XCTAssertFalse(definition.title.isEmpty, definition.id)
            XCTAssertFalse(definition.rules.isEmpty, definition.id)
            XCTAssertFalse(definition.summary.isEmpty, definition.id)
        }
    }

    func testPerfectPlaySucceedsAndMissesFail() {
        for definition in TrainingCatalog.all {
            let won = play(definition, perfectly: true)
            XCTAssertTrue(won.result?.success == true, "\(definition.id) perfect: \(won.result?.summary ?? "bez výsledku")")
            let lost = play(definition, perfectly: false)
            XCTAssertEqual(lost.status, .completed, definition.id)
            XCTAssertFalse(lost.result?.success == true, "\(definition.id) misses still won: \(lost.result?.summary ?? "")")
        }
    }

    func testTrebleIsNotAnySixty() {
        let definition = TrainingCatalog.find("treble-20")!
        var session = start(definition)
        for _ in 0..<30 {
            TrainingEngine.record(.dart(Dart(20, 1)), into: &session, at: session.startedAt)
        }
        XCTAssertEqual(session.result?.success, false)
        XCTAssertEqual(session.result?.hits, 0)
    }

    func testBustRestoresCheckoutAndDoubleOutRejectsSingle() {
        let definition = TrainingCatalog.find("checkout-40")!
        var session = start(definition)
        TrainingEngine.record(.dart(Dart(20, 1)), into: &session, at: session.startedAt)
        TrainingEngine.record(.dart(Dart(20, 1)), into: &session, at: session.startedAt)
        let projection = TrainingEngine.project(session, at: session.startedAt)
        XCTAssertEqual(projection.scoreText, "40")
        XCTAssertGreaterThan(projection.result?.busts ?? session.result?.busts ?? 0, 0)
        XCTAssertNotEqual(session.result?.success, true)
    }

    func testBogeysAreNotFinishable() {
        for score in [1, 159, 162, 163, 165, 166, 168, 169] {
            XCTAssertFalse(Checkout.canFinish(score), "\(score)")
        }
        XCTAssertTrue(Checkout.canFinish(170))
        XCTAssertTrue(Checkout.canFinish(40))
        let game = start(TrainingCatalog.find("checkout-1-100")!)
        XCTAssertFalse(game.assignment.leaves.contains(1))
        XCTAssertTrue(game.assignment.bogeys.contains(1))
    }

    func testDoubleInIgnoresSingles() {
        let outcome = ScoringRules.applyVisit(remaining: 81, opened: false, darts: [Dart(20, 1), Dart(20, 2)], rule: .double, doubleIn: true)
        XCTAssertEqual(outcome.remaining, 41)
        XCTAssertTrue(outcome.opened)
        XCTAssertFalse(outcome.bust)
    }

    func testUndoRestoresTargetAndResumeMatchesThrows() {
        let definition = TrainingCatalog.find("around-clock")!
        var session = start(definition)
        TrainingEngine.record(.dart(Dart(1)), into: &session, at: session.startedAt)
        XCTAssertEqual(TrainingEngine.project(session).target, "2")
        TrainingEngine.undo(&session)
        XCTAssertEqual(TrainingEngine.project(session).target, "1")
        XCTAssertEqual(session.status, .playing)
        let snapshot = session
        TrainingEngine.record(.dart(Dart(1)), into: &session, at: session.startedAt)
        let replay = TrainingSession(id: snapshot.id, owner: snapshot.owner, definitionID: snapshot.definitionID, config: snapshot.config, seed: snapshot.seed, kind: snapshot.kind, assignment: snapshot.assignment, actions: [.dart(Dart(1))], players: 1, names: ["Hráč"], startedAt: snapshot.startedAt)
        XCTAssertEqual(TrainingEngine.project(session).target, TrainingEngine.project(replay).target)
    }

    func testRestartClearsProgressWithoutResult() {
        var session = start(TrainingCatalog.find("jdc")!)
        TrainingEngine.record(.dart(Dart(20, 2)), into: &session, at: session.startedAt)
        TrainingEngine.restart(&session)
        XCTAssertTrue(session.actions.isEmpty)
        XCTAssertNil(session.result)
        XCTAssertEqual(session.status, .playing)
    }

    func testTimeLimitEndsRush() {
        var session = start(TrainingCatalog.find("rush")!)
        let later = session.startedAt.addingTimeInterval(120)
        TrainingEngine.sync(&session, at: later)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.result?.success, false)
    }

    func testXPAwardsOnceAndDropsAfterRepeats() {
        let definition = TrainingCatalog.find("checkout-40")!
        let result = TrainingResult(success: true, score: 40, higherIsBetter: true, darts: 1, hits: 1, accuracy: 1, bestStreak: 1, summary: "ok")
        let first = TrainingRewards.award(definition: definition, config: TrainingConfig(), result: result, completionsToday: 0, isRecord: true, isDaily: false, isWeekly: false)
        let farm = TrainingRewards.award(definition: definition, config: TrainingConfig(), result: result, completionsToday: 3, isRecord: true, isDaily: true, isWeekly: true)
        XCTAssertGreaterThan(first, 40)
        XCTAssertEqual(farm, 4)
        let empty = TrainingRewards.award(definition: definition, config: TrainingConfig(), result: TrainingResult(), completionsToday: 0, isRecord: false, isDaily: false, isWeekly: false)
        XCTAssertEqual(empty, 0)
    }

    func testX01RulesStayAlignedWithMatch() throws {
        let outcome = ScoringRules.applyVisit(remaining: 501, opened: true, darts: [Dart(20, 3), Dart(20, 3), Dart(20, 3)], rule: .double, doubleIn: false)
        var match = Match(config: GameConfig(), players: [Player(name: "A"), Player(name: "B")])
        try match.submit([Dart(20, 3), Dart(20, 3), Dart(20, 3)])
        XCTAssertEqual(outcome.remaining, match.states[0].remaining)
        XCTAssertFalse(outcome.bust)
        let bust = ScoringRules.applyVisit(remaining: 40, opened: true, darts: [Dart(20, 1), Dart(20, 1)], rule: .double, doubleIn: false)
        XCTAssertTrue(bust.bust)
        XCTAssertEqual(bust.remaining, 40)
    }

    func testCoachAsksForDiagnosisWithoutData() {
        let tip = TrainingCoach.recommend(matches: [], sessions: [], profileID: nil)
        XCTAssertEqual(tip.definitionID, "weak-spot")
        XCTAssertFalse(tip.reason.isEmpty)
    }

    func testPlanBuildsAndReacts() {
        var plan = TrainingPlans.make(goal: .checkouts, span: 7, daysPerWeek: 3, minutes: 10, level: .advanced, owner: UUID())
        XCTAssertEqual(plan.items.count, 3)
        let failed = (0..<3).map { _ in
            TrainingSession(owner: plan.owner, definitionID: "checkout-40", config: TrainingConfig(), seed: 1, kind: .checkoutFixed(leaves: [40], visits: 1, need: 1, doubleIn: false), assignment: TrainingAssignment(), status: .completed, result: TrainingResult(success: false, darts: 3, summary: "ne"))
        }
        let before = plan.items[0].definitionID
        TrainingPlans.react(&plan, sessions: failed)
        XCTAssertNotEqual(plan.items[0].definitionID, before)
    }

    private func start(_ definition: TrainingDefinition) -> TrainingSession {
        TrainingEngine.start(definition: definition, config: TrainingConfig(level: .advanced), owner: UUID(), seed: 42, now: Date(timeIntervalSince1970: 1_700_000_000), names: ["Hráč"])
    }

    private func play(_ definition: TrainingDefinition, perfectly: Bool) -> TrainingSession {
        var session = start(definition)
        var steps = 0
        while session.status == .playing && steps < 900 {
            let projection = TrainingEngine.project(session, at: session.startedAt)
            if projection.finished { break }
            if perfectly {
                guard let action = projection.ideal else { break }
                TrainingEngine.record(action, into: &session, at: session.startedAt)
            } else {
                switch projection.phase {
                case .memorize: TrainingEngine.record(.ready, into: &session, at: session.startedAt)
                case .choose: TrainingEngine.record(.choose(1), into: &session, at: session.startedAt)
                case .scoring: TrainingEngine.record(.dart(.miss), into: &session, at: session.startedAt)
                }
            }
            steps += 1
        }
        return session
    }
}
