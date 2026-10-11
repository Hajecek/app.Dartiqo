import XCTest
@testable import Dartiqo

final class GhostModeTests: XCTestCase {
    private let player = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func finishedMatch(
        averageSeed: [[Dart]],
        completed: Date,
        start: Int = 501,
        out: OutRule = .double,
        id: UUID = UUID()
    ) -> Match {
        var match = Match(
            config: GameConfig(mode: .x01, startingScore: start, outRule: out, legsToWin: 1),
            players: [Player(id: player, name: "Já"), Player(name: "Soupeř", botLevel: 3)]
        )
        match.id = id
        match.finished = true
        match.completedAt = completed
        match.winner = 0
        for visit in averageSeed {
            match.visits.append(Visit(player: 0, leg: 1, darts: visit, credited: visit.reduce(0) { $0 + $1.score }, bust: false, checkout: false, remaining: 501))
        }
        // Doplň soupeřovy návštěvy, ať je zápas úplný v historii.
        match.visits.append(Visit(player: 1, leg: 1, darts: [Dart(1), Dart(1), Dart(1)], credited: 3, bust: false, checkout: false, remaining: 498))
        return match
    }

    func testOffersPickBestLastYesterdayAndPB() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now))!
        let best = finishedMatch(
            averageSeed: [[Dart(20, 3), Dart(20, 3), Dart(20, 3)]],
            completed: now.addingTimeInterval(-86_400 * 3),
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        )
        let last = finishedMatch(
            averageSeed: [[Dart(20), Dart(20), Dart(20)]],
            completed: now.addingTimeInterval(-3_600),
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        )
        let yday = finishedMatch(
            averageSeed: [[Dart(19, 3), Dart(19, 3), Dart(19, 3)]],
            completed: yesterday.addingTimeInterval(12 * 3_600),
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        )
        let matches = [best, last, yday]
        let bestOffer = GhostMode.offer(kind: .best, matches: matches, playerID: player, startingScore: 501, outRule: .double, now: now)
        let lastOffer = GhostMode.offer(kind: .last, matches: matches, playerID: player, startingScore: 501, outRule: .double, now: now)
        let yesterdayOffer = GhostMode.offer(kind: .yesterday, matches: matches, playerID: player, startingScore: 501, outRule: .double, now: now)
        let pbOffer = GhostMode.offer(kind: .beatPB, matches: matches, playerID: player, startingScore: 501, outRule: .double, now: now)

        XCTAssertEqual(bestOffer?.sourceID, best.id)
        XCTAssertEqual(pbOffer?.sourceID, best.id)
        XCTAssertEqual(lastOffer?.sourceID, last.id)
        XCTAssertEqual(yesterdayOffer?.sourceID, yday.id)
        XCTAssertEqual(bestOffer?.average ?? -1, 180, accuracy: 0.01)
    }

    func testOfferIgnoresDifferentRules() {
        let match = finishedMatch(averageSeed: [[Dart(20, 3), Dart(20, 3), Dart(20, 3)]], completed: now, start: 301)
        let offer = GhostMode.offer(kind: .best, matches: [match], playerID: player, startingScore: 501, outRule: .double, now: now)
        XCTAssertNil(offer)
    }

    func testScriptPreservesVisitOrder() {
        let match = finishedMatch(
            averageSeed: [
                [Dart(20, 3), Dart(20, 3), Dart(20, 3)],
                [Dart(19, 3), Dart(19, 3), Dart(19, 3)]
            ],
            completed: now
        )
        let script = GhostMode.script(from: match, playerIndex: 0)
        XCTAssertEqual(script.count, 2)
        XCTAssertEqual(script[0], [Dart(20, 3), Dart(20, 3), Dart(20, 3)])
        XCTAssertEqual(script[1], [Dart(19, 3), Dart(19, 3), Dart(19, 3)])
    }

    func testGhostReplayAndUndoRestoresIndex() throws {
        var match = Match(
            config: GameConfig(mode: .x01, startingScore: 501, outRule: .double, legsToWin: 1),
            players: [Player(id: player, name: "Já"), Player(name: "Ghost · 180")],
            firstPlayer: 1
        )
        match.ghostKind = .best
        match.ghostAverage = 180
        match.ghostPlayerIndex = 1
        match.ghostVisitIndex = 0
        match.ghostVisits = [[Dart(20, 3), Dart(20, 3), Dart(20, 3)]]

        XCTAssertTrue(match.isGhostTurn)
        XCTAssertEqual(GhostMode.nextDart(in: match), Dart(20, 3))
        try match.recordDart(Dart(20, 3))
        try match.recordDart(Dart(20, 3))
        try match.recordDart(Dart(20, 3))
        XCTAssertEqual(match.ghostVisitIndex, 1)
        XCTAssertEqual(match.active, 0)
        XCTAssertEqual(match.states[1].remaining, 321)

        match.undoHumanTurn()
        // Po undo ghost tahu jsme znovu u ghosta se stejným indexem návštěvy.
        XCTAssertEqual(match.ghostVisitIndex, 0)
        XCTAssertTrue(match.isGhostTurn)
        XCTAssertEqual(match.states[1].remaining, 501)
    }

    func testExhaustedScriptReturnsMiss() {
        var match = Match(
            config: GameConfig(mode: .x01, startingScore: 501, outRule: .double, legsToWin: 1),
            players: [Player(name: "Já"), Player(name: "Ghost")],
            firstPlayer: 1
        )
        match.ghostPlayerIndex = 1
        match.ghostVisitIndex = 0
        match.ghostVisits = []
        XCTAssertEqual(GhostMode.nextDart(in: match), Dart.miss)
    }
}
