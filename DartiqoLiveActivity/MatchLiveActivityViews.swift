import ActivityKit
import SwiftUI
import WidgetKit

typealias MatchContext = ActivityViewContext<MatchActivityAttributes>
typealias MatchState = MatchActivityAttributes.ContentState

/// Barvy z `Theme` aplikace. Rozšíření nemá přístup k jejímu modulu.
enum LivePalette {
    static let brand = Color(red: 254 / 255, green: 252 / 255, blue: 3 / 255)
    static let positive = Color(red: 0.30, green: 0.85, blue: 0.52)
    static let live = Color(red: 0.96, green: 0.18, blue: 0.24)
    static let background = Color.black
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

/// Odznak jako v televizním přenosu: LIVE, PAUZA, ČEKÁ, KONEC.
struct LiveBadge: View {
    var context: MatchContext

    var body: some View {
        let (text, fill, ink) = style
        HStack(spacing: 4) {
            Circle()
                .fill(ink)
                .frame(width: 5, height: 5)
            Text(text)
        }
        .font(.system(size: 10, weight: .black, design: .rounded))
        .tracking(0.6)
        .foregroundStyle(ink)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(fill, in: Capsule())
        .fixedSize()
        .accessibilityLabel(text)
    }

    private var style: (String, Color, Color) {
        let state = context.state
        if state.phase == .finished { return ("KONEC", LivePalette.positive, .black) }
        if context.isStale { return ("ČEKÁ", .white.opacity(0.22), .white) }
        if state.paused { return ("PAUZA", .white.opacity(0.22), .white) }
        return ("LIVE", LivePalette.live, .white)
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
                        .background(.white.opacity(0.18), in: Capsule())
                } else {
                    Circle()
                        .strokeBorder(.white.opacity(0.4), lineWidth: 1.5)
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
                        .background(checkout ? LivePalette.brand : .white.opacity(0.18), in: Capsule())
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

/// Pozadí ve stylu „versus“: barvy hráčů z boků, silnější u toho, kdo je na tahu.
struct LiveBackground: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    var context: MatchContext

    var body: some View {
        let state = context.state
        let count = context.attributes.players.count
        ZStack {
            LivePalette.background
            if count == 2 {
                LinearGradient(
                    stops: [
                        .init(color: LivePalette.player(0).opacity(state.isHighlighted(0) ? 0.55 : 0.22), location: 0),
                        .init(color: .clear, location: 0.5),
                        .init(color: LivePalette.player(1).opacity(state.isHighlighted(1) ? 0.55 : 0.22), location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                LinearGradient(
                    colors: [LivePalette.player(state.active).opacity(0.5), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .opacity(dimmed ? 0.35 : 1)
    }
}

struct MatchLockScreenView: View {
    @Environment(\.activityFamily) private var family
    var context: MatchContext

    var body: some View {
        Group {
            if family == .small {
                MatchSmallView(context: context)
            } else {
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background { LiveBackground(context: context) }
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    @ViewBuilder private var content: some View {
        let manyPlayers = context.attributes.players.count >= 3
        VStack(spacing: 8) {
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
            LiveBadge(context: context)
            if showStatus, let status = MatchStatus(context) {
                Text(status.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(status.tint)
                    .lineLimit(1)
            } else {
                Text(context.attributes.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if context.state.phase != .finished {
                MatchClock(state: context.state)
            }
        }
    }
}

/// Karta se skóre v barvě hráče. Hráč na tahu má plnou barvu, ostatní jen nádech.
struct ScoreCard: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    var name: String
    var score: String
    var index: Int
    var highlighted: Bool
    var playing: Bool
    var alignment: HorizontalAlignment
    var scoreSize: CGFloat = 38

    var body: some View {
        let color = LivePalette.player(index)
        let filled = highlighted && !dimmed
        let leading = alignment == .leading
        VStack(alignment: alignment, spacing: 0) {
            HStack(spacing: 4) {
                if highlighted && playing && !leading { playMark }
                Text(name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if highlighted && playing && leading { playMark }
            }
            .opacity(0.85)
            Text(score)
                .font(.system(size: scoreSize, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(filled ? .black : .white.opacity(highlighted ? 1 : 0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(filled
                    ? AnyShapeStyle(LinearGradient(colors: [color, color.opacity(0.78)], startPoint: .top, endPoint: .bottom))
                    : AnyShapeStyle(color.opacity(highlighted ? 0.3 : 0.14)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(color.opacity(highlighted ? 0 : 0.45), lineWidth: 1)
        }
    }

    private var playMark: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 8, weight: .black))
            .accessibilityHidden(true)
    }
}

/// Stav legů mezi dvěma hráči. Každé číslo má barvu svého hráče; u setů je pod tím i sety.
struct MatchScoreboard: View {
    var context: MatchContext
    /// Menší verze pro Dynamic Island.
    var compact = false

    var body: some View {
        let state = context.state
        VStack(spacing: compact ? 1 : 3) {
            HStack(spacing: compact ? 3 : 4) {
                digit(state.line(0).legs, index: 0)
                Text(":")
                    .font(.system(size: compact ? 14 : 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                digit(state.line(1).legs, index: 1)
            }
            Text(caption)
                .font(.system(size: compact ? 8 : 9, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.65))
                .monospacedDigit()
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var caption: String {
        let state = context.state
        if context.attributes.playsSets {
            return "SETY \(state.line(0).sets):\(state.line(1).sets)"
        }
        return "LEGY"
    }

    private var accessibility: String {
        let state = context.state
        if context.attributes.playsSets {
            return "Sety \(state.line(0).sets) ku \(state.line(1).sets), legy \(state.line(0).legs) ku \(state.line(1).legs)"
        }
        return "Legy \(state.line(0).legs) ku \(state.line(1).legs)"
    }

    private func digit(_ value: Int, index: Int) -> some View {
        let color = LivePalette.player(index)
        let size: CGFloat = compact ? 16 : 22
        return Text("\(value)")
            .font(.system(size: size, weight: .black, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(.black)
            .frame(width: compact ? 22 : 28, height: compact ? 22 : 28)
            .background(
                LinearGradient(colors: [color, color.opacity(0.8)], startPoint: .top, endPoint: .bottom),
                in: RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: compact ? 6 : 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
            }
    }
}

/// Dva hráči proti sobě: barevné karty po stranách, legy uprostřed.
struct DuelBoard: View {
    var context: MatchContext

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            card(0, alignment: .leading)
            MatchScoreboard(context: context)
            card(1, alignment: .trailing)
        }
    }

    private func card(_ index: Int, alignment: HorizontalAlignment) -> some View {
        let state = context.state
        return ScoreCard(
            name: context.attributes.name(index),
            score: state.line(index).score,
            index: index,
            highlighted: state.isHighlighted(index),
            playing: state.phase == .playing,
            alignment: alignment
        )
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

/// Jeden hráč: velká karta se skóre a číslo legu.
struct SoloBoard: View {
    var context: MatchContext

    var body: some View {
        let line = context.state.line(0)
        HStack(spacing: 8) {
            ScoreCard(
                name: context.attributes.name(0),
                score: line.score,
                index: 0,
                highlighted: true,
                playing: context.state.phase == .playing,
                alignment: .leading,
                scoreSize: 40
            )
            VStack(alignment: .trailing, spacing: 2) {
                Text("LEG \(context.state.leg)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                if let last = line.last {
                    Text("poslední \(last)")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .monospacedDigit()
            .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Tři a čtyři hráči jako barevné pruhy v pořadí sestavy.
struct RowsBoard: View {
    @Environment(\.isLuminanceReduced) private var dimmed
    var context: MatchContext

    var body: some View {
        VStack(spacing: 3) {
            ForEach(context.attributes.players.indices, id: \.self) { index in
                row(index)
            }
        }
    }

    private func row(_ index: Int) -> some View {
        let state = context.state
        let line = state.line(index)
        let highlighted = state.isHighlighted(index)
        let filled = highlighted && !dimmed
        let color = LivePalette.player(index)
        let showsHint = state.phase == .playing && state.active == index
        return HStack(spacing: 8) {
            Text(context.attributes.name(index))
                .font(.system(size: 14, weight: highlighted ? .heavy : .semibold, design: .rounded))
                .lineLimit(1)
                .layoutPriority(1)
            if showsHint, let hint = state.hint {
                Text(hint)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(filled ? Color.black.opacity(0.85) : LivePalette.brand, in: Capsule())
                    .foregroundStyle(filled ? LivePalette.brand : .black)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(context.attributes.playsSets ? "\(line.sets)·" : "")\(line.legs)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background((filled ? Color.black : Color.white).opacity(0.18), in: Capsule())
            Text(line.score)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 40, alignment: .trailing)
        }
        .foregroundStyle(filled ? .black : .white.opacity(highlighted ? 1 : 0.75))
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .background(
            filled ? AnyShapeStyle(color) : AnyShapeStyle(color.opacity(highlighted ? 0.3 : 0.14)),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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
                LiveBadge(context: context)
                Spacer(minLength: 0)
                if context.attributes.isDuel {
                    Text("\(state.line(0).legs):\(state.line(1).legs)")
                        .font(.caption2.weight(.heavy))
                        .monospacedDigit()
                }
            }

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
