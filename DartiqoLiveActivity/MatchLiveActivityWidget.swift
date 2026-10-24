import ActivityKit
import SwiftUI
import WidgetKit

struct MatchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MatchActivityAttributes.self) { context in
            MatchLockScreenView(context: context)
                .activityBackgroundTint(LivePalette.background)
                .activitySystemActionForegroundColor(LivePalette.brand)
                .widgetURL(MatchActivityAttributes.openURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandSide(context: context, index: context.attributes.isDuel ? 0 : context.state.active, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.attributes.isDuel {
                        IslandSide(context: context, index: 1, alignment: .trailing)
                    } else {
                        VStack(alignment: .trailing, spacing: 4) {
                            Text("Leg \(context.state.leg)")
                                .font(.caption.weight(.bold))
                            if context.state.phase != .finished {
                                MatchClock(state: context.state)
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    IslandCenter(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MatchFooter(context: context)
                        .padding(.top, 4)
                }
            } compactLeading: {
                CompactLeading(context: context)
            } compactTrailing: {
                CompactTrailing(context: context)
            } minimal: {
                MinimalView(context: context)
            }
            .keylineTint(LivePalette.player(context.state.active))
            .widgetURL(MatchActivityAttributes.openURL)
        }
        .supplementalActivityFamilies([.small])
    }
}

// MARK: - Dynamic Island

private struct IslandSide: View {
    var context: MatchContext
    var index: Int
    var alignment: HorizontalAlignment

    var body: some View {
        let highlighted = context.state.isHighlighted(index)
        let leading = alignment == .leading
        VStack(alignment: alignment, spacing: 0) {
            HStack(spacing: 4) {
                if leading { PlayerMarker(index: index, highlighted: highlighted) }
                Text(context.attributes.name(index))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if !leading { PlayerMarker(index: index, highlighted: highlighted) }
            }
            Text(context.state.line(index).score)
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(highlighted ? .white : .white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: leading ? .leading : .trailing)
        .padding(leading ? .leading : .trailing, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct IslandCenter: View {
    var context: MatchContext

    var body: some View {
        if context.attributes.isDuel {
            MatchScoreboard(context: context, compact: true)
        } else {
            Text(context.attributes.headline)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

/// U dvou hráčů levé skóre, jinak značka Dartiqo.
private struct CompactLeading: View {
    var context: MatchContext

    var body: some View {
        let state = context.state
        if state.phase == .finished {
            Image(systemName: "trophy.fill")
                .foregroundStyle(LivePalette.positive)
        } else if context.attributes.isDuel {
            HStack(spacing: 4) {
                PlayerMarker(index: 0, highlighted: state.isHighlighted(0))
                CompactScore(text: state.line(0).score, highlighted: state.isHighlighted(0), index: 0)
            }
        } else {
            Image(systemName: "target")
                .foregroundStyle(LivePalette.brand)
        }
    }
}

/// U dvou hráčů pravé skóre, jinak skóre hráče na tahu.
private struct CompactTrailing: View {
    var context: MatchContext

    var body: some View {
        let state = context.state
        if state.phase == .finished {
            Text(context.attributes.isDuel ? "\(state.line(0).legs)–\(state.line(1).legs)" : "Konec")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .monospacedDigit()
        } else if context.attributes.isDuel {
            HStack(spacing: 4) {
                CompactScore(text: state.line(1).score, highlighted: state.isHighlighted(1), index: 1)
                PlayerMarker(index: 1, highlighted: state.isHighlighted(1))
            }
        } else {
            CompactScore(text: state.activeScore, highlighted: true, index: state.active)
        }
    }
}

private struct CompactScore: View {
    var text: String
    var highlighted: Bool
    var index: Int

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(highlighted ? LivePalette.player(index) : .white.opacity(0.55))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// Když běží víc aktivit naráz: skóre hráče na tahu v jeho barvě.
private struct MinimalView: View {
    var context: MatchContext

    var body: some View {
        if context.state.phase == .finished {
            Image(systemName: "trophy.fill")
                .foregroundStyle(LivePalette.positive)
        } else {
            Text(context.state.activeScore)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(LivePalette.player(context.state.active))
        }
    }
}

// MARK: - Náhledy

#if DEBUG
private extension MatchActivityAttributes {
    static let duel = MatchActivityAttributes(
        matchID: UUID(), mode: "X01", rules: "501 · Double", length: "First to 3 legy",
        players: [.init(name: "Marek", bot: false), .init(name: "Bot 12", bot: true)],
        playsSets: false
    )
    static let party = MatchActivityAttributes(
        matchID: UUID(), mode: "X01", rules: "301 · Double", length: "First to 2 legy",
        players: [.init(name: "Marek", bot: false), .init(name: "Jana", bot: false), .init(name: "Petr", bot: false), .init(name: "Bot 8", bot: true)],
        playsSets: false
    )
}

private extension MatchActivityAttributes.ContentState {
    static let checkout = MatchState(
        phase: .playing,
        lines: [.init(score: "96", legs: 1, sets: 0, last: 140), .init(score: "181", legs: 2, sets: 0, last: 60)],
        active: 0, leg: 4, set: 1, darts: ["S20"], hint: "T20 D8", hintIsCheckout: true,
        legWinner: nil, winner: nil, paused: false, played: 754, clockStart: Date().addingTimeInterval(-754)
    )
    static let legWon = MatchState(
        phase: .legWon,
        lines: [.init(score: "0", legs: 2, sets: 0, last: 96), .init(score: "181", legs: 2, sets: 0, last: 60)],
        active: 0, leg: 4, set: 1, darts: [], hint: nil, hintIsCheckout: false,
        legWinner: 0, winner: nil, paused: false, played: 801, clockStart: nil
    )
    static let finished = MatchState(
        phase: .finished,
        lines: [.init(score: "0", legs: 3, sets: 0, last: 40), .init(score: "36", legs: 2, sets: 0, last: 100)],
        active: 0, leg: 5, set: 1, darts: [], hint: nil, hintIsCheckout: false,
        legWinner: 0, winner: 0, paused: false, played: 1320, clockStart: nil
    )
    static let party = MatchState(
        phase: .playing,
        lines: [.init(score: "121", legs: 1, sets: 0, last: 45), .init(score: "57", legs: 0, sets: 0, last: 100),
                .init(score: "201", legs: 0, sets: 0, last: 26), .init(score: "140", legs: 1, sets: 0, last: 81)],
        active: 1, leg: 3, set: 1, darts: [], hint: "S17 D20", hintIsCheckout: true,
        legWinner: nil, winner: nil, paused: false, played: 410, clockStart: Date().addingTimeInterval(-410)
    )
}

#Preview("Zamčená obrazovka", as: .content, using: MatchActivityAttributes.duel) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchState.checkout
    MatchState.legWon
    MatchState.finished
}

#Preview("Čtyři hráči", as: .content, using: MatchActivityAttributes.party) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchState.party
}

#Preview("Island rozbalený", as: .dynamicIsland(.expanded), using: MatchActivityAttributes.duel) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchState.checkout
    MatchState.finished
}

#Preview("Island kompaktní", as: .dynamicIsland(.compact), using: MatchActivityAttributes.duel) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchState.checkout
}

#Preview("Island minimální", as: .dynamicIsland(.minimal), using: MatchActivityAttributes.duel) {
    MatchLiveActivityWidget()
} contentStates: {
    MatchState.checkout
}
#endif
