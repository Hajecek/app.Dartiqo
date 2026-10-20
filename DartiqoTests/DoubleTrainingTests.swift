import XCTest
@testable import Dartiqo

final class DoubleTrainingTests: XCTestCase {
    private let me = UUID()

    func testMatchAndTrainingDartsMergePerDouble() throws {
        var game = Match(
            config: GameConfig(mode: .x01, startingScore: 101, outRule: .double, legsToWin: 1),
            players: [Player(id: me, name: "Já")]
        )
        try game.submit([Dart(20, 3), Dart(9), Dart(16)])
        try game.submit([Dart(8, 2)])
        let session = completed(tallies: [
            AimTally(key: "D16", hits: 2, attempts: 10),
            AimTally(key: "BULL", hits: 1, attempts: 4),
            AimTally(key: "T20", hits: 5, attempts: 10),
            AimTally(key: "Libovolný double", hits: 3, attempts: 9)
        ])

        let insights = DoubleTraining.insights(matches: [game], sessions: [session], profileID: me)

        XCTAssertEqual(insights[16]?.attempts, 11)
        XCTAssertEqual(insights[16]?.hits, 2)
        XCTAssertEqual(insights[8]?.attempts, 1)
        XCTAssertEqual(insights[8]?.hits, 1)
        XCTAssertEqual(insights[25]?.attempts, 4)
        XCTAssertEqual(Set(insights.keys), [8, 16, 25])
    }

    func testWeakestSkipsThinDataAndSortsByRate() {
        let insights: [Int: DoubleInsight] = [
            20: DoubleInsight(segment: 20, hits: 4, attempts: 10),
            16: DoubleInsight(segment: 16, hits: 1, attempts: 10),
            8: DoubleInsight(segment: 8, hits: 0, attempts: 2),
            10: DoubleInsight(segment: 10, hits: 1, attempts: 5),
            25: DoubleInsight(segment: 25, hits: 1, attempts: 20)
        ]
        let weakest = DoubleTraining.weakest(in: insights)
        XCTAssertEqual(weakest.map(\.segment), [25, 16, 10])
        XCTAssertTrue(DoubleTraining.weakest(in: [:]).isEmpty)
    }

    func testChosenDoubleIsTheOnlyTarget() {
        let won = series(hits: 8)
        XCTAssertEqual(won.assignment.aims, [.segment(7, 2)])
        XCTAssertEqual(won.status, .completed)
        XCTAssertEqual(won.result?.darts, 30)
        XCTAssertEqual(won.result?.hits, 8)
        XCTAssertEqual(won.result?.success, true)
        XCTAssertEqual(won.result?.tallies.first { $0.key == "D7" }?.attempts, 30)

        let lost = series(hits: 7)
        XCTAssertEqual(lost.result?.success, false)
    }

    /// 30 šipek na D7: `hits` zásahů, zbytek S7, T7 a D16, které se nesmí počítat.
    private func series(hits: Int) -> TrainingSession {
        let definition = TrainingCatalog.find(DoubleTraining.definitionID)!
        var session = TrainingEngine.start(
            definition: definition,
            config: DoubleTraining.config(segment: 7, darts: 30, accuracy: 0.25),
            owner: me,
            seed: 1
        )
        let misses = [Dart(7), Dart(7, 3), Dart(16, 2)]
        for index in 0..<30 {
            let dart = index < hits ? Dart(7, 2) : misses[index % misses.count]
            TrainingEngine.record(.dart(dart), into: &session, at: session.startedAt)
        }
        return session
    }

    func testSeriesStatsTrackVisitsStreakAndGoal() {
        let definition = TrainingCatalog.find(DoubleTraining.definitionID)!
        var session = TrainingEngine.start(
            definition: definition,
            config: DoubleTraining.config(segment: 16, darts: 30, accuracy: 0.25),
            owner: me,
            seed: 1
        )
        XCTAssertTrue(DoubleTraining.isHitOrMiss(session))
        for dart in [Dart(16, 2), Dart(16, 2), .miss, Dart(16, 2), .miss] {
            TrainingEngine.record(.dart(dart), into: &session, at: session.startedAt)
        }
        let stats = TargetSeriesStats.make(session)!
        XCTAssertEqual(stats.thrown, 5)
        XCTAssertEqual(stats.hits, 3)
        XCTAssertEqual(stats.left, 25)
        XCTAssertEqual(stats.bestStreak, 2)
        XCTAssertEqual(stats.currentStreak, 0)
        XCTAssertEqual(stats.visits, [[true, true, false], [true, false]])
        XCTAssertEqual(stats.hitsNeeded, 5)
        XCTAssertTrue(stats.goalReachable)
        XCTAssertFalse(DoubleTraining.isHitOrMiss(start(TrainingCatalog.find("treble-20")!)))
    }

    private func start(_ definition: TrainingDefinition) -> TrainingSession {
        TrainingEngine.start(definition: definition, config: TrainingConfig(), owner: me, seed: 1)
    }

    func testBullTrainingNeedsInnerBull() {
        let definition = TrainingCatalog.find(DoubleTraining.definitionID)!
        let session = TrainingEngine.start(
            definition: definition,
            config: DoubleTraining.config(segment: 25, darts: 30, accuracy: 0.25),
            owner: me,
            seed: 1
        )
        XCTAssertEqual(session.assignment.aims, [.segment(25, 2)])
        XCTAssertFalse(Aim.segment(25, 2).matches(Dart(25)))
    }

    func testSuggestionsPointAtWeakDoubleAndTreble() {
        let session = completed(tallies: [
            AimTally(key: "D7", hits: 1, attempts: 20),
            AimTally(key: "D20", hits: 8, attempts: 20),
            AimTally(key: "T19", hits: 1, attempts: 30),
            AimTally(key: "T20", hits: 9, attempts: 30)
        ])
        let items = TrainingSuggestions.make(matches: [], sessions: [session], profileID: me)
        XCTAssertEqual(items.map(\.launch), [
            TrainingLaunch(gameID: DoubleTraining.definitionID, segment: 7),
            TrainingLaunch(gameID: "treble-20", segment: 19)
        ])
        XCTAssertTrue(TrainingSuggestions.make(matches: [], sessions: [], profileID: me).isEmpty)
    }

    func testVolumeTargetFollowsChosenSegment() {
        let treble = TrainingCatalog.find("treble-20")!
        var config = TrainingConfig()
        config.segments = [19]
        let session = TrainingEngine.start(definition: treble, config: config, owner: me, seed: 1)
        XCTAssertEqual(session.assignment.aims, [.segment(19, 3)])

        let hundred = TrainingCatalog.find("darts-100-20")!
        config.segments = [25]
        XCTAssertEqual(TrainingEngine.start(definition: hundred, config: config, owner: me, seed: 1).assignment.aims, [.bull])
    }

    func testEveryShelfGameExists() {
        for id in TrainingCatalog.showcase {
            XCTAssertNotNil(TrainingCatalog.find(id), id)
        }
        XCTAssertEqual(Set(TrainingCatalog.showcase).count, TrainingCatalog.showcase.count)
    }

    private func completed(tallies: [AimTally]) -> TrainingSession {
        TrainingSession(
            owner: me,
            definitionID: DoubleTraining.definitionID,
            config: TrainingConfig(),
            seed: 1,
            kind: .segments(pick: .list([16]), mult: 2, darts: 30, accuracy: 0.25),
            assignment: TrainingAssignment(),
            status: .completed,
            result: TrainingResult(success: false, darts: 30, tallies: tallies)
        )
    }
}
