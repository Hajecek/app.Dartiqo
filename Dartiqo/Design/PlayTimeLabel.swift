import SwiftUI

/// Celkový čas u terče. Od jedné hodiny se hodiny a minuty rozdělí, ať se dlouhý text vejde.
struct PlayTimeLabel: View {
    enum Layout {
        /// Jedna řádka vedle popisku. Hodiny jsou velké, jednotky malé.
        case inline
        /// Dvě řádky do díry v grafu.
        case ring(large: Bool)
    }

    var seconds: TimeInterval
    var layout: Layout

    private var parts: PlayTime.Components { PlayTime.components(seconds) }

    var body: some View {
        Group {
            if parts.hours > 0 {
                switch layout {
                case .inline: inlineHours
                case .ring(let large): ringHours(large: large)
                }
            } else {
                Text(PlayTime.format(seconds))
                    .font(.system(minutesFont, design: .rounded).weight(minutesWeight))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .accessibilityLabel(PlayTime.format(seconds))
    }

    private var minutesFont: Font.TextStyle {
        switch layout {
        case .inline: return .title3
        case .ring(let large): return large ? .title2 : .headline
        }
    }

    private var minutesWeight: Font.Weight {
        switch layout {
        case .inline: return .bold
        case .ring: return .heavy
        }
    }

    private var inlineHours: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            amount("\(parts.hours)", unit: "h")
            if parts.minutes > 0 {
                amount("\(parts.minutes)", unit: "min")
                    .padding(.leading, 4)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func ringHours(large: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(parts.hours)")
                    .font(.system(large ? .title : .title3, design: .rounded).weight(.heavy))
                Text("h")
                    .font(.system(large ? .footnote : .caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }
            if parts.minutes > 0 {
                Text("\(parts.minutes) min")
                    .font(.system(large ? .subheadline : .caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.65)
    }

    private func amount(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
            Text(unit)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .monospacedDigit()
    }
}
