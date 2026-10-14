import SwiftUI

/// Společná plocha zápisu pro zápas i trénink. Barvy sedí na zápasové plátno.
enum ScoringChrome {
    static let coral = Color(red: 1, green: 0.32, blue: 0.20)
    static let ink = Color(red: 0.045, green: 0.10, blue: 0.075)
    static let green = Color(red: 0.13, green: 0.80, blue: 0.49)
    static let aiTipSoft = Color(red: 0.78, green: 0.95, blue: 0.90)
    /// Pauza po kole, než se ukáže další — stejná v zápase i tréninku.
    static func visitHoldSeconds(botDelay: Double = 1.5, reduceMotion: Bool) -> Double {
        reduceMotion ? 0.45 : max(1.8, min(2.8, botDelay + 0.6))
    }
}

/// Způsob zápisu šipek — sdílený zápasem i tréninkem.
enum ScoringSurface: String, CaseIterable, Identifiable {
    case grid, board, total, voice, camera
    var id: String { rawValue }
    var title: String {
        switch self {
        case .grid: return "Čísla"
        case .board: return "Terč"
        case .total: return "Součet"
        case .voice: return "Hlas"
        case .camera: return "Kamera"
        }
    }
    var icon: String {
        switch self {
        case .grid: return "square.grid.3x3.fill"
        case .board: return "target"
        case .total: return "number"
        case .voice: return "mic.fill"
        case .camera: return "camera.fill"
        }
    }
}

/// Klávesnice součtu kola. Stejná v zápase i tréninku.
struct TotalScorePad: View {
    @Binding var sumText: String
    var showBust: Bool = true
    var onQuick: (Int) -> Void
    var onBust: () -> Void = {}
    var onTap: () -> Void = {}

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach([26, 41, 60, 100, 140, 180], id: \.self) { score in
                    Button {
                        onTap()
                        onQuick(score)
                    } label: {
                        Text("\(score)")
                            .font(AppFont.caption(13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Součet \(score)")
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(keys, id: \.self) { key in
                    if key.isEmpty {
                        Color.clear.frame(maxWidth: .infinity, minHeight: 48)
                    } else {
                        Button {
                            onTap()
                            if key == "⌫" {
                                if !sumText.isEmpty { sumText.removeLast() }
                            } else if key == "BUST" {
                                onBust()
                            } else if sumText.count < 3 {
                                sumText = sumText == "0" ? key : sumText + key
                            }
                        } label: {
                            Text(key)
                                .font(key == "BUST" || key == "⌫" ? AppFont.caption(14, weight: .bold) : AppFont.display(24, weight: .bold))
                                .foregroundStyle(key == "BUST" ? ScoringChrome.coral : Color.white)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(key == "⌫" ? "Smazat" : key == "BUST" ? "Přehoz" : key)
                    }
                }
            }
        }
    }

    private var keys: [String] {
        showBust
            ? ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "BUST"]
            : ["1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", ""]
    }
}

/// Karty „kolo hotovo“ při souhrnu součtu / hlasu.
struct VisitHoldSummaryCard: View {
    var title: String
    var value: String
    var labels: [String]

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(AppFont.caption(13, weight: .semibold))
                .foregroundStyle(ScoringChrome.ink.opacity(0.55))
            Text(value)
                .font(AppFont.display(48, weight: .bold))
                .foregroundStyle(ScoringChrome.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
            if !labels.isEmpty {
                Text(labels.joined(separator: " · "))
                    .font(AppFont.body(15, weight: .semibold))
                    .foregroundStyle(ScoringChrome.ink.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Inferované šipky pro zápis součtu (stejná logika jako v zápase).
enum ScoringTotal {
    static func darts(for score: Int) -> [Dart]? {
        guard let route = Match.scoringRoute(score) else { return nil }
        if score == 0 { return [.miss, .miss, .miss] }
        return Array(repeating: .miss, count: max(0, 3 - route.count)) + route
    }
}

/// Ruční zápis šipky: mřížka 1–20, bull, minutí a Double / Triple.
struct ManualScorePad: View {
    @Binding var multiplier: Int
    /// Jedno zvýrazněné pole, třeba aktuální cíl Kolem hodin. `nil` je obyčejná mřížka.
    var focus: Int? = nil
    var onSelect: () -> Void = {}
    var onHit: (Dart) -> Void

    private var accent: Color {
        switch multiplier {
        case 2: return ScoringChrome.coral
        case 3: return ScoringChrome.green
        default: return .white
        }
    }
    private var bullDisabled: Bool { multiplier == 3 }

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(1...20, id: \.self) { number in
                    Button { onHit(Dart(number, multiplier)) } label: {
                        Text("\(number)")
                            .font(AppFont.display(24, weight: .bold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(tileFill(focused: focus == number), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(tileStroke(focused: focus == number))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(multiplierName) \(number)")
                    .accessibilityAddTraits(focus == number ? .isSelected : [])
                }
            }

            HStack(spacing: 6) {
                Button {
                    guard !bullDisabled else { return }
                    onHit(Dart(25, min(max(multiplier, 1), 2)))
                } label: {
                    Text(multiplier == 2 ? "50" : "25")
                        .font(AppFont.display(24, weight: .bold))
                        .foregroundStyle(bullDisabled ? Color.white.opacity(0.22) : accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(tileFill(focused: focus == 25 && !bullDisabled, dimmed: bullDisabled), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(tileStroke(focused: focus == 25 && !bullDisabled))
                }
                .buttonStyle(.plain)
                .disabled(bullDisabled)
                .accessibilityLabel(multiplier == 2 ? "Bull 50" : "Outer 25")
                .accessibilityHint(bullDisabled ? "Triple bull neexistuje" : "")

                Button {
                    guard !bullDisabled else { return }
                    onHit(.miss)
                } label: {
                    Text("0")
                        .font(AppFont.display(24, weight: .bold))
                        .foregroundStyle(bullDisabled ? Color.white.opacity(0.22) : .white)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.white.opacity(bullDisabled ? 0.03 : 0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(bullDisabled)
                .accessibilityLabel("Mimo terč, 0 bodů")
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    multiplierButton("Double", value: 2, tint: ScoringChrome.coral)
                    multiplierButton("Triple", value: 3, tint: ScoringChrome.green)
                }
            }
        }
    }

    private var multiplierName: String {
        multiplier == 3 ? "Triple" : multiplier == 2 ? "Double" : "Single"
    }

    private func tileFill(focused: Bool, dimmed: Bool = false) -> Color {
        if dimmed { return Color.white.opacity(0.03) }
        if focused { return ScoringChrome.coral.opacity(0.28) }
        return Color.white.opacity(0.08)
    }

    private func tileStroke(focused: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(focused ? ScoringChrome.coral : .clear, lineWidth: 1.5)
    }

    private func multiplierButton(_ title: String, value: Int, tint: Color) -> some View {
        let selected = multiplier == value
        return Button {
            onSelect()
            multiplier = selected ? 1 : value
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(selected ? Theme.onAccent : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint.opacity(selected ? 1 : 0.62)).interactive(), in: Capsule())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(title)
    }
}

/// Jeden slot aktuálního hodu. Stejný v zápasu i v tréninku.
struct ThrowSlotFace: View {
    var index: Int
    var dart: Dart?
    var note: String? = nil

    var body: some View {
        if let dart {
            VStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(AppFont.caption(10, weight: .bold))
                    .foregroundStyle(ScoringChrome.ink.opacity(0.4))
                Text("\(dart.score)")
                    .font(AppFont.display(26, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(ScoringChrome.ink)
                Text(dart.label)
                    .font(AppFont.caption(12, weight: .bold))
                    .foregroundStyle(ScoringChrome.ink.opacity(0.65))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ScoringChrome.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel("\(index + 1). šipka \(dart.label)")
        } else {
            VStack(spacing: 4) {
                Text("\(index + 1)")
                    .font(AppFont.caption(10, weight: .bold))
                    .foregroundStyle(ScoringChrome.ink.opacity(0.35))
                Text("—")
                    .font(AppFont.display(26, weight: .bold))
                    .foregroundStyle(ScoringChrome.ink.opacity(0.22))
                Text(note ?? "\(index + 1). šipka")
                    .font(AppFont.caption(11, weight: .semibold))
                    .foregroundStyle(ScoringChrome.ink.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ScoringChrome.aiTipSoft.opacity(note != nil ? 0.55 : 0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityLabel(note.map { "\(index + 1). šipka, \($0)" } ?? "\(index + 1). šipka volná")
        }
    }
}

/// Bílý rám terče, stejný při hře i po odhodu.
struct ScoringDartboard: View {
    var marks: [Dart]
    var interactive: Bool
    var onHit: (Dart) -> Void = { _ in }

    var body: some View {
        TouchDartboard(marks: marks, interactive: interactive, onHit: onHit)
            .allowsHitTesting(interactive)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

/// Značky cricketu. Čísla jdou ve sloupcích, ať tabulka nezabere výšku terče.
struct CricketMarksCard: View {
    var names: [String]
    var marksByPlayer: [[Int: Int]]
    var numbers: [Int]
    var active: Int?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                Color.clear.frame(width: 52, height: 1)
                ForEach(numbers, id: \.self) { number in
                    Text(number == 25 ? "B" : "\(number)")
                        .font(AppFont.caption(12, weight: .bold))
                        .foregroundStyle(ScoringChrome.ink.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(names.indices, id: \.self) { index in
                HStack(spacing: 2) {
                    Text(shortName(names[index]))
                        .font(AppFont.caption(11, weight: .bold))
                        .foregroundStyle(index == active ? ScoringChrome.coral : ScoringChrome.ink.opacity(0.7))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 52, alignment: .leading)
                    ForEach(numbers, id: \.self) { number in
                        let marks = marksByPlayer.indices.contains(index) ? marksByPlayer[index][number, default: 0] : 0
                        Text(Self.symbol(marks))
                            .font(AppFont.body(16, weight: .bold))
                            .foregroundStyle(marks >= 3 ? ScoringChrome.green : ScoringChrome.ink.opacity(0.72))
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .accessibilityLabel("\(names[index]), \(number == 25 ? "bull" : "\(number)"), \(min(marks, 3)) zásahy")
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Značky cricketu")
    }

    private func shortName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 7 else { return trimmed }
        return String(trimmed.prefix(6))
    }

    private static func symbol(_ marks: Int) -> String {
        ["—", "/", "×", "⊗"][min(3, max(0, marks))]
    }
}

/// Postup Kolem hodin. Stejná bílá karta jako značky cricketu.
struct ClockProgressStrip: View {
    /// 1…20 je číslo, 21 je bull, 22 znamená uzavřeno.
    var current: Int
    var rule: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(rule.uppercased())
                .font(AppFont.caption(11, weight: .heavy))
                .tracking(0.6)
                .foregroundStyle(ScoringChrome.ink.opacity(0.45))
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(1...21, id: \.self) { step in
                            chip(step)
                                .id(step)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(min(max(current, 1), 21), anchor: .center) }
                .onChange(of: current) { _, step in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(min(max(step, 1), 21), anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if current >= 22 { return "Kolem hodin, všech 21 cílů hotovo. \(rule)" }
        let place = current >= 21 ? "bull" : "\(current)"
        let done = min(21, max(0, current - 1))
        return "Kolem hodin, cíl \(place), hotovo \(done) z 21. \(rule)"
    }

    private func chip(_ step: Int) -> some View {
        let now = step == current && current <= 21
        let done = step < current
        return Text(step == 21 ? "B" : "\(step)")
            .font(AppFont.caption(12, weight: now ? .heavy : .bold))
            .foregroundStyle(now ? Color.white : ScoringChrome.ink.opacity(done ? 0.85 : 0.32))
            .frame(width: now ? 34 : 26, height: 32)
            .background(now ? ScoringChrome.coral : ScoringChrome.ink.opacity(done ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
