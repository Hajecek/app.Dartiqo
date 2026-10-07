import SwiftUI

/// Přehled zavírání: úspěšnost na double, rozpis po jednotlivých doublech a pásma checkoutů.
/// Bez vlastního pozadí, aby seděl v tmavém detailu zápasu i v systémových Statistikách.
struct CheckoutStatsView: View {
    let stats: CheckoutStats
    var tint: Color = Theme.positive

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let best = stats.bestDouble {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        extreme(best, title: "Nejlepší double", symbol: "arrow.up.circle.fill", color: Theme.positive)
                        if let worst = stats.worstDouble {
                            extreme(worst, title: "Nejslabší double", symbol: "arrow.down.circle.fill", color: .red)
                        }
                    }
                    Text(stats.isComparisonReliable
                         ? "Porovnávají se doubly s aspoň \(CheckoutStats.comparableAttempts) pokusy."
                         : "Zatím málo pokusů, srovnání se zpřesní s dalšími hrami.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                cell("\(stats.checkouts.count)", "Zavření")
                cell(stats.highest == 0 ? "—" : "\(stats.highest)", "Nejvyšší")
                cell(stats.checkouts.isEmpty ? "—" : String(format: "%.0f", stats.average), "Průměrný")
            }
            if !stats.sortedDoubles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Podle doublu")
                        .font(.subheadline.weight(.semibold))
                    ForEach(stats.sortedDoubles) { row($0) }
                }
            }
            if !stats.checkouts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Výše zavření")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        ForEach(stats.ranges, id: \.title) { cell("\($0.count)", $0.title) }
                    }
                }
            }
            if stats.unknownAttempts {
                Text("Část návštěv byla zapsaná součtem. U nich nejsou známé jednotlivé šipky, takže se nepočítají do pokusů na double.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(stats.percentage.map { String(format: "%.1f %%", $0) } ?? "—")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text("úspěšnost na double")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(stats.hits) / \(stats.attempts)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("zavření / šipky na double")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func extreme(_ stat: DoubleStat, title: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stat.label)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                Spacer(minLength: 4)
                Text("\(Int(stat.percentage.rounded())) %")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            Text("\(stat.hits) z \(stat.attempts) pokusů")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(color.opacity(0.35), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func rowColor(_ stat: DoubleStat) -> Color {
        if stat.segment == stats.bestDouble?.segment { return Theme.positive }
        if stat.segment == stats.worstDouble?.segment { return .red }
        return tint
    }

    private func row(_ stat: DoubleStat) -> some View {
        let color = rowColor(stat)
        return HStack(spacing: 10) {
            Text(stat.label)
                .font(.headline)
                .foregroundStyle(color == tint ? Color.primary : color)
                .frame(width: 48, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.1))
                    Capsule()
                        .fill(color)
                        .frame(width: stat.hits == 0 ? 0 : max(6, geo.size.width * stat.percentage / 100))
                }
            }
            .frame(height: 8)
            Text("\(stat.hits)/\(stat.attempts)")
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
            Text("\(Int(stat.percentage.rounded())) %")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stat.label): \(stat.hits) z \(stat.attempts), \(Int(stat.percentage.rounded())) procent")
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
