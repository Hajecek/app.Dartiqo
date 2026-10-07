import SwiftUI

/// Historie hodů po legech. S `onRewind` jde hru vrátit na zvolené kolo.
struct VisitLog: View {
    var game: Match
    var onRewind: ((Visit) -> Void)? = nil

    @State private var player: Int?
    @State private var pendingRewind: Visit?

    private var legs: [Int] {
        Array(Set(game.visits.map(\.leg) + (game.currentDarts.isEmpty ? [] : [game.leg]))).sorted(by: >)
    }

    var body: some View {
        List {
            if game.players.count > 1 {
                Section {
                    Picker("Hráč", selection: $player) {
                        Text("Všichni").tag(nil as Int?)
                        ForEach(game.players.indices, id: \.self) { Text(game.players[$0].name).tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            ForEach(legs, id: \.self) { leg in
                let visits = game.visits.enumerated().filter { $0.element.leg == leg && (player == nil || $0.element.player == player) }
                Section {
                    if leg == game.leg && !game.currentDarts.isEmpty && (player == nil || player == game.active) {
                        openVisitRow
                    }
                    ForEach(visits.reversed(), id: \.element.id) { index, visit in
                        NavigationLink {
                            VisitDetailView(game: game, visit: visit, onRewind: onRewind)
                        } label: {
                            VisitRow(game: game, visit: visit, round: round(of: index))
                        }
                        .swipeActions(edge: .leading) {
                            if onRewind != nil {
                                Button { pendingRewind = visit } label: {
                                    Label("Vrátit sem", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Leg \(leg)")
                        Spacer()
                        if let winner = game.visits.last(where: { $0.leg == leg && $0.checkout })?.player {
                            Label(game.players[winner].name, systemImage: "trophy.fill")
                                .foregroundStyle(Theme.positive)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if game.visits.isEmpty && game.currentDarts.isEmpty {
                ContentUnavailableView("Zatím žádné hody", systemImage: "list.bullet", description: Text("Každé dohrané kolo se objeví tady."))
            }
        }
        .navigationTitle("Historie hodů")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Vrátit hru na toto kolo?", isPresented: Binding(get: { pendingRewind != nil }, set: { if !$0 { pendingRewind = nil } }), titleVisibility: .visible, presenting: pendingRewind) { visit in
            Button("Vrátit hru sem", role: .destructive) { onRewind?(visit) }
            Button("Zrušit", role: .cancel) {}
        } message: { visit in
            Text(VisitDetailView.rewindMessage(game: game, visit: visit))
        }
    }

    private var openVisitRow: some View {
        HStack(spacing: 12) {
            Avatar(name: game.currentPlayer.name, bot: game.currentPlayer.botLevel != nil, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(game.currentPlayer.name) · rozehrané").font(.subheadline.weight(.semibold))
                DartChips(darts: game.currentDarts)
            }
            Spacer()
            Image(systemName: "ellipsis").foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private func round(of index: Int) -> Int {
        let visit = game.visits[index]
        return game.visits[...index].filter { $0.leg == visit.leg && $0.player == visit.player }.count
    }
}

private struct VisitRow: View {
    let game: Match
    let visit: Visit
    let round: Int

    var body: some View {
        let player = game.players[visit.player]
        HStack(spacing: 12) {
            Avatar(name: player.name, bot: player.botLevel != nil, size: 36)
            VStack(alignment: .leading, spacing: 6) {
                Text("\(player.name) · kolo \(round)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if visit.enteredAsTotal == true {
                    Text("Zadáno součtem · \(visit.darts.count) šipky")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DartChips(darts: visit.darts)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                VisitScore(visit: visit, size: 22)
                if game.config.mode == .x01 {
                    Text("zbývá \(visit.remaining)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct VisitScore: View {
    let visit: Visit
    let size: CGFloat

    var body: some View {
        Group {
            if visit.bust {
                Text("BUST").foregroundStyle(.red)
            } else if visit.checkout {
                Label("\(visit.credited)", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.positive)
            } else {
                Text("\(visit.credited)")
            }
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .monospacedDigit()
    }
}

private struct DartChips: View {
    let darts: [Dart]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(darts.enumerated()), id: \.offset) { _, dart in
                Text(dart.segment == 0 ? "Mimo" : dart.label)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(chipColor(dart).opacity(0.16), in: Capsule())
                    .foregroundStyle(chipColor(dart))
            }
        }
    }

    private func chipColor(_ dart: Dart) -> Color {
        if dart.segment == 0 { return .secondary }
        if dart.segment == 25 { return .orange }
        return dart.multiplier == 3 ? .red : dart.multiplier == 2 ? Theme.positive : .primary
    }
}

struct VisitDetailView: View {
    let game: Match
    let visit: Visit
    var onRewind: ((Visit) -> Void)?

    @State private var confirmRewind = false

    private var index: Int { game.visits.firstIndex { $0.id == visit.id } ?? 0 }
    private var round: Int {
        game.visits[...index].filter { $0.leg == visit.leg && $0.player == visit.player }.count
    }
    private var player: Player { game.players[visit.player] }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if game.config.mode == .x01 {
                    HStack(spacing: 10) {
                        metric(visit.bust ? "\(visit.remaining)" : "\(visit.remaining + visit.credited)", "Před kolem")
                        metric("\(visit.remaining)", "Po kole")
                        metric("\(visit.darts.count)", "Šipky")
                    }
                }
                if visit.enteredAsTotal == true {
                    Label("Kolo bylo zadané součtem, přesné šipky nejsou známé.", systemImage: "number")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .surface()
                } else {
                    TouchDartboard(marks: visit.darts, interactive: false) { _ in }
                        .allowsHitTesting(false)
                        .frame(maxWidth: 340)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .environment(\.colorScheme, .dark)
                        .accessibilityLabel("Terč s šipkami \(visit.darts.map(\.label).joined(separator: ", "))")
                    VStack(spacing: 0) {
                        ForEach(Array(visit.darts.enumerated()), id: \.offset) { offset, dart in
                            HStack {
                                Text("\(offset + 1). šipka").foregroundStyle(.secondary)
                                Spacer()
                                Text(dart.segment == 0 ? "Mimo" : dart.label).font(.body.weight(.semibold))
                                Text("\(dart.score)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .trailing)
                            }
                            .padding(.vertical, 8)
                            if offset < visit.darts.count - 1 { Divider() }
                        }
                    }
                    .surface()
                }
                if onRewind != nil {
                    VStack(spacing: 8) {
                        Button { confirmRewind = true } label: {
                            Label("Vrátit hru na toto kolo", systemImage: "arrow.uturn.backward.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                        .controlSize(.large)
                        Text(Self.rewindMessage(game: game, visit: visit))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("Leg \(visit.leg) · kolo \(round)")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Vrátit hru na toto kolo?", isPresented: $confirmRewind, titleVisibility: .visible) {
            Button("Vrátit hru sem", role: .destructive) { onRewind?(visit) }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text(Self.rewindMessage(game: game, visit: visit))
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Avatar(name: player.name, bot: player.botLevel != nil, size: 56)
            Text(player.name).font(.headline)
            VisitScore(visit: visit, size: 56)
            if visit.checkout {
                Text(game.config.mode == .x01 ? "Zavřený leg" : "Vyhraný leg")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.positive)
            } else if visit.bust {
                Text("Přehoz, kolo se nezapočítalo").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .surface()
        .accessibilityElement(children: .combine)
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .surface()
        .accessibilityElement(children: .combine)
    }

    static func rewindMessage(game: Match, visit: Visit) -> String {
        let index = game.visits.firstIndex { $0.id == visit.id } ?? game.visits.count
        let later = game.visits.count - index - 1
        let name = game.players[visit.player].name
        let removed = later > 0 ? "Smaže se toto kolo a \(later) dalších." : "Smaže se toto kolo."
        let again = game.players[visit.player].botLevel != nil ? "\(name) hodí kolo znovu." : "\(name) hází toto kolo znovu."
        return "\(removed) \(again)"
    }
}
