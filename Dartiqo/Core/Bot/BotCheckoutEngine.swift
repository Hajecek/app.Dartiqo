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
        using rng: inout R
    ) -> Dart {
        let darts = min(3, max(1, dartsLeft))
        if !opened {
            return Dart(profile.preferredDoubles.first ?? 20, 2)
        }
        if rule != .straight && remaining <= 1 {
            return Dart(1, 2)
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
        return scoringAim(remaining: remaining, rule: rule, profile: profile, thrown: thrown, using: &rng)
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

    /// Skórovací žebříček terci — po zakrytí pole jde bot dolů (20 → 19 → 18), rozptyl zůstává stejný.
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

    /// Index terci v žebříčku pro aktuální šipku.
    /// Zakrytí pole, zásah do souseda (u 20 → 1/5) nebo „roam“ posune míření dál (20 → 19 → 18).
    static func scoringBedIndex<R: RandomNumberGenerator>(
        thrown: [Dart],
        ladder: [Int],
        profile: BotProfile,
        using rng: inout R
    ) -> Int {
        scoringBedIndex(thrown: thrown, ladder: ladder, profile: profile) { chance in
            Double.random(in: 0..<1, using: &rng) < chance
        }
    }

    static func scoringBedIndex(thrown: [Dart], ladder: [Int], profile: BotProfile) -> Int {
        scoringBedIndex(thrown: thrown, ladder: ladder, profile: profile) { chance in
            // Deterministicky: přejdi, když je šance aspoň typická pro danou úroveň.
            chance >= 0.55
        }
    }

    private static func scoringBedIndex(
        thrown: [Dart],
        ladder: [Int],
        profile: BotProfile,
        shouldSwitch: (Double) -> Bool
    ) -> Int {
        guard !ladder.isEmpty else { return 0 }
        let skill = profile.checkoutIntelligence
        // Po zásahu do aktuálního pole — „zakrytí“ — přechod na další terci.
        let coverChance = 0.28 + 0.70 * skill
        // Zásah do souseda (T20 → 1 nebo 5): hráč cítí, že skupina sedí vedle, a přejde na 19.
        let missReadChance = 0.30 + 0.58 * skill
        // Bez zásahu se lepší hráč občas stejně posune o jednu terci.
        let roamChance = 0.10 + 0.40 * skill
        var bed = 0
        for dart in thrown {
            let aim = ladder[bed]
            if dart.segment == aim {
                if shouldSwitch(coverChance) {
                    bed = min(bed + 1, ladder.count - 1)
                }
            } else if isNeighborMiss(dart.segment, of: aim), shouldSwitch(missReadChance) {
                bed = min(bed + 1, ladder.count - 1)
            }
        }
        let want = min(thrown.count, ladder.count - 1)
        if bed < want, shouldSwitch(roamChance) {
            bed = min(bed + 1, want)
        }
        return bed
    }

    /// Sousedi na terči — u 20 jsou 1 a 5, u 19 jsou 3 a 7 atd.
    private static func isNeighborMiss(_ segment: Int, of aim: Int) -> Bool {
        guard let neighbors = DartboardGeometry.neighbors(of: aim) else { return false }
        return segment == neighbors.clockwise || segment == neighbors.counterClockwise
    }

    static func scoringAim<R: RandomNumberGenerator>(
        remaining: Int,
        rule: OutRule,
        profile: BotProfile,
        thrown: [Dart] = [],
        using rng: inout R
    ) -> Dart {
        if let setup = ScoringSetup.aim(remaining: remaining, dartsLeft: visitDartsLeft(thrown), rule: rule, profile: profile) {
            return setup
        }
        let ladder = scoringLadder(for: profile)
        let start = scoringBedIndex(thrown: thrown, ladder: ladder, profile: profile, using: &rng)
        return pickScoringTreble(remaining: remaining, rule: rule, profile: profile, ladder: ladder, start: start)
            ?? pickScoringSingle(remaining: remaining, rule: rule, profile: profile)
    }

    static func scoringAim(remaining: Int, rule: OutRule, profile: BotProfile, thrown: [Dart] = []) -> Dart {
        if let setup = ScoringSetup.aim(remaining: remaining, dartsLeft: visitDartsLeft(thrown), rule: rule, profile: profile) {
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
