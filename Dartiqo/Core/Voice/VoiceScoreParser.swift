import Foundation

/// Výsledek českého hlasového zápisu — jednotlivé šipky, součet kola, nebo bust.
public enum VoiceScoreCommand: Equatable {
    case darts([Dart])
    case total(Int)
    case bust
}

/// Režim hlasového zápisu — přepínač v zápase.
public enum VoiceScoreMode: String, Equatable, CaseIterable, Identifiable {
    case darts
    case total

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .darts: return "Šipky"
        case .total: return "Součet"
        }
    }
}

/// Rozpozná české (i smíšené) fráze pro šipky a grubty.
public enum VoiceScoreParser {
    public static func parse(_ raw: String, mode: VoiceScoreMode = .darts) -> VoiceScoreCommand? {
        let text = normalize(raw)
        guard !text.isEmpty else { return nil }
        if isBust(text) { return .bust }

        switch mode {
        case .total:
            return parseTotalMode(text)
        case .darts:
            return parseDartsMode(text)
        }
    }

    /// Zpětná kompatibilita se starším `preferTotal`.
    public static func parse(_ raw: String, preferTotal: Bool) -> VoiceScoreCommand? {
        parse(raw, mode: preferTotal ? .total : .darts)
    }

    private static func parseTotalMode(_ text: String) -> VoiceScoreCommand? {
        if let total = parseCzechNumber(text), (0...180).contains(total) {
            return .total(total)
        }
        return nil
    }

    private static func parseDartsMode(_ text: String) -> VoiceScoreCommand? {
        if let spaced = parseSpacedSingles(text), !spaced.isEmpty {
            return .darts(spaced)
        }
        if looksLikeDartUtterance(text), let darts = parseDartSequence(text), !darts.isEmpty {
            return .darts(darts)
        }
        if let value = parseCzechNumber(text), (0...180).contains(value) {
            // V režimu šipek jen 1…20 jako single; větší čísla patří do Součtu.
            if value > 0, value <= 20, isSingleSegmentUtterance(text) {
                return .darts([Dart(value)])
            }
            return nil
        }
        if let darts = parseDartSequence(text), !darts.isEmpty {
            return .darts(darts)
        }
        return nil
    }

    /// 2–3 samostatná čísla 0…20 oddělená mezerou → šipky po jednom.
    private static func parseSpacedSingles(_ text: String) -> [Dart]? {
        let words = text.split(separator: " ").map(String.init)
        guard (2...3).contains(words.count) else { return nil }
        // „dvacet šest“ je 26, ne dvě šipky.
        if words.count == 2, czechTens(words[0]) != nil, czechUnit(words[1]) != nil {
            return nil
        }
        var darts: [Dart] = []
        for w in words {
            if w == "0" || w == "nula" || w == "mimo" || w == "miss" {
                darts.append(.miss)
                continue
            }
            guard let seg = parseSegment(w) else { return nil }
            darts.append(Dart(seg))
        }
        return darts
    }

    // MARK: - Normalize

    public static func normalize(_ raw: String) -> String {
        var s = raw
            .lowercased()
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        s = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "cs_CZ"))
        s = s.replacingOccurrences(of: #"(\d)\s*[x×]\s*"#, with: "$1 ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[-_/|]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[,;:!?.]+"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isBust(_ text: String) -> Bool {
        let keys = ["bust", "bus", "prehoz", "prehaz", "prehozeni", "prekroceni"]
        return keys.contains { text == $0 || text.hasPrefix($0 + " ") || text.hasSuffix(" " + $0) }
    }

    private static func isSingleSegmentUtterance(_ text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        if words.count == 1 {
            if Int(words[0]).map({ (1...20).contains($0) }) == true { return true }
            if let n = czechDigitWord(words[0]), (1...20).contains(n) { return true }
        }
        return false
    }

    private static func looksLikeDartUtterance(_ text: String) -> Bool {
        if text.range(of: #"\b[std]\d{1,2}\b"#, options: .regularExpression) != nil { return true }
        let words = text.split(separator: " ").map(String.init)
        if words.contains(where: isMultiplierWord) { return true }
        let markers: Set<String> = ["bull", "bullseye", "byk", "mimo", "miss", "outer", "nula"]
        if words.contains(where: { markers.contains($0) }) { return true }
        if text.contains(" a ") {
            let parts = text.components(separatedBy: " a ")
            if parts.count >= 2, parts.allSatisfy({ parseSingleDartPhrase($0) != nil }) { return true }
        }
        // Opakované segmenty: „dvacet dvacet dvacet“ — ne ale „dvacet šest“ (= 26).
        if words.count >= 2, words.allSatisfy({ parseSegment($0) != nil }) {
            if words.count == 2, czechTens(words[0]) != nil, czechUnit(words[1]) != nil {
                return false
            }
            return true
        }
        return false
    }

    // MARK: - Darts

    private static func parseDartSequence(_ text: String) -> [Dart]? {
        if let one = parseSingleDartPhrase(text) { return [one] }

        let parts: [String]
        if text.contains(" a ") {
            parts = text.components(separatedBy: " a ").map { $0.trimmingCharacters(in: .whitespaces) }
        } else {
            parts = splitDartParts(text)
        }
        guard !parts.isEmpty else { return nil }

        var darts: [Dart] = []
        for part in parts {
            guard let dart = parseSingleDartPhrase(part) else { return nil }
            darts.append(dart)
        }
        return darts.isEmpty ? nil : Array(darts.prefix(3))
    }

    private static func splitDartParts(_ text: String) -> [String] {
        let glued = text.replacingOccurrences(
            of: #"\b([std])\s+(\d{1,2})\b"#,
            with: "$1$2",
            options: .regularExpression
        )
        let words = glued.split(separator: " ").map(String.init)
        var out: [String] = []
        var i = 0
        while i < words.count {
            let w = words[i]
            if isMultiplierWord(w), i + 1 < words.count {
                out.append("\(w) \(words[i + 1])")
                i += 2
                continue
            }
            if looksLikeDartToken(w) || parseSegment(w) != nil {
                out.append(w)
                i += 1
                continue
            }
            return []
        }
        return out
    }

    private static func looksLikeDartToken(_ w: String) -> Bool {
        if w.range(of: #"^[std]\d{1,2}$"#, options: .regularExpression) != nil { return true }
        return ["bull", "bullseye", "byk", "mimo", "miss", "nula", "outer", "25", "petadvacet"].contains(w)
    }

    private static func isMultiplierWord(_ w: String) -> Bool {
        [
            "single", "singl", "singlova", "singlove", "singlovej",
            "double", "dvojita", "dvojity", "dvojite", "dvojitej", "dvojitou",
            "triple", "trojita", "trojity", "trojite", "trojitej", "trojitou", "tripla", "tripl"
        ].contains(w)
    }

    private static func parseSingleDartPhrase(_ text: String) -> Dart? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }

        if ["mimo", "miss", "nula", "nic", "vedle"].contains(t) { return .miss }
        if ["bull", "bullseye", "byk", "cerveny stred", "cervenej stred", "stred"].contains(t) {
            return Dart(25, 2)
        }
        if ["outer", "25", "zeleny stred", "zelenej stred", "petadvacet"].contains(t) {
            return Dart(25, 1)
        }

        if let match = t.wholeMatch(of: #/([std])(\d{1,2})/#) {
            let mult: Int = {
                switch match.1 {
                case "t": return 3
                case "d": return 2
                default: return 1
                }
            }()
            let seg = Int(match.2)!
            if seg == 25 { return Dart(25, min(mult, 2)) }
            if seg == 0 { return .miss }
            if (1...20).contains(seg) { return Dart(seg, mult) }
            return nil
        }
        if let match = t.wholeMatch(of: #/(\d{1,2})/#), let seg = Int(match.1), (1...20).contains(seg) {
            return Dart(seg)
        }

        var rest = t
        var mult = 1
        let words = rest.split(separator: " ").map(String.init)
        if let first = words.first, isMultiplierWord(first) {
            mult = multiplierValue(first)
            rest = words.dropFirst().joined(separator: " ")
        }
        if rest.isEmpty { return nil }

        if ["bull", "bullseye", "byk", "stred"].contains(rest) {
            return Dart(25, mult >= 2 ? min(mult, 2) : 2)
        }
        if rest == "25" || rest == "outer" || rest == "petadvacet" {
            return Dart(25, mult >= 2 ? 2 : 1)
        }

        guard let seg = parseSegment(rest), (1...20).contains(seg) else { return nil }
        return Dart(seg, mult)
    }

    private static func multiplierValue(_ w: String) -> Int {
        if ["triple", "trojita", "trojity", "trojite", "trojitej", "trojitou", "tripla", "tripl"].contains(w) {
            return 3
        }
        if ["double", "dvojita", "dvojity", "dvojite", "dvojitej", "dvojitou"].contains(w) {
            return 2
        }
        return 1
    }

    private static func parseSegment(_ text: String) -> Int? {
        if let n = Int(text), (1...20).contains(n) { return n }
        return czechDigitWord(text).flatMap { (1...20).contains($0) ? $0 : nil }
    }

    // MARK: - Czech numbers (0…180)

    public static func parseCzechNumber(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        if let n = Int(t) { return n }

        let words = t.split(separator: " ").map(String.init)
        var total = 0
        var i = 0
        while i < words.count {
            let w = words[i]
            if w == "sto" || w == "sta" {
                total += 100
                i += 1
                continue
            }
            if let tens = czechTens(w) {
                total += tens
                i += 1
                if i < words.count, let unit = czechUnit(words[i]) {
                    total += unit
                    i += 1
                }
                continue
            }
            if let teen = czechDigitWord(w), (11...19).contains(teen) {
                total += teen
                i += 1
                continue
            }
            if let unit = czechDigitWord(w) {
                total += unit
                i += 1
                continue
            }
            return nil
        }
        return words.isEmpty ? nil : total
    }

    private static func czechUnit(_ w: String) -> Int? {
        czechDigitWord(w).flatMap { (1...9).contains($0) ? $0 : nil }
    }

    private static func czechDigitWord(_ w: String) -> Int? {
        [
            "nula": 0, "nic": 0,
            "jedna": 1, "jeden": 1, "jednou": 1,
            "dva": 2, "dve": 2,
            "tri": 3,
            "ctyri": 4,
            "pet": 5,
            "sest": 6,
            "sedm": 7,
            "osm": 8,
            "devet": 9,
            "deset": 10,
            "jedenact": 11,
            "dvanact": 12,
            "trinact": 13,
            "ctrnact": 14,
            "patnact": 15,
            "sestnact": 16,
            "sedmnact": 17,
            "osmnact": 18,
            "devatenact": 19,
            "dvacet": 20
        ][w]
    }

    private static func czechTens(_ w: String) -> Int? {
        [
            "dvacet": 20,
            "tricet": 30,
            "ctyricet": 40,
            "padesat": 50,
            "sedesat": 60,
            "sedmdesat": 70,
            "osmdesat": 80,
            "devadesat": 90
        ][w]
    }
}
