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
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if store.matches.isEmpty {
                    ContentUnavailableView(
                        "Zatím žádné zápasy",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Dokončené hry se uloží sem včetně výsledku, statistik a hodů.")
                    )
                } else {
                    record
                    if let latest = matches.first {
                        latestMatch(latest)
                        if matches.count > 1 { timeline(Array(matches.dropFirst())) }
                    } else {
                        ContentUnavailableView(
                            "Žádný zápas neodpovídá",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("Změň filtry v horní liště.")
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("Moje hry")
        .navigationSubtitle(filterCaption)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { historyToolbar }
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.selection, trigger: result)
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
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Bilance")
                    Text("\(wins)–\(losses)\(draws > 0 ? "–\(draws)" : "")")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(winRate(wins: wins))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.positive)
                    Text("úspěšnost").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 0) {
                recordFact("\(matches.count)", "her")
                Divider().frame(height: 30)
                recordFact(PlayTime.format(matches.reduce(0) { $0 + $1.playedDuration }), "u terče")
                Divider().frame(height: 30)
                recordFact("\(matches.filter { $0.config.mode == .x01 }.count)", "X01")
            }
        }
        .surface()
    }

    private func recordFact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func latestMatch(_ match: Match) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(order == .newest ? "Poslední zápas" : "První zápas").font(.title3.bold())
                Spacer()
                Text((match.completedAt ?? match.createdAt).formatted(.relative(presentation: .named)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            NavigationLink {
                MatchDetailView(match: match, profileID: store.profile?.id)
            } label: {
                FeaturedMatchCard(match: match, outcome: outcome(match))
            }
            .buttonStyle(.plain)
        }
    }

    private func timeline(_ games: [Match]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Historie").font(.title3.bold())
            LazyVStack(spacing: 0) {
                ForEach(Array(games.enumerated()), id: \.element.id) { index, match in
                    NavigationLink {
                        MatchDetailView(match: match, profileID: store.profile?.id)
                    } label: {
                        MatchTimelineRow(match: match, outcome: outcome(match), last: index == games.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func outcome(_ match: Match) -> GameOutcome {
        guard let winner = match.winner else { return .draw }
        return match.players[winner].id == store.profile?.id ? .win : .loss
    }

    private func winRate(wins: Int) -> String {
        guard !matches.isEmpty else { return "—" }
        return "\(Int((Double(wins) / Double(matches.count) * 100).rounded())) %"
    }
}

private enum GameOutcome {
    case win, loss, draw
    var title: String {
        switch self { case .win: return "Výhra"; case .loss: return "Prohra"; case .draw: return "Remíza" }
    }
    var symbol: String {
        switch self { case .win: return "checkmark"; case .loss: return "xmark"; case .draw: return "equal" }
    }
    var color: Color {
        switch self { case .win: return Theme.positive; case .loss: return .secondary; case .draw: return .orange }
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
                Label(outcome.title, systemImage: outcome.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(outcome == .win ? Theme.brand : .white.opacity(0.7))
            }
            MatchScoreline(match: match, dark: true)
            HStack {
                Text(match.config.lengthLine)
                    .lineLimit(1)
                Spacer()
                if match.playedDuration > 0 {
                    Label(PlayTime.format(match.playedDuration), systemImage: "clock")
                }
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background {
            ZStack {
                Theme.heroWash
                Image(systemName: match.config.mode.symbol)
                    .font(.system(size: 150, weight: .bold))
                    .foregroundStyle(.white.opacity(0.05))
                    .offset(x: 100, y: 45)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otevře detail zápasu")
    }
}

private struct MatchTimelineRow: View {
    let match: Match
    let outcome: GameOutcome
    let last: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(outcome.color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 3))
                if !last {
                    Rectangle().fill(Theme.stroke).frame(width: 1, height: 72)
                }
            }
            .padding(.top, 18)
            VStack(spacing: 8) {
                HStack {
                    Label(match.config.mode.shortTitle, systemImage: match.config.mode.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text((match.completedAt ?? match.createdAt).formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.players.map(\.name).joined(separator: " vs "))
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(outcome.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(outcome.color)
                    }
                    Spacer(minLength: 4)
                    Text(score)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke, lineWidth: 0.5))
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otevře detail zápasu")
    }

    private var score: String {
        match.players.indices.map { "\(match.config.playsSets ? match.states[$0].sets : match.states[$0].legs)" }.joined(separator: " : ")
    }
}

private struct MatchScoreline: View {
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
                VStack(spacing: 2) {
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
    let match: Match
    let profileID: UUID?
    @State private var page: MatchDetailPage = .overview
    @State private var focus: Int

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
            NavigationLink {
                VisitLog(game: match)
            } label: {
                Image(systemName: "list.bullet")
            }
            .accessibilityLabel("Všechny hody")
        }
    }

    private var detailHero: some View {
        let result = outcome(match, profileID: profileID)
        return VStack(spacing: 12) {
            HStack {
                Label(result.title, systemImage: result.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(result == .win ? Theme.brand : .white.opacity(0.7))
                Spacer()
                Text((match.completedAt ?? match.createdAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
            MatchScoreline(match: match, dark: true)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(Theme.heroWash, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 1))
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
                            Avatar(name: match.players[index].name, bot: match.players[index].botLevel != nil, size: 28, asset: match.players[index].botLevel.map { BotLevel.get($0).photo })
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
        return VStack(spacing: 0) {
            ForEach(legs, id: \.self) { leg in
                let winner = match.bullOffLegs?[leg] ?? match.visits.last { $0.leg == leg && $0.checkout }?.player
                HStack(spacing: 12) {
                    Text("\(leg)")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(Theme.background, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(winner.map { match.players[$0].name } ?? "Bez vítěze")
                            .font(.subheadline.weight(.semibold))
                        Text(legCaption(leg)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if winner != nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.positive) }
                }
                .padding(.vertical, 10)
                if leg != legs.last { Divider() }
            }
        }
        .surface()
    }

    private func playerStats(_ index: Int) -> some View {
        let visits = match.visits.filter { $0.player == index }
        let darts = visits.reduce(0) { $0 + $1.darts.count }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Avatar(name: match.players[index].name, bot: match.players[index].botLevel != nil, size: 48, asset: match.players[index].botLevel.map { BotLevel.get($0).photo })
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

    private func legCaption(_ leg: Int) -> String {
        match.players.indices.map { index in
            let points = match.visits.filter { $0.player == index && $0.leg == leg }.reduce(0) { $0 + $1.credited }
            return "\(match.players[index].name) \(points)"
        }.joined(separator: " · ")
    }
}

private struct ThrowPreviewRow: View {
    let match: Match
    let visit: Visit

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: match.players[visit.player].name, bot: match.players[visit.player].botLevel != nil, size: 34, asset: match.players[visit.player].botLevel.map { BotLevel.get($0).photo })
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
