import Foundation

/// Kam bot míří, když chce zavřít nebo si zavření připravit.
/// Cesta se po každé šipce počítá znovu. Slabší bot volí jednodušší, ale pořád legální ránu.
public enum BotCheckoutEngine {
    public static func aim<R: RandomNumberGenerator>(
        remaining: Int,
        dartsLeft: Int,
        rule: OutRule,
        opened: Bool,
        profile: BotProfile,
        thrown: [Dart] = [],
        opponentAboveCheckout: Bool = false,
        using rng: inout R
    ) -> Dart {
        let darts = min(3, max(1, dartsLeft))
        if !opened {
            return Dart(profile.preferredDoubles.first ?? 20, 2)
        }
        if rule != .straight && remaining <= 1 {
            return Dart(1, 2)
        }
        if let shaped = shapedAim(
            remaining: remaining,
            darts: darts,
            rule: rule,
            profile: profile,
            thrown: thrown,
            opponentAboveCheckout: opponentAboveCheckout,
            using: &rng
        ) {
            return shaped
        }
        if let route = preferredRoute(remaining: remaining, rule: rule, darts: darts, profile: profile), let first = route.first {
            if route.count == 1 { return first }
            let skill = profile.checkoutIntelligence
            if Double.random(in: 0..<1, using: &rng) < (0.42 + 0.58 * skill) {
                return soften(first, remaining: remaining, rule: rule, profile: profile, using: &rng)
            }
            if let simple = simpleLeave(remaining: remaining, rule: rule), isSafe(simple, remaining: remaining, rule: rule) {
                return simple
            }
            return soften(first, remaining: remaining, rule: rule, profile: profile, using: &rng)
        }
        if remaining <= 180, let setup = Checkout.setup(for: remaining, rule: rule, darts: darts), let first = setup.darts.first {
            let take = profile.style == .tactical || Double.random(in: 0..<1, using: &rng) < (0.34 + 0.66 * profile.checkoutIntelligence)
            if take, isSafe(first, remaining: remaining, rule: rule) {
                return soften(first, remaining: remaining, rule: rule, profile: profile, using: &rng)
            }
        }
        return scoringAim(
            remaining: remaining,
            rule: rule,
            profile: profile,
            thrown: thrown,
            using: &rng
        )
    }

    /// Konkrétní sehrávky, které tabulkový checkout bere moc „bezpečně“.
    private static func shapedAim<R: RandomNumberGenerator>(
        remaining: Int,
        darts: Int,
        rule: OutRule,
        profile: BotProfile,
        thrown: [Dart],
        opponentAboveCheckout: Bool,
        using rng: inout R
    ) -> Dart? {
        guard rule == .double else { return nil }
        // 121: půl na půl střed (25 → 96 → T20, D18) a dvacítka (S20 → 101 → T17, bull).
        if remaining == 121, darts == 3 {
            return Double.random(in: 0..<1, using: &rng) < 0.5 ? Dart(25, 2) : Dart(20, 3)
        }
        // 119 je přirozeně T19. S19 nechá 100, S17 by nechalo 102 a dvě šipky nestačí.
        if remaining == 119, darts == 3 {
            return Dart(19, 3)
        }
        if darts == 1 {
            // 18 po minutém D18 je D9. S16 by nechalo D1.
            if let finish = oneDartFinish(remaining: remaining, rule: rule) { return finish }
            // 116: T20 nechá 56. T19 jen když v dvacítce už není místo. Single 16 ne.
            if remaining == 116 {
                let occupied = thrown.filter { $0.segment == 20 && $0.multiplier == 3 }
                if !trebleHasRoom(segment: 20, occupied: occupied, profile: profile) {
                    return Dart(19, 3)
                }
                return Dart(20, 3)
            }
            let chase170 = opponentAboveCheckout && Double.random(in: 0..<1, using: &rng) < 0.30
            if chase170,
               let shot = ScoringSetup.lastDart(remaining: remaining, allowAwkward170: true),
               isAwkward170Single(shot, remaining: remaining),
               isSafe(shot, remaining: remaining, rule: rule) {
                return shot
            }
            if let natural = ScoringSetup.lastDart(remaining: remaining, allowAwkward170: false),
               !isAwkward170Single(natural, remaining: remaining),
               isSafe(natural, remaining: remaining, rule: rule) {
                return natural
            }
        }
        return nil
    }

    /// Checkout jednou šipkou. Nechání se řeší až když tohle skóre zavřít nejde.
    private static func oneDartFinish(remaining: Int, rule: OutRule) -> Dart? {
        guard let finish = Checkout.route(for: remaining, rule: rule, darts: 1)?.first,
              isSafe(finish, remaining: remaining, rule: rule) else { return nil }
        return finish
    }

    /// Single mimo velká čísla, jen aby zbylo 170. Třeba 179 → S9.
    private static func isAwkward170Single(_ dart: Dart, remaining: Int) -> Bool {
        guard dart.multiplier == 1, dart.segment < 15 else { return false }
        let leave = remaining - dart.score
        return (160...170).contains(leave)
    }

    /// Když by treble stejného čísla byl přehoz, posune míření k okraji.
    /// Slabý rozptyl na double jinak často trefí triple a vynuluje celou návštěvu.
    static func safetyShift(aim: Dart, remaining: Int, rule: OutRule, sigma: Double) -> Double {
        guard sigma > 0.05, (1...20).contains(aim.segment) else { return 0 }
        guard ScoringRules.isBust(remaining: remaining, dart: Dart(aim.segment, 3), rule: rule) else { return 0 }
        switch aim.multiplier {
        case 2:
            let clearance = BoardGeometry.doubleInner - BoardGeometry.tripleOuter
            return min(0.14, max(0, 1.35 * sigma - clearance))
        case 1:
            return min(0.10, max(0, 0.85 * sigma - 0.08))
        default:
            return 0
        }
    }

    /// Bez náhody. Berou se matematicky výhodné cesty, ať testy i nápověda stojí na místě.
    public static func planned(remaining: Int, dartsLeft: Int, rule: OutRule, opened: Bool, profile: BotProfile, thrown: [Dart] = []) -> Dart {
        let darts = min(3, max(1, dartsLeft))
        if !opened { return Dart(profile.preferredDoubles.first ?? 20, 2) }
        if rule != .straight && remaining <= 1 { return Dart(1, 2) }
        if rule == .double, remaining == 121, darts == 3 { return Dart(25, 2) }
        if rule == .double, remaining == 119, darts == 3 { return Dart(19, 3) }
        if rule == .double, remaining == 116, darts == 1 {
            let occupied = thrown.filter { $0.segment == 20 && $0.multiplier == 3 }
            if !trebleHasRoom(segment: 20, occupied: occupied, profile: profile) { return Dart(19, 3) }
            return Dart(20, 3)
        }
        if darts == 1, let finish = oneDartFinish(remaining: remaining, rule: rule) {
            return finish
        }
        if rule == .double, darts == 1,
           let natural = ScoringSetup.lastDart(remaining: remaining, allowAwkward170: false),
           !isAwkward170Single(natural, remaining: remaining),
           isSafe(natural, remaining: remaining, rule: rule) {
            return natural
        }
        if let route = preferredRoute(remaining: remaining, rule: rule, darts: darts, profile: profile), let first = route.first, isSafe(first, remaining: remaining, rule: rule) {
            return first
        }
        if remaining <= 180, let setup = Checkout.setup(for: remaining, rule: rule, darts: darts), let first = setup.darts.first, isSafe(first, remaining: remaining, rule: rule) {
            return first
        }
        return scoringAim(remaining: remaining, rule: rule, profile: profile, thrown: thrown)
    }

    private static func preferredRoute(remaining: Int, rule: OutRule, darts: Int, profile: BotProfile) -> [Dart]? {
        guard let primary = Checkout.route(for: remaining, rule: rule, darts: darts) else { return nil }
        // 135 začíná na bull. Oblíbený double nesmí střed vyměnit za T20.
        if primary.first?.segment == 25 { return primary }
        guard profile.checkoutIntelligence >= 0.55, darts >= 2, primary.count > 1 else { return primary }
        let options = Checkout.alternatives(for: remaining, rule: rule, darts: darts, limit: 12)
        guard !options.isEmpty else { return primary }
        let pool = insuredOpening(primary: primary, options: options, remaining: remaining, rule: rule, darts: darts)
        return pool.min { rank($0, profile: profile) < rank($1, profile: profile) } ?? primary
    }

    /// Oblíbený double nesmí změnit první pole, když už je pojištěné.
    /// 126 je T19: S19 nechá 107 (T19, bull). T18 by po S18 nechalo 108, a to dvěma šipkami nejde.
    private static func insuredOpening(primary: [Dart], options: [[Dart]], remaining: Int, rule: OutRule, darts: Int) -> [[Dart]] {
        guard darts >= 3, let first = primary.first, first.multiplier == 3, (1...20).contains(first.segment) else {
            return options
        }
        guard Checkout.singleMissStillFinishable(first, from: remaining, rule: rule, dartsLeft: darts - 1) else {
            return options
        }
        let sameBed = options.filter { $0.first == first }
        return sameBed.isEmpty ? options : sameBed
    }

    private static func rank(_ route: [Dart], profile: BotProfile) -> Int {
        let end = route.last?.segment ?? 99
        let preference = profile.preferredDoubles.firstIndex(of: end) ?? 30
        var score = preference * 3 + route.count * 2
        if route.count > 1, route.first?.multiplier == 2 { score += 28 }
        if route.first?.multiplier == 3 { score -= 6 }
        if profile.style == .aggressive, route.first?.multiplier == 3 { score -= 4 }
        return score
    }

    /// Nižší inteligence občas míří na single stejného čísla místo na triple.
    private static func soften<R: RandomNumberGenerator>(_ dart: Dart, remaining: Int, rule: OutRule, profile: BotProfile, using rng: inout R) -> Dart {
        guard dart.multiplier == 3, profile.style != .aggressive else { return dart }
        let chance = 1 - profile.checkoutIntelligence
        guard Double.random(in: 0..<1, using: &rng) < chance * 0.55 else { return dart }
        let single = Dart(dart.segment)
        return isSafe(single, remaining: remaining, rule: rule) ? single : dart
    }

    private static func simpleLeave(remaining: Int, rule: OutRule) -> Dart? {
        let floor = rule == .straight ? 1 : 2
        let leaves = [40, 32, 36, 24, 16, 20, 50, 8, 12, 4, 60, 100, 80]
        for leave in leaves where leave < remaining && leave >= floor {
            let need = remaining - leave
            if (1...20).contains(need) { return Dart(need) }
            if need % 3 == 0, (1...20).contains(need / 3) { return Dart(need / 3, 3) }
        }
        return nil
    }

    /// Skórovací žebříček terci. Po T20 se na 19 neschází samo — jen když už se do pole další šipka nevejde.
    static func scoringLadder(for profile: BotProfile) -> [Int] {
        switch profile.style {
        case .aggressive:
            return uniqueSegments([20, 18, 19, 17])
        case .tactical:
            return uniqueSegments([20, 19, 18, 17])
        case .unpredictable:
            return uniqueSegments([profile.preferredScoringTarget.segment, 20, 19, 18, 17])
        default:
            return uniqueSegments([profile.preferredScoringTarget.segment, 20, 19, 18, 17])
        }
    }

    /// Index terci v žebříčku. Trefená T20 zůstává, dokud se do pole vejde další šipka.
    /// Podhoz do 19 (mimo její treble) nebo minutí zakryté T19 posune míření na 18.
    static func scoringBedIndex<R: RandomNumberGenerator>(
        thrown: [Dart],
        ladder: [Int],
        profile: BotProfile,
        using rng: inout R
    ) -> Int {
        _ = rng
        return scoringBedIndex(thrown: thrown, ladder: ladder, profile: profile)
    }

    static func scoringBedIndex(thrown: [Dart], ladder: [Int], profile: BotProfile) -> Int {
        guard !ladder.isEmpty else { return 0 }
        var bed = 0
        for (index, dart) in thrown.enumerated() {
            let aim = ladder[bed]
            let next = bed + 1 < ladder.count ? ladder[bed + 1] : nil
            if dart.segment == aim, dart.multiplier == 3 {
                let occupied = thrown[...index].filter { $0.segment == aim && $0.multiplier == 3 }
                if !trebleHasRoom(segment: aim, occupied: Array(occupied), profile: profile) {
                    bed = min(bed + 1, ladder.count - 1)
                }
            } else if let next, dart.segment == next {
                // Podhoz do dalšího čísla bez treble (19) přeskakuje rovnou na 18. Trefená T19 se na 19 nechá.
                bed = min(bed + (dart.multiplier == 3 ? 1 : 2), ladder.count - 1)
            } else if dart.segment == aim, dart.multiplier != 3,
                      thrown[..<index].contains(where: { $0.segment == aim }) {
                bed = min(bed + 1, ladder.count - 1)
            }
        }
        return bed
    }

    /// Ve treble segmentu ještě zbývá místo na další šipku.
    /// Průměr hlavičky je asi 6,6 mm, poloměr bodované plochy 170 mm. Lepší bot se vejde do menší mezery.
    static func trebleHasRoom(segment: Int, occupied: [Dart], profile: BotProfile) -> Bool {
        guard (1...20).contains(segment), let index = BoardGeometry.sectors.firstIndex(of: segment) else { return true }
        let points: [(Double, Double)] = occupied.map { dart in
            if let x = dart.x, let y = dart.y, x.isFinite, y.isFinite { return (x, y) }
            let aim = DartboardGeometry.aim(segment: dart.segment, multiplier: max(1, dart.multiplier))
            return (aim.x, aim.y)
        }
        guard !points.isEmpty else { return true }
        let skill = min(1, max(0, profile.checkoutIntelligence))
        let gap = (8.2 - 3.6 * skill) / 170
        let inset = 6.6 / 170 / 2
        let radialMin = BoardGeometry.tripleInner + inset
        let radialMax = BoardGeometry.tripleOuter - inset
        guard radialMax > radialMin else { return false }
        let center = -Double.pi / 2 + Double(index) * .pi / 10
        let half = Double.pi / 20
        let angularInset = inset / ((radialMin + radialMax) / 2)
        let angleMin = center - half + angularInset
        let angleMax = center + half - angularInset
        guard angleMax > angleMin else { return false }
        let radialSteps = 3
        let angularSteps = 7
        for rStep in 0..<radialSteps {
            let t = Double(rStep) / Double(radialSteps - 1)
            let radius = radialMin + (radialMax - radialMin) * t
            for aStep in 0..<angularSteps {
                let u = Double(aStep) / Double(angularSteps - 1)
                let angle = angleMin + (angleMax - angleMin) * u
                let x = cos(angle) * radius
                let y = sin(angle) * radius
                if points.allSatisfy({ hypot(x - $0.0, y - $0.1) >= gap }) { return true }
            }
        }
        return false
    }

    static func scoringAim<R: RandomNumberGenerator>(
        remaining: Int,
        rule: OutRule,
        profile: BotProfile,
        thrown: [Dart] = [],
        using rng: inout R
    ) -> Dart {
        if let setup = ScoringSetup.aim(
            remaining: remaining,
            dartsLeft: visitDartsLeft(thrown),
            rule: rule,
            profile: profile,
            thrown: thrown
        ) {
            return setup
        }
        let ladder = scoringLadder(for: profile)
        let start = scoringBedIndex(thrown: thrown, ladder: ladder, profile: profile, using: &rng)
        return pickScoringTreble(remaining: remaining, rule: rule, profile: profile, ladder: ladder, start: start)
            ?? pickScoringSingle(remaining: remaining, rule: rule, profile: profile)
    }

    static func scoringAim(remaining: Int, rule: OutRule, profile: BotProfile, thrown: [Dart] = []) -> Dart {
        if let setup = ScoringSetup.aim(
            remaining: remaining,
            dartsLeft: visitDartsLeft(thrown),
            rule: rule,
            profile: profile,
            thrown: thrown
        ) {
            return setup
        }
        let ladder = scoringLadder(for: profile)
        let start = scoringBedIndex(thrown: thrown, ladder: ladder, profile: profile)
        return pickScoringTreble(remaining: remaining, rule: rule, profile: profile, ladder: ladder, start: start)
            ?? pickScoringSingle(remaining: remaining, rule: rule, profile: profile)
    }

    private static func visitDartsLeft(_ thrown: [Dart]) -> Int {
        min(3, max(1, 3 - thrown.count))
    }

    private static func pickScoringTreble(remaining: Int, rule: OutRule, profile: BotProfile, ladder: [Int], start: Int) -> Dart? {
        guard !ladder.isEmpty else { return nil }
        let order = Array(ladder[start...]) + Array(ladder[..<start])
        for segment in order {
            let treble = Dart(min(20, max(1, segment)), 3)
            guard isSafe(treble, remaining: remaining, rule: rule) else { continue }
            let leave = remaining - treble.score
            if profile.style == .tactical, leave <= 170, leave >= 2, Checkout.route(for: leave, rule: rule) == nil {
                continue
            }
            return treble
        }
        return nil
    }

    private static func pickScoringSingle(remaining: Int, rule: OutRule, profile: BotProfile) -> Dart {
        let floor = rule == .straight ? 0 : 2
        let wide = profile.singleSigma > 0.10
        for segment in stride(from: 20, through: 1, by: -1) {
            let single = Dart(segment)
            if wide && !missesStayIn(segment: segment, remaining: remaining, rule: rule) { continue }
            if isSafe(single, remaining: remaining, rule: rule), remaining - single.score >= floor || rule == .straight {
                return single
            }
        }
        return Dart(1)
    }

    private static func uniqueSegments(_ values: [Int]) -> [Int] {
        var seen = Set<Int>()
        var out: [Int] = []
        for value in values {
            let segment = min(20, max(1, value))
            if seen.insert(segment).inserted { out.append(segment) }
        }
        return out
    }

    static func isSafe(_ dart: Dart, remaining: Int, rule: OutRule) -> Bool {
        !ScoringRules.isBust(remaining: remaining, dart: dart, rule: rule)
    }

    /// U širokého rozptylu nesmí ani triple ani double téhož čísla shodit návštěvu.
    private static func missesStayIn(segment: Int, remaining: Int, rule: OutRule) -> Bool {
        isSafe(Dart(segment, 2), remaining: remaining, rule: rule)
            && isSafe(Dart(segment, 3), remaining: remaining, rule: rule)
    }
}
