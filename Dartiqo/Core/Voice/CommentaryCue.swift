import Foundation

/// Kdo v zápase hlásí skóre. Volba je u hráčského profilu.
enum Commentator: String, Codable, CaseIterable, Identifiable {
    case system
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Výchozí"
        case .custom: return "Můj hlas"
        }
    }
}

/// Jedna namluvitelná situace. Skóre 1…180 a zvláštní momenty mají vlastní nahrávku.
enum CommentaryCue: Hashable, Identifiable {
    case score(Int)
    case celebration180
    case bust
    case checkout
    case zero
    case newLeg
    case newSet
    case matchWin
    case matchStart

    var id: String {
        switch self {
        case .score(let value): return "score-\(value)"
        case .celebration180: return "celebration-180"
        case .bust: return "bust"
        case .checkout: return "checkout"
        case .zero: return "zero"
        case .newLeg: return "new-leg"
        case .newSet: return "new-set"
        case .matchWin: return "match-win"
        case .matchStart: return "match-start"
        }
    }

    var title: String {
        switch self {
        case .score(let value): return "\(value)"
        case .celebration180: return "180"
        case .bust: return "Přehoz"
        case .checkout: return "Zavření"
        case .zero: return "Nula"
        case .newLeg: return "Nový leg"
        case .newSet: return "Nový set"
        case .matchWin: return "Výhra"
        case .matchStart: return "Začátek zápasu"
        }
    }

    var detail: String {
        switch self {
        case .score: return "Skóre kola"
        case .celebration180: return "Oslava maxima"
        case .bust: return "Přehozené kolo"
        case .checkout: return "Zavřený leg"
        case .zero: return "Kolo bez bodů"
        case .newLeg: return "Start dalšího legu"
        case .newSet: return "Start dalšího setu"
        case .matchWin: return "Konec zápasu"
        case .matchStart: return "První leg"
        }
    }

    var symbol: String {
        switch self {
        case .score: return "number"
        case .celebration180: return "flame.fill"
        case .bust: return "arrow.uturn.backward"
        case .checkout: return "flag.checkered"
        case .zero: return "circle.slash"
        case .newLeg: return "arrow.forward.circle"
        case .newSet: return "square.stack.3d.up"
        case .matchWin: return "trophy.fill"
        case .matchStart: return "play.circle.fill"
        }
    }

    /// Co má člověk u mikrofonu říct.
    var prompt: String {
        switch self {
        case .score(let value):
            return "Namluv skóre \(value). V zápase se pustí po kole s tímhle součtem."
        case .celebration180:
            return "Namluv oslavu 180. Při maximu se pustí tahle hláška. Záloha je nahrávka skóre 180, potom výchozí hlas."
        case .bust:
            return "Namluv přehoz. Pustí se, když kolo neplatí."
        case .checkout:
            return "Namluv zavření. Pustí se při zavřeném legu. Když nahrávka chybí, ozve se skóre kola."
        case .zero:
            return "Namluv kolo za nulu. Tři šipky mimo, které nejsou přehoz."
        case .newLeg:
            return "Namluv začátek legu. Pustí se při přechodu na další leg."
        case .newSet:
            return "Namluv začátek setu. Když nahrávka chybí, zkusí se hláška nového legu."
        case .matchWin:
            return "Namluv výhru. Pustí se při vítězném zavření. Když nahrávka chybí, ozve se zavření nebo skóre kola."
        case .matchStart:
            return "Namluv úvod zápasu. Pustí se při startu hry."
        }
    }

    static let specials: [CommentaryCue] = [
        .celebration180, .bust, .checkout, .zero, .newLeg, .newSet, .matchWin, .matchStart
    ]

    static let scores: [CommentaryCue] = (1...180).map { .score($0) }

    static var all: [CommentaryCue] { specials + scores }

    static let scoreBands: [(title: String, cues: [CommentaryCue])] = stride(from: 1, through: 161, by: 20).map { start in
        let end = min(start + 19, 180)
        return ("\(start)–\(end)", (start...end).map { CommentaryCue.score($0) })
    }

    /// Pořadí, v jakém se hledá nahrávka. První uložená se pustí.
    static func playbackOrder(score: Int?, spoken: String?, checkout: Bool, matchWon: Bool) -> [CommentaryCue] {
        if spoken == "Přehoz" { return [.bust] }
        guard let score else { return [] }
        if score == 0 { return [.zero] }
        guard (1...180).contains(score) else { return [] }
        var order: [CommentaryCue] = []
        if score == 180 { order.append(.celebration180) }
        if matchWon { order.append(.matchWin) }
        if checkout { order.append(.checkout) }
        order.append(.score(score))
        return order
    }
}
