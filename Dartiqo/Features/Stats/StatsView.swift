import SwiftUI

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
        }.screen().navigationTitle("Moje hry").toolbar(.visible, for: .navigationBar)
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
