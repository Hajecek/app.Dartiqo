import Foundation

/// Jak zápas dopadl pro reputaci hráče. První zápis vyhrává, další se stejným id se ignoruje.
public enum MatchCompletionOutcome: String, Codable, Equatable {
    case completed
    case abandoned
}

/// Veřejný snímek bez interních id. Soupeř ho vidí u klasického zápasu a později i online.
public struct MatchCompletionSnapshot: Codable, Equatable {
    public var completed: Int
    public var abandoned: Int
    /// 0…100. `nil`, dokud hráč nemá ani jeden rozhodnutý zápas.
    public var percent: Double?

    public var decided: Int { completed + abandoned }

    public init(completed: Int, abandoned: Int, percent: Double?) {
        self.completed = completed
        self.abandoned = abandoned
        self.percent = percent
    }
}

/// Trvalá bilance dokončených a zrušených zápasů.
/// Smazání zápasu z historie záznam nevymaže — id tu zůstane a procento se nevrátí nahoru.
public struct MatchCompletionLedger: Codable, Equatable {
    public private(set) var entries: [Entry] = []

    public init() {}

    public struct Entry: Codable, Equatable {
        public var matchID: UUID
        public var outcome: MatchCompletionOutcome

        public init(matchID: UUID, outcome: MatchCompletionOutcome) {
            self.matchID = matchID
            self.outcome = outcome
        }
    }

    public var completed: Int { entries.filter { $0.outcome == .completed }.count }
    public var abandoned: Int { entries.filter { $0.outcome == .abandoned }.count }
    public var decided: Int { entries.count }

    /// 0…100. Bez rozhodnutého zápasu `nil`, ať nula her nevypadá jako sto procent.
    public var percent: Double? {
        guard decided > 0 else { return nil }
        return Double(completed) / Double(decided) * 100
    }

    public var snapshot: MatchCompletionSnapshot {
        MatchCompletionSnapshot(completed: completed, abandoned: abandoned, percent: percent)
    }

    /// Zapíše výsledek jednou. Stejné id znovu nic nemění, ani kdyby druhý pokus tvrdil opak.
    @discardableResult
    public mutating func note(_ matchID: UUID, outcome: MatchCompletionOutcome) -> Bool {
        guard !entries.contains(where: { $0.matchID == matchID }) else { return false }
        entries.append(Entry(matchID: matchID, outcome: outcome))
        return true
    }

    /// Přepíše bilanci podle tabulky matches na serveru. Lokální id se neuchovávají.
    public mutating func replace(from remote: MatchCompletionSnapshot) {
        entries = []
        for index in 0..<max(0, remote.completed) {
            entries.append(Entry(matchID: Self.remoteID(kind: 0, index: index), outcome: .completed))
        }
        for index in 0..<max(0, remote.abandoned) {
            entries.append(Entry(matchID: Self.remoteID(kind: 1, index: index), outcome: .abandoned))
        }
    }

    private static func remoteID(kind: Int, index: Int) -> UUID {
        let hex = String(format: "%012x", (kind << 24) | (index & 0x00FF_FFFF))
        return UUID(uuidString: "00000000-0000-4000-8000-\(hex)") ?? UUID()
    }
}
