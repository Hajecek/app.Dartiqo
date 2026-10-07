import SwiftUI
import Charts

struct StatsView: View {
    @EnvironmentObject var store: AppStore
    private var bestCheckout: Int { store.ownVisits.filter(\.checkout).map(\.credited).max() ?? 0 }
    private var darts: Int { store.ownVisits.reduce(0) { $0 + $1.darts.count } }
    private var checkout: CheckoutStats {
        var total = CheckoutStats()
        for match in store.x01Matches {
            guard let player = match.players.firstIndex(where: { $0.id == store.profile?.id }) else { continue }
            total.merge(.make(from: match, player: player))
        }
        return total
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) { Eyebrow(text: "Každá šipka je pokrok"); Text("Tvoje čísla.\nTvůj příběh.").font(.system(size: 34, weight: .bold, design: .rounded)) }
                if store.matches.isEmpty { EmptyCard(title: "Statistiky začínají hrou", subtitle: "Dokonči zápas a ulož výsledek. Ukážeme ti skutečná data, žádné ukázkové hodnoty.", symbol: "chart.xyaxis.line") }
                else {
                    HStack(spacing: 12) { StatTile(value: "\(store.matches.count)", label: "Dokončené hry", icon: "flag.checkered"); StatTile(value: "\(Int(Double(store.wins) / Double(max(1,store.matches.count)) * 100)) %", label: "Úspěšnost výher", icon: "trophy") }
                    HStack(spacing: 12) { StatTile(value: String(format: "%.1f", store.average), label: "X01 průměr / 3 šipky", icon: "chart.xyaxis.line"); StatTile(value: "\(bestCheckout)", label: "Nejvyšší checkout", icon: "checkmark.seal") }
                    HStack(spacing: 12) { StatTile(value: "\(store.n180)", label: "Hozené 180", icon: "flame"); StatTile(value: "\(darts)", label: "Zapsané šipky v X01", icon: "scope") }
                    trend
                    let finish = checkout
                    if finish.hasData {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Zavírání").font(.title2.bold())
                            Text("Všechny tvoje zápasy X01 s double nebo master out").font(.subheadline).foregroundStyle(.secondary)
                        }
                        CheckoutStatsView(stats: finish).surface()
                    }
                }
                Text("Tvoje milníky").font(.title2.bold())
                achievement("První krok", subtitle: "Dokonči první zápas", symbol: "shoeprints.fill", unlocked: !store.matches.isEmpty)
                achievement("Vítězný pocit", subtitle: "Vyhraj svůj první zápas", symbol: "trophy.fill", unlocked: store.wins > 0)
                achievement("Maximum!", subtitle: "Zapiš 180 v jedné návštěvě X01", symbol: "flame.fill", unlocked: store.n180 > 0)
                achievement("Velké zavření", subtitle: "Zavři X01 na 100 a více bodů", symbol: "sparkles", unlocked: bestCheckout >= 100)
                achievement("Pravidelný hráč", subtitle: "Dokonči 20 zápasů", symbol: "medal.fill", unlocked: store.matches.count >= 20)
                NavigationLink { HistoryView() } label: { Label("Kompletní historie", systemImage: "clock.arrow.circlepath").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton())
                Text("Průměr X01 = započítané body / skutečně zapsané šipky × 3. Přehoz má 0 bodů; šipky před double-in se počítají. Ostatní režimy průměr X01 neovlivňují. Výhry a XP zahrnují i sólo trénink.").font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: 700)
        }.screen().navigationTitle("Statistiky").navigationBarTitleDisplayMode(.inline)
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Forma v čase").font(.headline)
            Text("Posledních 12 zápasů X01").font(.caption).foregroundStyle(.secondary)
            if store.x01Matches.isEmpty { Text("Zatím nemáš dokončenou hru X01.").foregroundStyle(.secondary) }
            else {
                Chart(Array(store.x01Matches.prefix(12).reversed().enumerated()), id: \.element.id) { index, match in
                    let player = match.players.firstIndex { $0.id == store.profile?.id } ?? 0
                    LineMark(x: .value("Zápas", index + 1), y: .value("Průměr", match.average(for: player))).foregroundStyle(Theme.mint).interpolationMethod(.monotone)
                    PointMark(x: .value("Zápas", index + 1), y: .value("Průměr", match.average(for: player))).foregroundStyle(Theme.mint)
                }.chartYScale(domain: 0...max(100,store.x01Matches.map { $0.average(for: $0.players.firstIndex { $0.id == store.profile?.id } ?? 0) }.max() ?? 100)).frame(height: 180)
            }
        }.surface()
    }
    private func achievement(_ title: String, subtitle: String, symbol: String, unlocked: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: unlocked ? symbol : "lock").font(.title2).foregroundStyle(unlocked ? Theme.mint : .secondary).frame(width: 32)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer(); if unlocked { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint) }
        }.surface().opacity(unlocked ? 1 : 0.65)
    }
}
struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    @State private var filter: GameMode?
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("Režim", selection: $filter) { Text("Vše").tag(nil as GameMode?); ForEach(GameMode.allCases) { Text($0.shortTitle).tag(Optional($0)) } }.pickerStyle(.menu)
                let matches = store.matches.filter { filter == nil || $0.config.mode == filter }
                if matches.isEmpty { EmptyCard(title: "Zatím žádné zápasy", subtitle: "Dokončené hry v tomto režimu se objeví tady.") }
                ForEach(matches) { game in NavigationLink { MatchDetailView(match: game) } label: { MatchRow(match: game, profileID: store.profile?.id) }.buttonStyle(.plain) }
            }.padding(22).frame(maxWidth: 700)
        }.screen().navigationTitle("Historie").toolbar(.visible, for: .navigationBar)
    }
}
struct MatchDetailView: View {
    var match: Match
    var body: some View {
        List {
            Section {
                Text(match.config.summary)
                Text(match.createdAt.formatted(date: .long, time: .shortened)).foregroundStyle(.secondary)
                Text(match.winner.map { "Vítěz: \(match.players[$0].name)" } ?? "Remíza").font(.headline)
            }
            Section("Hráči") {
                ForEach(match.players.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(match.players[i].name).font(.headline)
                        Text("Legy: \(match.states[i].legs) · návštěvy: \(match.visits.filter { $0.player == i }.count)").font(.subheadline)
                        if match.config.mode == .x01 { Text(String(format: "Průměr %.2f · nejlepší návštěva %d", match.average(for: i), match.best(for: i))).font(.caption).foregroundStyle(.secondary) }
                        else { Text("Body: \(match.states[i].points)").font(.caption).foregroundStyle(.secondary) }
                    }.padding(.vertical, 6)
                }
            }
            NavigationLink("Všechny hody") { VisitLog(game: match) }
        }.navigationTitle("Detail zápasu").navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}
