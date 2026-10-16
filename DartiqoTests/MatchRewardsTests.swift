import XCTest
@testable import Dartiqo

final class MatchRewardsTests: XCTestCase {
    private let config = MatchXPConfig.standard

    func testSpecExampleAddsTo120AndLossReplacesWin() {
        let raw = config.playedXP + config.completedXP + config.winXP
            + MatchRewards.averageXP(65, legs: 3, darts: 9)
            + MatchRewards.checkoutXP(rate: 35, attempts: 3, legs: 3)
            + config.oneEightyXP
            + config.highCheckoutXP
        XCTAssertEqual(raw, 120)
        XCTAssertEqual(MatchRewards.rounded(raw, coefficient: 1), 120)
        let loss = raw - config.winXP + config.lossXP
        XCTAssertEqual(loss, 80)
        XCTAssertEqual(MatchRewards.rounded(loss, coefficient: 1), 80)
    }

    func testAverageAndCheckoutBands() {
        XCTAssertEqual(MatchRewards.averageXP(0, legs: 3, darts: 3), 5)
        XCTAssertEqual(MatchRewards.averageXP(29.99, legs: 3, darts: 3), 5)
        XCTAssertEqual(MatchRewards.averageXP(30, legs: 3, darts: 3), 10)
        XCTAssertEqual(MatchRewards.averageXP(65, legs: 3, darts: 9), 25)
        XCTAssertEqual(MatchRewards.averageXP(109.99, legs: 3, darts: 3), 45)
        XCTAssertEqual(MatchRewards.averageXP(110, legs: 3, darts: 3), 50)
        XCTAssertEqual(MatchRewards.averageXP(65, legs: 2, darts: 9), 0)
        XCTAssertEqual(MatchRewards.averageXP(65, legs: 3, darts: 2), 0)

        XCTAssertEqual(MatchRewards.checkoutXP(rate: 0, attempts: 5, legs: 3), 0)
        XCTAssertEqual(MatchRewards.checkoutXP(rate: 9.99, attempts: 3, legs: 3), 5)
        XCTAssertEqual(MatchRewards.checkoutXP(rate: 10, attempts: 3, legs: 3), 10)
        XCTAssertEqual(MatchRewards.checkoutXP(rate: 35, attempts: 3, legs: 3), 20)
        XCTAssertEqual(MatchRewards.checkoutXP(rate: 100, attempts: 3, legs: 3), 50)
        XCTAssertEqual(MatchRewards.checkoutXP(rate: 35, attempts: 2, legs: 3), 0)
        XCTAssertEqual(MatchRewards.checkoutXP(rate: 35, attempts: 3, legs: 2), 0)
    }

    func testOnlineThreeLegMatchPaysPerformance() {
        let match = sample(online: true, legs: 3)
        let xp = MatchRewards.award(match: match, playerID: match.players[0].id)
        XCTAssertEqual(xp.lines.first { $0.id == "played" }?.amount, 5)
        XCTAssertEqual(xp.lines.first { $0.id == "completed" }?.amount, 15)
        XCTAssertEqual(xp.lines.first { $0.id == "win" }?.amount, 30)
        XCTAssertEqual(xp.lines.first { $0.id == "average" }?.amount, 15)
        XCTAssertEqual(xp.lines.first { $0.id == "checkout" }?.amount, 20)
        XCTAssertNil(xp.lines.first { $0.id == "one-eighty" })
        XCTAssertNil(xp.lines.first { $0.id == "adjustment" })
        XCTAssertEqual(xp.total, 85)
        XCTAssertEqual(xp.coefficient, 1)
        XCTAssertTrue(xp.reasons.isEmpty)
    }

    func testShortMatchKeepsOnlyBaseAndResult() {
        let match = sample(online: true, legs: 1, includeOneEighty: true)
        let xp = MatchRewards.award(match: match, playerID: match.players[0].id)
        XCTAssertEqual(xp.lines.map(\.id), ["played", "completed", "win"])
        XCTAssertEqual(xp.total, 50)
        XCTAssertTrue(xp.reasons.contains { $0.contains("3 dokončené legy") })
    }

    func testSpecialsCapAtThreeEightiesAndTwoHighCheckouts() {
        let match = cappedSpecials()
        let xp = MatchRewards.award(match: match, playerID: match.players[0].id)
        XCTAssertEqual(xp.lines.first { $0.id == "one-eighty" }?.amount, 30)
        XCTAssertEqual(xp.lines.first { $0.id == "high-checkout" }?.amount, 30)
    }

    func testLossDrawAndNoDarts() {
        var loss = sample(online: true, legs: 1)
        loss.winner = 1
        loss.states[1].legs = 1
        loss.states[0].legs = 0
        let lost = MatchRewards.award(match: loss, playerID: loss.players[0].id)
        XCTAssertEqual(lost.lines.first { $0.id == "loss" }?.amount, -10)
        XCTAssertNil(lost.lines.first { $0.id == "win" })
        XCTAssertEqual(lost.total, 10)

        var draw = sample(online: true, legs: 1)
        draw.winner = nil
        let drawn = MatchRewards.award(match: draw, playerID: draw.players[0].id)
        XCTAssertEqual(drawn.lines.first { $0.id == "draw" }?.amount, 15)
        XCTAssertEqual(drawn.total, 35)

        var empty = sample(online: true, legs: 1)
        empty.visits = []
        let none = MatchRewards.award(match: empty, playerID: empty.players[0].id)
        XCTAssertEqual(none.total, 0)
        XCTAssertTrue(none.reasons.contains { $0.contains("šipk") })

        var open = sample(online: true, legs: 1)
        open.finished = false
        let unfinished = MatchRewards.award(match: open, playerID: open.players[0].id)
        XCTAssertFalse(unfinished.hasAward)
        XCTAssertEqual(unfinished.total, 0)
    }

    func testLocalSoloAndGhostAwardNothing() {
        let local = sample(online: false, legs: 3)
        let localXP = MatchRewards.award(match: local, playerID: local.players[0].id)
        XCTAssertEqual(localXP.total, 0)
        XCTAssertEqual(localXP.coefficient, 0)
        XCTAssertTrue(localXP.reasons.contains { $0.contains("Lokální") })

        var solo = sample(online: true, legs: 1)
        solo.players = [solo.players[0]]
        solo.states = [solo.states[0]]
        solo.visits = solo.visits.filter { $0.player == 0 }
        solo.verifiedOnline = nil
        let soloXP = MatchRewards.award(match: solo, playerID: solo.players[0].id)
        XCTAssertEqual(soloXP.total, 0)
        XCTAssertTrue(soloXP.reasons.contains { $0.contains("soupeře") })
        XCTAssertNil(soloXP.lines.first { $0.id == "win" })

        var ghost = sample(online: false, legs: 1)
        ghost.ghostVisits = []
        ghost.ghostPlayerIndex = 1
        ghost.ghostKind = .best
        let ghostXP = MatchRewards.award(match: ghost, playerID: ghost.players[0].id)
        XCTAssertEqual(ghostXP.total, 0)
        XCTAssertTrue(ghostXP.reasons.contains { $0.contains("Ghost") })
    }

    func testBotHalvesXPAndNeedsAThrow() {
        let match = botMatch(level: 3, botThrows: true)
        let xp = MatchRewards.award(match: match, playerID: match.players[0].id)
        XCTAssertEqual(xp.total, 25)
        XCTAssertTrue(xp.reasons.contains { $0.contains("50 %") })

        let silent = botMatch(level: 3, botThrows: false)
        let quiet = MatchRewards.award(match: silent, playerID: silent.players[0].id)
        XCTAssertEqual(quiet.total, 0)
        XCTAssertTrue(quiet.reasons.contains { $0.contains("bot taky hodil") })
    }

    func testRepeatWindowAndBotDailyCap() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let me = Player(id: UUID(), name: "Já")
        var history: [Match] = []
        for offset in 0..<3 {
            history.append(botMatch(level: 4, botThrows: true, me: me, at: now.addingTimeInterval(TimeInterval(-3_600 * (offset + 1)))))
        }
        let fourth = botMatch(level: 4, botThrows: true, me: me, at: now)
        let half = MatchRewards.award(match: fourth, playerID: me.id, history: history)
        XCTAssertEqual(half.total, 13)
        XCTAssertTrue(half.reasons.contains { $0.contains("4. zápas") })

        history.append(botMatch(level: 4, botThrows: true, me: me, at: now.addingTimeInterval(-1_800)))
        history.append(botMatch(level: 4, botThrows: true, me: me, at: now.addingTimeInterval(-1_200)))
        let sixth = botMatch(level: 4, botThrows: true, me: me, at: now)
        let blocked = MatchRewards.award(match: sixth, playerID: me.id, history: history)
        XCTAssertEqual(blocked.total, 0)
        XCTAssertTrue(blocked.reasons.contains { $0.contains("6. zápas") })

        let stale = (0..<5).map { botMatch(level: 4, botThrows: true, me: me, at: now.addingTimeInterval(-26 * 3_600 - TimeInterval($0))) }
        let fresh = MatchRewards.award(match: botMatch(level: 4, botThrows: true, me: me, at: now), playerID: me.id, history: stale)
        XCTAssertEqual(fresh.total, 25)

        var today: [Match] = []
        for level in 1...10 {
            today.append(botMatch(level: level, botThrows: true, me: me, at: now.addingTimeInterval(TimeInterval(-level * 60))))
        }
        let eleventh = MatchRewards.award(match: botMatch(level: 11, botThrows: true, me: me, at: now), playerID: me.id, history: today)
        XCTAssertEqual(eleventh.total, 0)
        XCTAssertTrue(eleventh.reasons.contains { $0.contains("10") })
    }

    func testSingleFastWinStillPaysButBrokenLedgerAndPatternsDoNot() {
        var fast = sample(online: true, legs: 1)
        fast.playSeconds = 5
        fast.visits += Array(repeating: fast.visits[0], count: 3)
        let paid = MatchRewards.award(match: fast, playerID: fast.players[0].id)
        XCTAssertGreaterThan(paid.total, 0)
        XCTAssertFalse(paid.reasons.contains { $0.contains("prověření") })

        var broken = sample(online: true, legs: 1)
        broken.visits[0].remaining = 4
        let held = MatchRewards.award(match: broken, playerID: broken.players[0].id)
        XCTAssertEqual(held.total, 0)
        XCTAssertTrue(held.reasons.contains { $0.contains("nesedí") })

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let me = Player(id: UUID(), name: "Já")
        let prior = (0..<2).map { giveaway(me: me, at: now.addingTimeInterval(TimeInterval(-600 * ($0 + 1)))) }
        let third = MatchRewards.award(match: giveaway(me: me, at: now), playerID: me.id, history: prior)
        XCTAssertEqual(third.total, 0)
        XCTAssertTrue(third.reasons.contains { $0.contains("bez hodu soupeře") })

        let once = MatchRewards.award(match: giveaway(me: me, at: now), playerID: me.id)
        XCTAssertGreaterThan(once.total, 0)
    }

    func testOutlierAloneDoesNotWithholdButTwoSignalsDo() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let me = Player(id: UUID(), name: "Já")
        let baseline = (0..<5).map { ordinary(me: me, at: now.addingTimeInterval(TimeInterval(-86_400 * ($0 + 2)))) }
        var hot = ordinary(me: me, at: now)
        hot.playSeconds = 4
        hot.visits = (0..<4).map { index in
            Visit(player: 0, leg: 1, darts: [Dart(20, 3), Dart(20, 3), Dart(20, 1)], credited: 140, bust: false, checkout: index == 3, remaining: index == 3 ? 0 : 361)
        }
        hot.states[0].legs = 1
        let flagged = MatchRewards.award(match: hot, playerID: me.id, history: baseline)
        XCTAssertEqual(flagged.total, 0)
        XCTAssertTrue(flagged.review.contains("short-time"))
        XCTAssertTrue(flagged.review.contains("outlier"))

        hot.playSeconds = 600
        let onlyHigh = MatchRewards.award(match: hot, playerID: me.id, history: baseline)
        XCTAssertGreaterThan(onlyHigh.total, 0)
        XCTAssertTrue(onlyHigh.review.contains("outlier"))
        XCTAssertFalse(onlyHigh.reasons.contains { $0.contains("prověření") })
    }

    func testSameAwardCannotBeInsertedTwice() {
        let match = sample(online: true, legs: 1)
        let breakdown = MatchRewards.award(match: match, playerID: match.players[0].id)
        let award = MatchXPAward(owner: match.players[0].id, matchID: match.id, breakdown: breakdown)
        var book: [MatchXPAward] = []
        XCTAssertTrue(MatchXPBook.insert(award, into: &book))
        XCTAssertFalse(MatchXPBook.insert(award, into: &book))
        XCTAssertEqual(book.count, 1)
        XCTAssertEqual(book[0].amount, breakdown.total)
    }

    @MainActor
    func testFinishStoresOneAwardForTheProfile() {
        let profile = Profile(name: "Já")
        var stored = StoredData()
        stored.profiles = [profile]
        stored.selectedProfile = profile.id
        let store = AppStore(preview: stored)
        var match = sample(online: true, legs: 1)
        match.players[0].id = profile.id
        match.players[0].name = profile.name
        store.activeMatch = match
        store.finish()
        let first = store.xp
        XCTAssertEqual(first, 50)
        store.activeMatch = match
        store.finish()
        XCTAssertEqual(store.xp, first)
        XCTAssertEqual(store.data.matchXPAwards?.filter { $0.matchID == match.id }.count, 1)
    }

    // MARK: - Fixtures

    private func sample(online: Bool, legs: Int, includeOneEighty: Bool = false) -> Match {
        let config = GameConfig(startingScore: 40, outRule: .double, legsToWin: max(1, legs))
        var match = Match(config: config, players: [Player(name: "Já"), Player(name: "Soupeř")])
        match.finished = true
        match.winner = 0
        match.verifiedOnline = online ? true : nil
        match.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        match.states[0].legs = legs
        match.playSeconds = 600
        var visits: [Visit] = []
        if includeOneEighty {
            visits.append(Visit(player: 0, leg: 1, darts: [Dart(20, 3), Dart(20, 3), Dart(20, 3)], credited: 180, bust: false, checkout: true, remaining: 0))
        } else {
            visits.append(Visit(player: 0, leg: 1, darts: [.miss, .miss, Dart(20, 2)], credited: 40, bust: false, checkout: true, remaining: 0))
        }
        visits.append(Visit(player: 1, leg: 1, darts: [Dart(1)], credited: 1, bust: false, checkout: false, remaining: 39))
        if legs >= 3 {
            match.bullOffLegs = [2: 0, 3: 0]
        }
        match.visits = visits
        return match
    }

    private func cappedSpecials() -> Match {
        var match = Match(config: GameConfig(startingScore: 501, outRule: .straight, legsToWin: 3), players: [Player(name: "Já"), Player(name: "Soupeř")])
        match.finished = true
        match.winner = 0
        match.verifiedOnline = true
        match.states[0].legs = 3
        match.completedAt = Date(timeIntervalSince1970: 1_700_000_000)
        match.playSeconds = 900
        var visits: [Visit] = []
        for _ in 0..<4 {
            visits.append(Visit(player: 0, leg: 1, darts: [Dart(20, 3), Dart(20, 3), Dart(20, 3)], credited: 180, bust: false, checkout: false, remaining: 321))
        }
        for leg in 1...3 {
            visits.append(Visit(player: 0, leg: leg, darts: [Dart(20, 3), Dart(20, 3), Dart(20, 1)], credited: 140, bust: false, checkout: true, remaining: 0))
            visits.append(Visit(player: 1, leg: leg, darts: [Dart(1)], credited: 1, bust: false, checkout: false, remaining: 500))
        }
        match.visits = visits
        return match
    }

    private func botMatch(level: Int, botThrows: Bool, me: Player = Player(name: "Já"), at date: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> Match {
        var match = Match(config: GameConfig(startingScore: 40, outRule: .double, legsToWin: 1), players: [me, Player(name: "Bot", botLevel: level)])
        match.finished = true
        match.winner = 0
        match.states[0].legs = 1
        match.completedAt = date
        match.playSeconds = 120
        match.visits = [Visit(player: 0, leg: 1, darts: [Dart(20, 2)], credited: 40, bust: false, checkout: true, remaining: 0)]
        if botThrows {
            match.visits.append(Visit(player: 1, leg: 1, darts: [Dart(1)], credited: 1, bust: false, checkout: false, remaining: 39))
        }
        return match
    }

    private func giveaway(me: Player, at date: Date) -> Match {
        var match = botMatch(level: 2, botThrows: false, me: me, at: date)
        match.players[1] = Player(name: "Soupeř")
        match.verifiedOnline = true
        return match
    }

    private func ordinary(me: Player, at date: Date) -> Match {
        var match = Match(config: GameConfig(startingScore: 501, outRule: .straight, legsToWin: 1), players: [me, Player(name: "Soupeř")])
        match.finished = true
        match.winner = 0
        match.verifiedOnline = true
        match.states[0].legs = 1
        match.completedAt = date
        match.playSeconds = 400
        let scoring = Visit(player: 0, leg: 1, darts: [Dart(20), Dart(20), Dart(20)], credited: 40, bust: false, checkout: false, remaining: 461)
        match.visits = [scoring, scoring, scoring]
        match.visits.append(Visit(player: 1, leg: 1, darts: [Dart(1)], credited: 1, bust: false, checkout: false, remaining: 500))
        match.visits.append(Visit(player: 0, leg: 1, darts: [Dart(20, 2)], credited: 40, bust: false, checkout: true, remaining: 0))
        return match
    }
}
