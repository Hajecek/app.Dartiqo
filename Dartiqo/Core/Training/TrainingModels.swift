import Foundation

enum TrainingLevel: String, Codable, CaseIterable, Identifiable {
    case beginner, advanced, pro, adaptive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .beginner: return "Začátečník"
        case .advanced: return "Pokročilý"
        case .pro: return "Profesionál"
        case .adaptive: return "Adaptivní"
        }
    }
}

enum TrainingCategory: String, Codable, CaseIterable, Identifiable {
    case accuracy, doubles, checkout, scoring, endurance, original, adaptive, daily
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accuracy: return "Přesnost a segmenty"
        case .doubles: return "Doubly a triply"
        case .checkout: return "Checkout a zavírání"
        case .scoring: return "Scoring a průměry"
        case .endurance: return "Výdrž a konzistence"
        case .original: return "Dartiqo Challenge"
        case .adaptive: return "Adaptivní tréninky"
        case .daily: return "Denní a týdenní výzvy"
        }
    }
    var symbol: String {
        switch self {
        case .accuracy: return "scope"
        case .doubles: return "circle.circle"
        case .checkout: return "flag.checkered"
        case .scoring: return "chart.bar.fill"
        case .endurance: return "timer"
        case .original: return "bolt.fill"
        case .adaptive: return "brain.head.profile"
        case .daily: return "sun.max.fill"
        }
    }
}

enum TrainingLength: String, CaseIterable, Identifiable {
    case short, medium, long
    var id: String { rawValue }
    var title: String {
        switch self {
        case .short: return "Do 5 min"
        case .medium: return "5–12 min"
        case .long: return "Nad 12 min"
        }
    }
    func contains(_ minutes: Int) -> Bool {
        switch self {
        case .short: return minutes <= 5
        case .medium: return (6...12).contains(minutes)
        case .long: return minutes > 12
        }
    }
}

enum Aim: Codable, Hashable {
    case segment(Int, Int?)
    case anyDouble
    case anyTriple
    case anySingle
    case bull
    case innerBull
    case outerBull

    var label: String {
        switch self {
        case .segment(let number, let multiplier):
            if number == 25 {
                if multiplier == 2 { return "BULL" }
                if multiplier == 1 { return "25" }
                return "Bull"
            }
            if let multiplier { return Dart(number, multiplier).label }
            return "\(number)"
        case .anyDouble: return "Libovolný double"
        case .anyTriple: return "Libovolný triple"
        case .anySingle: return "Libovolný single"
        case .bull: return "Bull"
        case .innerBull: return "BULL"
        case .outerBull: return "25"
        }
    }

    func matches(_ dart: Dart) -> Bool {
        switch self {
        case .segment(let number, let multiplier):
            return dart.segment == number && (multiplier == nil || dart.multiplier == multiplier)
        case .anyDouble:
            return dart.multiplier == 2 && dart.score > 0
        case .anyTriple:
            return dart.multiplier == 3 && (1...20).contains(dart.segment)
        case .anySingle:
            return dart.multiplier == 1 && (1...20).contains(dart.segment)
        case .bull:
            return dart.segment == 25
        case .innerBull:
            return dart.segment == 25 && dart.multiplier == 2
        case .outerBull:
            return dart.segment == 25 && dart.multiplier == 1
        }
    }

    var example: Dart {
        switch self {
        case .segment(let number, let multiplier):
            return Dart(number, multiplier ?? 1)
        case .anyDouble: return Dart(16, 2)
        case .anyTriple: return Dart(20, 3)
        case .anySingle: return Dart(20, 1)
        case .bull, .outerBull: return Dart(25, 1)
        case .innerBull: return Dart(25, 2)
        }
    }

    var tallyKey: String { label }
}

enum TrainingAction: Codable, Equatable {
    case dart(Dart)
    case ready
    case choose(Int)
}

enum TrainingPhase: String, Codable, Equatable {
    case scoring, memorize, choose
}

enum TrainingFeedback: String, Codable, Equatable {
    case none, hit, miss, bust, checkout, life, halved, advance
}

enum TrainingStatus: String, Codable {
    case playing, completed, abandoned
}

enum SegmentPick: Codable, Equatable {
    case list([Int])
    case rare
    case weak
    case singles
}

enum TrainingKind: Codable, Equatable {
    case around(mult: Int?, bull: Bool, limit: Int)
    case bobs27
    case jdc
    case volume(aim: Aim, darts: Int, accuracy: Double)
    case shanghai(numbers: [Int], instant: Bool, limit: Int)
    case halve
    case cricket(numbers: [Int], limit: Int)
    case checkoutFixed(leaves: [Int], visits: Int, need: Int, doubleIn: Bool)
    case checkoutUntil(start: Int, visits: Int, doubleIn: Bool)
    case checkoutRange(low: Int, high: Int, count: Int, need: Int)
    case checkoutGenerated(mode: String, need: Int)
    case x01(start: Int, limit: Int, doubleIn: Bool, minAverage: Double?)
    case visitGoal(atLeast: Int?, exact: Int?, count: Int, need: Int)
    case ladder(targets: [Int])
    case consistency(visits: Int, spread: Int, floor: Int)
    case highScore(visits: Int)
    case average(visits: Int, target: Double)
    case sniper(rounds: Int, need: Int)
    case hunter(rounds: Int, lives: Int)
    case survivor(steps: Int, lives: Int)
    case streak(aim: Aim, need: Int, limit: Int)
    case switchTreble(darts: Int, need: Int)
    case roulette(visits: Int, need: Int)
    case bullScore(darts: Int, target: Int)
    case combo(need: Int, limit: Int)
    case sudden(need: Int, limit: Int)
    case puzzle(count: Int, need: Int)
    case rush(seconds: Int, need: Int, limit: Int)
    case marathon(tasks: Int, limit: Int)
    case risk(rounds: Int, target: Int)
    case chaos(limit: Int)
    case segments(pick: SegmentPick, mult: Int?, darts: Int, accuracy: Double)
    case perfect(visits: Int, need: Int, total: Int)
    case exact(rounds: Int, need: Int)
    case memory(length: Int)
    case escape(rooms: Int, lives: Int)
    case tower(floors: Int)
    case oneDart(rounds: Int, need: Int)
    case ghost(visits: Int)
    case comeback(opponentVisits: Int)
    case finalDart(visits: Int, need: Int)
    case daily(tasks: Int)
    case world(stops: Int)
    case boss(lives: Int)
    case stepList(tasks: Int, darts: Int, fail: Bool)
}

struct TrainingOptions: Equatable {
    var level = true
    var rounds = false
    var darts = false
    var time = false
    var lives = false
    var segments = false
    var target = false
    var accuracy = false
    var checkouts = false
    var multiplayer = false
    var ghost = false
}

struct TrainingConfig: Codable, Equatable {
    var level: TrainingLevel = .advanced
    var rounds: Int?
    var dartCount: Int?
    var timeLimit: TimeInterval?
    var lives: Int?
    var segments: [Int]?
    var targetScore: Int?
    var requiredAccuracy: Double?
    var showCheckouts = true
    var players = 1
    var secondName = ""
    var ghostDarts: [Dart]?
    var isDaily = false
    var isWeekly = false
}

struct TrainingDefinition: Identifiable, Equatable {
    var id: String
    var number: Int
    var title: String
    var summary: String
    var rules: String
    var category: TrainingCategory
    var minutes: Int
    var listed: TrainingLevel
    var options: TrainingOptions
    var kind: TrainingKind
}

struct TrainingAssignment: Codable, Equatable {
    var aims: [Aim] = []
    var leaves: [Int] = []
    var routes: [[Dart]] = []
    var memory: [Dart] = []
    var labels: [String] = []
    var bogeys: [Int] = []
    var ghostScores: [Int] = []
    var solutions: [[Dart]] = []
}

struct TrainingContext: Equatable {
    var weakAims: [Aim] = []
    var rareSegments: [Int] = []
    var recentAccuracy: Double?
    var recentAverage: Double?
}

struct AimTally: Codable, Equatable, Identifiable {
    var key: String
    var hits: Int
    var attempts: Int
    var id: String { key }
    var rate: Double { attempts == 0 ? 0 : Double(hits) / Double(attempts) }
}

struct TrainingResult: Codable, Equatable {
    var success = false
    var score = 0
    var higherIsBetter = true
    var darts = 0
    var hits = 0
    var accuracy = 0.0
    var average: Double?
    var first9: Double?
    var bestVisit: Int?
    var bestStreak = 0
    var tons = 0
    var tonForties = 0
    var oneEighties = 0
    var checkoutHits = 0
    var checkoutAttempts = 0
    var busts = 0
    var summary = ""
    var visitScores: [Int] = []
    var tallies: [AimTally] = []
    var checkoutLeaves: [Int] = []
    var checkoutMade: [Int] = []
}

struct TrainingSession: Codable, Identifiable, Equatable {
    var id = UUID()
    var owner: UUID
    var definitionID: String
    var config: TrainingConfig
    var seed: UInt64
    var kind: TrainingKind
    var assignment: TrainingAssignment
    var actions: [TrainingAction] = []
    var players = 1
    var names: [String] = []
    var startedAt = Date()
    var finishedAt: Date?
    var status: TrainingStatus = .playing
    var result: TrainingResult?
}

struct TrainingProjection: Equatable {
    var task = ""
    var target = ""
    var scoreText = "0"
    var detail = ""
    var dartsLeft = 3
    var visit = 1
    var progress = 0.0
    var progressText = ""
    var recent: [Dart] = []
    var feedback: TrainingFeedback = .none
    var finished = false
    var success = false
    var phase: TrainingPhase = .scoring
    var choices: [String] = []
    var memory: [String] = []
    var lives: Int?
    var combo = 0
    var bossHP: Int?
    var bossMax: Int?
    var hint: String?
    var routes: [[Dart]] = []
    var bogeys: [Int] = []
    var ghost: String?
    var playerLine: String?
    var score = 0
    var higherIsBetter = true
    var result: TrainingResult?
    var ideal: TrainingAction?
}

struct XPEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var owner: UUID
    var sessionID: UUID
    var definitionID: String
    var amount: Int
    var createdAt = Date()
}

struct AchievementUnlock: Codable, Equatable, Identifiable {
    var id = UUID()
    var owner: UUID
    var key: String
    var unlockedAt = Date()
}

enum TrainingGoal: String, Codable, CaseIterable, Identifiable {
    case scoring, doubles, checkouts, average, tournament, consistency, complete
    var id: String { rawValue }
    var title: String {
        switch self {
        case .scoring: return "Zlepšit scoring"
        case .doubles: return "Zlepšit doubly"
        case .checkouts: return "Zlepšit checkouty"
        case .average: return "Zvýšit průměr"
        case .tournament: return "Příprava na turnaj"
        case .consistency: return "Zlepšit konzistenci"
        case .complete: return "Kompletní rozvoj"
        }
    }
}

struct TrainingPlanItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var day: Int
    var definitionID: String
    var sessionID: UUID?
}

struct TrainingPlan: Codable, Identifiable, Equatable {
    var id = UUID()
    var owner: UUID
    var goal: TrainingGoal
    var span: Int
    var daysPerWeek: Int
    var minutes: Int
    var level: TrainingLevel
    var createdAt = Date()
    var items: [TrainingPlanItem] = []
}

struct TrainingRecommendation: Equatable, Identifiable {
    var definitionID: String
    var reason: String
    var config: TrainingConfig
    var id: String { definitionID + reason }
}

struct TrainingRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xD1CE5EED : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: Range<Int>) -> Int {
        guard !range.isEmpty else { return range.lowerBound }
        return range.lowerBound + Int(next() % UInt64(range.count))
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int { int(range.lowerBound..<(range.upperBound + 1)) }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }
    mutating func shuffle<T>(_ items: [T]) -> [T] {
        var copy = items
        guard copy.count > 1 else { return copy }
        for index in stride(from: copy.count - 1, through: 1, by: -1) {
            copy.swapAt(index, int(0...index))
        }
        return copy
    }
}
