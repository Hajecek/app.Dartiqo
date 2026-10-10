import Foundation

enum TrainingReplay {
    static func play(_ session: TrainingSession, at now: Date) -> TrainingProjection {
        let run = TrainingRun(session: session, now: now)
        switch session.kind {
        case .around(_, _, let limit):
            return run.untilHit(limit: limit, lowScore: true)
        case .chaos(let limit):
            return run.untilHit(limit: limit, lowScore: true)
        case .bobs27:
            return run.bobs()
        case .jdc:
            return run.cards(halve: false)
        case .halve:
            return run.cards(halve: true)
        case .volume(_, let darts, let accuracy):
            return run.steps(fail: false, dartsEach: darts, accuracy: accuracy, minimumHits: nil)
        case .shanghai(let numbers, let instant, let limit):
            return run.shanghai(numbers: numbers, instant: instant, limit: limit)
        case .cricket(let numbers, let limit):
            return run.cricket(numbers: numbers, limit: limit)
        case .checkoutFixed(_, let visits, let need, let doubleIn):
            return run.checkouts(maxVisits: visits, need: need, doubleIn: doubleIn)
        case .checkoutUntil(let start, let visits, let doubleIn):
            return run.until(start: start, visits: visits, doubleIn: doubleIn)
        case .checkoutRange(_, _, _, let need):
            return run.checkouts(maxVisits: 1, need: need, doubleIn: false)
        case .checkoutGenerated(_, let need):
            return run.checkouts(maxVisits: 1, need: need, doubleIn: false)
        case .x01(let start, let limit, let doubleIn, let average):
            return run.leg(start: start, limit: limit, doubleIn: doubleIn, minAverage: average, opponentAt: nil)
        case .visitGoal(let atLeast, let exact, let count, let need):
            return run.goals(atLeast: atLeast, exact: exact, count: count, need: need)
        case .ladder(let targets):
            return run.ladder(targets: targets)
        case .consistency(let visits, let spread, let floor):
            return run.consistency(visits: visits, spread: spread, floor: floor)
        case .highScore(let visits):
            return run.highScore(visits: visits)
        case .average(let visits, let target):
            return run.average(visits: visits, target: target)
        case .sniper(_, let need), .switchTreble(_, let need):
            return run.steps(fail: false, dartsEach: 1, accuracy: nil, minimumHits: need)
        case .hunter(_, let lives):
            return run.hunter(lives: lives)
        case .survivor(_, let lives):
            return run.survivor(lives: lives)
        case .streak(_, let need, let limit):
            return run.streak(need: need, limit: limit)
        case .roulette(_, let need):
            return run.roulette(need: need)
        case .bullScore(let darts, let target):
            return run.bulls(darts: darts, target: target)
        case .combo(let need, let limit):
            return run.combo(need: need, limit: limit)
        case .sudden(let need, let limit):
            return run.sudden(need: need, limit: limit)
        case .puzzle(_, let need):
            return run.puzzles(need: need)
        case .rush(let seconds, let need, let limit):
            return run.rush(seconds: seconds, need: need, limit: limit)
        case .marathon(_, _), .tower(_), .daily(_), .world(_), .stepList(_, _, _):
            return run.steps(fail: true, dartsEach: 3, accuracy: nil, minimumHits: nil)
        case .risk(let rounds, let target):
            return run.risk(rounds: rounds, target: target)
        case .segments(_, _, let darts, let accuracy):
            return run.steps(fail: false, dartsEach: darts, accuracy: accuracy, minimumHits: nil)
        case .perfect(_, let need, _):
            return run.exact(need: need)
        case .exact(_, let need):
            return run.exact(need: need)
        case .memory:
            return run.recall()
        case .escape(_, let lives):
            return run.escape(lives: lives)
        case .oneDart(_, let need):
            return run.steps(fail: false, dartsEach: 1, accuracy: nil, minimumHits: need)
        case .ghost(let visits):
            return run.ghost(visits: visits)
        case .comeback(let opponentVisits):
            return run.leg(start: 301, limit: 90, doubleIn: false, minAverage: nil, opponentAt: opponentVisits)
        case .finalDart(_, let need):
            return run.final(need: need)
        case .boss(let lives):
            return run.boss(lives: lives)
        }
    }
}

private final class TrainingRun {
    let actions: [TrainingAction]
    let assignment: TrainingAssignment
    let players: Int
    let names: [String]
    let now: Date
    let started: Date
    var index = 0
    var ideal: TrainingAction?
    var waiting = false
    var darts: [Dart] = []
    var feedback: TrainingFeedback = .none
    var hits = 0
    var misses = 0
    var score = 0
    var combo = 0
    var bestCombo = 0
    var lives: Int?
    var busts = 0
    var checkoutHits = 0
    var checkoutAttempts = 0
    var visitScores: [Int] = []
    var visitDartCounts: [Int] = []
    var checkoutLeaves: [Int] = []
    var checkoutMade: [Int] = []
    var tally: [String: (hits: Int, attempts: Int)] = [:]
    var visit = 1
    var task = "Hoď"
    var target = ""
    var detail = ""
    var hint: String?
    var routes: [[Dart]] = []
    var phase: TrainingPhase = .scoring
    var choices: [String] = []
    var memory: [String] = []
    var bossHP: Int?
    var bossMax: Int?
    var ghost: String?
    var playerLine: String?
    var progress = 0.0
    var progressText = ""
    var scoreText = "0"
    var higher = true
    var record = 0
    var dartsLeft = 3
    var success = false
    var summary = ""
    var trackAverage = false
    var bogeys: [Int] = []

    init(session: TrainingSession, now: Date) {
        actions = session.actions
        assignment = session.assignment
        players = max(1, session.players)
        names = session.names.isEmpty ? ["Hráč"] : session.names
        self.now = now
        started = session.startedAt
        bogeys = session.assignment.bogeys
    }

    func dart(_ fallback: Dart) -> Dart? {
        while index < actions.count {
            let action = actions[index]
            index += 1
            if case .dart(let thrown) = action { return thrown.isValid ? thrown : .miss }
        }
        ideal = .dart(fallback)
        waiting = true
        phase = .scoring
        return nil
    }

    func choice() -> Int? {
        while index < actions.count {
            let action = actions[index]
            index += 1
            if case .choose(let value) = action { return value }
        }
        ideal = .choose(0)
        waiting = true
        phase = .choose
        choices = ["Jistota S20", "Risk T20"]
        return nil
    }

    func ready() -> Bool {
        while index < actions.count {
            let action = actions[index]
            index += 1
            if case .ready = action { return true }
        }
        ideal = .ready
        waiting = true
        phase = .memorize
        return false
    }

    func push(_ dart: Dart) { darts.append(dart) }

    @discardableResult
    func absorb(_ dart: Dart, aim: Aim) -> Bool {
        push(dart)
        var slot = tally[aim.tallyKey] ?? (0, 0)
        slot.attempts += 1
        let hit = aim.matches(dart)
        if hit {
            slot.hits += 1
            hits += 1
            combo += 1
            bestCombo = max(bestCombo, combo)
            feedback = .hit
        } else {
            misses += 1
            combo = 0
            feedback = .miss
        }
        tally[aim.tallyKey] = slot
        return hit
    }

    func closeVisit(_ credited: Int, dartsUsed: Int) {
        visitScores.append(credited)
        visitDartCounts.append(max(1, dartsUsed))
        if credited >= 180 { /* counted below */ }
        if credited >= 100 { /* visit list is enough */ }
        visit += 1
    }

    func mark(_ done: Int, of total: Int) {
        let total = max(total, 1)
        progress = min(1, Double(done) / Double(total))
        progressText = "\(min(done, total))/\(total)"
    }

    func pause() -> TrainingProjection { output(finished: false) }

    func finish(_ won: Bool, _ text: String) -> TrainingProjection {
        success = won
        summary = text
        return output(finished: true)
    }

    func output(finished: Bool) -> TrainingProjection {
        var projection = TrainingProjection()
        projection.task = task
        projection.target = target
        projection.scoreText = scoreText
        projection.detail = detail
        projection.dartsLeft = dartsLeft
        projection.visit = max(1, visit)
        projection.progress = finished ? 1 : progress
        projection.progressText = progressText
        projection.recent = Array(darts.suffix(8))
        projection.feedback = feedback
        projection.finished = finished
        projection.success = finished && success
        projection.phase = phase
        projection.choices = choices
        projection.memory = memory
        projection.lives = lives
        projection.combo = combo
        projection.bossHP = bossHP
        projection.bossMax = bossMax
        projection.hint = hint
        projection.routes = routes
        projection.bogeys = bogeys
        projection.ghost = ghost
        projection.playerLine = players > 1 ? playerLine : nil
        projection.score = record
        projection.higherIsBetter = higher
        projection.ideal = waiting ? ideal : nil
        if finished { projection.result = makeResult() }
        return projection
    }

    func makeResult() -> TrainingResult {
        var result = TrainingResult()
        result.success = success
        result.score = record
        result.higherIsBetter = higher
        result.darts = darts.count
        result.hits = hits
        result.accuracy = hits + misses == 0 ? 0 : Double(hits) / Double(hits + misses)
        if trackAverage, !darts.isEmpty {
            let points = visitScores.reduce(0, +)
            result.average = Double(points) * 3 / Double(darts.count)
            let firstPoints = visitScores.prefix(3).reduce(0, +)
            let firstDarts = visitDartCounts.prefix(3).reduce(0, +)
            if firstDarts > 0 { result.first9 = Double(firstPoints) * 3 / Double(firstDarts) }
            result.bestVisit = visitScores.max()
            result.tons = visitScores.filter { $0 >= 100 }.count
            result.tonForties = visitScores.filter { $0 >= 140 }.count
            result.oneEighties = visitScores.filter { $0 >= 180 }.count
            result.visitScores = visitScores
        }
        result.bestStreak = bestCombo
        result.checkoutHits = checkoutHits
        result.checkoutAttempts = checkoutAttempts
        result.busts = busts
        result.summary = summary
        result.tallies = tally.map { AimTally(key: $0.key, hits: $0.value.hits, attempts: $0.value.attempts) }.sorted { $0.key < $1.key }
        result.checkoutLeaves = checkoutLeaves
        result.checkoutMade = checkoutMade
        return result
    }

    func untilHit(limit: Int, lowScore: Bool) -> TrainingProjection {
        var step = 0
        var thrown = 0
        let aims = assignment.aims
        while step < aims.count && thrown < limit {
            let aim = aims[step]
            task = "Tref \(aim.label)"
            target = aim.label
            dartsLeft = limit - thrown
            mark(step, of: aims.count)
            guard let dart = dart(aim.example) else { return pause() }
            thrown += 1
            if absorb(dart, aim: aim) { step += 1 }
            scoreText = "\(step)/\(aims.count)"
        }
        let won = step == aims.count && !aims.isEmpty
        record = darts.count
        higher = !lowScore
        scoreText = won ? "\(darts.count) šipek" : "\(step)/\(aims.count)"
        return finish(won, won ? "Hotovo na \(darts.count) šipek." : "Do limitu se cíl neuzavřel.")
    }

    func bobs() -> TrainingProjection {
        var bank = 27
        scoreText = "27"
        for number in 1...20 {
            let aim = Aim.segment(number, 2)
            task = "Tři šipky na \(aim.label)"
            target = aim.label
            var scored = 0
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(number - 1, of: 20)
                guard let thrown = dart(aim.example) else { return pause() }
                if absorb(thrown, aim: aim) {
                    scored += 1
                    bank += number * 2
                }
            }
            if scored == 0 { bank -= number * 2; feedback = .life }
            score = bank
            scoreText = "\(bank)"
            if bank <= 0 { record = bank; return finish(false, "Bob's 27 spadlo na \(bank).") }
        }
        record = bank
        return finish(true, "Bob's 27 končí na \(bank).")
    }

    func cards(halve: Bool) -> TrainingProjection {
        var bank = 0
        let aims = assignment.aims
        for (offset, aim) in aims.enumerated() {
            task = halve ? "Halve-It: \(aim.label)" : "JDC: \(aim.label)"
            target = aim.label
            var gained = 0
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(offset, of: aims.count)
                guard let thrown = dart(aim.example) else { return pause() }
                if absorb(thrown, aim: aim) { gained += thrown.score }
            }
            if halve, gained == 0 { bank /= 2; feedback = .halved } else { bank += gained }
            score = bank
            scoreText = "\(bank)"
        }
        record = bank
        return finish(bank > 0, "\(halve ? "Halve-It" : "JDC") skóre \(bank).")
    }

    func shanghai(numbers: [Int], instant: Bool, limit: Int) -> TrainingProjection {
        if numbers.count == 1 && !instant {
            let number = numbers[0]
            var got = Set<Int>()
            var thrown = 0
            while thrown < limit && got.count < 3 {
                let missing = [1, 2, 3].first { !got.contains($0) } ?? 1
                task = "Seber S, D i T na \(number)"
                target = Dart(number, missing).label
                dartsLeft = limit - thrown
                mark(got.count, of: 3)
                guard let thrownDart = dart(Dart(number, missing)) else { return pause() }
                thrown += 1
                _ = absorb(thrownDart, aim: Aim.segment(number, nil))
                if thrownDart.segment == number, (1...3).contains(thrownDart.multiplier) {
                    got.insert(thrownDart.multiplier)
                    score += thrownDart.score
                }
                scoreText = "\(score)"
            }
            record = score
            return finish(got.count == 3, got.count == 3 ? "Shanghai 20 je kompletní." : "Chybí násobič na 20.")
        }
        for number in numbers {
            var got = Set<Int>()
            task = "Shanghai \(number)"
            target = "\(number)"
            for shot in 0..<3 {
                let missing = [1, 2, 3].first { !got.contains($0) } ?? 1
                dartsLeft = 3 - shot
                guard let thrownDart = dart(Dart(number, missing)) else { return pause() }
                _ = absorb(thrownDart, aim: Aim.segment(number, nil))
                if thrownDart.segment == number, (1...3).contains(thrownDart.multiplier) {
                    got.insert(thrownDart.multiplier)
                    score += thrownDart.score
                }
            }
            scoreText = "\(score)"
            if instant, got.count == 3 {
                record = score
                return finish(true, "Shanghai na \(number).")
            }
        }
        record = score
        return finish(score > 0, "Shanghai skóre \(score).")
    }

    func cricket(numbers: [Int], limit: Int) -> TrainingProjection {
        var marks: [Int: Int] = [:]
        func closed(_ number: Int) -> Bool { marks[number, default: 0] >= 3 }
        var thrown = 0
        while thrown < limit && !numbers.allSatisfy(closed) {
            let next = numbers.first { !closed($0) } ?? numbers[0]
            let need = 3 - marks[next, default: 0]
            let hint = next == 25 ? (need >= 2 ? Dart(25, 2) : Dart(25, 1)) : Dart(next, min(3, max(1, need)))
            task = "Zavři \(next == 25 ? "bull" : "\(next)")"
            target = hint.label
            dartsLeft = limit - thrown
            mark(numbers.filter(closed).count, of: numbers.count)
            guard let thrownDart = dart(hint) else { return pause() }
            thrown += 1
            _ = absorb(thrownDart, aim: Aim.segment(next, nil))
            if numbers.contains(thrownDart.segment) {
                marks[thrownDart.segment, default: 0] = min(3, marks[thrownDart.segment, default: 0] + thrownDart.multiplier)
            }
            scoreText = "\(numbers.filter(closed).count)/\(numbers.count)"
        }
        let won = numbers.allSatisfy(closed)
        record = thrown
        higher = false
        return finish(won, won ? "Zavřeno na \(thrown) šipek." : "Na zavření nestačil limit.")
    }

    struct LeaveResult { var won = false; var waiting = false }

    func playLeave(start: Int, maxVisits: Int, doubleIn: Bool) -> LeaveResult {
        var remaining = start
        var opened = !doubleIn
        var visits = 0
        while visits < maxVisits && remaining > 0 {
            let origin = remaining
            let originOpened = opened
            var chunk: [Dart] = []
            var bust = false
            var won = false
            var credited = 0
            while chunk.count < 3 && !bust && !won {
                dartsLeft = 3 - chunk.count
                scoreText = "\(remaining)"
                target = "\(remaining)"
                let hint = idealScoringDart(remaining: remaining, dartsInVisit: chunk.count, budget: 99, doubleIn: doubleIn, opened: opened)
                guard let thrown = dart(hint) else { return LeaveResult(waiting: true) }
                push(thrown)
                chunk.append(thrown)
                if !ScoringRules.counts(thrown, opened: opened, doubleIn: doubleIn) {
                    feedback = .miss
                    misses += 1
                    continue
                }
                if doubleIn && !opened { opened = true; feedback = .advance }
                if ScoringRules.isBust(remaining: remaining, dart: thrown, rule: .double) {
                    remaining = origin
                    opened = originOpened
                    bust = true
                    busts += 1
                    credited = 0
                    feedback = .bust
                    break
                }
                remaining -= thrown.score
                credited += thrown.score
                feedback = remaining == 0 ? .checkout : .hit
                hits += 1
                won = remaining == 0
            }
            closeVisit(credited, dartsUsed: chunk.count)
            visits += 1
            checkoutAttempts += 1
            checkoutLeaves.append(start)
            if won {
                checkoutHits += 1
                checkoutMade.append(start)
                scoreText = "0"
                return LeaveResult(won: true)
            }
            scoreText = "\(remaining)"
        }
        return LeaveResult(won: remaining == 0)
    }

    func checkouts(maxVisits: Int, need: Int, doubleIn: Bool) -> TrainingProjection {
        var cleared = 0
        let leaves = assignment.leaves
        for (offset, leave) in leaves.enumerated() {
            task = "Zavři \(leave)"
            target = "\(leave)"
            routes = Checkout.alternatives(for: leave)
            hint = routes.first.map { $0.map(\.label).joined(separator: " · ") }
            detail = bogeys.isEmpty ? "" : "Nelze zavřít: \(bogeys.map(String.init).joined(separator: ", "))"
            mark(offset, of: leaves.count)
            let outcome = playLeave(start: leave, maxVisits: maxVisits, doubleIn: doubleIn)
            if outcome.waiting { return pause() }
            if outcome.won { cleared += 1 }
            score = cleared
            scoreText = "\(cleared)/\(leaves.count)"
        }
        record = cleared
        let won = !leaves.isEmpty && cleared >= min(need, leaves.count)
        return finish(won, "Checkouty \(cleared) z \(leaves.count).")
    }

    func until(start: Int, visits: Int, doubleIn: Bool) -> TrainingProjection {
        task = doubleIn ? "Nejdřív double, pak zavři \(start)" : "Zavři \(start)"
        target = "\(start)"
        routes = Checkout.alternatives(for: start)
        hint = routes.first.map { $0.map(\.label).joined(separator: " · ") }
        if !Checkout.canFinish(start, darts: 3), visits == 1 {
            detail = "\(start) nejde třemi šipkami zavřít."
            return finish(false, "Skóre \(start) je nezavřitelné.")
        }
        let outcome = playLeave(start: start, maxVisits: visits, doubleIn: doubleIn)
        if outcome.waiting { return pause() }
        record = outcome.won ? start : 0
        return finish(outcome.won, outcome.won ? "Checkout \(start) je tam." : "Checkout \(start) nevyšel.")
    }

    func leg(start: Int, limit: Int, doubleIn: Bool, minAverage: Double?, opponentAt: Int?) -> TrainingProjection {
        trackAverage = true
        var remaining = start
        var opened = !doubleIn
        var opponent = 0
        task = opponentAt == nil ? "Dohraj \(start)" : "Soupeř zavře za \(opponentAt ?? 0) kol. Ty máš \(start)."
        while darts.count < limit && remaining > 0 {
            if let opponentAt, opponent >= opponentAt {
                record = start - remaining
                scoreText = "\(remaining)"
                return finish(false, "Soupeř zavřel dřív.")
            }
            let origin = remaining
            let originOpened = opened
            var chunk: [Dart] = []
            var bust = false
            var won = false
            var credited = 0
            while chunk.count < 3 && darts.count < limit && !bust && !won {
                dartsLeft = min(3 - chunk.count, limit - darts.count)
                scoreText = "\(remaining)"
                target = "\(remaining)"
                routes = Checkout.alternatives(for: remaining)
                hint = routes.first.map { $0.map(\.label).joined(separator: " · ") }
                if routes.isEmpty, remaining > 1, remaining <= 170 {
                    detail = Checkout.canFinish(remaining) ? "" : "\(remaining) teď nejde zavřít."
                }
                let hintDart = idealScoringDart(remaining: remaining, dartsInVisit: chunk.count, budget: limit - darts.count, doubleIn: doubleIn, opened: opened)
                guard let thrown = dart(hintDart) else { return pause() }
                push(thrown)
                chunk.append(thrown)
                if !ScoringRules.counts(thrown, opened: opened, doubleIn: doubleIn) {
                    feedback = .miss
                    misses += 1
                    continue
                }
                if doubleIn && !opened { opened = true }
                if ScoringRules.isBust(remaining: remaining, dart: thrown, rule: .double) {
                    remaining = origin
                    opened = originOpened
                    bust = true
                    busts += 1
                    credited = 0
                    feedback = .bust
                    break
                }
                remaining -= thrown.score
                credited += thrown.score
                hits += 1
                feedback = remaining == 0 ? .checkout : .hit
                won = remaining == 0
            }
            if !chunk.isEmpty {
                closeVisit(credited, dartsUsed: chunk.count)
                if won { checkoutHits += 1; checkoutAttempts += 1; checkoutMade.append(origin) }
                else if origin <= 170 { checkoutAttempts += 1; checkoutLeaves.append(origin) }
            }
            if won { break }
            opponent += 1
            if let opponentAt {
                let left = max(0, opponentAt - opponent)
                detail = "Soupeř zavře za \(left) kol."
                if opponent >= opponentAt { break }
            }
        }
        scoreText = "\(remaining)"
        let won = remaining == 0 && (opponentAt == nil || opponent < (opponentAt ?? 0) || remaining == 0)
        let average = darts.isEmpty ? 0 : Double(visitScores.reduce(0, +)) * 3 / Double(darts.count)
        let pace = minAverage.map { average >= $0 } ?? true
        let beatClock = opponentAt.map { opponent < $0 || remaining == 0 } ?? true
        let success = won && pace && (opponentAt == nil || remaining == 0)
        record = Int(average.rounded())
        higher = true
        if let opponentAt, remaining == 0, opponent <= opponentAt {
            return finish(true, "Otočeno. Průměr \(Int(average.rounded())).")
        }
        if won && !pace { return finish(false, "Zavřeno, ale průměr \(Int(average.rounded())) je pod cílem.") }
        _ = beatClock
        return finish(success, success ? "Leg zavřený. Průměr \(Int(average.rounded()))." : "Leg se nepodařilo zavřít.")
    }

    func goals(atLeast: Int?, exact: Int?, count: Int, need: Int) -> TrainingProjection {
        trackAverage = true
        var got = [Int](repeating: 0, count: players)
        for round in 0..<count {
            for player in 0..<players {
                playerLine = names.indices.contains(player) ? names[player] : nil
                var sum = 0
                task = exact == 180 ? "Hledej 180" : atLeast.map { "Alespoň \($0)" } ?? "Skóruj"
                target = task
                for shot in 0..<3 {
                    dartsLeft = 3 - shot
                    visit = round + 1
                    guard let thrown = dart(Dart(20, 3)) else { return pause() }
                    push(thrown)
                    sum += thrown.score
                    feedback = .hit
                    hits += 1
                }
                let ok = exact.map { sum == $0 } ?? atLeast.map { sum >= $0 } ?? true
                if ok { got[player] += 1; feedback = .checkout } else { misses += 1 }
                if player == 0 { closeVisit(sum, dartsUsed: 3) }
                scoreText = "\(got[0])"
                mark(got[0], of: need)
            }
        }
        record = got[0]
        let won = got[0] >= need && (players == 1 || got[0] >= got[1])
        return finish(won, "Trefených návštěv \(got[0]) z \(count).")
    }

    func ladder(targets: [Int]) -> TrainingProjection {
        trackAverage = true
        for (offset, target) in targets.enumerated() {
            task = "Návštěva aspoň \(target)"
            self.target = "\(target)+"
            var sum = 0
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(offset, of: targets.count)
                guard let thrown = dart(Dart(20, 3)) else { return pause() }
                push(thrown)
                sum += thrown.score
            }
            closeVisit(sum, dartsUsed: 3)
            scoreText = "\(sum)"
            if sum < target { record = offset; return finish(false, "\(sum) nestačí na \(target).") }
            hits += 1
        }
        record = visitScores.reduce(0, +)
        return finish(true, "Žebřík je splněný.")
    }

    func consistency(visits: Int, spread: Int, floor: Int) -> TrainingProjection {
        trackAverage = true
        for round in 0..<visits {
            task = "Drž stabilní návštěvu"
            target = "Rozptyl do \(spread)"
            var sum = 0
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(round, of: visits)
                guard let thrown = dart(Dart(20, 3)) else { return pause() }
                push(thrown)
                sum += thrown.score
                hits += 1
            }
            closeVisit(sum, dartsUsed: 3)
            scoreText = "\(sum)"
        }
        let band = (visitScores.max() ?? 0) - (visitScores.min() ?? 0)
        let average = darts.isEmpty ? 0 : Double(visitScores.reduce(0, +)) * 3 / Double(darts.count)
        record = band
        higher = false
        let won = band <= spread && average >= Double(floor)
        return finish(won, "Rozptyl \(band), průměr \(Int(average.rounded())).")
    }

    func highScore(visits: Int) -> TrainingProjection {
        trackAverage = true
        var totals = [Int](repeating: 0, count: players)
        for round in 0..<visits {
            for player in 0..<players {
                playerLine = names.indices.contains(player) ? names[player] : nil
                var sum = 0
                for shot in 0..<3 {
                    dartsLeft = 3 - shot
                    visit = round + 1
                    guard let thrown = dart(Dart(20, 3)) else { return pause() }
                    push(thrown)
                    sum += thrown.score
                    hits += 1
                }
                totals[player] += sum
                if player == 0 { closeVisit(sum, dartsUsed: 3) }
                scoreText = "\(totals[0])"
            }
        }
        record = totals[0]
        score = totals[0]
        let won = totals[0] > 0 && (players == 1 || totals[0] >= totals[1])
        return finish(won, players == 1 ? "Součet \(totals[0])." : "\(totals[0]) : \(totals[1])")
    }

    func average(visits: Int, target: Double) -> TrainingProjection {
        trackAverage = true
        for round in 0..<visits {
            task = "Průměr aspoň \(Int(target))"
            self.target = "\(Int(target))"
            var sum = 0
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(round, of: visits)
                guard let thrown = dart(Dart(20, 3)) else { return pause() }
                push(thrown)
                sum += thrown.score
                hits += 1
            }
            closeVisit(sum, dartsUsed: 3)
            let average = Double(visitScores.reduce(0, +)) * 3 / Double(max(darts.count, 1))
            scoreText = String(format: "%.0f", average)
        }
        let average = darts.isEmpty ? 0 : Double(visitScores.reduce(0, +)) * 3 / Double(darts.count)
        record = Int(average.rounded())
        return finish(average >= target, "Průměr \(Int(average.rounded())).")
    }

    func steps(fail: Bool, dartsEach: Int, accuracy: Double?, minimumHits: Int?) -> TrainingProjection {
        let aims = assignment.aims
        guard !aims.isEmpty else { return finish(false, "Hra nemá cíle.") }
        for (offset, aim) in aims.enumerated() {
            task = "Tref \(aim.label)"
            target = aim.label
            detail = assignment.labels.indices.contains(offset) ? assignment.labels[offset] : detail
            var landed = false
            let shots = max(1, dartsEach)
            for shot in 0..<shots {
                dartsLeft = shots - shot
                mark(offset, of: aims.count)
                guard let thrown = dart(aim.example) else { return pause() }
                if absorb(thrown, aim: aim) {
                    landed = true
                    if fail || minimumHits != nil { break }
                }
            }
            scoreText = "\(hits)"
            if fail && !landed { record = offset; return finish(false, "\(aim.label) nevyšel.") }
            if let minimumHits, hits >= minimumHits {
                record = hits
                return finish(true, "Splněno \(hits) zásahů.")
            }
        }
        record = hits
        if let accuracy {
            let rate = hits + misses == 0 ? 0 : Double(hits) / Double(hits + misses)
            return finish(rate >= accuracy, "Úspěšnost \(Int((rate * 100).rounded())) %.")
        }
        if let minimumHits { return finish(hits >= minimumHits, "Zásahů \(hits).") }
        return finish(true, "Úkoly splněny.")
    }

    func hunter(lives: Int) -> TrainingProjection {
        var left = lives
        self.lives = left
        var step = 0
        while step < assignment.aims.count && left > 0 {
            let aim = assignment.aims[step]
            task = "Ulov \(aim.label)"
            target = aim.label
            var found = false
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(step, of: assignment.aims.count)
                guard let thrown = dart(aim.example) else { return pause() }
                if absorb(thrown, aim: aim) { found = true; break }
            }
            if found { step += 1 } else { left -= 1; self.lives = left; feedback = .life }
            scoreText = "\(step)"
        }
        record = step
        return finish(step == assignment.aims.count && !assignment.aims.isEmpty, "Ulovených doublů \(step).")
    }

    func survivor(lives: Int) -> TrainingProjection {
        var left = lives
        self.lives = left
        var step = 0
        while step < assignment.aims.count && left > 0 {
            let aim = assignment.aims[step]
            task = "Přežij \(aim.label)"
            target = aim.label
            dartsLeft = 1
            mark(step, of: assignment.aims.count)
            guard let thrown = dart(aim.example) else { return pause() }
            if absorb(thrown, aim: aim) { step += 1 } else { left -= 1; self.lives = left; feedback = .life }
            scoreText = "\(left) životů"
        }
        record = step
        return finish(!assignment.aims.isEmpty && step == assignment.aims.count && left > 0, "Přežito \(step) cílů.")
    }

    func streak(need: Int, limit: Int) -> TrainingProjection {
        let aim = assignment.aims.first ?? .segment(20, 3)
        var thrown = 0
        task = "Série bez chyby"
        target = aim.label
        while thrown < limit && combo < need {
            dartsLeft = limit - thrown
            mark(combo, of: need)
            guard let thrownDart = dart(aim.example) else { return pause() }
            thrown += 1
            if !absorb(thrownDart, aim: aim) {
                record = bestCombo
                scoreText = "\(bestCombo)"
                return finish(false, "Série skončila na \(bestCombo).")
            }
            scoreText = "\(combo)"
        }
        record = bestCombo
        return finish(bestCombo >= need, "Nejdelší série \(bestCombo).")
    }

    func roulette(need: Int) -> TrainingProjection {
        var cleared = 0
        for (offset, aim) in assignment.aims.enumerated() {
            task = "Double rulety"
            target = aim.label
            var found = false
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(offset, of: assignment.aims.count)
                guard let thrown = dart(aim.example) else { return pause() }
                if absorb(thrown, aim: aim) { found = true }
            }
            if found { cleared += 1 }
            scoreText = "\(cleared)"
        }
        record = cleared
        return finish(cleared >= need, "Trefených kol \(cleared).")
    }

    func bulls(darts count: Int, target: Int) -> TrainingProjection {
        let aim = Aim.bull
        for shot in 0..<count {
            task = "Body jen bullem"
            self.target = "Bull"
            dartsLeft = count - shot
            mark(shot, of: count)
            guard let thrown = dart(Dart(25, 2)) else { return pause() }
            if absorb(thrown, aim: aim) {
                score += thrown.score * max(1, combo)
            }
            scoreText = "\(score)"
        }
        record = score
        return finish(score >= target, "Bull skóre \(score).")
    }

    func combo(need: Int, limit: Int) -> TrainingProjection {
        let pattern = assignment.aims.isEmpty ? [Aim.segment(20, 1), .segment(20, 2), .segment(20, 3), .bull] : assignment.aims
        var step = 0
        var patterns = 0
        var thrown = 0
        while thrown < limit && patterns < need {
            let aim = pattern[step]
            task = "Kombo \(patterns + 1)"
            target = aim.label
            dartsLeft = limit - thrown
            mark(patterns, of: need)
            guard let thrownDart = dart(aim.example) else { return pause() }
            thrown += 1
            if absorb(thrownDart, aim: aim) {
                step += 1
                if step == pattern.count {
                    patterns += 1
                    step = 0
                    feedback = .advance
                }
            } else {
                step = 0
            }
            score = patterns
            scoreText = "\(patterns)"
        }
        record = patterns
        return finish(patterns >= need, "Komba \(patterns).")
    }

    func sudden(need: Int, limit: Int) -> TrainingProjection {
        guard !assignment.aims.isEmpty else { return finish(false, "Chybí cíle.") }
        var scores = [Int](repeating: 0, count: players)
        var alive = [Bool](repeating: true, count: players)
        var thrown = 0
        var turn = 0
        var aimIndex = 0
        while thrown < limit && scores[0] < need {
            if !alive[turn] {
                if !alive[0] { break }
                turn = (turn + 1) % players
                continue
            }
            let aim = assignment.aims[aimIndex % assignment.aims.count]
            task = "Jedna chyba končí"
            target = aim.label
            playerLine = names.indices.contains(turn) ? names[turn] : nil
            dartsLeft = 1
            mark(scores[0], of: need)
            guard let thrownDart = dart(aim.example) else { return pause() }
            thrown += 1
            aimIndex += 1
            if absorb(thrownDart, aim: aim) {
                scores[turn] += 1
            } else if turn == 0 {
                record = scores[0]
                scoreText = "\(scores[0])"
                return finish(false, "Sudden death po \(scores[0]) zásazích.")
            } else {
                alive[turn] = false
            }
            scoreText = "\(scores[0])"
            turn = (turn + 1) % players
        }
        record = scores[0]
        return finish(scores[0] >= need, "Sudden death \(scores[0]).")
    }

    func puzzles(need: Int) -> TrainingProjection {
        var cleared = 0
        for (offset, route) in assignment.routes.enumerated() {
            let leave = route.reduce(0) { $0 + $1.score }
            task = "Odehraj checkout \(leave)"
            target = "\(leave)"
            routes = [route]
            hint = route.map(\.label).joined(separator: " · ")
            mark(offset, of: assignment.routes.count)
            let outcome = playLeave(start: leave, maxVisits: 1, doubleIn: false)
            if outcome.waiting { return pause() }
            if outcome.won { cleared += 1 }
            scoreText = "\(cleared)"
        }
        record = cleared
        return finish(!assignment.routes.isEmpty && cleared >= need, "Puzzle \(cleared)/\(assignment.routes.count).")
    }

    func rush(seconds: Int, need: Int, limit: Int) -> TrainingProjection {
        guard !assignment.aims.isEmpty else { return finish(false, "Chybí cíle.") }
        var thrown = 0
        var aimIndex = 0
        while hits < need && thrown < limit {
            let aim = assignment.aims[aimIndex % assignment.aims.count]
            task = "Co nejvíc cílů"
            target = aim.label
            dartsLeft = limit - thrown
            mark(hits, of: need)
            guard let thrownDart = dart(aim.example) else {
                if now.timeIntervalSince(started) >= Double(seconds) {
                    record = hits
                    return finish(hits >= need, "Čas vypršel na \(hits) zásazích.")
                }
                return pause()
            }
            thrown += 1
            aimIndex += 1
            _ = absorb(thrownDart, aim: aim)
            scoreText = "\(hits)"
        }
        record = hits
        return finish(hits >= need, "Rush \(hits) zásahů.")
    }

    func risk(rounds: Int, target: Int) -> TrainingProjection {
        choices = ["Jistota S20", "Risk T20"]
        for round in 0..<rounds {
            phase = .choose
            task = "Vyber jistotu nebo risk"
            self.target = "Kolo \(round + 1)"
            guard let pick = choice() else { return pause() }
            phase = .scoring
            let aim: Aim = pick == 1 ? .segment(20, 3) : .segment(20, 1)
            self.target = aim.label
            var chunk: [Dart] = []
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(round, of: rounds)
                guard let thrown = dart(aim.example) else { return pause() }
                _ = absorb(thrown, aim: aim)
                chunk.append(thrown)
            }
            let gained = pick == 1
                ? (chunk.allSatisfy { Aim.segment(20, 3).matches($0) } ? 180 : 0)
                : chunk.filter { Aim.segment(20, 1).matches($0) }.count * 20
            score += gained
            scoreText = "\(score)"
        }
        record = score
        return finish(score >= target, "Risk skóre \(score).")
    }

    func exact(need: Int) -> TrainingProjection {
        var cleared = 0
        for (offset, solution) in assignment.solutions.enumerated() {
            let total = solution.reduce(0) { $0 + $1.score }
            task = "Přesně \(total) třemi šipkami"
            target = "\(total)"
            var sum = 0
            for shot in 0..<3 {
                let hint = shot < solution.count ? solution[shot] : Dart(1)
                dartsLeft = 3 - shot
                mark(offset, of: assignment.solutions.count)
                guard let thrown = dart(hint) else { return pause() }
                push(thrown)
                sum += thrown.score
            }
            closeVisit(sum, dartsUsed: 3)
            if sum == total { cleared += 1; hits += 1; feedback = .hit } else { misses += 1; feedback = .miss }
            scoreText = "\(cleared)"
        }
        record = cleared
        return finish(cleared >= need && !assignment.solutions.isEmpty, "Přesných návštěv \(cleared).")
    }

    func recall() -> TrainingProjection {
        phase = .memorize
        memory = assignment.memory.map(\.label)
        task = "Zapamatuj si pořadí"
        target = memory.joined(separator: " · ")
        guard ready() else { return pause() }
        phase = .scoring
        memory = []
        for (offset, expected) in assignment.memory.enumerated() {
            task = "Odehraj \(offset + 1). šipku"
            target = expected.label
            dartsLeft = assignment.memory.count - offset
            mark(offset, of: assignment.memory.count)
            guard let thrown = dart(expected) else { return pause() }
            push(thrown)
            if thrown == expected { hits += 1; feedback = .hit } else {
                misses += 1
                record = offset
                return finish(false, "Místo \(expected.label) padlo \(thrown.label).")
            }
        }
        record = assignment.memory.count
        return finish(!assignment.memory.isEmpty, "Posloupnost sedí.")
    }

    func escape(lives: Int) -> TrainingProjection {
        var left = lives
        self.lives = left
        var step = 0
        while step < assignment.leaves.count && left > 0 {
            let leave = assignment.leaves[step]
            detail = assignment.labels.indices.contains(step) ? assignment.labels[step] : "Místnost"
            task = "Uteč checkoutem \(leave)"
            target = "\(leave)"
            routes = Checkout.alternatives(for: leave)
            hint = routes.first.map { $0.map(\.label).joined(separator: " · ") }
            mark(step, of: assignment.leaves.count)
            let outcome = playLeave(start: leave, maxVisits: 1, doubleIn: false)
            if outcome.waiting { return pause() }
            if outcome.won { step += 1 } else { left -= 1; self.lives = left; feedback = .life }
            scoreText = "\(step)"
        }
        record = step
        return finish(step == assignment.leaves.count && left > 0, "Místností \(step).")
    }

    func ghost(visits: Int) -> TrainingProjection {
        trackAverage = true
        var mine = 0
        for round in 0..<visits {
            var sum = 0
            task = assignment.ghostScores.isEmpty ? "Nastav ghosta" : "Překonej ghosta"
            target = "Nejvyšší součet"
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                visit = round + 1
                guard let thrown = dart(Dart(20, 3)) else { return pause() }
                push(thrown)
                sum += thrown.score
                hits += 1
            }
            mine += sum
            closeVisit(sum, dartsUsed: 3)
            scoreText = "\(mine)"
            let ghostTotal = assignment.ghostScores.prefix(round + 1).reduce(0, +)
            ghost = assignment.ghostScores.isEmpty ? "První průběh se uloží jako ghost." : "Ty \(mine) · ghost \(ghostTotal)"
        }
        record = mine
        let ghostTotal = assignment.ghostScores.reduce(0, +)
        if assignment.ghostScores.isEmpty { return finish(mine > 0, "Ghost uložen: \(mine).") }
        return finish(mine > ghostTotal, mine > ghostTotal ? "Ghost padl \(mine):\(ghostTotal)." : "Ghost vede \(ghostTotal):\(mine).")
    }

    func final(need: Int) -> TrainingProjection {
        var cleared = 0
        for (offset, aim) in assignment.aims.enumerated() {
            task = "Rozhoduje 3. šipka"
            target = aim.label
            var last: Dart?
            for shot in 0..<3 {
                dartsLeft = 3 - shot
                mark(offset, of: assignment.aims.count)
                let hint = shot == 2 ? aim.example : Dart(1)
                guard let thrown = dart(hint) else { return pause() }
                push(thrown)
                if shot == 2 { last = thrown }
            }
            if let last, aim.matches(last) { cleared += 1; hits += 1; feedback = .hit } else { misses += 1; feedback = .miss }
            scoreText = "\(cleared)"
        }
        record = cleared
        return finish(cleared >= need, "Finálních zásahů \(cleared).")
    }

    func boss(lives: Int) -> TrainingProjection {
        var hp = 100
        var left = lives
        self.lives = left
        bossMax = 100
        bossHP = hp
        var taskIndex = 0
        while hp > 0 && left > 0 && taskIndex < 12 {
            let stage = min(2, max(0, (100 - hp) / 34))
            detail = assignment.labels.indices.contains(stage) ? assignment.labels[stage] : "Boss"
            bossHP = hp
            scoreText = "\(hp) HP"
            if taskIndex % 3 == 2, !assignment.leaves.isEmpty {
                let leave = assignment.leaves[taskIndex % assignment.leaves.count]
                task = "Seber bossovi checkout \(leave)"
                target = "\(leave)"
                let outcome = playLeave(start: leave, maxVisits: 1, doubleIn: false)
                if outcome.waiting { return pause() }
                if outcome.won { hp -= 34 } else { left -= 1; feedback = .life }
            } else if !assignment.aims.isEmpty {
                let aim = assignment.aims[taskIndex % assignment.aims.count]
                task = "Zásah \(aim.label) bere životy"
                target = aim.label
                var landed = false
                for shot in 0..<3 {
                    dartsLeft = 3 - shot
                    guard let thrown = dart(aim.example) else { return pause() }
                    if absorb(thrown, aim: aim) { landed = true; break }
                }
                if landed { hp -= 34 } else { left -= 1; feedback = .life }
            } else {
                return finish(false, "Boss nemá úkoly.")
            }
            self.lives = left
            bossHP = max(0, hp)
            taskIndex += 1
            mark(min(100, 100 - hp), of: 100)
        }
        record = max(0, 100 - hp)
        return finish(hp <= 0 && left > 0, hp <= 0 ? "Všichni tři bossové jsou poraženi." : "Boss odolal.")
    }
}
