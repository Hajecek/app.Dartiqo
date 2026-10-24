import ActivityKit
import SwiftUI
import WidgetKit

typealias MatchContext = ActivityViewContext<MatchActivityAttributes>
typealias MatchState = MatchActivityAttributes.ContentState

/// Barvy z `Theme` aplikace. Rozšíření nemá přístup k jejímu modulu.
enum LivePalette {
    static let brand = Color(red: 254 / 255, green: 252 / 255, blue: 3 / 255)
    static let positive = Color(red: 0.30, green: 0.85, blue: 0.52)
    static let background = Color.black.opacity(0.88)
    private static let players: [Color] = [
        brand,
        Color(red: 0.35, green: 0.78, blue: 1),
        Color(red: 1, green: 0.55, blue: 0.25),
        Color(red: 0.95, green: 0.45, blue: 0.85)
    ]
    static func player(_ index: Int) -> Color {
        players[((index % players.count) + players.count) % players.count]
    }
}

extension MatchActivityAttributes {
    func name(_ index: Int) -> String {
        players.indices.contains(index) ? players[index].name : ""
    }
    var isDuel: Bool { players.count == 2 }
    var headline: String {
        [mode, rules].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension MatchActivityAttributes.ContentState {
    func line(_ index: Int) -> Line {
        lines.indices.contains(index) ? lines[index] : Line(score: "–", legs: 0, sets: 0, last: nil)
    }
    /// Kdo je zvýrazněný: hráč na tahu, po konci leg/zápas vítěz.
    func isHighlighted(_ index: Int) -> Bool {
        switch phase {
        case .finished: return winner == index
        case .legWon: return legWinner == index
        default: return active == index
        }
    }
    var activeScore: String { line(active).score }
}

/// Stav, který má přednost před tipem na checkout.
struct MatchStatus {
    var symbol: String
    var text: String
    var tint: Color

    init?(_ context: MatchContext) {
        let state = context.state
        let attributes = context.attributes
        switch state.phase {
        case .finished:
            if let winner = state.winner {
                self.init(symbol: "trophy.fill", text: attributes.players.count == 1 ? "Hotovo" : "Vítěz: \(attributes.name(winner))", tint: LivePalette.positive)
            } else {
                self.init(symbol: "flag.checkered", text: "Zápas skončil", tint: .secondary)
            }
        case _ where context.isStale:
            self.init(symbol: "hourglass", text: "Zápas čeká na pokračování", tint: .secondary)
        case _ where state.paused:
            self.init(symbol: "pause.circle.fill", text: "Pauza", tint: LivePalette.brand)
        case .legWon:
            self.init(symbol: "flag.checkered", text: "Leg bere \(attributes.name(state.legWinner ?? state.active))", tint: LivePalette.positive)
        case .bullOff:
            self.init(symbol: "scope", text: "Leg rozhodne rozhoz na střed", tint: LivePalette.brand)
        case .decidingStarter:
            self.init(symbol: "arrow.triangle.2.circlepath", text: "Rozhodující leg · kdo začne?", tint: LivePalette.brand)
        case .playing:
            return nil
        }
    }

    private init(symbol: String, text: String, tint: Color) {
        self.symbol = symbol
        self.text = text
        self.tint = tint
    }
}

// MARK: - Dílčí pohledy

/// Odehraný čas. Když běží, počítá ho systém sám bez aktualizací z aplikace.
struct MatchClock: View {
    var state: MatchState

    var body: some View {
        HStack(spacing: 3) {
            if state.paused {
                Image(systemName: "pause.fill")
                    .font(.caption2)
            }
            if let start = state.clockStart {
                Text(timerInterval: start...start.addingTimeInterval(24 * 3600), countsDown: false)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 58, alignment: .trailing)
            } else {
                Text(Self.format(state.played))
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .accessibilityLabel(state.paused ? "Pauza, odehráno \(Self.format(state.played))" : "Odehraný čas")
    }

    static func format(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = seconds / 60 % 60
        let rest = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }
}

/// Barevná značka hráče. Hráč na tahu má protaženou kapsli.
struct PlayerMarker: View {
    var index: Int
    var highlighted: Bool

    var body: some View {
        Capsule()
            .fill(LivePalette.player(index).opacity(highlighted ? 1 : 0.4))
            .frame(width: highlighted ? 14 : 6, height: 6)
            .accessibilityHidden(true)
    }
}

/// Šipky v rozehraném kole. Prázdné kroužky jsou šipky, které ještě zbývají.
struct VisitDarts: View {
    var darts: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { slot in
                if slot < darts.count {
                    Text(darts[slot])
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.16), in: Capsule())
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
                        .frame(width: 9, height: 9)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(darts.isEmpty ? "Tři šipky v ruce" : "Hozeno \(darts.joined(separator: ", "))")
    }
}

/// Doporučený checkout nebo nahrávka jako řada šipek.
struct HintRoute: View {
    var hint: String
    var checkout: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(checkout ? "CHECKOUT" : "NAHRÁVKA")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(checkout ? LivePalette.brand : .secondary)
                .fixedSize()
            ForEach(Array(hint.split(separator: " ").enumerated()), id: \.offset) { _, token in
                if token == "→" {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text(token)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(checkout ? .black : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(checkout ? LivePalette.brand : .white.opacity(0.16), in: Capsule())
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(checkout ? "Checkout" : "Nahrávka") \(hint.replacingOccurrences(of: "→", with: "na"))")
    }
}

/// Spodní řádek: stav zápasu, jinak tip a šipky v kole.
struct MatchFooter: View {
    var context: MatchContext

    var body: some View {
        HStack(spacing: 8) {
            if let status = MatchStatus(context) {
                Label(status.text, systemImage: status.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                if let hint = context.state.hint {
                    HintRoute(hint: hint, checkout: context.state.hintIsCheckout)
                } else {
                    Text("Na tahu \(context.attributes.name(context.state.active))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                VisitDarts(darts: context.state.darts)
            }
        }
    }
}

// MARK: - Zamčená obrazovka a banner

struct MatchLockScreenView: View {
    @Environment(\.activityFamily) private var family
    var context: MatchContext

    var body: some View {
        Group {
            if family == .small {
                MatchSmallView(context: context)
            } else {
                content
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var content: some View {
        let manyPlayers = context.attributes.players.count >= 3
        VStack(spacing: manyPlayers ? 8 : 10) {
            header(showStatus: manyPlayers)
            switch context.attributes.players.count {
            case 1: SoloBoard(context: context)
            case 2: DuelBoard(context: context)
            default: RowsBoard(context: context)
            }
            if !manyPlayers { MatchFooter(context: context) }
        }
    }

    /// U tří a čtyř hráčů se stav vejde do hlavičky, aby aktivita nepřekročila 160 bodů.
    private func header(showStatus: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "target")
                .font(.caption.weight(.bold))
                .foregroundStyle(LivePalette.brand)
                .accessibilityHidden(true)
            if showStatus, let status = MatchStatus(context) {
                Label(status.text, systemImage: status.symbol)
                    .labelStyle(.titleOnly)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
            } else {
                Text(context.attributes.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if context.state.phase != .finished {
                MatchClock(state: context.state)
            }
        }
    }
}

/// Dva hráči proti sobě jako tabule: skóre po stranách, legy uprostřed.
struct DuelBoard: View {
    var context: MatchContext

    var body: some View {
        let state = context.state
        HStack(alignment: .center, spacing: 6) {
            side(0, alignment: .leading)
            VStack(spacing: 1) {
                Text("\(state.line(0).legs) – \(state.line(1).legs)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(context.attributes.playsSets ? "SETY \(state.line(0).sets)–\(state.line(1).sets)" : "LEGY")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(context.attributes.playsSets
                ? "Sety \(state.line(0).sets) ku \(state.line(1).sets), legy \(state.line(0).legs) ku \(state.line(1).legs)"
                : "Legy \(state.line(0).legs) ku \(state.line(1).legs)")
            side(1, alignment: .trailing)
        }
    }

    private func side(_ index: Int, alignment: HorizontalAlignment) -> some View {
        let state = context.state
        let line = state.line(index)
        let highlighted = state.isHighlighted(index)
        let leading = alignment == .leading
        return VStack(alignment: alignment, spacing: 0) {
            HStack(spacing: 5) {
                if leading { PlayerMarker(index: index, highlighted: highlighted) }
                Text(context.attributes.name(index))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !leading { PlayerMarker(index: index, highlighted: highlighted) }
            }
            Text(line.score)
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(highlighted ? .white : .white.opacity(0.45))
            Text(line.last.map { "poslední \($0)" } ?? " ")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility(index))
    }

    private func accessibility(_ index: Int) -> String {
        let line = context.state.line(index)
        var parts = ["\(context.attributes.name(index)) \(line.score)"]
        if let last = line.last { parts.append("poslední kolo \(last)") }
        if context.state.phase == .playing, context.state.active == index { parts.append("na tahu") }
        return parts.joined(separator: ", ")
    }
}

/// Jeden hráč: velké skóre a číslo legu.
struct SoloBoard: View {
    var context: MatchContext

    var body: some View {
        let line = context.state.line(0)
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    PlayerMarker(index: 0, highlighted: true)
                    Text(context.attributes.name(0))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(line.score)
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Leg \(context.state.leg)")
                    .font(.subheadline.weight(.bold))
                if let last = line.last {
                    Text("poslední \(last)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tři a čtyři hráči jako žebříček v pořadí sestavy.
struct RowsBoard: View {
    var context: MatchContext

    var body: some View {
        VStack(spacing: 2) {
            ForEach(context.attributes.players.indices, id: \.self) { index in
                row(index)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let state = context.state
        let line = state.line(index)
        let highlighted = state.isHighlighted(index)
        let showsHint = state.phase == .playing && state.active == index
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(LivePalette.player(index).opacity(highlighted ? 1 : 0.4))
                .frame(width: 4, height: 16)
            Text(context.attributes.name(index))
                .font(.subheadline.weight(highlighted ? .bold : .medium))
                .lineLimit(1)
                .layoutPriority(1)
            if showsHint, let hint = state.hint {
                HintRoute(hint: hint, checkout: state.hintIsCheckout)
                    .layoutPriority(0)
            }
            Spacer(minLength: 4)
            Text("\(context.attributes.playsSets ? "\(line.sets)·" : "")\(line.legs)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text(line.score)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 40, alignment: .trailing)
        }
        .foregroundStyle(highlighted ? .white : .white.opacity(0.6))
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(highlighted ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(context.attributes.name(index)) \(line.score), legy \(line.legs)\(showsHint ? ", na tahu" : "")")
    }
}

/// Apple Watch Smart Stack a CarPlay. Jen to nejdůležitější.
struct MatchSmallView: View {
    var context: MatchContext

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "target")
                    .foregroundStyle(LivePalette.brand)
                Text(context.attributes.mode)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if context.attributes.isDuel {
                    Text("\(state.line(0).legs)–\(state.line(1).legs)")
                        .monospacedDigit()
                }
            }
            .font(.caption2.weight(.bold))

            if context.attributes.isDuel {
                HStack {
                    score(0)
                    Spacer(minLength: 4)
                    score(1)
                }
            } else {
                HStack {
                    Text(context.attributes.name(state.active))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    score(state.active)
                }
            }

            if let status = MatchStatus(context) {
                Text(status.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
            } else if let hint = state.hint, state.hintIsCheckout {
                Text(hint)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(LivePalette.brand)
                    .lineLimit(1)
            }
        }
        .padding(10)
    }

    private func score(_ index: Int) -> some View {
        let highlighted = context.state.isHighlighted(index)
        return Text(context.state.line(index).score)
            .font(.system(size: 24, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(highlighted ? LivePalette.player(index) : .white.opacity(0.5))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}
