import ActivityKit
import Foundation

/// Živá aktivita rozehraného zápasu. Sdílí ji aplikace i rozšíření s Live Activity.
/// Neměnné údaje jsou tady, proměnlivý stav v `ContentState`. Ten musí zůstat pod 4 KB.
nonisolated struct MatchActivityAttributes: ActivityAttributes {
    nonisolated struct Player: Codable, Hashable, Sendable {
        var name: String
        var bot: Bool
    }

    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Phase: String, Codable, Hashable, Sendable {
            /// Hraje se, `active` je na tahu.
            case playing
            /// Leg je dohraný, čeká se na další.
            case legWon
            /// Limit šipek vypršel, rozhodne rozhoz na střed.
            case bullOff
            /// Rozhodující leg čeká, kdo začne.
            case decidingStarter
            case finished
        }

        nonisolated struct Line: Codable, Hashable, Sendable {
            /// Zbývá u X01, body u Cricketu a Count Up, cíl u Kolem hodin.
            var score: String
            var legs: Int
            var sets: Int
            /// Poslední dokončené kolo.
            var last: Int?
        }

        var phase: Phase
        var lines: [Line]
        var active: Int
        var leg: Int
        var set: Int
        /// Šipky rozhozené v právě běžícím kole, např. `["T20", "S20"]`.
        var darts: [String]
        /// Doporučený checkout nebo nahrávka pro hráče na tahu.
        var hint: String?
        var hintIsCheckout: Bool
        var legWinner: Int?
        var winner: Int?
        var paused: Bool
        /// Odehrané sekundy v okamžiku aktualizace.
        var played: Int
        /// Kdy by hodiny ukazovaly nulu, kdyby běžely celou dobu. Jen když čas právě běží.
        var clockStart: Date?
    }

    var matchID: UUID
    /// Např. „X01“ nebo „Cricket“.
    var mode: String
    /// Např. „501 · Double“.
    var rules: String
    /// Např. „First to 3 legy“.
    var length: String
    var players: [Player]
    var playsSets: Bool
}

extension MatchActivityAttributes {
    /// Odkaz, který po klepnutí na aktivitu otevře rozehraný zápas.
    static let openURL = URL(string: "dartiqo://match")!
}
