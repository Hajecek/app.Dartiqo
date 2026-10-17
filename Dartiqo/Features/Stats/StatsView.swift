import SwiftUI

private enum HistoryResultFilter: String, CaseIterable, Identifiable {
    case all, wins, losses
    var id: String { rawValue }
    func title(training: Bool) -> String {
        switch self {
        case .all: return "Všechny"
        case .wins: return training ? "Splněné" : "Výhry"
        case .losses: return training ? "Nesplněné" : "Prohry"
        }
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

private enum HistoryModeFilter: Hashable, Identifiable {
    case all
    case game(GameMode)
    case training

    var id: String {
        switch self {
        case .all: return "all"
        case .game(let mode): return mode.rawValue
        case .training: return "training"
        }
    }

    var menuTitle: String {
        switch self {
        case .all: return "Všechny režimy"
        case .game(let mode): return mode.shortTitle
        case .training: return "Trénink"
        }
    }

    var toolbarTitle: String {
        switch self {
        case .all: return "Hra"
        case .game(let mode): return mode.shortTitle
        case .training: return "Trénink"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "slider.horizontal.3"
        case .game(let mode): return mode.symbol
        case .training: return "figure.strengthtraining.traditional"
        }
    }

    var isTraining: Bool {
        if case .training = self { return true }
        return false
    }
}

private enum HistoryDeleteTarget: Identifiable, Equatable {
    case match(UUID)
    case training(UUID)
    var id: String {
        switch self {
        case .match(let id): return "m-\(id.uuidString)"
        case .training(let id): return "t-\(id.uuidString)"
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode: HistoryModeFilter = .all
    @State private var result: HistoryResultFilter = .all
    @State private var order: HistoryOrder = .newest
    @State private var pendingDelete: HistoryDeleteTarget?
    @State private var selectedMatch: UUID?
    @State private var selectedTraining: UUID?

    private var matches: [Match] {
        let filtered = store.matches.filter { match in
            let modeFits: Bool = {
                switch mode {
                case .all: return true
                case .game(let game): return match.config.mode == game
                case .training: return false
                }
            }()
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

    private var trainings: [TrainingSession] {
        let filtered = store.trainingHistory.filter { session in
            switch result {
            case .all: return true
            case .wins: return session.result?.success == true
            case .losses: return session.result?.success != true
            }
        }
        return order == .newest ? filtered : filtered.reversed()
    }

    private var archiveEmpty: Bool {
        mode.isTraining ? store.trainingHistory.isEmpty : store.matches.isEmpty
    }

    var body: some View {
        List {
            if archiveEmpty {
                Section {
                    ContentUnavailableView(
                        mode.isTraining ? "Zatím žádné tréninky" : "Zatím žádné zápasy",
                        systemImage: mode.isTraining ? "figure.strengthtraining.traditional" : "clock.arrow.circlepath",
                        description: Text(mode.isTraining
                            ? "Dokončené tréninky se uloží sem včetně výsledku a statistik."
                            : "Dokončené hry se uloží sem včetně výsledku, statistik a hodů.")
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            } else if mode.isTraining {
                trainingList
            } else {
                matchList
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
        .navigationDestination(item: $selectedTraining) { id in
            if let session = store.trainingHistory.first(where: { $0.id == id }) {
                TrainingSessionDetailView(session: session)
            }
        }
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.selection, trigger: result)
        .alert(deleteAlertTitle, isPresented: deleteDialog) {
            Button(deleteConfirmTitle, role: .destructive) {
                if let pendingDelete {
                    switch pendingDelete {
                    case .match(let id): store.deleteMatch(id)
                    case .training(let id): store.deleteTraining(id)
                    }
                }
                pendingDelete = nil
            }
            Button("Zrušit", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteAlertMessage)
        }
    }

    @ViewBuilder
    private var matchList: some View {
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

    @ViewBuilder
    private var trainingList: some View {
        Section {
            trainingRecord
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }

        if let latest = trainings.first {
            Section(order == .newest ? "Poslední trénink" : "První trénink") {
                trainingLink(latest, featured: true)
            }

            ForEach(trainingGroups(Array(trainings.dropFirst()))) { group in
                Section(group.title) {
                    ForEach(group.sessions) { session in
                        trainingLink(session)
                    }
                }
            }
        } else {
            Section {
                ContentUnavailableView(
                    "Žádný trénink neodpovídá",
                    systemImage: "line.3.horizontal.decrease.circle",
                    description: Text("Změň filtry v horní liště.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
    }

    private var deleteDialog: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var deleteAlertTitle: String {
        if case .training = pendingDelete { return "Opravdu smazat trénink?" }
        return "Opravdu smazat zápas?"
    }

    private var deleteConfirmTitle: String {
        if case .training = pendingDelete { return "Smazat trénink" }
        return "Smazat zápas"
    }

    private var deleteAlertMessage: String {
        if case .training = pendingDelete {
            return "Trénink, jeho výsledek i získané XP z tohoto běhu budou trvale odstraněny."
        }
        return "Zápas, jeho statistiky i všechny hody budou trvale odstraněny."
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
                pendingDelete = .match(match.id)
            } label: {
                Label("Smazat", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    @ViewBuilder
    private func trainingLink(_ session: TrainingSession, featured: Bool = false) -> some View {
        Button {
            selectedTraining = session.id
        } label: {
            if featured {
                FeaturedTrainingCard(session: session)
                    .padding(.vertical, 4)
            } else {
                TrainingHistoryRow(session: session)
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(featured ? EdgeInsets() : EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = .training(session.id)
            } label: {
                Label("Smazat", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private var filterCaption: String {
        if mode.isTraining {
            return "\(mode.menuTitle) · \(czechCount(trainings.count, "trénink", "tréninky", "tréninků"))"
        }
        return "\(mode.menuTitle) · \(czechCount(matches.count, "hra", "hry", "her"))"
    }

    @ToolbarContentBuilder
    private var historyToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Picker("Výsledek", selection: $result) {
                    ForEach(HistoryResultFilter.allCases) { item in
                        Label(item.title(training: mode.isTraining), systemImage: item.symbol).tag(item)
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
                Label(result.title(training: mode.isTraining), systemImage: result.symbol)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Hra", selection: $mode) {
                    Label("Všechny režimy", systemImage: "square.grid.2x2").tag(HistoryModeFilter.all)
                    ForEach(GameMode.allCases) { item in
                        Label(item.shortTitle, systemImage: item.symbol).tag(HistoryModeFilter.game(item))
                    }
                    Label("Trénink", systemImage: "figure.strengthtraining.traditional").tag(HistoryModeFilter.training)
                }
                .pickerStyle(.inline)
            } label: {
                Label(mode.toolbarTitle, systemImage: mode.symbol)
            }
        }
    }

    private var record: some View {
        let ranked = matches.filter(\.countsForCompetitiveRecord)
        let wins = ranked.filter { outcome($0) == .win }.count
        let losses = ranked.filter { outcome($0) == .loss }.count
        let draws = ranked.filter { outcome($0) == .draw }.count
        let recent = Array(ranked.prefix(8))
        let tone = recordTone(wins: wins, ranked: ranked.count)
        return VStack(alignment: .leading, spacing: 16) {
            recordHeader(
                eyebrow: "Bilance",
                headline: recordHeadline(wins: wins, ranked: ranked.count),
                detail: recordDetail(wins: wins, losses: losses, ranked: ranked),
                rate: winRate(wins: wins, ranked: ranked.count),
                caption: "úspěšnost",
                tone: tone,
                ranked: ranked.count
            )

            recordShare(wins: wins, draws: draws, losses: losses)

            HStack(spacing: 8) {
                recordStat("\(wins)", "výhry", Theme.positive)
                recordStat("\(losses)", "prohry", .red)
                recordStat("\(draws)", "remízy", .orange)
            }

            let total = matches.reduce(0) { $0 + $1.playedDuration }
            if PlayTime.components(total).hours > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    recentForm(recent)
                    boardTotal(total)
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    recentForm(recent)
                    Spacer(minLength: 8)
                    boardTotal(total)
                }
            }
        }
        .surface()
    }

    private func recordHeader(
        eyebrow: String,
        headline: String,
        detail: String,
        rate: String,
        caption: String,
        tone: Color,
        ranked: Int
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 1) {
                Text(rate)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ranked == 0 ? Color.secondary : tone)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 96, height: 78)
            .background(
                tone.opacity(ranked == 0 ? 0.08 : 0.14),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(tone.opacity(ranked == 0 ? 0.12 : 0.35), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: eyebrow)
                Text(headline)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private func recordShare(wins: Int, draws: Int, losses: Int) -> some View {
        let parts: [(count: Int, color: Color)] = [
            (wins, Theme.positive),
            (draws, .orange),
            (losses, Color.red.opacity(0.82))
        ]
        let visible = parts.filter { $0.count > 0 }
        let total = visible.reduce(0) { $0 + $1.count }
        return GeometryReader { geo in
            if total == 0 {
                Capsule().fill(Color.primary.opacity(0.08))
            } else {
                let gap: CGFloat = 3
                let usable = max(0, geo.size.width - gap * CGFloat(max(visible.count - 1, 0)))
                let floor = min(8, usable / CGFloat(visible.count))
                let flex = max(0, usable - floor * CGFloat(visible.count))
                HStack(spacing: gap) {
                    ForEach(Array(visible.enumerated()), id: \.offset) { _, part in
                        Capsule()
                            .fill(part.color)
                            .frame(width: floor + flex * CGFloat(part.count) / CGFloat(total))
                    }
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    private func recordStat(_ value: String, _ label: String, _ tint: Color) -> some View {
        let quiet = value == "0"
        let color = quiet ? Color.secondary : tint
        return VStack(spacing: 5) {
            Capsule()
                .fill(color.opacity(quiet ? 0.35 : 1))
                .frame(width: 22, height: 3)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(tint.opacity(quiet ? 0.06 : 0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func recordTone(wins: Int, ranked: Int) -> Color {
        guard ranked > 0 else { return .secondary }
        if wins > ranked / 2 { return Theme.positive }
        if wins * 2 == ranked { return .orange }
        return .red
    }

    private func recentForm(_ recent: [Match]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("POSLEDNÍ FORMA")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(recent) { game in
                    let item = outcome(game)
                    Text(item.shortTitle)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(item == .loss || item == .practice ? Color.primary : Color.white)
                        .frame(width: 24, height: 24)
                        .background(item.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
    }

    /// Celkový čas pod formou. V hodinách jde na celou šířku, ať se „8 h 29 min“ nesrazí se štítky.
    private func boardTotal(_ seconds: TimeInterval) -> some View {
        let parts = PlayTime.components(seconds)
        return Group {
            if parts.hours > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    PlayTimeLabel(seconds: seconds, layout: .inline)
                    Spacer(minLength: 8)
                    Text("celkem u terče")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(PlayTime.format(seconds))
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                    Text("celkem u terče")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Celkem u terče \(PlayTime.format(seconds))")
    }

    private func recordHeadline(wins: Int, ranked: Int) -> String {
        guard ranked > 0 else { return "Bez soutěžních her" }
        if wins == ranked { return "Bez porážky" }
        if wins > ranked / 2 { return "Kladná bilance" }
        if wins * 2 == ranked { return "Vyrovnaná bilance" }
        return "Je na čem pracovat"
    }

    private func recordDetail(wins: Int, losses: Int, ranked: [Match]) -> String {
        if let streak = currentStreak(in: ranked) {
            return streak.count == 1
                ? "Poslední zápas: \(streak.outcome.title.lowercased())"
                : "\(streak.count)× \(streak.outcome == .win ? "výhra" : streak.outcome == .loss ? "prohra" : "remíza") v řadě"
        }
        return "\(wins) výher · \(losses) proher"
    }

    private func currentStreak(in ranked: [Match]) -> (outcome: GameOutcome, count: Int)? {
        guard let first = ranked.first.map(outcome), first != .practice else { return nil }
        let count = ranked.prefix { outcome($0) == first }.count
        return (first, count)
    }

    private func outcome(_ match: Match) -> GameOutcome {
        guard match.countsForCompetitiveRecord else { return .practice }
        guard let winner = match.winner else { return .draw }
        return match.players[winner].id == store.profile?.id ? .win : .loss
    }

    private func winRate(wins: Int, ranked: Int) -> String {
        guard ranked > 0 else { return "—" }
        return "\(Int((Double(wins) / Double(ranked) * 100).rounded())) %"
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

    private var trainingRecord: some View {
        let done = trainings.filter { $0.result?.success == true }.count
        let miss = trainings.count - done
        let darts = trainings.reduce(0) { $0 + ($1.result?.darts ?? 0) }
        let seconds = trainings.reduce(0.0) { sum, session in
            guard let end = session.finishedAt else { return sum }
            return sum + max(0, end.timeIntervalSince(session.startedAt))
        }
        let tone = recordTone(wins: done, ranked: trainings.count)
        return VStack(alignment: .leading, spacing: 16) {
            recordHeader(
                eyebrow: "Trénink",
                headline: trainingHeadline(done: done, total: trainings.count),
                detail: trainings.isEmpty
                    ? "Zatím bez dokončených tréninků"
                    : "\(done) splněno · \(miss) nesplněno",
                rate: winRate(wins: done, ranked: trainings.count),
                caption: "splněno",
                tone: tone,
                ranked: trainings.count
            )

            recordShare(wins: done, draws: 0, losses: miss)

            HStack(spacing: 8) {
                recordStat("\(done)", "splněno", Theme.positive)
                recordStat("\(miss)", "nesplněno", .red)
                recordStat("\(darts)", "šipek", .orange)
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label("Celkem u terče", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                PlayTimeLabel(seconds: seconds, layout: .inline)
            }
        }
        .surface()
    }

    private func trainingHeadline(done: Int, total: Int) -> String {
        guard total > 0 else { return "Bez tréninků" }
        if done == total { return "Všechny splněné" }
        if done > total / 2 { return "Dobrá série" }
        if done * 2 == total { return "Půl na půl" }
        return "Je na čem pracovat"
    }

    private func trainingGroups(_ sessions: [TrainingSession]) -> [TrainingHistoryMonth] {
        let calendar = Calendar.current
        var keys: [Date] = []
        var grouped: [Date: [TrainingSession]] = [:]
        for session in sessions {
            let date = session.finishedAt ?? session.startedAt
            let components = calendar.dateComponents([.year, .month], from: date)
            guard let month = calendar.date(from: components) else { continue }
            if grouped[month] == nil { keys.append(month) }
            grouped[month, default: []].append(session)
        }
        return keys.map {
            TrainingHistoryMonth(id: $0, title: $0.formatted(.dateTime.month(.wide).year()), sessions: grouped[$0] ?? [])
        }
    }
}

private enum GameOutcome {
    case win, loss, draw, practice
    var title: String {
        switch self {
        case .win: return "Vítězství"
        case .loss: return "Prohra"
        case .draw: return "Remíza"
        case .practice: return "Trénink"
        }
    }
    var symbol: String {
        switch self {
        case .win: return "trophy.fill"
        case .loss: return "xmark"
        case .draw: return "equal"
        case .practice: return "figure.walk"
        }
    }
    var color: Color {
        switch self {
        case .win: return Theme.positive
        case .loss: return .red
        case .draw: return .orange
        case .practice: return Theme.stroke
        }
    }
    var shortTitle: String {
        switch self {
        case .win: return "V"
        case .loss: return "P"
        case .draw: return "R"
        case .practice: return "T"
        }
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

private struct TrainingHistoryMonth: Identifiable {
    let id: Date
    let title: String
    let sessions: [TrainingSession]
}

private func trainingOutcome(_ session: TrainingSession) -> GameOutcome {
    session.result?.success == true ? .win : .loss
}

private func trainingTitle(_ session: TrainingSession) -> String {
    TrainingCatalog.find(session.definitionID)?.title ?? session.definitionID
}

private func trainingCategory(_ session: TrainingSession) -> TrainingCategory? {
    TrainingCatalog.find(session.definitionID)?.category
}

private func trainingDuration(_ session: TrainingSession) -> TimeInterval {
    guard let end = session.finishedAt else { return 0 }
    return max(0, end.timeIntervalSince(session.startedAt))
}

private struct FeaturedTrainingCard: View {
    let session: TrainingSession

    private var outcome: GameOutcome { trainingOutcome(session) }
    private var definitionTitle: String { trainingTitle(session) }
    private var category: TrainingCategory? { trainingCategory(session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(category?.title ?? "Trénink", systemImage: category?.symbol ?? "figure.strengthtraining.traditional")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(definitionTitle)
                    .font(.title2.bold())
                Text(session.result?.summary.isEmpty == false ? session.result!.summary : (outcome == .win ? "Splněno" : "Nesplněno"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
            }
            HStack {
                if let result = session.result, result.darts > 0 {
                    Text(czechCount(result.darts, "šipka", "šipky", "šipek"))
                }
                Spacer()
                let seconds = trainingDuration(session)
                if seconds > 0 {
                    Label(PlayTime.format(seconds), systemImage: "clock")
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
                Image(systemName: category?.symbol ?? "figure.strengthtraining.traditional")
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
            Image(systemName: outcome == .win ? "checkmark.seal.fill" : "xmark.seal.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(outcome.color)
                .frame(width: 30, height: 30)
                .background(.black.opacity(0.35), in: Circle())
                .padding(14)
                .accessibilityLabel(outcome == .win ? "Splněno" : "Nesplněno")
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otevře detail tréninku")
    }
}

private struct TrainingHistoryRow: View {
    let session: TrainingSession

    private var outcome: GameOutcome { trainingOutcome(session) }
    private var date: Date { session.finishedAt ?? session.startedAt }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Image(systemName: outcome == .win ? "checkmark" : "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(outcome.color)
                    .accessibilityLabel(outcome == .win ? "Splněno" : "Nesplněno")
            }
            .frame(width: 40, height: 46)
            .background(outcome.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(trainingTitle(session))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let category = trainingCategory(session) {
                        Label(category.title, systemImage: category.symbol)
                    } else {
                        Label("Trénink", systemImage: "figure.strengthtraining.traditional")
                    }
                    let seconds = trainingDuration(session)
                    if seconds > 0 {
                        Text("·")
                        Text(PlayTime.format(seconds))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                Text(scoreText)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
        .accessibilityHint("Otevře detail tréninku")
    }

    private var scoreText: String {
        guard let result = session.result else { return "—" }
        if !result.summary.isEmpty, result.summary.count <= 12 { return result.summary }
        if result.higherIsBetter { return "\(result.score)" }
        return "\(result.score)"
    }
}

private struct TrainingSessionDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let session: TrainingSession
    @State private var confirmDelete = false

    private var outcome: GameOutcome { trainingOutcome(session) }
    private var definition: TrainingDefinition? { TrainingCatalog.find(session.definitionID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                FeaturedTrainingCard(session: session)
                if let result = session.result {
                    stats(result)
                }
                meta
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("Detail tréninku")
        .navigationSubtitle(definition?.title ?? "Trénink")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Smazat", systemImage: "trash")
                }
            }
        }
        .alert("Opravdu smazat tento trénink?", isPresented: $confirmDelete) {
            Button("Smazat trénink", role: .destructive) {
                store.deleteTraining(session.id)
                dismiss()
            }
            Button("Zrušit", role: .cancel) {}
        } message: {
            Text("Výsledek i získané XP z tohoto běhu budou trvale odstraněny.")
        }
    }

    private func stats(_ result: TrainingResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Výsledek")
                .font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                detailFact(outcome == .win ? "Splněno" : "Nesplněno", "stav")
                detailFact("\(result.score)", "skóre")
                detailFact("\(result.darts)", "šipek")
                detailFact("\(Int((result.accuracy * 100).rounded())) %", "přesnost")
                if let average = result.average {
                    detailFact(String(format: "%.1f", average), "průměr")
                }
                if result.oneEighties > 0 {
                    detailFact("\(result.oneEighties)", "180")
                }
                if result.checkoutAttempts > 0 {
                    detailFact("\(result.checkoutHits)/\(result.checkoutAttempts)", "checkout")
                }
                if result.bestStreak > 0 {
                    detailFact("\(result.bestStreak)", "série")
                }
            }
            if !result.summary.isEmpty {
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .surface()
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Průběh")
                .font(.headline)
            LabeledContent("Začátek", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
            if let finished = session.finishedAt {
                LabeledContent("Konec", value: finished.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Délka", value: PlayTime.format(trainingDuration(session)))
            }
            if let category = definition?.category {
                LabeledContent("Kategorie", value: category.title)
            }
            if session.config.isDaily {
                LabeledContent("Typ", value: "Denní výzva")
            } else if session.config.isWeekly {
                LabeledContent("Typ", value: "Týdenní výzva")
            }
        }
        .surface()
    }

    private func detailFact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
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
    /// Vypnout odkaz zpět do H2H, ať se nestackuje historie zápas ↔ H2H.
    var showsHeadToHeadLink = true
    @State private var page: MatchDetailPage = .overview
    @State private var focus: Int
    @State private var confirmDelete = false

    init(match: Match, profileID: UUID?, showsHeadToHeadLink: Bool = true) {
        self.match = match
        self.profileID = profileID
        self.showsHeadToHeadLink = showsHeadToHeadLink
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
            if showsHeadToHeadLink,
               match.players.count == 2,
               let me = profileID,
               match.players.contains(where: { $0.id == me }),
               let key = HeadToHead.key(forOpponentIn: match, me: me),
               let series = HeadToHead.series(from: store.matches, me: me, key: key),
               series.played > 0 {
                section("Vzájemně", symbol: "person.2.fill") {
                    NavigationLink {
                        HeadToHeadDetailView(rivalKey: key)
                    } label: {
                        HeadToHeadPreviewCard(series: series)
                    }
                    .buttonStyle(.plain)
                }
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
                        SegmentRoseChart(darts: marks, title: "", compact: true)
                            .frame(width: 108, height: 108)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Rozložení hodů").font(.headline)
                            Text(boardSummary(marks))
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

    private func boardSummary(_ marks: [Dart]) -> String {
        let count = czechCount(marks.count, "šipka", "šipky", "šipek")
        guard let best = SegmentSpread.make(marks).best, best.count > 0 else { return count }
        return "Nejvíc na \(best.segment) · \(count)"
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
    guard match.countsForCompetitiveRecord else { return .practice }
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

#if DEBUG
#Preview("Historie") {
    NavigationStack { HistoryView() }.dartiqoPreview()
}
#Preview("Detail") {
    let store = PreviewSupport.store(finished: true)
    NavigationStack {
        MatchDetailView(match: store.activeMatch!, profileID: store.profile?.id)
    }
    .dartiqoPreview(store)
}
#endif
