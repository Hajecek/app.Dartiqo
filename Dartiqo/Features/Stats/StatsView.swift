import Charts
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
    var symbol: String { self == .newest ? "arrow.down" : "arrow.up" }
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

    private var modeMatches: [Match] {
        store.matches.filter { match in
            switch mode {
            case .all: return true
            case .game(let game): return match.config.mode == game
            case .training: return false
            }
        }
    }

    private var matches: [Match] {
        let filtered = modeMatches.filter { match in
            switch result {
            case .all: return true
            case .wins: return outcome(match) == .win
            case .losses: return outcome(match) == .loss
            }
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
                ContentUnavailableView(
                    mode.isTraining ? "Zatím žádné tréninky" : "Zatím žádné zápasy",
                    systemImage: mode.isTraining ? "figure.strengthtraining.traditional" : "clock.arrow.circlepath",
                    description: Text(mode.isTraining
                        ? "Dokončené tréninky se uloží sem včetně výsledku a statistik."
                        : "Dokončené hry se uloží sem včetně výsledku, statistik a hodů.")
                )
                .historyRow(top: 60)
            } else if mode.isTraining {
                trainingList
            } else {
                matchList
            }
        }
        .listStyle(.plain)
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
        .sensoryFeedback(.selection, trigger: order)
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
        record
            .historyRow(top: 8, bottom: 10)
        resultPicker
            .historyRow(bottom: 2)

        if matches.isEmpty {
            noResults("Žádný zápas neodpovídá")
        } else {
            ForEach(historyGroups(matches)) { group in
                monthHeader(group.title, count: czechCount(group.matches.count, "zápas", "zápasy", "zápasů"))
                ForEach(group.matches) { match in
                    matchLink(match)
                }
            }
        }
    }

    @ViewBuilder
    private var trainingList: some View {
        trainingRecord
            .historyRow(top: 8, bottom: 10)
        resultPicker
            .historyRow(bottom: 2)

        if trainings.isEmpty {
            noResults("Žádný trénink neodpovídá")
        } else {
            ForEach(trainingGroups(trainings)) { group in
                monthHeader(group.title, count: czechCount(group.sessions.count, "trénink", "tréninky", "tréninků"))
                ForEach(group.sessions) { session in
                    trainingLink(session)
                }
            }
        }
    }

    private var resultPicker: some View {
        Picker("Výsledek", selection: $result) {
            ForEach(HistoryResultFilter.allCases) { item in
                Text(item.title(training: mode.isTraining)).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private func monthHeader(_ title: String, count: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.prefix(1).uppercased() + title.dropFirst())
                .font(.headline)
            Spacer(minLength: 8)
            Text(count)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .historyRow(top: 18, bottom: 4)
    }

    private func noResults(_ title: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "line.3.horizontal.decrease.circle",
            description: Text("Zkus jiný výsledek nebo režim v horní liště.")
        )
        .historyRow(top: 24)
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

    private func matchLink(_ match: Match) -> some View {
        Button {
            selectedMatch = match.id
        } label: {
            MatchHistoryRow(match: match, outcome: outcome(match))
        }
        .buttonStyle(HistoryPressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Button("Smazat zápas", systemImage: "trash", role: .destructive) {
                pendingDelete = .match(match.id)
            }
        }
        .historyRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDelete = .match(match.id)
            } label: {
                Label("Smazat", systemImage: "trash")
            }
            .tint(.red)
        }
    }

    private func trainingLink(_ session: TrainingSession) -> some View {
        Button {
            selectedTraining = session.id
        } label: {
            TrainingHistoryRow(session: session)
        }
        .buttonStyle(HistoryPressStyle())
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contextMenu {
            Button("Smazat trénink", systemImage: "trash", role: .destructive) {
                pendingDelete = .training(session.id)
            }
        }
        .historyRow()
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
                Picker("Řazení", selection: $order) {
                    ForEach(HistoryOrder.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Label(order.title, systemImage: "arrow.up.arrow.down")
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

    /// Bilance bere všechny hry zvoleného režimu. Filtr výsledku mění jen seznam pod ní.
    private var record: some View {
        let games = modeMatches
        let ranked = games.filter(\.countsForCompetitiveRecord)
        let wins = ranked.filter { outcome($0) == .win }.count
        let losses = ranked.filter { outcome($0) == .loss }.count
        let draws = ranked.filter { outcome($0) == .draw }.count
        let totals = MatchTotals(games, me: store.profile?.id)
        return SummaryHero(
            eyebrow: mode == .all ? "Celková bilance" : "Bilance · \(mode.menuTitle)",
            headline: recordHeadline(wins: wins, ranked: ranked.count),
            detail: recordDetail(wins: wins, losses: losses, ranked: ranked),
            rate: ranked.isEmpty ? nil : Double(wins) / Double(ranked.count),
            rateCaption: "výher",
            tone: recordTone(wins: wins, ranked: ranked.count),
            parts: [
                .init(count: wins, label: "výhry", color: Theme.positive),
                .init(count: draws, label: "remízy", color: .orange),
                .init(count: losses, label: "prohry", color: .red)
            ],
            stats: [
                .init(value: "\(games.count)", label: "Zápasy"),
                .init(value: totals.average, label: "Průměr X01"),
                .init(value: totals.bestTurn > 0 ? "\(totals.bestTurn)" : "—", label: "Nejlepší kolo"),
                .init(value: "\(totals.oneEighties)", label: "180"),
                .init(value: totals.bestCheckout > 0 ? "\(totals.bestCheckout)" : "—", label: "Max checkout"),
                .init(value: totals.darts.formatted(), label: "Šipek")
            ],
            form: ranked.prefix(8).map(outcome),
            seconds: totals.seconds
        )
    }

    private var trainingRecord: some View {
        let all = store.trainingHistory
        let results = all.compactMap(\.result)
        let done = results.filter(\.success).count
        let miss = all.count - done
        let accuracy = results.isEmpty ? nil : results.reduce(0.0) { $0 + $1.accuracy } / Double(results.count)
        let challenges = all.filter { $0.config.isDaily || $0.config.isWeekly }.count
        return SummaryHero(
            eyebrow: "Celkem v tréninku",
            headline: trainingHeadline(done: done, total: all.count),
            detail: all.isEmpty ? "Zatím bez dokončených tréninků" : "\(done) splněno · \(miss) nesplněno",
            rate: all.isEmpty ? nil : Double(done) / Double(all.count),
            rateCaption: "splněno",
            tone: recordTone(wins: done, ranked: all.count),
            parts: [
                .init(count: done, label: "splněno", color: Theme.positive),
                .init(count: miss, label: "nesplněno", color: .red)
            ],
            stats: [
                .init(value: "\(all.count)", label: "Tréninky"),
                .init(value: accuracy.map { "\(Int(($0 * 100).rounded())) %" } ?? "—", label: "Přesnost"),
                .init(value: results.reduce(0) { $0 + $1.darts }.formatted(), label: "Šipek"),
                .init(value: "\(results.map(\.bestStreak).max() ?? 0)", label: "Nejdelší série"),
                .init(value: "\(results.reduce(0) { $0 + $1.oneEighties })", label: "180"),
                .init(value: "\(challenges)", label: "Výzvy")
            ],
            form: all.prefix(8).map(trainingOutcome),
            formSymbols: true,
            seconds: all.reduce(0.0) { $0 + trainingDuration($1) }
        )
    }

    private func recordTone(wins: Int, ranked: Int) -> Color {
        guard ranked > 0 else { return .secondary }
        if wins > ranked / 2 { return Theme.positive }
        if wins * 2 == ranked { return .orange }
        return .red
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

/// Celková čísla hráče přes zvolené zápasy. Průměr, kola a checkout jen z X01.
private struct MatchTotals {
    var seconds: TimeInterval = 0
    var darts = 0
    var bestTurn = 0
    var oneEighties = 0
    var bestCheckout = 0
    private var x01Points = 0
    private var x01Darts = 0

    init(_ matches: [Match], me: UUID?) {
        for match in matches {
            seconds += match.playedDuration
            if match.onlineForfeit == true { continue }
            guard let index = match.players.firstIndex(where: { $0.id == me }) else { continue }
            let own = match.visits.filter { $0.player == index }
            let thrown = own.reduce(0) { $0 + $1.darts.count }
            darts += thrown
            guard match.config.mode == .x01 else { continue }
            x01Points += own.reduce(0) { $0 + $1.credited }
            x01Darts += thrown
            bestTurn = max(bestTurn, own.map(\.credited).max() ?? 0)
            oneEighties += own.filter { $0.credited == 180 }.count
            bestCheckout = max(bestCheckout, own.filter(\.checkout).map(\.credited).max() ?? 0)
        }
    }

    var average: String {
        guard x01Darts > 0 else { return "—" }
        return String(format: "%.1f", Double(x01Points) / Double(x01Darts) * 3)
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
    /// Malý odznak na avataru a ve štítku výsledku.
    var badgeSymbol: String {
        switch self {
        case .win: return "checkmark"
        case .loss: return "xmark"
        case .draw: return "equal"
        case .practice: return "person.fill"
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
    /// Barva textu výsledku na běžném pozadí karty.
    var ink: Color {
        switch self {
        case .win: return Theme.positive
        case .loss: return .red
        case .draw: return .orange
        case .practice: return .secondary
        }
    }
    /// Text a ikona položená na plnou `color`.
    var onFill: Color {
        switch self {
        case .win, .draw: return .black
        case .loss: return .white
        case .practice: return .primary
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

// MARK: Jednotný vzhled sekce Moje hry

/// Tmavý panel nahoře v přehledu i v detailu. Barva výsledku jen jemně prosvítá.
private struct HistoryHeroStyle: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack(alignment: .topLeading) {
                    Theme.heroWash
                    Circle()
                        .fill(tint.opacity(0.32))
                        .frame(width: 280, height: 280)
                        .blur(radius: 80)
                        .offset(x: -90, y: -110)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(tint.opacity(0.3), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

private struct HistoryCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        content
            .padding(16)
            .background(Theme.card, in: shape)
            .overlay(shape.stroke(Theme.stroke, lineWidth: 0.5))
    }
}

private struct HistoryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

private extension View {
    func historyHero(_ tint: Color) -> some View { modifier(HistoryHeroStyle(tint: tint)) }
    func historyCard() -> some View { modifier(HistoryCardStyle()) }
    func historyRow(top: CGFloat = 5, bottom: CGFloat = 5) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: 16, bottom: bottom, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// Dlaždice s číslem. Stejná v přehledu, v detailu zápasu i tréninku.
private struct HistoryStatCell: View {
    let value: String
    let label: String
    var icon: String?
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct HistorySection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .labelStyle(HistoryLabelStyle())
                .accessibilityAddTraits(.isHeader)
            content
        }
    }
}

private struct StatusCapsule: View {
    let outcome: GameOutcome
    let title: String

    var body: some View {
        Label(title, systemImage: outcome.badgeSymbol)
            .font(.caption.weight(.bold))
            .foregroundStyle(outcome.onFill)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(outcome.color, in: Capsule())
    }
}

private struct RateRing: View {
    let rate: Double?
    let tint: Color
    let caption: String

    private var text: String { rate.map { "\(Int(($0 * 100).rounded())) %" } ?? "—" }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.1), lineWidth: 8)
            if let rate, rate > 0 {
                Circle()
                    .trim(from: 0, to: rate)
                    .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.55), radius: 6)
            }
            VStack(spacing: 0) {
                Text(text)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(caption)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text) \(caption)")
    }
}

/// Celkové statistiky nahoře v Moje hry. Pro zápasy i trénink stejné rozložení.
private struct SummaryHero: View {
    struct Part {
        let count: Int
        let label: String
        let color: Color
    }

    struct Stat: Identifiable {
        var id: String { label }
        let value: String
        let label: String
    }

    let eyebrow: String
    let headline: String
    let detail: String
    let rate: Double?
    let rateCaption: String
    let tone: Color
    let parts: [Part]
    let stats: [Stat]
    let form: [GameOutcome]
    var formSymbols = false
    let seconds: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                RateRing(rate: rate, tint: tone, caption: rateCaption)
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: eyebrow)
                    Text(headline)
                        .font(.title3.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)

            VStack(spacing: 10) {
                shareBar
                HStack(spacing: 0) {
                    ForEach(parts, id: \.label) { part in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(part.color)
                                .frame(width: 7, height: 7)
                            Text("\(part.count)")
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .monospacedDigit()
                            Text(part.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(stats) { stat in
                    HistoryStatCell(value: stat.value, label: stat.label)
                }
            }

            VStack(spacing: 12) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 1)
                if !form.isEmpty {
                    formRow
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label("Celkem u terče", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    PlayTimeLabel(seconds: seconds, layout: .inline)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .historyHero(tone)
    }

    private var shareBar: some View {
        let visible = parts.filter { $0.count > 0 }
        let total = visible.reduce(0) { $0 + $1.count }
        return GeometryReader { geo in
            if total == 0 {
                Capsule().fill(Color.primary.opacity(0.1))
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

    private var formRow: some View {
        HStack(spacing: 10) {
            Text("Forma")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                ForEach(Array(form.enumerated()), id: \.offset) { _, item in
                    Group {
                        if formSymbols {
                            Image(systemName: item.badgeSymbol)
                                .font(.system(size: 10, weight: .black))
                        } else {
                            Text(item.shortTitle)
                                .font(.caption2.weight(.heavy))
                        }
                    }
                    .foregroundStyle(item.onFill)
                    .frame(width: 22, height: 22)
                    .background(item.color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Forma: \(form.map(\.title).joined(separator: ", "))")
    }
}

/// Jeden řádek seznamu. Zápas i trénink mají stejnou kostru, liší se jen ikonou vlevo a skóre.
private struct HistoryRowCard<Leading: View, Score: View>: View {
    let outcome: GameOutcome
    let status: String
    let title: String
    let detail: String
    let badge: String?
    let leading: Leading
    let score: Score

    init(
        outcome: GameOutcome,
        status: String,
        title: String,
        detail: String,
        badge: String? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder score: () -> Score
    ) {
        self.outcome = outcome
        self.status = status
        self.title = title
        self.detail = detail
        self.badge = badge
        self.leading = leading()
        self.score = score()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        HStack(spacing: 12) {
            leading
                .frame(width: 44, height: 44)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: outcome.badgeSymbol)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(outcome.onFill)
                        .frame(width: 18, height: 18)
                        .background(outcome.color, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                        .offset(x: 4, y: 4)
                }

            VStack(alignment: .leading, spacing: 3) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.18), in: Capsule())
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                score
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(status.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(outcome.ink)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            shape.fill(Theme.card)
                .overlay(alignment: .leading) {
                    LinearGradient(colors: [outcome.color.opacity(0.16), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 150)
                }
                .clipShape(shape)
        }
        .overlay(shape.stroke(Theme.stroke, lineWidth: 0.5))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
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

private func historyDay(_ date: Date) -> String {
    date.formatted(.dateTime.day().month(.abbreviated))
}

/// Hlavička detailu tréninku. Stejný tmavý panel jako bilance a detail zápasu.
private struct TrainingHero: View {
    @EnvironmentObject private var store: AppStore
    let session: TrainingSession

    private var outcome: GameOutcome { trainingOutcome(session) }
    private var category: TrainingCategory? { trainingCategory(session) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                StatusCapsule(outcome: outcome, title: outcome == .win ? "Splněno" : "Nesplněno")
                Spacer(minLength: 8)
                Text((session.finishedAt ?? session.startedAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                Avatar(name: store.profile?.name ?? "", size: 52, photo: store.profile?.photoJPEG)
                    .overlay(Circle().strokeBorder(outcome.color, lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Label(category?.title ?? "Trénink", systemImage: category?.symbol ?? "figure.strengthtraining.traditional")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(trainingTitle(session))
                        .font(.title2.bold())
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if let summary = session.result?.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                if let result = session.result, result.darts > 0 {
                    Label(czechCount(result.darts, "šipka", "šipky", "šipek"), systemImage: "smallcircle.filled.circle")
                }
                Spacer(minLength: 8)
                let seconds = trainingDuration(session)
                if seconds > 0 {
                    Label(PlayTime.format(seconds), systemImage: "clock")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .historyHero(outcome.color)
        .accessibilityElement(children: .combine)
    }
}

private struct TrainingHistoryRow: View {
    let session: TrainingSession

    private var outcome: GameOutcome { trainingOutcome(session) }

    var body: some View {
        HistoryRowCard(
            outcome: outcome,
            status: outcome == .win ? "Splněno" : "Nesplněno",
            title: trainingTitle(session),
            detail: detail
        ) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.14))
                Image(systemName: trainingCategory(session)?.symbol ?? "figure.strengthtraining.traditional")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        } score: {
            Text(scoreText)
        }
        .accessibilityHint("Otevře detail tréninku")
    }

    private var detail: String {
        var parts = [historyDay(session.finishedAt ?? session.startedAt)]
        parts.append(trainingCategory(session)?.title ?? "Trénink")
        let seconds = trainingDuration(session)
        if seconds > 0 { parts.append(PlayTime.format(seconds)) }
        return parts.joined(separator: " · ")
    }

    private var scoreText: String {
        guard let result = session.result else { return "—" }
        if !result.summary.isEmpty, result.summary.count <= 12 { return result.summary }
        return "\(result.score)"
    }
}

private struct TrainingSessionDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let session: TrainingSession
    @State private var confirmDelete = false

    private var definition: TrainingDefinition? { TrainingCatalog.find(session.definitionID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                TrainingHero(session: session)
                if let result = session.result {
                    HistorySection(title: "Výsledek", symbol: "chart.bar.fill") { stats(result) }
                }
                HistorySection(title: "Průběh", symbol: "flag.checkered") { meta }
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
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                HistoryStatCell(value: "\(result.score)", label: "Skóre", icon: "sum", tint: Theme.positive)
                HistoryStatCell(value: "\(result.darts)", label: "Šipek", icon: "smallcircle.filled.circle", tint: .blue)
                HistoryStatCell(value: "\(Int((result.accuracy * 100).rounded())) %", label: "Přesnost", icon: "scope", tint: Theme.positive)
                if let average = result.average {
                    HistoryStatCell(value: String(format: "%.1f", average), label: "Průměr", icon: "chart.line.uptrend.xyaxis", tint: .purple)
                }
                if result.oneEighties > 0 {
                    HistoryStatCell(value: "\(result.oneEighties)", label: "180", icon: "flame.fill", tint: .red)
                }
                if result.checkoutAttempts > 0 {
                    HistoryStatCell(value: "\(result.checkoutHits)/\(result.checkoutAttempts)", label: "Checkout", icon: "checkmark.seal.fill", tint: Theme.positive)
                }
                if result.bestStreak > 0 {
                    HistoryStatCell(value: "\(result.bestStreak)", label: "Série", icon: "bolt.fill", tint: .orange)
                }
            }
            if !result.summary.isEmpty {
                Text(result.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !result.visitScores.isEmpty {
                trainingRounds(result.visitScores)
            }
            if !result.tallies.isEmpty {
                trainingAims(result.tallies)
            }
        }
        .historyCard()
    }

    private func trainingRounds(_ scores: [Int]) -> some View {
        let shown = Array(scores.prefix(18))
        let peak = max(shown.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Kola")
                .font(.subheadline.weight(.semibold))
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(shown.enumerated()), id: \.offset) { _, score in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(score >= 100 ? Color.red.opacity(0.85) : Theme.positive)
                        .frame(height: max(8, 68 * CGFloat(score) / CGFloat(peak)))
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("Kolo \(score)")
                }
            }
            .frame(height: 72, alignment: .bottom)
        }
    }

    private func trainingAims(_ tallies: [AimTally]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Zásahy")
                .font(.subheadline.weight(.semibold))
            ForEach(tallies.prefix(8)) { tally in
                HStack(spacing: 10) {
                    Text(tally.key)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 56, alignment: .leading)
                        .lineLimit(1)
                    ProgressView(value: tally.rate)
                        .tint(Theme.positive)
                    Text("\(tally.hits)/\(tally.attempts)")
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .trailing)
                }
            }
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        .historyCard()
    }
}

private struct MatchHistoryRow: View {
    @EnvironmentObject private var store: AppStore
    let match: Match
    let outcome: GameOutcome

    private var me: Int? { match.players.firstIndex { $0.id == store.profile?.id } }
    private var rivals: [Int] { match.players.indices.filter { $0 != me && match.players[$0].id != store.profile?.id } }

    var body: some View {
        HistoryRowCard(
            outcome: outcome,
            status: rowStatus,
            title: title,
            detail: detail,
            badge: match.playedOnline == true ? "ONLINE" : nil
        ) {
            avatar(rivals.first ?? me ?? 0)
        } score: {
            HStack(spacing: 3) {
                ForEach(Array(match.players.indices.enumerated()), id: \.offset) { offset, index in
                    if offset > 0 {
                        Text(":").foregroundStyle(.tertiary)
                    }
                    Text("\(tally(index))")
                        .foregroundStyle(index == me ? outcome.ink : .primary)
                }
            }
        }
        .accessibilityHint("Otevře detail zápasu")
    }

    private var rowStatus: String {
        if match.playedOnline == true, match.winner == nil { return "Vzdáno" }
        return outcome == .practice ? "Sólo" : outcome.title
    }

    private var title: String {
        guard me != nil else { return match.players.map(\.name).joined(separator: " vs ") }
        if rivals.isEmpty { return "Sólo · \(match.players.first?.name ?? "")" }
        return "vs " + rivals.map { match.players[$0].name }.joined(separator: ", ")
    }

    private var detail: String {
        var parts = [historyDay(match.completedAt ?? match.createdAt), match.config.mode.shortTitle]
        if match.playedDuration > 0 { parts.append(PlayTime.format(match.playedDuration)) }
        return parts.joined(separator: " · ")
    }

    private func avatar(_ index: Int) -> some View {
        let player = match.players[index]
        return Avatar(
            name: player.name,
            bot: player.botLevel != nil,
            size: 44,
            photo: store.photo(for: player.id),
            asset: player.botLevel.map { BotLevel.get($0).photo }
        )
    }

    private func tally(_ index: Int) -> Int {
        match.config.playsSets ? match.states[index].sets : match.states[index].legs
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
    case overview, stats, board, visits
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Přehled"
        case .stats: return "Statistiky"
        case .board: return "Terč"
        case .visits: return "Hody"
        }
    }
}

private enum BoardLens: String, CaseIterable, Identifiable {
    case heat, impacts, fields
    var id: String { rawValue }
    var title: String {
        switch self {
        case .heat: return "Heatmapa"
        case .impacts: return "Dopady"
        case .fields: return "Pole"
        }
    }
}

/// Barva hráče v grafech a lištách. První hráč má akcent, ať je čitelný i ve světlém režimu.
private func playerTint(_ index: Int) -> Color {
    index == 0 ? Theme.accent : Theme.playerColor(index)
}

private func scoreBandColor(_ credited: Int, bust: Bool = false) -> Color {
    if bust { return Color.secondary.opacity(0.4) }
    switch credited {
    case 180...: return .red
    case 140..<180: return .orange
    case 100..<140: return Color(red: 0.95, green: 0.78, blue: 0.15)
    case 60..<100: return Theme.positive
    case 40..<60: return Color(red: 0.25, green: 0.72, blue: 0.78)
    default: return Color(red: 0.35, green: 0.55, blue: 0.95)
    }
}

/// Čísla jednoho hráče v zápase. Sdílí je souboj, statistiky i tabulka legů.
private struct PlayerLine {
    let index: Int
    let visits: [Visit]
    let darts: Int
    let average: Double
    let firstNine: Double
    let best: Int
    let maxes: Int
    let ton40: Int
    let tons: Int
    let busts: Int
    let checkout: CheckoutStats
    let bestLeg: Int?
    let legs: Int

    init(match: Match, index: Int) {
        self.index = index
        let own = match.visits.filter { $0.player == index }
        visits = own
        darts = own.reduce(0) { $0 + $1.darts.count }
        average = match.average(for: index)
        best = own.map(\.credited).max() ?? 0
        maxes = own.filter { $0.credited == 180 }.count
        ton40 = own.filter { (140..<180).contains($0.credited) }.count
        tons = own.filter { (100..<140).contains($0.credited) }.count
        busts = own.filter(\.bust).count
        checkout = match.config.mode == .x01 ? CheckoutStats.make(from: match, player: index) : CheckoutStats()
        legs = match.states.indices.contains(index) ? match.states[index].legs : 0

        var openingPoints = 0
        var openingDarts = 0
        var fastest: Int?
        for leg in Set(own.map(\.leg)) {
            let legVisits = own.filter { $0.leg == leg }
            let opening = legVisits.prefix(3)
            openingPoints += opening.reduce(0) { $0 + $1.credited }
            openingDarts += opening.reduce(0) { $0 + $1.darts.count }
            if legVisits.contains(where: \.checkout) {
                let count = legVisits.reduce(0) { $0 + $1.darts.count }
                fastest = min(fastest ?? count, count)
            }
        }
        firstNine = openingDarts > 0 ? Double(openingPoints) * 3 / Double(openingDarts) : 0
        bestLeg = fastest
    }
}

private struct CompareRow: Identifiable {
    let label: String
    let values: [Double?]
    var decimals = 0
    var suffix = ""
    var lowerIsBetter = false
    var neutral = false
    var id: String { label }

    func text(_ slot: Int) -> String {
        guard values.indices.contains(slot), let value = values[slot] else { return "—" }
        let number = decimals > 0 ? String(format: "%.\(decimals)f", value) : "\(Int(value.rounded()))"
        return number + suffix
    }

    var leader: Int? {
        guard !neutral else { return nil }
        let known = values.enumerated().compactMap { offset, value in value.map { (offset, $0) } }
        guard known.count > 1 else { return nil }
        let sorted = known.sorted { lowerIsBetter ? $0.1 < $1.1 : $0.1 > $1.1 }
        guard sorted[0].1 != sorted[1].1 else { return nil }
        return sorted[0].0
    }

    /// Podíl prvního hráče na liště souboje. U „méně je lépe“ se poměr otočí.
    var split: Double? {
        guard values.count == 2, let a = values[0], let b = values[1], a + b > 0 else { return nil }
        return lowerIsBetter ? b / (a + b) : a / (a + b)
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
    @State private var raceLeg: Int?
    @State private var boardLeg: Int?
    @State private var boardLens: BoardLens = .heat
    @State private var visitsLeg: Int?

    init(match: Match, profileID: UUID?, showsHeadToHeadLink: Bool = true) {
        self.match = match
        self.profileID = profileID
        self.showsHeadToHeadLink = showsHeadToHeadLink
        let people = MatchDetailView.statPlayers(in: match)
        let start = people.first { match.players[$0].id == profileID } ?? people.first ?? match.winner ?? 0
        _focus = State(initialValue: start)
    }

    /// Statistiky patří jen klasickým hráčům. Bot a ghost v přehledu nejsou.
    private static func statPlayers(in match: Match) -> [Int] {
        let people = match.players.indices.filter(match.isClassicPlayer)
        return people.isEmpty ? Array(match.players.indices) : people
    }

    private var statPlayers: [Int] { Self.statPlayers(in: match) }

    private var playerIndex: Int { statPlayers.contains(focus) ? focus : (statPlayers.first ?? 0) }

    private var legs: [Int] { Array(Set(match.visits.map(\.leg))).sorted() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHero
                Picker("Část detailu", selection: $page) {
                    ForEach(MatchDetailPage.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                switch page {
                case .overview: overview
                case .stats: statistics(playerIndex)
                case .board: boardPage(playerIndex)
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
        .sensoryFeedback(.selection, trigger: boardLens)
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
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Section {
                    NavigationLink {
                        VisitLog(game: match)
                    } label: {
                        Label("Podrobný záznam hodů", systemImage: "list.bullet")
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

    private func detailStatus(_ result: GameOutcome) -> String {
        if match.playedOnline == true, match.winner == nil { return "Vzdáno" }
        return result == .practice ? "Sólo" : result.title
    }

    private var detailHero: some View {
        let result = outcome(match, profileID: profileID)
        return VStack(spacing: 16) {
            HStack {
                StatusCapsule(outcome: result, title: detailStatus(result))
                if match.playedOnline == true {
                    Text("ONLINE")
                        .font(.system(size: 9, weight: .heavy))
                        .tracking(0.6)
                        .foregroundStyle(.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 8)
                Text((match.completedAt ?? match.createdAt).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MatchScoreline(match: match, dark: true)
            HStack(spacing: 10) {
                Label(match.config.mode.shortTitle, systemImage: match.config.mode.symbol)
                Text(match.config.lengthLine)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if match.playedDuration > 0 {
                    Label(PlayTime.format(match.playedDuration), systemImage: "clock")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .historyHero(result.color)
    }

    private func section<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        HistorySection(title: title, symbol: symbol, content: content)
    }

    // MARK: Přehled

    @ViewBuilder
    private var overview: some View {
        let lines = match.players.indices.map { PlayerLine(match: match, index: $0) }
        VStack(alignment: .leading, spacing: 22) {
            if match.players.count == 2 {
                section("Souboj v číslech", symbol: "person.2.fill") {
                    DuelCard(match: match, rows: compareRows(lines))
                }
            } else if match.players.count > 2 {
                section("Srovnání hráčů", symbol: "person.3.fill") {
                    CompareTable(match: match, rows: compareRows(lines))
                }
            } else {
                section("Výkon", symbol: "chart.bar.fill") { playerCard(playerIndex) }
            }

            if !legs.isEmpty {
                section("Průběh legu", symbol: "chart.xyaxis.line") { raceCard }
            }

            section("Legy", symbol: "flag.checkered") { legList }

            if showsHeadToHeadLink,
               match.players.count == 2,
               let me = profileID,
               match.players.contains(where: { $0.id == me }),
               let key = HeadToHead.key(forOpponentIn: match, me: me),
               let series = HeadToHead.series(from: store.matches, me: me, key: key),
               series.played > 0 {
                section("Vzájemně", symbol: "person.2.circle.fill") {
                    NavigationLink {
                        HeadToHeadDetailView(rivalKey: key)
                    } label: {
                        HeadToHeadPreviewCard(series: series)
                    }
                    .buttonStyle(.plain)
                }
            }

            section("O zápase", symbol: "info.circle") { infoCard }
        }
    }

    private func compareRows(_ lines: [PlayerLine]) -> [CompareRow] {
        func row(
            _ label: String,
            decimals: Int = 0,
            suffix: String = "",
            lower: Bool = false,
            neutral: Bool = false,
            _ value: (PlayerLine) -> Double?
        ) -> CompareRow {
            CompareRow(label: label, values: lines.map(value), decimals: decimals, suffix: suffix, lowerIsBetter: lower, neutral: neutral)
        }
        switch match.config.mode {
        case .x01:
            return [
                row("Průměr", decimals: 1) { $0.darts > 0 ? $0.average : nil },
                row("Prvních 9", decimals: 1) { $0.firstNine > 0 ? $0.firstNine : nil },
                row("Na double", suffix: " %") { $0.checkout.percentage },
                row("Nejvyšší checkout") { $0.checkout.highest > 0 ? Double($0.checkout.highest) : nil },
                row("Nejlepší kolo") { Double($0.best) },
                row("180") { Double($0.maxes) },
                row("140+") { Double($0.ton40) },
                row("100+") { Double($0.tons) },
                row("Šipek na leg", lower: true) { $0.bestLeg.map(Double.init) }
            ]
        case .cricket, .countUp:
            return [
                row("Body") { Double(match.states[$0.index].points) },
                row("Body na kolo", decimals: 1) { $0.darts > 0 ? $0.average : nil },
                row("Nejlepší kolo") { Double($0.best) },
                row("Kola", neutral: true) { Double($0.visits.count) }
            ]
        case .aroundClock:
            return [
                row("Cíl") { Double(min(match.states[$0.index].clockTarget, 21)) },
                row("Šipky", lower: true) { Double($0.darts) },
                row("Kola", neutral: true) { Double($0.visits.count) }
            ]
        }
    }

    private var raceCard: some View {
        let leg = raceLeg.flatMap { legs.contains($0) ? $0 : nil } ?? legs.last ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            if legs.count > 1 {
                LegChips(legs: legs, selection: Binding<Int?>(get: { leg }, set: { raceLeg = $0 }))
            }
            LegRaceChart(match: match, leg: leg)
            HStack(spacing: 14) {
                ForEach(match.players.indices, id: \.self) { index in
                    HStack(spacing: 6) {
                        Capsule().fill(playerTint(index)).frame(width: 14, height: 4)
                        Text(match.players[index].name)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            Text(match.config.mode == .x01
                 ? "Kolik zbývalo po každém kole. Vlajka značí zavření legu."
                 : "Body nasbírané po jednotlivých kolech.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .historyCard()
    }

    private var legList: some View {
        let darts = match.visits.reduce(0) { $0 + $1.darts.count }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                flowFact("\(legs.count)", czech(legs.count, "leg", "legy", "legů"))
                Divider().frame(height: 34)
                flowFact("\(match.visits.count)", czech(match.visits.count, "kolo", "kola", "kol"))
                Divider().frame(height: 34)
                flowFact("\(darts)", czech(darts, "šipka", "šipky", "šipek"))
            }
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(spacing: 0) {
                ForEach(Array(legs.enumerated()), id: \.element) { offset, leg in
                    legRow(leg, last: offset == legs.count - 1)
                }
            }
        }
        .historyCard()
    }

    private func legRow(_ leg: Int, last: Bool) -> some View {
        let winner = winnerForLeg(leg, lastLeg: legs.last)
        return HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text("\(leg)")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .frame(width: 32, height: 32)
                    .background((winner.map(playerTint) ?? Color.secondary).opacity(0.22), in: Circle())
                    .overlay(Circle().strokeBorder(winner.map(playerTint) ?? Color.secondary.opacity(0.4), lineWidth: 1.5))
                if !last {
                    Rectangle()
                        .fill(Theme.stroke)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    if let winner {
                        Avatar(
                            name: match.players[winner].name,
                            bot: match.players[winner].botLevel != nil,
                            size: 24,
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
                    Spacer(minLength: 8)
                    Text(runningScore(through: leg))
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(legDetail(leg))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.bottom, last ? 0 : 16)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var infoCard: some View {
        let start = match.resolvedOpeningStarter
        return VStack(spacing: 0) {
            infoRow("Režim", match.config.mode.title, symbol: match.config.mode.symbol)
            if match.playedOnline == true {
                Divider()
                infoRow("Podoba", "Online", symbol: "wifi")
            }
            Divider()
            infoRow("Pravidla", match.config.summary, symbol: "list.bullet.rectangle")
            Divider()
            infoRow("Datum", (match.completedAt ?? match.createdAt).formatted(date: .long, time: .shortened), symbol: "calendar")
            if match.playedDuration > 0 {
                Divider()
                infoRow("Čas u terče", PlayTime.format(match.playedDuration), symbol: "clock")
            }
            if match.players.indices.contains(start) {
                Divider()
                infoRow("Začínal", match.players[start].name, symbol: "play.circle")
            }
        }
        .padding(.vertical, -6)
        .historyCard()
    }

    private func infoRow(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
                .fixedSize()
            Spacer(minLength: 8)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
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

    private func runningScore(through leg: Int) -> String {
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
                return "Checkout \(checkout.credited) · \(route) · \(czechCount(darts, "šipka", "šipky", "šipek"))"
            }
            return "Checkout \(checkout.credited) · \(czechCount(darts, "šipka", "šipky", "šipek"))"
        }
        return "\(czechCount(visits.count, "kolo", "kola", "kol")) · \(czechCount(darts, "šipka", "šipky", "šipek"))"
    }

    // MARK: Statistiky

    private func statistics(_ index: Int) -> some View {
        let line = PlayerLine(match: match, index: index)
        return VStack(alignment: .leading, spacing: 22) {
            if statPlayers.count > 1 {
                playerStrip
            }
            section("Výkon", symbol: "chart.bar.fill") { playerCard(index) }
            if !line.visits.isEmpty {
                section("Kola v zápase", symbol: "chart.bar.xaxis") { visitChart(line) }
            }
            if match.config.mode == .x01 {
                section("Rozložení kol", symbol: "square.stack.3d.up.fill") { scoringBands(line) }
                if line.checkout.hasData {
                    section("Zavírání", symbol: "checkmark.seal.fill") {
                        CheckoutStatsView(stats: line.checkout).historyCard()
                    }
                }
            }
            if !line.visits.isEmpty {
                section("Legy hráče", symbol: "list.number") { legTable(line) }
            }
        }
    }

    private var playerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(statPlayers, id: \.self) { index in
                    Button { focus = index } label: {
                        HStack(spacing: 7) {
                            Avatar(name: match.players[index].name, bot: match.players[index].botLevel != nil, size: 28, photo: store.photo(for: match.players[index].id), asset: match.players[index].botLevel.map { BotLevel.get($0).photo })
                            Text(playerName(index)).lineLimit(1)
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.leading, 5)
                        .padding(.trailing, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(index == playerIndex ? Theme.onAccent : .primary)
                        .background(index == playerIndex ? Theme.accentFill : Theme.card, in: Capsule())
                        .overlay(Capsule().stroke(Theme.stroke, lineWidth: index == playerIndex ? 0 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(index == playerIndex ? .isSelected : [])
                }
            }
        }
    }

    private func playerCard(_ index: Int) -> some View {
        let line = PlayerLine(match: match, index: index)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Avatar(name: match.players[index].name, bot: match.players[index].botLevel != nil, size: 56, photo: store.photo(for: match.players[index].id), asset: match.players[index].botLevel.map { BotLevel.get($0).photo })
                    .overlay(Circle().strokeBorder(match.winner == index ? Theme.positive : Theme.stroke, lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(playerName(index)).font(.headline).lineLimit(1)
                        if match.winner == index {
                            Image(systemName: "crown.fill").font(.caption).foregroundStyle(Theme.positive)
                        }
                    }
                    Text("\(czechCount(line.visits.count, "kolo", "kola", "kol")) · \(czechCount(line.darts, "šipka", "šipky", "šipek"))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(String(format: "%.1f", line.average))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.positive)
                    Text(match.config.mode == .x01 ? "průměr" : "bodů na kolo")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(metrics(line), id: \.label) { item in
                    HistoryStatCell(value: item.value, label: item.label, icon: item.icon, tint: item.tint)
                }
            }
        }
        .historyCard()
    }

    private func metrics(_ line: PlayerLine) -> [(value: String, label: String, icon: String, tint: Color)] {
        let index = line.index
        switch match.config.mode {
        case .x01:
            return [
                (line.firstNine > 0 ? String(format: "%.1f", line.firstNine) : "—", "Prvních 9", "9.circle.fill", .blue),
                (line.checkout.percentage.map { "\(Int($0.rounded())) %" } ?? "—", "Na double", "scope", Theme.positive),
                ("\(line.best)", "Nejlepší kolo", "star.fill", .orange),
                ("\(line.maxes)", "180", "flame.fill", .red),
                ("\(line.visits.filter(\.checkout).count)", "Zavření", "checkmark.seal.fill", Theme.positive),
                ("\(line.busts)", "Přehozy", "arrow.uturn.backward", .red),
                (line.checkout.highest > 0 ? "\(line.checkout.highest)" : "—", "Nejvyšší checkout", "trophy.fill", .orange),
                (line.bestLeg.map(String.init) ?? "—", "Šipek na leg", "stopwatch.fill", .purple)
            ]
        case .cricket, .countUp:
            return [
                ("\(match.states[index].points)", "Body", "sum", Theme.positive),
                ("\(match.states[index].rounds)", "Kola", "repeat", .blue),
                ("\(line.best)", "Maximum", "star.fill", .orange),
                ("\(line.darts)", "Šipky", "smallcircle.filled.circle", .purple)
            ]
        case .aroundClock:
            return [
                (match.states[index].clockTarget >= 21 ? "Hotovo" : "\(match.states[index].clockTarget)", "Cíl", "target", Theme.positive),
                ("\(line.darts)", "Šipky", "smallcircle.filled.circle", .blue),
                ("\(line.visits.count)", "Kola", "repeat", .orange)
            ]
        }
    }

    private func visitChart(_ line: PlayerLine) -> some View {
        let rows = Array(line.visits.enumerated())
        let mean = line.visits.isEmpty ? 0 : Double(line.visits.reduce(0) { $0 + $1.credited }) / Double(line.visits.count)
        let top = match.config.mode == .x01 ? 180 : max(line.best, 1)
        let barWidth = min(12, max(2, 230 / Double(max(rows.count, 1))))
        return VStack(alignment: .leading, spacing: 12) {
            Chart {
                ForEach(rows, id: \.offset) { offset, visit in
                    BarMark(
                        x: .value("Kolo", offset + 1),
                        y: .value("Body", visit.credited),
                        width: .fixed(barWidth)
                    )
                    .foregroundStyle(scoreBandColor(visit.credited, bust: visit.bust))
                    .cornerRadius(3)
                }
                RuleMark(y: .value("Průměr", mean))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Ø \(Int(mean.rounded()))")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
            }
            .chartYScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    AxisValueLabel()
                }
            }
            .frame(height: 190)

            if match.config.mode == .x01 {
                HStack(spacing: 12) {
                    bandLegend("180", .red)
                    bandLegend("140+", .orange)
                    bandLegend("100+", scoreBandColor(100))
                    bandLegend("60+", Theme.positive)
                    bandLegend("40+", scoreBandColor(40))
                    bandLegend("méně", scoreBandColor(0))
                }
            }
            Text("Každý sloupec je jedno kolo, čárkovaná čára je průměr kola.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .historyCard()
    }

    private func bandLegend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func scoringBands(_ line: PlayerLine) -> some View {
        let visits = line.visits.filter { !$0.bust }
        let bands: [BarItem] = [
            BarItem(label: "180", count: visits.filter { $0.credited == 180 }.count, color: .red),
            BarItem(label: "140+", count: visits.filter { (140..<180).contains($0.credited) }.count, color: .orange),
            BarItem(label: "100+", count: visits.filter { (100..<140).contains($0.credited) }.count, color: scoreBandColor(100)),
            BarItem(label: "60+", count: visits.filter { (60..<100).contains($0.credited) }.count, color: Theme.positive),
            BarItem(label: "40+", count: visits.filter { (40..<60).contains($0.credited) }.count, color: scoreBandColor(40)),
            BarItem(label: "pod 40", count: visits.filter { $0.credited < 40 }.count, color: scoreBandColor(0)),
            BarItem(label: "Bust", count: line.busts, color: Color.secondary.opacity(0.5))
        ]
        return BarList(items: bands, total: line.visits.count).historyCard()
    }

    private func legTable(_ line: PlayerLine) -> some View {
        let played = Array(Set(line.visits.map(\.leg))).sorted()
        return VStack(spacing: 0) {
            HStack {
                Text("Leg").frame(maxWidth: .infinity, alignment: .leading)
                Text(match.config.mode == .x01 ? "Průměr" : "Body / kolo").frame(width: 78, alignment: .trailing)
                Text("Šipky").frame(width: 52, alignment: .trailing)
                Text("Výsledek").frame(width: 78, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            ForEach(played, id: \.self) { leg in
                let visits = line.visits.filter { $0.leg == leg }
                let darts = visits.reduce(0) { $0 + $1.darts.count }
                let points = visits.reduce(0) { $0 + $1.credited }
                let won = winnerForLeg(leg, lastLeg: legs.last) == line.index
                let checkout = visits.last(where: \.checkout)?.credited
                Divider()
                HStack {
                    Text("Leg \(leg)")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(darts > 0 ? String(format: "%.1f", Double(points) / Double(darts) * 3) : "—")
                        .frame(width: 78, alignment: .trailing)
                    Text("\(darts)")
                        .frame(width: 52, alignment: .trailing)
                    Group {
                        if won {
                            Label(checkout.map { "\($0)" } ?? "Výhra", systemImage: "checkmark")
                                .foregroundStyle(Theme.positive)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(width: 78, alignment: .trailing)
                }
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .historyCard()
    }

    // MARK: Terč

    private func boardDarts(_ index: Int, leg: Int?) -> [Dart] {
        match.visits
            .filter { $0.player == index && $0.enteredAsTotal != true && (leg == nil || $0.leg == leg) }
            .flatMap(\.darts)
    }

    private func boardPage(_ index: Int) -> some View {
        let all = boardDarts(index, leg: nil)
        let legFilter = boardLeg.flatMap { legs.contains($0) ? $0 : nil }
        let darts = boardDarts(index, leg: legFilter)
        return VStack(alignment: .leading, spacing: 22) {
            if statPlayers.count > 1 {
                playerStrip
            }
            if all.isEmpty {
                ContentUnavailableView(
                    "Žádné šipky na terči",
                    systemImage: "target",
                    description: Text("Tento hráč zapisoval jen součty kol, takže není kam šipky umístit.")
                )
                .historyCard()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if legs.count > 1 {
                        LegChips(legs: legs, selection: $boardLeg, allTitle: "Celý zápas")
                    }
                    Picker("Zobrazení terče", selection: $boardLens) {
                        ForEach(BoardLens.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                boardCard(darts)
                boardFacts(darts)

                if !darts.isEmpty {
                    section("Typ zásahu", symbol: "circle.grid.3x3.fill") { hitTypes(darts) }
                    section("Nejčastější pole", symbol: "list.number") { topFields(darts) }
                }

                NavigationLink {
                    HeatmapView(darts: darts, title: match.players[index].name)
                } label: {
                    Label("Terč na celou obrazovku", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PrimaryButton())
                .disabled(darts.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func boardCard(_ darts: [Dart]) -> some View {
        switch boardLens {
        case .fields:
            SegmentRoseChart(darts: darts, title: "Podíl zásahů")
        case .heat, .impacts:
            let approximate = darts.contains { $0.x == nil && $0.segment != 0 }
            VStack(alignment: .leading, spacing: 12) {
                HeatBoard(darts: darts, lens: boardLens)
                    .padding(6)
                    .background(BoardFace.plate, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .environment(\.colorScheme, .dark)
                if boardLens == .heat {
                    HStack(spacing: 10) {
                        Text("Méně")
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 0.45, green: 0.1, blue: 0.02), .orange, .yellow, .white], startPoint: .leading, endPoint: .trailing))
                            .frame(height: 6)
                        Text("Více")
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 14) {
                        HStack(spacing: 5) {
                            Circle().fill(BoardFace.heat).frame(width: 8, height: 8)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 1.5).padding(-3))
                            Text(czechCount(darts.count, "šipka", "šipky", "šipek"))
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                Text(approximate
                     ? "Šipky zapsané tlačítky nemají přesné místo, kreslí se doprostřed svého pole."
                     : (boardLens == .heat ? "Čím světlejší místo, tím víc šipek tam dopadlo." : "Každá tečka je jedna šipka na přesném místě dopadu."))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .historyCard()
        }
    }

    private func boardFacts(_ darts: [Dart]) -> some View {
        let fields = HeatmapView.topFields(darts.filter { $0.segment != 0 })
        let bulls = darts.filter { $0.segment == 25 }.count
        let misses = darts.filter { $0.segment == 0 }.count
        let total = max(1, darts.count)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            HistoryStatCell(value: fields.first?.label ?? "—", label: "Nejčastěji")
            HistoryStatCell(value: "\(Int((Double(bulls) / Double(total) * 100).rounded())) %", label: "Bull")
            HistoryStatCell(value: "\(misses)", label: "Vedle")
        }
    }

    private func hitTypes(_ darts: [Dart]) -> some View {
        let triples = darts.filter { $0.multiplier == 3 }.count
        let doubles = darts.filter { $0.multiplier == 2 && $0.segment != 25 }.count
        let bulls = darts.filter { $0.segment == 25 }.count
        let misses = darts.filter { $0.segment == 0 }.count
        let singles = darts.count - triples - doubles - bulls - misses
        let items = [
            BarItem(label: "Triple", count: triples, color: .orange),
            BarItem(label: "Double", count: doubles, color: Theme.positive),
            BarItem(label: "Single", count: singles, color: Color(red: 0.35, green: 0.55, blue: 0.95)),
            BarItem(label: "Bull", count: bulls, color: .red),
            BarItem(label: "Vedle", count: misses, color: Color.secondary.opacity(0.5))
        ]
        return BarList(items: items, total: darts.count).historyCard()
    }

    private func topFields(_ darts: [Dart]) -> some View {
        let fields = Array(HeatmapView.topFields(darts).prefix(6))
        let total = max(1, darts.count)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.element.label) { offset, field in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(field.label == "MISS" ? "Vedle" : field.label)
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 2)
                        Text("#\(offset + 1)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(offset == 0 ? Theme.accent : Color.secondary)
                    }
                    Text("\(field.count)× · \(Int((Double(field.count) / Double(total) * 100).rounded())) %")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .historyCard()
    }

    // MARK: Hody

    private var visitsPage: some View {
        let shown = visitsLeg.flatMap { legs.contains($0) ? [$0] : nil } ?? legs
        let darts = match.visits.reduce(0) { $0 + $1.darts.count }
        return VStack(alignment: .leading, spacing: 22) {
            if legs.count > 1 {
                LegChips(legs: legs, selection: $visitsLeg, allTitle: "Všechny legy")
            }
            HStack(spacing: 0) {
                flowFact("\(match.visits.count)", czech(match.visits.count, "kolo", "kola", "kol"))
                Divider().frame(height: 34)
                flowFact("\(darts)", czech(darts, "šipka", "šipky", "šipek"))
                Divider().frame(height: 34)
                flowFact("\(match.visits.filter { $0.credited >= 100 }.count)", "100+")
                Divider().frame(height: 34)
                flowFact("\(match.visits.filter(\.checkout).count)", czech(match.visits.filter(\.checkout).count, "zavření", "zavření", "zavření"))
            }
            .padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, lineWidth: 0.5))

            ForEach(shown, id: \.self) { leg in
                section(legTitle(leg), symbol: "flag.fill") { legVisits(leg) }
            }

            NavigationLink {
                VisitLog(game: match)
            } label: {
                Label("Podrobný záznam hodů", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(PrimaryButton())
        }
    }

    private func legTitle(_ leg: Int) -> String {
        guard let winner = winnerForLeg(leg, lastLeg: legs.last) else { return "Leg \(leg)" }
        return "Leg \(leg) · \(match.players[winner].name)"
    }

    private func legVisits(_ leg: Int) -> some View {
        let visits = match.visits.filter { $0.leg == leg }
        return VStack(spacing: 0) {
            ForEach(Array(visits.enumerated()), id: \.element.id) { offset, visit in
                VisitRowView(
                    match: match,
                    visit: visit,
                    round: visits.prefix(offset).filter { $0.player == visit.player }.count + 1,
                    photo: store.photo(for: match.players[visit.player].id)
                )
                if offset < visits.count - 1 {
                    Divider().padding(.leading, 48)
                }
            }
        }
        .padding(.vertical, -6)
        .historyCard()
    }

    private func playerName(_ index: Int) -> String {
        match.players[index].id == profileID ? "\(match.players[index].name) · Ty" : match.players[index].name
    }
}

// MARK: Součásti detailu zápasu

private struct BarItem: Identifiable {
    let label: String
    let count: Int
    let color: Color
    var id: String { label }
}

/// Vodorovné pruhy s počtem a podílem. Délka je vůči nejčastější položce.
private struct BarList: View {
    let items: [BarItem]
    let total: Int

    var body: some View {
        let peak = max(1, items.map(\.count).max() ?? 1)
        VStack(spacing: 11) {
            ForEach(items) { item in
                HStack(spacing: 10) {
                    Text(item.label)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 56, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(item.color)
                                .frame(width: item.count > 0 ? max(8, geo.size.width * CGFloat(item.count) / CGFloat(peak)) : 0)
                        }
                    }
                    .frame(height: 10)
                    Text("\(item.count)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .frame(width: 30, alignment: .trailing)
                    Text("\(Int((Double(item.count) / Double(max(total, 1)) * 100).rounded())) %")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
                .opacity(item.count == 0 ? 0.55 : 1)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct LegChips: View {
    let legs: [Int]
    @Binding var selection: Int?
    var allTitle: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let allTitle {
                    chip(allTitle, selected: selection == nil) { selection = nil }
                }
                ForEach(legs, id: \.self) { leg in
                    chip("Leg \(leg)", selected: selection == leg) { selection = leg }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Theme.onAccent : .primary)
                .background(selected ? Theme.accentFill : Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.stroke, lineWidth: selected ? 0 : 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Souboj dvou hráčů: hodnoty po stranách a lišta, kdo měl navrch.
private struct DuelCard: View {
    @EnvironmentObject private var store: AppStore
    let match: Match
    let rows: [CompareRow]

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .center) {
                head(0)
                Text("VS")
                    .font(.system(.caption, design: .rounded).weight(.black))
                    .foregroundStyle(.tertiary)
                head(1)
            }
            VStack(spacing: 14) {
                ForEach(rows) { line($0) }
            }
        }
        .historyCard()
    }

    private func head(_ index: Int) -> some View {
        let player = match.players[index]
        return VStack(spacing: 6) {
            Avatar(
                name: player.name,
                bot: player.botLevel != nil,
                size: 44,
                photo: store.photo(for: player.id),
                asset: player.botLevel.map { BotLevel.get($0).photo }
            )
            .overlay(Circle().strokeBorder(playerTint(index), lineWidth: 2))
            Text(player.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func line(_ row: CompareRow) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                value(row, 0).frame(maxWidth: .infinity, alignment: .leading)
                Text(row.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                value(row, 1).frame(maxWidth: .infinity, alignment: .trailing)
            }
            bar(row)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label): \(match.players[0].name) \(row.text(0)), \(match.players[1].name) \(row.text(1))")
    }

    private func value(_ row: CompareRow, _ slot: Int) -> some View {
        let lead = row.leader == slot
        return HStack(spacing: 5) {
            if lead, slot == 1 { leaderMark(slot) }
            Text(row.text(slot))
                .font(.system(.headline, design: .rounded).weight(lead ? .heavy : .semibold))
                .monospacedDigit()
                .foregroundStyle(lead ? Color.primary : Color.secondary)
            if lead, slot == 0 { leaderMark(slot) }
        }
    }

    private func leaderMark(_ slot: Int) -> some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(playerTint(slot))
    }

    private func bar(_ row: CompareRow) -> some View {
        GeometryReader { geo in
            let split = row.split ?? 0.5
            let empty = row.split == nil
            HStack(spacing: 3) {
                Capsule()
                    .fill(empty ? Color.primary.opacity(0.08) : playerTint(0).opacity(row.leader == 1 ? 0.35 : 1))
                    .frame(width: max(3, (geo.size.width - 3) * split))
                Capsule()
                    .fill(empty ? Color.primary.opacity(0.08) : playerTint(1).opacity(row.leader == 0 ? 0.35 : 1))
            }
        }
        .frame(height: 6)
    }
}

/// Tři a čtyři hráči: tabulka se sloupcem pro každého.
private struct CompareTable: View {
    @EnvironmentObject private var store: AppStore
    let match: Match
    let rows: [CompareRow]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ForEach(match.players.indices, id: \.self) { index in
                    VStack(spacing: 4) {
                        Avatar(
                            name: match.players[index].name,
                            bot: match.players[index].botLevel != nil,
                            size: 30,
                            photo: store.photo(for: match.players[index].id),
                            asset: match.players[index].botLevel.map { BotLevel.get($0).photo }
                        )
                        .overlay(Circle().strokeBorder(playerTint(index), lineWidth: 2))
                        Text(match.players[index].name)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 62)
                }
            }
            .padding(.bottom, 10)
            ForEach(rows) { row in
                Divider()
                HStack(spacing: 0) {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(match.players.indices, id: \.self) { index in
                        Text(row.text(index))
                            .font(.system(.subheadline, design: .rounded).weight(row.leader == index ? .heavy : .medium))
                            .monospacedDigit()
                            .foregroundStyle(row.leader == index ? Color.primary : Color.secondary)
                            .frame(width: 62)
                    }
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .historyCard()
    }
}

/// Průběh jednoho legu: X01 klesá k nule, ostatní režimy sčítají body.
private struct LegRaceChart: View {
    struct Point: Identifiable {
        let id: String
        let series: String
        let round: Int
        let value: Int
        let checkout: Bool
    }

    let match: Match
    let leg: Int

    private var names: [String] {
        match.players.indices.map { index in
            let name = match.players[index].name
            let twins = match.players.filter { $0.name == name }.count > 1
            return twins ? "\(name) (\(index + 1))" : name
        }
    }

    private var points: [Point] {
        let x01 = match.config.mode == .x01
        var result: [Point] = []
        for index in match.players.indices {
            var value = x01 ? match.config.startingScore(for: index) : 0
            result.append(Point(id: "\(index)-0", series: names[index], round: 0, value: value, checkout: false))
            let visits = match.visits.filter { $0.leg == leg && $0.player == index }
            for (offset, visit) in visits.enumerated() {
                value = x01 ? visit.remaining : value + visit.credited
                result.append(Point(id: "\(index)-\(offset + 1)", series: names[index], round: offset + 1, value: value, checkout: visit.checkout))
            }
        }
        return result
    }

    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("Kolo", point.round), y: .value("Skóre", point.value))
                .foregroundStyle(by: .value("Hráč", point.series))
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            if point.checkout {
                PointMark(x: .value("Kolo", point.round), y: .value("Skóre", point.value))
                    .foregroundStyle(by: .value("Hráč", point.series))
                    .symbolSize(70)
                    .annotation(position: .top, spacing: 4) {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.positive)
                    }
            }
        }
        .chartForegroundStyleScale(domain: names, range: names.indices.map(playerTint))
        .chartLegend(.hidden)
        .chartXScale(domain: 0...max(points.map(\.round).max() ?? 1, 1))
        .chartYScale(domain: 0...max(Double(points.map(\.value).max() ?? 1) * 1.08, 1))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .frame(height: 210)
        .accessibilityLabel("Graf průběhu legu \(leg)")
    }
}

/// Terč s místy dopadu. Heatmapa sčítá světlo, takže hustá místa září do bíla.
private struct HeatBoard: View {
    let darts: [Dart]
    let lens: BoardLens

    var body: some View {
        Canvas { context, size in
            let layout = BoardFace.layout(in: size)
            let center = layout.center
            let radius = layout.radius
            BoardFace.drawScoringBeds(context: context, center: center, radius: radius)
            BoardFace.drawWires(context: context, center: center, radius: radius)
            BoardFace.drawBulls(context: context, center: center, radius: radius)
            BoardFace.drawNumbers(context: context, center: center, radius: radius)

            let spots = Self.spots(darts).map { CGPoint(x: center.x + $0.x * radius, y: center.y + $0.y * radius) }
            if lens == .heat {
                context.fill(BoardFace.disk(factor: 1.0, center: center, radius: radius), with: .color(.black.opacity(0.58)))
                context.drawLayer { layer in
                    layer.blendMode = .plusLighter
                    let spread = radius * 0.14
                    let gradient = Gradient(colors: [
                        Color(red: 1, green: 0.3, blue: 0.04).opacity(0.55),
                        Color(red: 1, green: 0.2, blue: 0).opacity(0)
                    ])
                    for spot in spots {
                        let rect = CGRect(x: spot.x - spread, y: spot.y - spread, width: spread * 2, height: spread * 2)
                        layer.fill(Path(ellipseIn: rect), with: .radialGradient(gradient, center: spot, startRadius: 0, endRadius: spread))
                    }
                }
                for spot in spots {
                    let dot = CGRect(x: spot.x - 1.5, y: spot.y - 1.5, width: 3, height: 3)
                    context.fill(Path(ellipseIn: dot), with: .color(.white.opacity(0.75)))
                }
            } else {
                for spot in spots {
                    let ring = CGRect(x: spot.x - 6, y: spot.y - 6, width: 12, height: 12)
                    let core = CGRect(x: spot.x - 3.5, y: spot.y - 3.5, width: 7, height: 7)
                    context.stroke(Path(ellipseIn: ring), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
                    context.fill(Path(ellipseIn: core), with: .color(BoardFace.heat))
                    context.stroke(Path(ellipseIn: core), with: .color(.black.opacity(0.55)), lineWidth: 1)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(lens == .heat ? "Heatmapa dopadů, \(darts.count) šipek" : "Místa dopadů, \(darts.count) šipek")
    }

    /// Šipky bez souřadnic leží doprostřed pole, mírný rozptyl je oddělí od sebe.
    static func spots(_ darts: [Dart]) -> [(x: Double, y: Double)] {
        darts.enumerated().compactMap { offset, dart in
            guard let base = BoardGeometry.marker(for: dart) else { return nil }
            let distance = hypot(base.x, base.y)
            if dart.x != nil {
                let limit = 1.12
                guard distance > limit else { return base }
                return (base.x / distance * limit, base.y / distance * limit)
            }
            guard distance > 0.01 else { return base }
            let a = Double((offset * 7919) % 997) / 997 - 0.5
            let b = Double((offset * 104_729) % 991) / 991 - 0.5
            let angle = atan2(base.y, base.x) + a * .pi / 14
            let depth = dart.multiplier == 1 ? 0.28 : 0.035
            let r = distance * (1 + b * depth)
            return (cos(angle) * r, sin(angle) * r)
        }
    }
}

private struct DartChip: View {
    let dart: Dart

    private var tint: Color {
        if dart.segment == 0 { return .secondary }
        if dart.segment == 25 { return .red }
        switch dart.multiplier {
        case 3: return .orange
        case 2: return Theme.positive
        default: return .primary
        }
    }

    var body: some View {
        Text(dart.segment == 0 ? "Vedle" : dart.label)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .frame(minWidth: 36)
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .foregroundStyle(tint)
            .background(tint.opacity(dart.multiplier == 1 && dart.segment != 25 ? 0.08 : 0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct VisitRowView: View {
    let match: Match
    let visit: Visit
    let round: Int
    let photo: Data?

    var body: some View {
        let player = match.players[visit.player]
        HStack(spacing: 12) {
            Avatar(
                name: player.name,
                bot: player.botLevel != nil,
                size: 36,
                photo: photo,
                asset: player.botLevel.map { BotLevel.get($0).photo }
            )
            .overlay(Circle().strokeBorder(playerTint(visit.player), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(match.players[visit.player].name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text("\(round). kolo")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    tag
                }
                if visit.enteredAsTotal == true {
                    Text("Zapsáno součtem")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(visit.darts.enumerated()), id: \.offset) { _, dart in
                            DartChip(dart: dart)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(visit.bust ? "BUST" : "\(visit.credited)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor)
                if match.config.mode == .x01 {
                    Text("zbývá \(visit.remaining)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var scoreColor: Color {
        if visit.bust { return .red }
        if visit.checkout { return Theme.positive }
        if match.config.mode == .x01, visit.credited >= 100 { return scoreBandColor(visit.credited) }
        return .primary
    }

    @ViewBuilder
    private var tag: some View {
        if visit.checkout {
            badge("CHECKOUT", Theme.positive)
        } else if match.config.mode == .x01, visit.credited == 180 {
            badge("180", .red)
        } else if match.config.mode == .x01, visit.credited >= 140 {
            badge("140+", .orange)
        } else if match.config.mode == .x01, visit.credited >= 100 {
            badge("TON", scoreBandColor(100))
        }
    }

    private func badge(_ title: String, _ color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
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
    switch abs(count) {
    case 1: one
    case 2...4: few
    default: many
    }
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
