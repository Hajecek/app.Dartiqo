import SwiftUI

/// Historie hodů po legech. Každý hod je řádek přes celou šířku: šipky v polích, skóre vpravo.
struct VisitLog: View {
    var game: Match
    var onRewind: ((Visit) -> Void)? = nil

    @State private var player: Int?
    @State private var pendingRewind: Visit?

    private var shownPlayers: [Int] {
        if let player { return [player] }
        return Array(game.players.indices)
    }

    private var sheets: [LegSheet] {
        makeSheets().filter { sheet in
            if !sheet.lines.isEmpty { return true }
            return player == nil && sheet.winner != nil
        }
    }

    var body: some View {
        Group {
            if game.visits.isEmpty && game.currentDarts.isEmpty {
                ContentUnavailableView("Zatím žádné hody", systemImage: "list.bullet", description: Text("Každé dohrané kolo se objeví tady."))
            } else {
                List {
                    if game.players.count > 1 {
                        Section {
                            filterBar
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    }
                    if sheets.isEmpty {
                        Section {
                            Text("\(filteredName) tu ještě nemá zapsané kolo.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(sheets) { sheet in
                        Section {
                            ForEach(sheet.lines) { line in
                                lineRow(line)
                            }
                        } header: {
                            legHeader(sheet)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .screen()
        .navigationTitle("Historie hodů")
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: player)
        .confirmationDialog("Vrátit hru na toto kolo?", isPresented: Binding(get: { pendingRewind != nil }, set: { if !$0 { pendingRewind = nil } }), titleVisibility: .visible, presenting: pendingRewind) { visit in
            Button("Vrátit hru sem", role: .destructive) { onRewind?(visit) }
            Button("Zrušit", role: .cancel) {}
        } message: { visit in
            Text(VisitDetailView.rewindMessage(game: game, visit: visit))
        }
    }

    private var filteredName: String {
        guard let player, game.players.indices.contains(player) else { return "Hráč" }
        return game.players[player].name
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("Všichni", selected: player == nil) { player = nil }
                ForEach(game.players.indices, id: \.self) { index in
                    filterChip(game.players[index].name, color: Theme.playerColor(index), selected: player == index) {
                        player = index
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, color: Color? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color {
                    Circle().fill(selected ? Theme.onAccent : color).frame(width: 8, height: 8)
                }
                Text(title).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(selected ? Theme.onAccent : .primary)
            .background(selected ? Theme.accentFill : Theme.card, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.clear : Theme.stroke, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func legHeader(_ sheet: LegSheet) -> some View {
        let live = sheet.leg == game.leg && !game.finished && game.legWinner == nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(game.config.playsSets ? "Set \(sheet.set) · Leg \(sheet.leg)" : "Leg \(sheet.leg)")
                    .font(.subheadline.weight(.bold))
                if live {
                    Text("TEĎ")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accentFill, in: Capsule())
                }
                Spacer(minLength: 8)
                scoreline(sheet.score)
            }
            if let winner = sheet.winner {
                Text(winnerLine(winner, sheet: sheet))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if game.needsBullOff, sheet.leg == game.leg {
                Text("Čeká na rozhoz na střed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .textCase(nil)
        .foregroundStyle(.primary)
        .padding(.bottom, 2)
    }

    private func winnerLine(_ winner: Int, sheet: LegSheet) -> String {
        let name = game.players[winner].name
        if sheet.bullOff { return "\(name) · rozhoz" }
        if let checkout = sheet.checkout { return "\(name) · zavřeno \(checkout)" }
        return "\(name) bere leg"
    }

    private func scoreline(_ score: [Int]) -> some View {
        HStack(spacing: 0) {
            ForEach(game.players.indices, id: \.self) { index in
                if index > 0 {
                    Text(":")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 3)
                }
                HStack(spacing: 3) {
                    Circle()
                        .fill(Theme.playerColor(index))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text("\(score[index])")
                        .monospacedDigit()
                }
            }
        }
        .font(.subheadline.weight(.bold))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skóre " + game.players.indices.map { "\(game.players[$0].name) \(score[$0])" }.joined(separator: ", "))
    }

    @ViewBuilder
    private func lineRow(_ line: ThrowLine) -> some View {
        switch line.kind {
        case .visit(let visit):
            NavigationLink {
                VisitDetailView(game: game, visit: visit, onRewind: onRewind)
            } label: {
                ThrowRow(game: game, player: line.player, round: line.round, visit: visit, openDarts: nil)
            }
            .buttonStyle(.plain)
            .navigationLinkIndicatorVisibility(.hidden)
            .listRowBackground(rowFill(visit))
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if onRewind != nil {
                    Button { pendingRewind = visit } label: {
                        Label("Vrátit sem", systemImage: "arrow.uturn.backward")
                    }
                    .tint(.orange)
                }
            }
        case .open(let darts):
            ThrowRow(game: game, player: line.player, round: line.round, visit: nil, openDarts: darts)
                .listRowBackground(rowWash(Theme.accentFill.opacity(0.34)))
        }
    }

    private func rowFill(_ visit: Visit) -> some View {
        rowWash(visit.bust ? Color.red.opacity(0.14) : visit.checkout ? Theme.positive.opacity(0.18) : .clear)
    }

    private func rowWash(_ tint: Color) -> some View {
        ZStack {
            Theme.card
            tint
        }
    }

    private func makeSheets() -> [LegSheet] {
        let count = game.players.count
        let playsSets = game.config.playsSets
        let target = game.config.legsToWin
        var set = 1
        var setLegs = Array(repeating: 0, count: count)
        var matchLegs = Array(repeating: 0, count: count)
        var built: [LegSheet] = []

        var numbers = Set(game.visits.map(\.leg))
        if !game.currentDarts.isEmpty { numbers.insert(game.leg) }
        numbers.formUnion(game.bullOffLegs?.keys.map { $0 } ?? [])

        for leg in numbers.sorted() {
            let winner = winner(of: leg)
            var shown = playsSets ? setLegs : matchLegs
            if let winner { shown[winner] += 1 }
            let bullOff = game.bullOffLegs?[leg] != nil
            let checkout = bullOff ? nil : game.visits.last { $0.leg == leg && $0.checkout }?.credited
            built.append(LegSheet(leg: leg, set: set, winner: winner, bullOff: bullOff, checkout: checkout, score: shown, lines: lines(for: leg)))
            guard let winner else { continue }
            setLegs[winner] += 1
            matchLegs[winner] += 1
            if playsSets, setLegs[winner] >= target {
                set += 1
                setLegs = Array(repeating: 0, count: count)
            }
        }
        return Array(built.reversed())
    }

    private func winner(of leg: Int) -> Int? {
        if let winner = game.bullOffLegs?[leg] { return winner }
        if let winner = game.visits.last(where: { $0.leg == leg && $0.checkout })?.player { return winner }
        if leg == game.leg, game.finished { return game.winner }
        return nil
    }

    private func lines(for leg: Int) -> [ThrowLine] {
        var counts = Array(repeating: 0, count: game.players.count)
        var rows: [ThrowLine] = []
        for visit in game.visits where visit.leg == leg && shownPlayers.contains(visit.player) {
            counts[visit.player] += 1
            rows.append(ThrowLine(id: visit.id.uuidString, player: visit.player, round: counts[visit.player], kind: .visit(visit)))
        }
        let open = leg == game.leg && !game.currentDarts.isEmpty && shownPlayers.contains(game.active) && game.legWinner == nil && !game.finished
        if open {
            rows.append(ThrowLine(id: "open-\(leg)", player: game.active, round: counts[game.active] + 1, kind: .open(game.currentDarts)))
        }
        return rows
    }
}

private struct LegSheet: Identifiable {
    var leg: Int
    var set: Int
    var winner: Int?
    var bullOff: Bool
    var checkout: Int?
    var score: [Int]
    var lines: [ThrowLine]
    var id: Int { leg }
}

private struct ThrowLine: Identifiable {
    var id: String
    var player: Int
    var round: Int
    var kind: Kind

    enum Kind {
        case visit(Visit)
        case open([Dart])
    }
}

private struct ThrowRow: View {
    let game: Match
    let player: Int
    let round: Int
    var visit: Visit?
    var openDarts: [Dart]?

    private var darts: [Dart] { visit?.darts ?? openDarts ?? [] }
    private var isOpen: Bool { visit == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.playerColor(player))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(game.players[player].name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("kolo \(round)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isOpen {
                    Text("teď")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(Theme.onAccent)
                        .background(Theme.accentFill, in: Capsule())
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .center, spacing: 10) {
                marks
                score
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var marks: some View {
        if visit?.enteredAsTotal == true {
            Text("Součet · \(darts.count) \(czechWord(darts.count, "šipka", "šipky", "šipek"))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    if index < darts.count {
                        DartTile(dart: darts[index])
                    } else if isOpen {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                    } else {
                        Color.clear.frame(maxWidth: .infinity).frame(height: 34)
                    }
                }
            }
        }
    }

    private var score: some View {
        VStack(alignment: .trailing, spacing: 1) {
            if let visit {
                Text(visit.bust ? "BUST" : "\(visit.credited)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(throwScoreColor(visit))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if game.config.mode == .x01 {
                    Text("zbývá \(visit.remaining)")
                        .font(.caption2.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(width: visit == nil ? 0 : 78, alignment: .trailing)
    }
}

private struct DartTile: View {
    let dart: Dart

    var body: some View {
        Text(dart.segment == 0 ? "Mimo" : dart.label)
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .foregroundStyle(visitDartColor(dart))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(tileFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var tileFill: Color {
        let color = visitDartColor(dart)
        return dart.segment == 0 ? Color.primary.opacity(0.06) : color.opacity(0.16)
    }
}

private func throwScoreColor(_ visit: Visit) -> Color {
    if visit.bust || visit.credited == 180 { return .red }
    if visit.checkout { return Theme.positive }
    return .primary
}

private func visitDartColor(_ dart: Dart) -> Color {
    if dart.segment == 0 { return .secondary }
    if dart.segment == 25 { return .orange }
    if dart.multiplier == 3 { return .red }
    if dart.multiplier == 2 { return Theme.positive }
    return .primary
}

private func czechWord(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
    let tail = count % 100
    let digit = count % 10
    if tail < 10 || tail >= 20 {
        if digit == 1 { return one }
        if (2...4).contains(digit) { return few }
    }
    return many
}

struct VisitDetailView: View {
    @EnvironmentObject private var store: AppStore
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
                } else if visit.darts.contains(where: { $0.x != nil && $0.y != nil }) {
                    TouchDartboard(marks: visit.darts.filter { $0.x != nil && $0.y != nil }, interactive: false) { _ in }
                        .allowsHitTesting(false)
                        .frame(maxWidth: 340)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(BoardFace.plate, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .environment(\.colorScheme, .dark)
                        .accessibilityLabel("Terč s šipkami \(visit.darts.map(\.label).joined(separator: ", "))")
                } else {
                    SegmentRoseChart(darts: visit.darts, title: "Kam šipky padaly")
                }
                if visit.enteredAsTotal != true {
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
            Avatar(name: player.name, bot: player.botLevel != nil, size: 56, photo: store.photo(for: player.id), asset: player.botLevel.map { BotLevel.get($0).photo })
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
                Text("\(visit.credited)").foregroundStyle(visit.credited == 180 ? .red : .primary)
            }
        }
        .font(.system(size: size, weight: .bold, design: .rounded))
        .monospacedDigit()
    }
}

#if DEBUG
#Preview("Dva hráči") {
    NavigationStack {
        VisitLog(game: VisitLogPreview.match(players: 2), onRewind: { _ in })
    }
    .dartiqoPreview()
}

#Preview("Tři hráči") {
    NavigationStack {
        VisitLog(game: VisitLogPreview.match(players: 3))
    }
    .dartiqoPreview()
}

private enum VisitLogPreview {
    static func match(players: Int) -> Match {
        if players >= 3 {
            var match = Match(
                config: GameConfig(startingScore: 301),
                players: [Player(name: "Jan"), Player(name: "Pavel"), Player(name: "Bot", botLevel: 5)]
            )
            play(&match, [Dart(20, 3), Dart(20, 3), Dart(20, 3)])
            play(&match, [Dart(20, 3), Dart(20, 3), Dart(19)])
            play(&match, [Dart(19, 3), Dart(19, 3), Dart(20)])
            play(&match, [Dart(20, 3), Dart(20, 3), Dart(20, 3)])
            play(&match, [Dart(20), Dart(20), Dart(5)])
            play(&match, [Dart(20), Dart(1), Dart(1)])
            match.pendingDarts = [Dart(20, 3)]
            return match
        }

        var match = Match(
            config: GameConfig(startingScore: 301, legsToWin: 2),
            players: [Player(name: "Jan"), Player(name: "Bot", botLevel: 5)]
        )
        play(&match, [Dart(20, 3), Dart(20, 3), Dart(20, 3)])
        play(&match, [Dart(20, 3), Dart(20, 3), Dart(20, 3)])
        play(&match, [Dart(19, 3), Dart(20, 3), Dart(12, 2)])
        play(&match, [Dart(20, 3), Dart(20), Dart(1)])
        play(&match, [Dart(20, 3), Dart(11), Dart(20, 2)])
        play(&match, [Dart(20, 2)])
        match.nextLeg()
        play(&match, [Dart(20), Dart(20), Dart(20)])
        play(&match, [Dart(20, 3), Dart(19, 3), Dart(18)])
        match.pendingDarts = [Dart(20, 3), Dart(5)]
        return match
    }

    private static func play(_ match: inout Match, _ darts: [Dart]) {
        do { try match.submit(darts) }
        catch { assertionFailure("Náhled historie selhal: \(error)") }
    }
}
#endif
