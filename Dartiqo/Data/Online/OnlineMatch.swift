import Foundation

struct OnlineFailure: LocalizedError {
    var message: String
    var match: OnlineMatch?
    var errorDescription: String? { message }
}

struct OnlineSnapshot: Decodable {
    var message: String?
    var match: OnlineMatch?
    var invites: [OnlineInvite]
    var lobbyInvites: [OnlineLobbyInvite]
    var lobbies: [OnlineLobby]

    init() {
        invites = []
        lobbyInvites = []
        lobbies = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        match = try container.decodeIfPresent(OnlineMatch.self, forKey: .match)
        invites = try container.decodeIfPresent([OnlineInvite].self, forKey: .invites) ?? []
        lobbyInvites = try container.decodeIfPresent([OnlineLobbyInvite].self, forKey: .lobbyInvites) ?? []
        lobbies = try container.decodeIfPresent([OnlineLobby].self, forKey: .lobbies) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case message, match, invites, lobbyInvites, lobbies
    }
}

struct OnlineMatch: Codable, Equatable, Identifiable {
    var id: String
    var code: String?
    var kind: String?
    var visibility: String?
    var status: String
    var seq: Int
    var yourSlot: Int?
    var activeSlot: Int
    var yourTurn: Bool
    var member: Bool
    var winner: Int?
    var rules: OnlineRules
    var players: [OnlinePlayer]
    var state: OnlineBoard

    /// Pravidla i se hrou, když ji server posílá jako `kind` mimo `rules`.
    var playRules: OnlineRules { rules.applying(kind: kind) }

    var you: OnlinePlayer? { players.first { $0.you } }
    var isHost: Bool { yourSlot == 0 }
    var isPublic: Bool { visibility == "public" }
    var isLive: Bool { status == "live" }
    var isOpen: Bool { status == "lobby" || status == "live" }

    func name(for slot: Int?) -> String {
        guard let slot else { return "Hráč" }
        return players.first { $0.slot == slot }?.name ?? "Hráč"
    }
}

struct OnlineRuleChip: Identifiable, Equatable {
    var title: String
    var value: String
    var id: String { title }
}

struct OnlineRules: Codable, Equatable {
    var startingScore: Int
    var outRule: String
    var legsToWin: Int
    var setsToWin: Int?
    var format: String?
    var mode: String?
    var cricketNumbers: [Int]?
    var cricketNoScore: Bool?
    var clockStyle: String?
    var countUpRounds: Int?

    var gameMode: GameMode { GameMode(rawValue: mode ?? "") ?? .x01 }

    /// Doplní hru z `kind`, když ji pravidla sama neobsahují. `classic` zůstává X01.
    func applying(kind: String?) -> OnlineRules {
        guard mode == nil, let kind, let game = GameMode(rawValue: kind) else { return self }
        var copy = self
        copy.mode = game.rawValue
        return copy
    }

    var config: GameConfig {
        var config = GameConfig(
            mode: gameMode,
            startingScore: startingScore,
            outRule: OutRule(rawValue: outRule) ?? .double,
            legsToWin: legsToWin,
            setsToWin: setsToWin ?? 1,
            format: format == "bestOf" ? .bestOf : .firstTo
        )
        var options = MatchOptions()
        if let cricketNumbers { options.cricketNumbers = cricketNumbers }
        if let cricketNoScore { options.cricketNoScore = cricketNoScore }
        if let clockStyle, let style = ClockStyle(rawValue: clockStyle) { options.clockStyle = style }
        if let countUpRounds { options.countUpRounds = countUpRounds }
        config.options = options
        return config
    }

    var outLabel: String { (OutRule(rawValue: outRule) ?? .double).title }
    var lengthLabel: String { config.lengthLine }
    var playsSets: Bool { (setsToWin ?? 1) > 1 }
    var summary: String {
        gameMode == .x01 ? "\(startingScore) · \(outLabel) · \(lengthLabel)" : config.summary
    }

    var overviewChips: [OnlineRuleChip] {
        switch gameMode {
        case .x01:
            return [
                OnlineRuleChip(title: "Start", value: "\(startingScore)"),
                OnlineRuleChip(title: "Zavření", value: outLabel),
                OnlineRuleChip(title: "Délka", value: lengthLabel),
            ]
        case .cricket:
            return [
                OnlineRuleChip(title: "Body", value: cricketNoScore == true ? "Bez bodů" : "S body"),
                OnlineRuleChip(title: "Čísla", value: MatchOptions.cricketNumbersLine(cricketNumbers ?? MatchOptions.standardCricketNumbers)),
                OnlineRuleChip(title: "Délka", value: lengthLabel),
            ]
        case .countUp:
            let rounds = countUpRounds ?? 10
            return [
                OnlineRuleChip(title: "Kola", value: "\(rounds)"),
                OnlineRuleChip(title: "Šipky", value: "\(rounds * 3)"),
            ]
        case .aroundClock:
            let style = ClockStyle(rawValue: clockStyle ?? "") ?? .any
            return [OnlineRuleChip(title: "Zásah", value: style.title)]
        }
    }
}

struct OnlinePlayer: Codable, Equatable, Identifiable {
    var slot: Int
    var id: String
    var name: String
    var username: String
    /// Relativní cesta k profilové fotce na serveru.
    var photo: String?
    var ready: Bool
    var you: Bool
    var remaining: Int
    var legs: Int
    var sets: Int?
}

struct OnlineBoard: Codable, Equatable {
    var leg: Int
    var set: Int?
    var currentDarts: [String]
    var winner: Int?
    var visits: [OnlineVisit]?

    /// Všechny šipky zápasu v pořadí hodu, včetně rozhozeného kola.
    var thrownDarts: [Dart]? {
        var labels = (visits ?? []).flatMap(\.darts)
        labels += currentDarts
        var darts: [Dart] = []
        for label in labels {
            guard let dart = Dart(onlineLabel: label) else { return nil }
            darts.append(dart)
        }
        return darts
    }
}

struct OnlineVisit: Codable, Equatable {
    var player: Int
    var leg: Int
    var darts: [String]
}

extension Dart {
    /// Popisek ze serveru: S20, D16, T19, 25, BULL nebo MISS.
    init?(onlineLabel label: String) {
        switch label {
        case "MISS": self.init(0)
        case "BULL": self.init(25, 2)
        case "25": self.init(25)
        default:
            guard let prefix = label.first, let segment = Int(label.dropFirst()) else { return nil }
            let multiplier: Int
            switch prefix {
            case "S": multiplier = 1
            case "D": multiplier = 2
            case "T": multiplier = 3
            default: return nil
            }
            self.init(segment, multiplier)
        }
        guard isValid else { return nil }
    }
}

struct OnlineInvite: Codable, Equatable, Identifiable {
    var id: Int
    var matchId: String
    var code: String
    var startingScore: Int
    var outRule: String
    var legsToWin: Int
    var setsToWin: Int?
    var format: String?
    var from: String
    var username: String

    var rules: OnlineRules {
        OnlineRules(startingScore: startingScore, outRule: outRule, legsToWin: legsToWin, setsToWin: setsToWin, format: format)
    }
    var summary: String { rules.summary }
}

struct OnlineLobbyInvite: Codable, Equatable, Identifiable {
    var name: String
    var username: String
    var publicId: String
    var status: String
    var id: String { publicId }
}

/// Veřejné lobby ze seznamu. Vstoupí se do něj rovnou, bez kódu.
struct OnlineLobby: Codable, Equatable, Identifiable {
    struct Host: Codable, Equatable {
        var name: String
        var username: String
        var publicId: String
        var photo: String?
    }

    var id: String
    var kind: String?
    var rules: OnlineRules
    var host: Host
    var seated: Int
    var open: Bool
    var createdAt: String

    var playRules: OnlineRules { rules.applying(kind: kind) }
}

/// Co telefon posílá při založení i úpravě lobby.
struct OnlineLobbySettings: Equatable {
    var isPublic = true
    var mode = GameMode.x01
    var startingScore = 501
    var outRule = OutRule.double
    var legsToWin = 2
    var setsToWin = 1
    var format = MatchFormat.firstTo
    var cricketNumbers: [Int]?
    var cricketNoScore = false
    var clockStyle = ClockStyle.any
    var countUpRounds = 10

    init() {}

    init(config: GameConfig, isPublic: Bool) {
        let options = config.settings
        self.isPublic = isPublic
        mode = config.mode
        startingScore = config.startingScore
        outRule = config.outRule
        legsToWin = config.legsToWin
        setsToWin = config.setsToWin
        format = config.format
        cricketNumbers = options.cricketNumbers
        cricketNoScore = options.cricketNoScore
        clockStyle = options.clockStyle
        countUpRounds = options.countUpRounds
    }

    var body: [String: Any] {
        var payload: [String: Any] = [
            "kind": mode == .x01 ? "classic" : mode.rawValue,
            "visibility": isPublic ? "public" : "private",
            // Lobby drží jen kód. Prázdné heslo smaže starší zámek, kdyby na serveru ještě zůstal.
            "password": "",
            "keepPassword": false,
            "startingScore": startingScore,
            "outRule": outRule.rawValue,
            "legsToWin": legsToWin,
            "setsToWin": setsToWin,
            "format": format == .bestOf ? "bestOf" : "firstTo",
        ]
        // X01 posílá stejné pole jako dřív. Ostatní hry přidají vlastní pravidla.
        if mode != .x01 {
            payload["mode"] = mode.rawValue
        }
        switch mode {
        case .x01:
            break
        case .cricket:
            payload["cricketNumbers"] = cricketNumbers ?? MatchOptions.standardCricketNumbers
            payload["cricketNoScore"] = cricketNoScore
        case .aroundClock:
            payload["clockStyle"] = clockStyle.rawValue
        case .countUp:
            payload["countUpRounds"] = countUpRounds
        }
        return payload
    }
}
