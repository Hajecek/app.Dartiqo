import Foundation

/// Sehrávka na checkout podle příručky, ne pořád T20.
/// 273 → T19 T19 S19 (140). 305 a 308 začínají na 18, protože single 20 nechá bogey.
/// 265 začíná na 19: pět zásahů (jedna T19 a dva singly) nechá 170, pět dvacítek bogey 165.
/// Po T19 se dál míří na T19. Single je minutí podle úspěšnosti úrovně, ne další plán.
/// Když už 180 z dvacítek nechá zavření, zůstává na 20. Čisté skórování (501) řeší rotace terci.
enum ScoringSetup {
    private static let beds = [20, 19, 18]
    /// Čísla, na která se vyplatí sehrát i za cenu menšího součtu.
    private static let tierOne: Set<Int> = [170, 167, 164, 161, 160, 140, 100, 80, 50, 40, 32]
    private static let tierTwo: Set<Int> = [158, 157, 156, 154, 152, 150, 141, 136, 130, 121, 120, 110, 101, 81, 64, 60, 41, 36, 24, 16]
    private static let threeDartBogeys: Set<Int> = [169, 168, 166, 165, 163, 162, 159]
    private static let sixDartBogeys: Set<Int> = [349, 348, 346, 345, 343, 342, 339]
    private static let sixDartTargets: Set<Int> = [350, 347, 344, 341, 340]

    /// `nil`, když není co sehrávat — skórování pak řeší rotace 20 → 19 → 18.
    static func aim(remaining: Int, dartsLeft: Int, rule: OutRule, profile: BotProfile) -> Dart? {
        guard rule == .double, profile.checkoutIntelligence >= 0.40 else { return nil }
        guard (1...3).contains(dartsLeft), (2...501).contains(remaining), remaining <= 490 else { return nil }
        if (451...490).contains(remaining) {
            return sixDartAim(remaining: remaining, darts: dartsLeft)
        }
        return checkoutAim(remaining: remaining, darts: dartsLeft, profile: profile)
    }

    private static let finishable: Set<Int> = Set((2...170).filter { Checkout.canFinish($0) })

    /// Pořadí nechání, když zbývá jedna šipka. 170 je výš než 167, ať 227 jde na T19.
    private static let oneDartLeaves = [170, 167, 164, 161, 160, 158, 157, 156, 154, 152, 150, 140, 136, 120, 130, 110, 100, 81, 80, 64, 60, 50, 41, 40, 36, 32, 24, 16, 8, 4]

    private static func checkoutAim(remaining: Int, darts: Int, profile: BotProfile) -> Dart? {
        if darts == 1, let exact = oneDartLeave(remaining: remaining) { return exact }
        if let five = fiveMarkAim(remaining: remaining, darts: darts, profile: profile) { return five }
        guard let choice = bestBed(remaining: remaining, darts: darts, score: { path in
            checkoutValue(path, remaining: remaining)
        }) else { return nil }
        let trebleFinishes = finishable.contains(choice.trebleLeave)
        let singleFinishes = finishable.contains(choice.singleLeave)
        guard trebleFinishes || singleFinishes else { return nil }
        if darts == 1, choice.singleValue > choice.trebleValue { return choice.single }
        return choice.treble
    }

    private static func sixDartAim(remaining: Int, darts: Int) -> Dart? {
        // Single má stejnou váhu: S20 z 488/485 nechá šestidartový bogey, proto se začíná na 18.
        guard let choice = bestBed(remaining: remaining, darts: darts, trebleWeight: 50, singleWeight: 50, score: { path in
            sixDartValue(path, remaining: remaining)
        }) else { return nil }
        guard sixDartTargets.contains(choice.trebleLeave) || sixDartTargets.contains(choice.singleLeave) else { return nil }
        return choice.treble
    }

    private struct BedChoice {
        var treble: Dart
        var single: Dart
        var trebleValue: Int
        var singleValue: Int
        var trebleLeave: Int
        var singleLeave: Int
    }

    private static func bestBed(remaining: Int, darts: Int, trebleWeight: Int = 60, singleWeight: Int = 40, score: ([Dart]) -> Int) -> BedChoice? {
        let paths = sequences(remaining: remaining, darts: darts)
        var best: (blend: Int, choice: BedChoice)?
        for segment in beds {
            let treble = Dart(segment, 3)
            let single = Dart(segment)
            let trebles = paths.filter { $0.first == treble }
            let singles = paths.filter { $0.first == single }
            guard let treblePath = trebles.max(by: { score($0) < score($1) }),
                  let singlePath = singles.max(by: { score($0) < score($1) }) else { continue }
            let trebleValue = score(treblePath)
            let singleValue = score(singlePath)
            let blend = trebleValue * trebleWeight + singleValue * singleWeight
            let choice = BedChoice(
                treble: treble,
                single: single,
                trebleValue: trebleValue,
                singleValue: singleValue,
                trebleLeave: remaining - treblePath.reduce(0) { $0 + $1.score },
                singleLeave: remaining - singlePath.reduce(0) { $0 + $1.score }
            )
            if best == nil || blend > best!.blend {
                best = (blend, choice)
            }
        }
        return best?.choice
    }

    private static func checkoutValue(_ path: [Dart], remaining: Int) -> Int {
        let scored = path.reduce(0) { $0 + $1.score }
        let leave = remaining - scored
        guard leave >= 2 else { return -1_000_000 }
        let sameBed = path.allSatisfy { $0.segment == path[0].segment }
        return scored + leaveBonus(leave) + (sameBed ? 12 : 0)
    }

    /// Pět zásahů do 19 nechá 170/167/164. Na 265, 262 a 259 se proto začíná na T19.
    /// Další šipka pořád míří na T19. Na single přejde jen tehdy, když to podle
    /// úspěšnosti dané úrovně vychází zřetelně líp.
    private static func fiveMarkAim(remaining: Int, darts: Int, profile: BotProfile) -> Dart? {
        if darts == 3 {
            let onTwenty = remaining - 100
            if finishable.contains(onTwenty), !threeDartBogeys.contains(onTwenty) { return nil }
            guard [170, 167, 164, 161, 160].contains(remaining - 95) else { return nil }
            return Dart(19, 3)
        }
        guard darts == 2 else { return nil }
        let stillOnNineteen = fiveMarkAim(remaining: remaining + 57, darts: 3, profile: profile) != nil
            || fiveMarkAim(remaining: remaining + 19, darts: 3, profile: profile) != nil
        guard stillOnNineteen else { return nil }
        return trebleUnlessSinglePays(remaining: remaining, segment: 19, profile: profile)
    }

    /// Očekávaná hodnota míření na treble a na single. Single vyhraje, jen když je jasně lepší.
    private static func trebleUnlessSinglePays(remaining: Int, segment: Int, profile: BotProfile) -> Dart {
        let treble = Dart(segment, 3)
        let single = Dart(segment)
        let trebleValue = expectedFinish(remaining: remaining, aim: treble, profile: profile)
        let singleValue = expectedFinish(remaining: remaining, aim: single, profile: profile)
        if singleValue > trebleValue + 18 { return single }
        return treble
    }

    /// Dvě zbývající šipky: tahle podle rozptylu úrovně, poslední podle nejlepšího nechání.
    private static func expectedFinish(remaining: Int, aim: Dart, profile: BotProfile) -> Double {
        let thrown = sampleHits(aim: aim, profile: profile)
        var total = 0.0
        var count = 0
        for hit in thrown {
            let next = remaining - hit.score
            guard next >= 2 else {
                total += -400
                count += 1
                continue
            }
            let follow = oneDartLeave(remaining: next) ?? aim
            for last in sampleHits(aim: follow, profile: profile) {
                let leave = next - last.score
                let scored = hit.score + last.score
                total += leave >= 2 ? Double(scored + leaveBonus(leave)) : -400
                count += 1
            }
        }
        guard count > 0 else { return -1_000 }
        return total / Double(count)
    }

    /// Stejný rozptyl → stejné zásahy. Úroveň vstupuje jen přes sigmu profilu.
    private static func sampleHits(aim: Dart, profile: BotProfile, count: Int = 72) -> [Dart] {
        let sigma = profile.sigma(for: aim)
        let seed = UInt64((sigma * 20_000).rounded()) ^ UInt64(aim.segment * 97 + aim.multiplier * 13) ^ 0xA11
        var rng = BotRNG(seed: seed == 0 ? 1 : seed)
        return (0..<count).map { _ in
            DartThrowSimulator.throw(at: aim, profile: profile, using: &rng)
        }
    }

    /// Velká nechání, kvůli kterým se vyplatí i menší pole (221 → T17, 187 → S17).
    private static let eliteLeaves: Set<Int> = [170, 167, 164, 161, 160, 140, 100, 80, 50, 40, 36, 32, 24, 16]

    /// Jedna šipka: vezmi hod, po kterém zůstane nejlepší zavření. 227 − T19 = 170.
    /// Malá pole jen tehdy, když trefí elitní nechání — ať 159 nejde na S1 kvůli 158.
    private static func oneDartLeave(remaining: Int) -> Dart? {
        let options = (1...20).reversed().flatMap { [Dart($0, 3), Dart($0, 2), Dart($0)] } + [Dart(25, 2), Dart(25)]
        var best: (rank: Int, dart: Dart)?
        for dart in options {
            let leave = remaining - dart.score
            guard leave >= 2, finishable.contains(leave) else { continue }
            guard isBigBed(dart) || eliteLeaves.contains(leave) else { continue }
            let rank = oneDartRank(leave) * 1_000 + dart.segment * 10 + dart.multiplier
            if best == nil || rank > best!.rank {
                best = (rank, dart)
            }
        }
        return best?.dart
    }

    private static func isBigBed(_ dart: Dart) -> Bool {
        if dart.segment == 25 { return true }
        if (15...20).contains(dart.segment), dart.multiplier == 3 || dart.multiplier == 1 { return true }
        return dart.multiplier == 2 && [20, 16, 8].contains(dart.segment)
    }

    /// Dvoušipkové zavření na dvou číslech (98 = T20 + D19), ne přes bull.
    private static let twoNumberOuts: Set<Int> = {
        Set((2...110).filter { leave in
            guard let route = Checkout.route(for: leave, darts: 2) else { return false }
            return route.allSatisfy { $0.segment <= 20 }
        })
    }()

    private static func oneDartRank(_ leave: Int) -> Int {
        // 170–160 pořád nejvýš (227 → T19). Pod nimi dvoušipkové zavření: 158 → T20 nechá 98.
        if let index = oneDartLeaves.firstIndex(of: leave), index <= 4 { return 800 - index }
        if twoNumberOuts.contains(leave) { return 600 }
        if Checkout.canFinish(leave, darts: 2) { return 500 }
        if let index = oneDartLeaves.firstIndex(of: leave) { return 400 - index }
        return 40
    }

    private static func leaveBonus(_ leave: Int) -> Int {
        if threeDartBogeys.contains(leave) || sixDartBogeys.contains(leave) { return -250 }
        guard finishable.contains(leave) else { return 0 }
        if tierOne.contains(leave) { return 120 }
        if tierTwo.contains(leave) { return 100 }
        return 40
    }

    private static func sixDartValue(_ path: [Dart], remaining: Int) -> Int {
        let scored = path.reduce(0) { $0 + $1.score }
        let leave = remaining - scored
        guard leave >= 2 else { return -1_000_000 }
        if sixDartBogeys.contains(leave) { return -400 }
        if sixDartTargets.contains(leave) { return 800 + scored }
        return scored
    }

    /// T/S 20, 19, 18, plus 25 a bull. Dva bully v jedné návštěvě ne.
    private static func sequences(remaining: Int, darts: Int) -> [[Dart]] {
        let options = beds.flatMap { [Dart($0, 3), Dart($0)] } + [Dart(25), Dart(25, 2)]
        var found: [[Dart]] = []
        func walk(_ left: Int, _ need: Int, _ path: [Dart]) {
            if need == 0 {
                found.append(path)
                return
            }
            let usedBull = path.contains { $0.segment == 25 && $0.multiplier == 2 }
            for dart in options {
                if usedBull, dart.segment == 25, dart.multiplier == 2 { continue }
                let next = left - dart.score
                guard next >= 2 else { continue }
                walk(next, need - 1, path + [dart])
            }
        }
        walk(remaining, darts, [])
        return found
    }
}
