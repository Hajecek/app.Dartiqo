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

struct OnlineRules: Codable, Equatable {
    var startingScore: Int
    var outRule: String
    var legsToWin: Int
    var setsToWin: Int?
    var format: String?

    var config: GameConfig {
        var config = GameConfig(
            mode: .x01,
            startingScore: startingScore,
            outRule: OutRule(rawValue: outRule) ?? .double,
            legsToWin: legsToWin,
            setsToWin: setsToWin ?? 1,
            format: format == "bestOf" ? .bestOf : .firstTo
        )
        config.options = MatchOptions()
        return config
    }

    var outLabel: String { (OutRule(rawValue: outRule) ?? .double).title }
    var lengthLabel: String { config.lengthLine }
    var playsSets: Bool { (setsToWin ?? 1) > 1 }
    var summary: String { "\(startingScore) · \(outLabel) · \(lengthLabel)" }
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
    var rules: OnlineRules
    var host: Host
    var seated: Int
    var open: Bool
    var createdAt: String
}

/// Co telefon posílá při založení i úpravě lobby.
struct OnlineLobbySettings: Equatable {
    var isPublic = true
    var startingScore = 501
    var outRule = OutRule.double
    var legsToWin = 2
    var setsToWin = 1
    var format = MatchFormat.firstTo

    init() {}

    init(config: GameConfig, isPublic: Bool) {
        self.isPublic = isPublic
        startingScore = config.startingScore
        outRule = config.outRule
        legsToWin = config.legsToWin
        setsToWin = config.setsToWin
        format = config.format
    }

    var body: [String: Any] {
        [
            "kind": "classic",
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
    }
}
