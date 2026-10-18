import XCTest
@testable import Dartiqo

final class MatchCompletionTests: XCTestCase {
    func testFirstOutcomeSticks() {
        var ledger = MatchCompletionLedger()
        let id = UUID()
        XCTAssertTrue(ledger.note(id, outcome: .abandoned))
        XCTAssertFalse(ledger.note(id, outcome: .completed))
        XCTAssertEqual(ledger.abandoned, 1)
        XCTAssertEqual(ledger.completed, 0)
        XCTAssertEqual(ledger.percent ?? -1, 0, accuracy: 0.001)
        XCTAssertNil(MatchCompletionLedger().percent)
    }

    func testLegacyProfileDecodesWithoutLedger() throws {
        let id = UUID()
        let raw = """
        {"id":"\(id.uuidString)","name":"Já","createdAt":0}
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(Profile.self, from: raw)
        XCTAssertEqual(profile.id, id)
        XCTAssertNil(profile.matchCompletion)
    }

    @MainActor
    func testFinishCountsAndDeleteKeepsTheRate() {
        let profile = Profile(name: "Já")
        let store = store(profile)
        let match = finishedMatch(profile)
        store.activeMatch = match
        store.finish()

        XCTAssertEqual(store.matchCompletion.completed, 1)
        XCTAssertEqual(store.matchCompletion.abandoned, 0)
        XCTAssertEqual(store.matchCompletion.percent ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(store.matches.count, 1)

        store.deleteMatch(match.id)
        XCTAssertTrue(store.matches.isEmpty)
        XCTAssertEqual(store.matchCompletion.snapshot, MatchCompletionSnapshot(completed: 1, abandoned: 0, percent: 100))
    }

    @MainActor
    func testAbandonAndReplaceLowerTheRate() {
        let profile = Profile(name: "Já")
        let store = store(profile)
        let done = finishedMatch(profile)
        store.activeMatch = done
        store.finish()

        var live = openMatch(profile)
        store.activeMatch = live
        live.leg = 2
        store.activeMatch = live
        XCTAssertEqual(store.matchCompletion.abandoned, 0, "Stejné id je pořád ten samý zápas.")

        let replacement = openMatch(profile)
        store.activeMatch = replacement
        XCTAssertEqual(store.matchCompletion.abandoned, 1)

        store.activeMatch = nil
        XCTAssertEqual(store.matchCompletion.completed, 1)
        XCTAssertEqual(store.matchCompletion.abandoned, 2)
        XCTAssertEqual(store.matchCompletion.percent ?? -1, 100.0 / 3.0, accuracy: 0.001)

        store.deleteMatch(done.id)
        XCTAssertEqual(store.matchCompletion.completed, 1)
        XCTAssertEqual(store.matchCompletion.abandoned, 2)
    }

    @MainActor
    func testBackfillSurvivesHistoryDeletion() {
        let profile = Profile(name: "Já")
        var stored = StoredData()
        stored.profiles = [profile]
        stored.selectedProfile = profile.id
        let first = finishedMatch(profile)
        let second = finishedMatch(profile)
        stored.matches = [first, second]
        let store = AppStore(preview: stored)

        XCTAssertEqual(store.matchCompletion.completed, 2)
        XCTAssertEqual(store.matchCompletion.percent ?? -1, 100, accuracy: 0.001)

        store.deleteMatch(first.id)
        XCTAssertEqual(store.matches.count, 1)
        XCTAssertEqual(store.matchCompletion.completed, 2)

        let again = AppStore(preview: store.data)
        XCTAssertEqual(again.matchCompletion.completed, 2)
        XCTAssertEqual(again.matches.count, 1)
    }

    @MainActor
    func testAbandonHitsOnlyThePlayerWhoQuit() {
        let me = Profile(name: "Já")
        let pal = Profile(name: "Kamarád")
        var stored = StoredData()
        stored.profiles = [me, pal]
        stored.selectedProfile = me.id
        let store = AppStore(preview: stored)

        var match = Match(
            config: GameConfig(),
            players: [Player(id: me.id, name: me.name), Player(id: pal.id, name: pal.name)]
        )
        match.finished = true
        match.winner = 0
        store.activeMatch = match
        store.finish()

        XCTAssertEqual(ledger(me.id, in: store).completed, 1)
        XCTAssertEqual(ledger(pal.id, in: store).completed, 1)

        store.activeMatch = Match(
            config: GameConfig(),
            players: [Player(id: me.id, name: me.name), Player(id: pal.id, name: pal.name)]
        )
        store.activeMatch = nil
        XCTAssertEqual(ledger(me.id, in: store).abandoned, 1)
        XCTAssertEqual(ledger(pal.id, in: store).abandoned, 0)
        XCTAssertEqual(ledger(me.id, in: store).percent ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(ledger(pal.id, in: store).percent ?? -1, 100, accuracy: 0.001)
    }

    @MainActor
    func testScoringForOthersDoesNotChangeOwnRate() {
        let profile = Profile(name: "Já")
        let store = store(profile)
        store.activeMatch = Match(config: GameConfig(), players: [Player(name: "A"), Player(name: "B")])
        store.activeMatch = nil
        XCTAssertEqual(store.matchCompletion.decided, 0)
    }

    @MainActor
    private func store(_ profile: Profile) -> AppStore {
        var stored = StoredData()
        stored.profiles = [profile]
        stored.selectedProfile = profile.id
        return AppStore(preview: stored)
    }

    private func finishedMatch(_ profile: Profile) -> Match {
        var match = openMatch(profile)
        match.finished = true
        match.winner = 0
        match.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        return match
    }

    private func openMatch(_ profile: Profile) -> Match {
        Match(
            config: GameConfig(),
            players: [Player(id: profile.id, name: profile.name), Player(name: "Soupeř", botLevel: 3)]
        )
    }

    @MainActor
    private func ledger(_ id: UUID, in store: AppStore) -> MatchCompletionLedger {
        store.data.profiles.first { $0.id == id }?.matchCompletion ?? MatchCompletionLedger()
    }
}
