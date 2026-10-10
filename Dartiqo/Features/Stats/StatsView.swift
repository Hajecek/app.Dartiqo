import SwiftUI

private enum HistoryResultFilter: String, CaseIterable, Identifiable {
    case all, wins, losses
    var id: String { rawValue }
    var title: String {
        switch self { case .all: return "Všechny"; case .wins: return "Výhry"; case .losses: return "Prohry" }
    }
    var symbol: String {
        switch self { case .all: return "clock.arrow.circlepath"; case .wins: return "checkmark.seal"; case .losses: return "xmark.seal" }
    }
}

private enum HistoryOrder: String, CaseIterable, Identifiable {
    case newest, oldest
    var id: String { rawValue }
    var title: String { self == .newest ? "Nejnovější první" : "Nejstarší první" }
}

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode: GameMode?
    @State private var result: HistoryResultFilter = .all
    @State private var order: HistoryOrder = .newest
    @State private var pendingDelete: UUID?
    @State private var selectedMatch: UUID?

    private var matches: [Match] {
        let filtered = store.matches.filter { match in
            let modeFits = mode == nil || match.config.mode == mode
            let outcomeFits: Bool = {
                switch result {
                case .all: return true
                case .wins: return outcome(match) == .win
                case .losses: return outcome(match) == .loss
                }
            }()
            return modeFits && outcomeFits
        }
        return order == .newest ? filtered : filtered.reversed()
    }

    var body: some View {
        List {
            if store.matches.isEmpty {
                Section {
                    ContentUnavailableView(
                        "Zatím žádné zápasy",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Dokončené hry se uloží sem včetně výsledku, statistik a hodů.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    record
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if let latest = matches.first {
                    Section(order == .newest ? "Poslední zápas" : "První zápas") {
                        matchLink(latest, featured: true)
                    }

                    ForEach(historyGroups(Array(matches.dropFirst()))) { group in
                        Section(group.title) {
                            ForEach(group.matches) { match in
                                matchLink(match)
                            }
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            "Žádný zápas neodpovídá",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Změň filtry v horní liště.")
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Moje hry")
        .navigationSubtitle(filterCaption)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { historyToolbar }
        .navigationDestination(item: $selectedMatch) { id in
            if let match = store.matches.first(where: { $0.id == id }) {
                MatchDetailView(match: match, profileID: store.profile?.id)
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.selection, trigger: result)
        .alert("Opravdu smazat zápas?", isPresented: deleteDialog) {
            Button("Smazat zápas", role: .destructive) {
                if let pendingDelete { store.deleteMatch(pendingDelete) }
                pendingDelete = nil
            }
            Button("Zrušit", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Zápas, jeho statistiky i všechny hody budou trvale odstraněny.")
        }
    }

    private var deleteDialog: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    @ViewBuilder
    private func matchLink(_ match: Match, featured: Bool = false) -> some View {
        Button {
            selectedMatch = match.id
        } label: {
            if featured {
                FeaturedMatchCard(match: match, outcome: outcome(match))
                    .padding(.vertical, 4)
            } else {
                MatchHistoryRow(match: match, outcome: outcome(match))
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(featured ? EdgeInsets() : EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = match.id
            } label: {
                Label("Smazat", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private var filterCaption: String {
        let title = mode?.shortTitle ?? "Všechny režimy"
        return "\(title) · \(czechCount(matches.count, "hra", "hry", "her"))"
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Výsledek", selection: $result) {
                    ForEach(HistoryResultFilter.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.inline)
                Section {
                    Picker("Řazení", selection: $order) {
                        ForEach(HistoryOrder.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }
            } label: {
                Label(result.title, systemImage: result.symbol)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Hra", selection: $mode) {
                    Label("Všechny režimy", systemImage: "square.grid.2x2").tag(nil as GameMode?)
                    ForEach(GameMode.allCases) { item in
                        Label(item.shortTitle, systemImage: item.symbol).tag(Optional(item))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(mode?.shortTitle ?? "Hra", systemImage: mode?.symbol ?? "slider.horizontal.3")
            }
        }
    }

    private var record: some View {
        let wins = matches.filter { outcome($0) == .win }.count
        let losses = matches.filter { outcome($0) == .loss }.count
        let draws = matches.filter { outcome($0) == .draw }.count
        let recent = Array(matches.prefix(8))
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Bilance")
                    Text(recordHeadline(wins: wins))
                        .font(.title2.bold())
                    Text(recordDetail(wins: wins, losses: losses))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                winRateGauge(wins: wins)
            }

            HStack(spacing: 0) {
                recordFact("\(wins)", "výhry", Theme.positive)
                Divider().frame(height: 38)
                recordFact("\(losses)", "prohry", .secondary)
                Divider().frame(height: 38)
                recordFact("\(draws)", "remízy", .orange)
            }
            .padding(.vertical, 10)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("POSLEDNÍ FORMA")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(recent) { game in
                            let item = outcome(game)
                            Text(item.shortTitle)
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(item == .loss ? Color.primary : Color.white)
                                .frame(width: 24, height: 24)
                                .background(item.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PlayTime.format(matches.reduce(0) { $0 + $1.playedDuration }))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text("celkem u terče")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .surface()
    }

    private func recordFact(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(tint)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func winRateGauge(wins: Int) -> some View {
        let rate = matches.isEmpty ? 0 : Double(wins) / Double(matches.count)
        return ZStack {
            Circle()
                .stroke(Theme.stroke, lineWidth: 7)
            Circle()
                .trim(from: 0, to: rate)
                .stroke(Theme.positive, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(winRate(wins: wins))
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("výher")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 74, height: 74)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Úspěšnost \(winRate(wins: wins))")
    }

    private func recordHeadline(wins: Int) -> String {
        guard !matches.isEmpty else { return "Bez odehraných her" }
        if wins == matches.count { return "Bez porážky" }
        if wins > matches.count / 2 { return "Kladná bilance" }
        if wins * 2 == matches.count { return "Vyrovnaná bilance" }
        return "Je na čem pracovat"
    }

    private func recordDetail(wins: Int, losses: Int) -> String {
        if let streak = currentStreak {
            return streak.count == 1
                ? "Poslední zápas: \(streak.outcome.title.lowercased())"
                : "\(streak.count)× \(streak.outcome == .win ? "výhra" : streak.outcome == .loss ? "prohra" : "remíza") v řadě"
        }
        return "\(wins) výher · \(losses) proher"
    }

    private var currentStreak: (outcome: GameOutcome, count: Int)? {
        guard let first = matches.first.map(outcome) else { return nil }
        let count = matches.prefix { outcome($0) == first }.count
        return (first, count)
    }

    private func outcome(_ match: Match) -> GameOutcome {
        guard let winner = match.winner else { return .draw }
        return match.players[winner].id == store.profile?.id ? .win : .loss
    }

    private func winRate(wins: Int) -> String {
        guard !matches.isEmpty else { return "—" }
        return "\(Int((Double(wins) / Double(matches.count) * 100).rounded())) %"
    }

    private func historyGroups(_ games: [Match]) -> [HistoryMonth] {
        let calendar = Calendar.current
        var keys: [Date] = []
        var grouped: [Date: [Match]] = [:]
        for game in games {
            let date = game.completedAt ?? game.createdAt
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let month = calendar.date(from: components) else { continue }
            if grouped[month] == nil { keys.append(month) }
            grouped[month, default: []].append(game)
        }
        return keys.map {
            HistoryMonth(id: $0, title: $0.formatted(.dateTime.month(.wide).year()), matches: grouped[$0] ?? [])
        }
    }
}

private enum GameOutcome {
    case win, loss, draw
    var title: String {
        switch self { case .win: return "Vítězství"; case .loss: return "Prohra"; case .draw: return "Remíza" }
    }
    var symbol: String {
        switch self { case .win: return "trophy.fill"; case .loss: return "xmark"; case .draw: return "equal" }
    }
    var color: Color {
        switch self { case .win: return Theme.positive; case .loss: return .red; case .draw: return .orange }
    }
    var shortTitle: String {
        switch self { case .win: return "V"; case .loss: return "P"; case .draw: return "R" }
    }
}

private struct FeaturedMatchCard: View {
    let match: Match
    let outcome: GameOutcome

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Label(match.config.mode.shortTitle, systemImage: match.config.mode.symbol)
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            MatchScoreline(match: match, dark: true)
            HStack {
                Text(match.config.lengthLine)
                    .lineLimit(1)
                Spacer()
                if match.playedDuration > 0 {
                    Label(PlayTime.format(match.playedDuration), systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background {
            ZStack {
                Theme.heroWash
                LinearGradient(
                    colors: [outcome.color.opacity(0.42), outcome.color.opacity(0.10), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                Image(systemName: match.config.mode.symbol)
                    .font(.system(size: 150, weight: .bold))
                    .foregroundStyle(.white.opacity(0.05))
                    .offset(x: 100, y: 45)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(outcome.color.opacity(0.65), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: outcome.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(outcome.color)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.35), in: Circle())
                .padding(14)
                .accessibilityLabel(outcome.title)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otevře detail zápasu")
    }
}

private struct HistoryMonth: Identifiable {
    let id: Date
    let title: String
    let matches: [Match]
}

private struct MatchHistoryRow: View {
    let match: Match
    let outcome: GameOutcome

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Image(systemName: outcome.symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(outcome.color)
                    .accessibilityLabel(outcome.title)
            }
            .frame(width: 40, height: 46)
            .background(outcome.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(match.players.map(\.name).joined(separator: " vs "))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(match.config.mode.shortTitle, systemImage: match.config.mode.symbol)
                    if match.playedDuration > 0 {
                        Text("·")
                        Text(PlayTime.format(match.playedDuration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(score)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.card)
                .overlay {
                    LinearGradient(
                        colors: [outcome.color.opacity(0.22), outcome.color.opacity(0.06), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(outcome.color.opacity(0.3), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otevře detail zápasu")
    }

    private var date: Date { match.completedAt ?? match.createdAt }

    private var score: String {
        match.players.indices.map { "\(match.config.playsSets ? match.states[$0].sets : match.states[$0].legs)" }.joined(separator: " : ")
    }
}

private struct MatchScoreline: View {
    @EnvironmentObject private var store: AppStore
    let match: Match
    var dark = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(match.players.indices, id: \.self) { index in
                if index > 0 {
                    Text(":")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(dark ? Color.white.opacity(0.25) : Color.secondary.opacity(0.55))
                        .padding(.horizontal, 4)
                        .accessibilityHidden(true)
                }
                VStack(spacing: 4) {
                    Avatar(
                        name: match.players[index].name,
                        bot: match.players[index].botLevel != nil,
                        size: 34,
                        photo: store.photo(for: match.players[index].id),
                        asset: match.players[index].botLevel.map { BotLevel.get($0).photo }
                    )
                    .overlay(Circle().strokeBorder(match.winner == index ? (dark ? Theme.brand : Theme.positive) : .clear, lineWidth: 2))
                    Text("\(tally(index))")
                        .font(.system(size: match.players.count > 2 ? 28 : 40, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(match.winner == index ? (dark ? Theme.brand : Theme.positive) : (dark ? .white : .primary))
                    Text(match.players[index].name)
                        .font(.caption)
                        .foregroundStyle(dark ? .white.opacity(0.6) : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func tally(_ index: Int) -> Int {
        match.config.playsSets ? match.states[index].sets : match.states[index].legs
    }
}

private enum MatchDetailPage: String, CaseIterable, Identifiable {
    case overview, stats, visits
    var id: String { rawValue }
    var title: String {
        switch self { case .overview: return "Přehled"; case .stats: return "Statistiky"; case .visits: return "Hody" }
    }
}

struct MatchDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let match: Match
    let profileID: UUID?
    @State private var page: MatchDetailPage = .overview
    @State private var focus: Int
    @State private var confirmDelete = false

    init(match: Match, profileID: UUID?) {
        self.match = match
        self.profileID = profileID
        _focus = State(initialValue: match.players.firstIndex { $0.id == profileID } ?? match.winner ?? 0)
    }

    private var playerIndex: Int { match.players.indices.contains(focus) ? focus : 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailHero
                Picker("Část detailu", selection: $page) {
                    ForEach(MatchDetailPage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch page {
                case .overview: overview
                case .stats: statistics(playerIndex)
                case .visits: visitsPage
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("Detail zápasu")
        .navigationSubtitle(match.config.mode.shortTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { detailToolbar }
        .sensoryFeedback(.selection, trigger: page)
        .sensoryFeedback(.selection, trigger: focus)
        .alert("Opravdu smazat tento zápas?", isPresented: $confirmDelete) {
            Button("Smazat zápas", role: .destructive) {
                store.deleteMatch(match.id)
                dismiss()
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Statistiky a všechny uložené hody tohoto zápasu budou trvale odstraněny.")
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if page == .stats, match.players.count > 1 {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Hráč", selection: $focus) {
                        ForEach(match.players.indices, id: \.self) { index in
                            Label(playerName(index), systemImage: match.winner == index ? "crown" : "person").tag(index)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label(match.players[playerIndex].name, systemImage: "person")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section {
                    NavigationLink {
                        VisitLog(game: match)
                    } label: {
                        Label("Všechny hody", systemImage: "list.bullet")
                    }
                }
                Section {
                    Button("Smazat zápas", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Další možnosti")
        }
    }

    private var detailHero: some View {
        let result = outcome(match, profileID: profileID)
        return VStack(spacing: 12) {
            HStack {
                Spacer()
                Text((match.completedAt ?? match.createdAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            MatchScoreline(match: match, dark: true)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background {
            ZStack {
                Theme.heroWash
                LinearGradient(
                    colors: [result.color.opacity(0.42), result.color.opacity(0.10), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(result.color.opacity(0.65), lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Image(systemName: result.symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(result.color)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.35), in: Circle())
                .padding(14)
                .accessibilityLabel(result.title)
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("O zápase", symbol: "info.circle") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(match.config.summary, systemImage: match.config.mode.symbol)
                    Label((match.completedAt ?? match.createdAt).formatted(date: .long, time: .shortened), systemImage: "calendar")
                    if match.playedDuration > 0 {
                        Label(PlayTime.format(match.playedDuration), systemImage: "clock")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .surface()
            }
            section("Průběh", symbol: "flag.checkered") { legList }
            HStack(spacing: 12) {
                overviewAction("Statistiky", "chart.bar.fill", .stats)
                overviewAction("Hody", "list.bullet", .visits)
            }
        }
    }

    private func overviewAction(_ title: String, _ symbol: String, _ destination: MatchDetailPage) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.2)) { page = destination } } label: {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(destination == .stats ? Theme.onAccent : .primary)
                .background(destination == .stats ? Theme.accentFill : Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func statistics(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if match.players.count > 1 {
                playerStrip
            }
            section("Výkon", symbol: "chart.bar.fill") { playerStats(index) }
            if match.config.mode == .x01 {
                section("Rozložení kol", symbol: "chart.bar.xaxis") { scoringBands(index) }
                let checkout = CheckoutStats.make(from: match, player: index)
                if checkout.hasData {
                    section("Zavírání", symbol: "checkmark.seal.fill") {
                        CheckoutStatsView(stats: checkout).surface()
                    }
                }
            }
            boardBlock(index)
        }
    }

    private var playerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(match.players.indices, id: \.self) { index in
                    Button { focus = index } label: {
                        HStack(spacing: 7) {
                            Avatar(name: match.players[index].name, bot: match.players[index].botLevel != nil, size: 28, photo: store.photo(for: match.players[index].id), asset: match.players[index].botLevel.map { BotLevel.get($0).photo })
                            Text(playerName(index)).lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .foregroundStyle(index == playerIndex ? Theme.onAccent : .primary)
                        .background(index == playerIndex ? Theme.accentFill : Theme.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index == playerIndex ? .isSelected : [])
                }
            }
        }
    }

    private var visitsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            section("Poslední kola", symbol: "arrow.down.to.line") {
                VStack(spacing: 0) {
                    ForEach(Array(match.visits.suffix(10).reversed())) { visit in
                        ThrowPreviewRow(match: match, visit: visit)
                        if visit.id != match.visits.suffix(10).first?.id { Divider() }
                    }
                }
                .surface()
            }
            NavigationLink {
                VisitLog(game: match)
            } label: {
                Label("Otevřít všechny hody", systemImage: "list.bullet")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryButton())
        }
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .labelStyle(HistoryLabelStyle())
            content()
        }
    }

    private var legList: some View {
        let legs = Array(Set(match.visits.map(\.leg))).sorted()
        let darts = match.visits.reduce(0) { $0 + $1.darts.count }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                flowFact("\(legs.count)", czech(legs.count, "leg", "legy", "legů"))
                Divider().frame(height: 34)
                flowFact("\(match.visits.count)", czech(match.visits.count, "návštěva", "návštěvy", "návštěv"))
                Divider().frame(height: 34)
                flowFact("\(darts)", czech(darts, "šipka", "šipky", "šipek"))
            }
            .padding(.vertical, 8)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.element) { offset, leg in
                    let winner = winnerForLeg(leg, lastLeg: legs.last)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            ZStack {
                                Circle()
                                    .fill(winner == nil ? Color.secondary : Theme.playerColor(winner!))
                                    .frame(width: 32, height: 32)
                                Image(systemName: winner == nil ? "ellipsis" : "flag.fill")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(winner == nil ? Color.white : Color.black)
                            }
                            if offset < legs.count - 1 {
                                Rectangle()
                                    .fill(Theme.stroke)
                                    .frame(width: 2, height: 62)
                            }
                        }

                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Leg \(leg)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(runningScore(through: leg, legs: legs))
                                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                            }
                            HStack(spacing: 8) {
                                if let winner {
                                    Avatar(
                                        name: match.players[winner].name,
                                        bot: match.players[winner].botLevel != nil,
                                        size: 30,
                                        photo: store.photo(for: match.players[winner].id),
                                        asset: match.players[winner].botLevel.map { BotLevel.get($0).photo }
                                    )
                                    Text(match.players[winner].name)
                                        .font(.headline)
                                        .lineLimit(1)
                                } else {
                                    Text("Bez vítěze")
                                        .font(.headline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(legDetail(leg))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.bottom, offset < legs.count - 1 ? 14 : 0)
                    }
                }
            }
        }
        .surface()
    }

    private func flowFact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func winnerForLeg(_ leg: Int, lastLeg: Int?) -> Int? {
        if let winner = match.bullOffLegs?[leg] { return winner }
        if let winner = match.visits.last(where: { $0.leg == leg && $0.checkout })?.player { return winner }
        if leg == lastLeg, match.finished { return match.winner }
        return nil
    }

    private func runningScore(through leg: Int, legs: [Int]) -> String {
        var score = Array(repeating: 0, count: match.players.count)
        for item in legs where item <= leg {
            if let winner = winnerForLeg(item, lastLeg: legs.last) { score[winner] += 1 }
        }
        return score.map(String.init).joined(separator: " : ")
    }

    private func legDetail(_ leg: Int) -> String {
        let visits = match.visits.filter { $0.leg == leg }
        let darts = visits.reduce(0) { $0 + $1.darts.count }
        if match.bullOffLegs?[leg] != nil {
            return "Rozhodnuto rozhozem na střed · \(czechCount(darts, "šipka", "šipky", "šipek"))"
        }
        if let checkout = visits.last(where: \.checkout) {
            let route = checkout.enteredAsTotal == true ? nil : checkout.darts.map(\.label).joined(separator: " · ")
            if let route, !route.isEmpty {
                return "Checkout \(checkout.credited) · \(route)"
            }
            return "Checkout \(checkout.credited) · \(czechCount(checkout.darts.count, "šipka", "šipky", "šipek"))"
        }
        return "\(czechCount(visits.count, "návštěva", "návštěvy", "návštěv")) · \(czechCount(darts, "šipka", "šipky", "šipek"))"
    }

    private func playerStats(_ index: Int) -> some View {
        let visits = match.visits.filter { $0.player == index }
        let darts = visits.reduce(0) { $0 + $1.darts.count }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(name: match.players[index].name, bot: match.players[index].botLevel != nil, size: 48, photo: store.photo(for: match.players[index].id), asset: match.players[index].botLevel.map { BotLevel.get($0).photo })
                VStack(alignment: .leading, spacing: 2) {
                    Text(match.players[index].name).font(.headline)
                    Text("\(czechCount(darts, "šipka", "šipky", "šipek")) · \(czechCount(visits.count, "kolo", "kola", "kol"))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if match.winner == index { Image(systemName: "crown.fill").foregroundStyle(Theme.positive) }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(metrics(index, visits: visits), id: \.label) { item in
                    metric(item.value, item.label)
                }
            }
        }
        .surface()
    }

    private func metrics(_ index: Int, visits: [Visit]) -> [(value: String, label: String)] {
        switch match.config.mode {
        case .x01:
            return [
                (String(format: "%.1f", match.average(for: index)), "Průměr"),
                ("\(match.best(for: index))", "Nejlepší kolo"),
                ("\(visits.filter { $0.credited == 180 }.count)", "180"),
                ("\(visits.filter(\.checkout).count)", "Zavření"),
                (CheckoutStats.make(from: match, player: index).percentage.map { "\(Int($0.rounded())) %" } ?? "—", "Na double"),
                ("\(visits.filter(\.bust).count)", "Přehozy")
            ]
        case .cricket, .countUp:
            return [("\(match.states[index].points)", "Body"), ("\(match.states[index].rounds)", "Kola"), ("\(match.best(for: index))", "Maximum")]
        case .aroundClock:
            return [(match.states[index].clockTarget >= 21 ? "Hotovo" : "\(match.states[index].clockTarget)", "Cíl"), ("\(visits.flatMap(\.darts).count)", "Šipky"), ("\(visits.count)", "Kola")]
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Theme.positive)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func scoringBands(_ index: Int) -> some View {
        let visits = match.visits.filter { $0.player == index && !$0.bust }
        let bands: [(String, Int, Color)] = [
            ("180", visits.filter { $0.credited == 180 }.count, .red),
            ("140+", visits.filter { (140..<180).contains($0.credited) }.count, .orange),
            ("100+", visits.filter { (100..<140).contains($0.credited) }.count, .yellow),
            ("60+", visits.filter { (60..<100).contains($0.credited) }.count, Theme.positive),
            ("<60", visits.filter { $0.credited < 60 }.count, .secondary.opacity(0.35))
        ]
        let total = max(1, bands.reduce(0) { $0 + $1.1 })
        return VStack(spacing: 14) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(bands, id: \.0) { band in
                        if band.1 > 0 {
                            Rectangle().fill(band.2)
                                .frame(width: max(4, (proxy.size.width - 8) * CGFloat(band.1) / CGFloat(total)))
                        }
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 14)
            HStack(spacing: 0) {
                ForEach(bands, id: \.0) { band in
                    VStack(spacing: 2) {
                        Text("\(band.1)").font(.headline.monospacedDigit())
                        Text(band.0).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .surface()
    }

    @ViewBuilder
    private func boardBlock(_ index: Int) -> some View {
        let marks = match.visits
            .filter { $0.player == index && $0.enteredAsTotal != true }
            .flatMap(\.darts)
            .filter { $0.x != nil && $0.y != nil }
        if !marks.isEmpty {
            section("Terč", symbol: "target") {
                NavigationLink {
                    HeatmapView(darts: marks, title: match.players[index].name)
                } label: {
                    HStack(spacing: 16) {
                        TouchDartboard(marks: marks, interactive: false, showMarkNumbers: false) { _ in }
                            .frame(width: 108, height: 108)
                            .allowsHitTesting(false)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Mapa dopadů").font(.headline)
                            Text(czechCount(marks.count, "umístěná šipka", "umístěné šipky", "umístěných šipek"))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .surface()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func playerName(_ index: Int) -> String {
        match.players[index].id == profileID ? "\(match.players[index].name) · Ty" : match.players[index].name
    }
}

private struct ThrowPreviewRow: View {
    @EnvironmentObject private var store: AppStore
    let match: Match
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: match.players[visit.player].name, bot: match.players[visit.player].botLevel != nil, size: 34, photo: store.photo(for: match.players[visit.player].id), asset: match.players[visit.player].botLevel.map { BotLevel.get($0).photo })
            VStack(alignment: .leading, spacing: 3) {
                Text("\(match.players[visit.player].name) · leg \(visit.leg)")
                    .font(.subheadline.weight(.semibold))
                Text(visit.enteredAsTotal == true ? "Zadáno součtem" : visit.darts.map(\.label).joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(visit.bust ? "BUST" : "\(visit.credited)")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(visit.bust ? .red : visit.checkout ? Theme.positive : .primary)
        }
        .padding(.vertical, 9)
    }
}

private struct HistoryLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

private func outcome(_ match: Match, profileID: UUID?) -> GameOutcome {
    guard let winner = match.winner else { return .draw }
    return match.players[winner].id == profileID ? .win : .loss
}

private func czech(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
    let tail = count % 100
    let digit = count % 10
    if tail < 10 || tail >= 20 {
        if digit == 1 { return one }
        if (2...4).contains(digit) { return few }
    }
    return many
}

private func czechCount(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
    "\(count) \(czech(count, one, few, many))"
}
