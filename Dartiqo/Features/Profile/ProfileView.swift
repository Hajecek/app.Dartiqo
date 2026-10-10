import SwiftUI
import Charts

/// Hráčský profil se statistikami. Nastavení je na vlastní záložce.
struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @State private var mode: GameMode = .x01
    @State private var period: StatsPeriod = .all
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var showRange = false

    private var playedDays: Set<Date> {
        Set(store.matches.filter { $0.config.mode == mode }.map { Calendar.current.startOfDay(for: $0.completedAt ?? $0.createdAt) })
    }

    private var periodTitle: String {
        guard period == .custom else { return period.title }
        let from = min(customFrom, customTo), to = max(customFrom, customTo)
        if Calendar.current.isDate(from, inSameDayAs: to) { return from.formatted(.dateTime.day().month()) }
        return "\(from.formatted(.dateTime.day().month())) – \(to.formatted(.dateTime.day().month()))"
    }

    private var stats: PlayerStats {
        guard let id = store.profile?.id else { return PlayerStats() }
        return PlayerStats.make(matches: store.matches, playerID: id, mode: mode, range: period.range(from: customFrom, to: customTo))
    }

    var body: some View {
        let stats = stats
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                playerCard(stats)
                if stats.isEmpty {
                    ContentUnavailableView("Zatím tu nic není",
                                           systemImage: "chart.bar.xaxis",
                                           description: Text("Dokonči zápas v režimu \(mode.shortTitle) za zvolené období a čísla se objeví tady."))
                } else {
                    form(stats)
                    keyNumbers(stats)
                    if mode == .x01 {
                        scoring(stats)
                        if stats.checkout.hasData {
                            block("Zavírání", symbol: "checkmark.seal.fill") {
                                CheckoutStatsView(stats: stats.checkout).surface()
                            }
                        }
                    }
                    board(stats)
                    records(stats)
                    career(stats)
                }
                playTime
                milestones
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("Profil")
        .navigationSubtitle("\(mode.shortTitle) · \(periodTitle)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Picker("Hra", selection: $mode) {
                        ForEach(GameMode.allCases) { Label($0.shortTitle, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Hra: \(mode.shortTitle)", systemImage: mode.symbol)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Období", selection: $period) {
                        ForEach(StatsPeriod.allCases.filter { $0 != .custom }) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Section {
                        Button { showRange = true } label: {
                            Label(period == .custom ? "Vlastní: \(periodTitle)" : "Vlastní rozsah…", systemImage: period == .custom ? "checkmark" : "calendar.badge.clock")
                        }
                    }
                } label: {
                    Label("Období: \(periodTitle)", systemImage: "calendar")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Nastavení")
            }
        }
        .sheet(isPresented: $showRange) {
            DateRangeSheet(from: customFrom, to: customTo, playedDays: playedDays) { from, to in
                customFrom = from
                customTo = to
                period = .custom
            }
            .presentationDetents([.large])
        }
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.selection, trigger: period)
    }

    // MARK: Karta hráče

    private func playerCard(_ stats: PlayerStats) -> some View {
        let progress = Double(store.xp % 500) / 500
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Avatar(name: store.profile?.name ?? "", size: 64, photo: store.profile?.photoJPEG)
                    .overlay(Circle().strokeBorder(Theme.brandBlack, lineWidth: 2.5))
                    .environment(\.colorScheme, .dark)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.profile?.name ?? "Hráč")
                        .font(.title2.bold())
                        .lineLimit(1)
                    Label(rank.title, systemImage: rank.icon)
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.7)
                }
                Spacer(minLength: 8)
                VStack(spacing: 0) {
                    Text("LVL").font(.caption2.weight(.heavy)).opacity(0.6)
                    Text("\(store.level)").font(.system(.title, design: .rounded).weight(.heavy))
                }
                .frame(width: 58, height: 58)
                .background(Theme.brandBlack.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: progress)
                    .tint(Theme.brandBlack)
                Text("\(store.xp % 500) / 500 XP do levelu \(store.level + 1)")
                    .font(.caption.weight(.medium))
                    .opacity(0.65)
            }

            HStack(alignment: .bottom) {
                headline(String(format: "%.1f", stats.average), mode == .x01 ? "průměr" : "bodů / kolo")
                Spacer()
                headline(percent(stats.winRate), "výher")
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 4) {
                        let recent = Array(stats.timeline.suffix(5))
                        ForEach(0..<5, id: \.self) { index in
                            let offset = index - (5 - recent.count)
                            Circle()
                                .fill(offset >= 0 ? (recent[offset].won ? Theme.brandBlack : Theme.brandBlack.opacity(0.18)) : .clear)
                                .strokeBorder(Theme.brandBlack.opacity(0.35), lineWidth: offset >= 0 ? 0 : 1)
                                .frame(width: 11, height: 11)
                        }
                    }
                    Text("forma").font(.caption.weight(.medium)).opacity(0.65)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Forma: \(stats.timeline.suffix(5).filter(\.won).count) výher z posledních \(min(5, stats.timeline.count))")
            }
        }
        .foregroundStyle(Theme.brandBlack)
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.brand)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "target")
                        .font(.system(size: 170, weight: .bold))
                        .foregroundStyle(Theme.brandBlack.opacity(0.05))
                        .offset(x: 50, y: -40)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
    }

    private func headline(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption.weight(.medium)).opacity(0.65)
        }
        .accessibilityElement(children: .combine)
    }

    private var rank: (title: String, icon: String) {
        switch store.level {
        case ..<3: return ("Začátečník", "leaf.fill")
        case 3..<6: return ("Hráč", "target")
        case 6..<10: return ("Pokročilý", "flame.fill")
        default: return ("Expert", "crown.fill")
        }
    }

    // MARK: Forma

    @ViewBuilder
    private func form(_ stats: PlayerStats) -> some View {
        let points = Array(stats.timeline.suffix(20))
        if points.count >= 2 {
            let recent = points.suffix(5).map(\.average)
            let earlier = points.dropLast(5).suffix(5).map(\.average)
            let delta = earlier.isEmpty ? nil : recent.reduce(0, +) / Double(recent.count) - earlier.reduce(0, +) / Double(earlier.count)
            block("Forma", symbol: "waveform.path.ecg", trailing: delta.map { String(format: "%+.1f", $0) }, trailingTint: (delta ?? 0) >= 0 ? Theme.positive : .red) {
                VStack(alignment: .leading, spacing: 8) {
                    Chart(Array(points.enumerated()), id: \.element.id) { index, point in
                        AreaMark(x: .value("Zápas", index), y: .value("Průměr", point.average))
                            .foregroundStyle(LinearGradient(colors: [Theme.positive.opacity(0.35), Theme.positive.opacity(0)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.catmullRom)
                        LineMark(x: .value("Zápas", index), y: .value("Průměr", point.average))
                            .foregroundStyle(Theme.positive)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
                    .frame(height: 140)
                    Text(delta == nil ? "Posledních \(points.count) zápasů" : "Posledních 5 zápasů oproti 5 předchozím")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .surface()
            }
        }
    }

    // MARK: Klíčová čísla

    private func keyNumbers(_ stats: PlayerStats) -> some View {
        block("Klíčová čísla", symbol: "number") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                if mode == .x01 {
                    metric(String(format: "%.1f", stats.first9Average), "Prvních 9", "průměr úvodních tří kol", "9.square.fill", .blue)
                    metric(stats.checkout.percentage.map(percent) ?? "—", "Checkout", "\(stats.checkout.hits) z \(stats.checkout.attempts) pokusů", "scope", Theme.positive)
                } else {
                    metric("\(stats.bestVisit)", "Nejlepší kolo", "v jedné návštěvě", "star.square.fill", .blue)
                    metric("\(stats.points)", "Body", "celkem v režimu", "sum", Theme.positive)
                }
                metric(stats.decidingRate.map(percent) ?? "—", "Rozhodující legy", "\(stats.decidingWon) z \(stats.decidingLegs) vyhráno", "bolt.square.fill", .orange)
                metric("\(stats.legsWon)/\(stats.legsPlayed)", "Legy", "vyhrané / odehrané", "flag.square.fill", .purple)
            }
        }
    }

    private func metric(_ value: String, _ title: String, _ detail: String, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
        .accessibilityElement(children: .combine)
    }

    // MARK: Skórování

    private func scoring(_ stats: PlayerStats) -> some View {
        let low = max(0, stats.visits - stats.n180 - stats.n140 - stats.n100 - stats.n60)
        let bands: [(String, Int, Color)] = [
            ("180", stats.n180, .red), ("140+", stats.n140, .orange), ("100+", stats.n100, .yellow),
            ("60+", stats.n60, Theme.positive), ("pod 60", low, Color.secondary.opacity(0.35))
        ]
        let total = max(1, stats.visits)
        return block("Skórování", symbol: "chart.bar.fill", trailing: "\(stats.visits) kol") {
            VStack(alignment: .leading, spacing: 14) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(bands, id: \.0) { band in
                            if band.1 > 0 {
                                Rectangle()
                                    .fill(band.2)
                                    .frame(width: max(4, (proxy.size.width - 8) * CGFloat(band.1) / CGFloat(total)))
                            }
                        }
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 14)
                .accessibilityHidden(true)
                HStack(spacing: 0) {
                    ForEach(bands, id: \.0) { band in
                        VStack(spacing: 2) {
                            Text("\(band.1)")
                                .font(.system(.headline, design: .rounded))
                                .monospacedDigit()
                            HStack(spacing: 4) {
                                Circle().fill(band.2).frame(width: 7, height: 7)
                                Text(band.0).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .surface()
        }
    }

    // MARK: Terč

    @ViewBuilder
    private func board(_ stats: PlayerStats) -> some View {
        if !stats.positioned.isEmpty {
            block("Kam házíš", symbol: "target") {
                NavigationLink {
                    HeatmapView(darts: stats.positioned, title: "\(mode.shortTitle) · \(periodTitle)")
                } label: {
                    HStack(spacing: 16) {
                        TouchDartboard(marks: stats.positioned, interactive: false, showMarkNumbers: false) { _ in }
                            .frame(width: 112, height: 112)
                            .allowsHitTesting(false)
                        VStack(alignment: .leading, spacing: 6) {
                            if let top = HeatmapView.topFields(stats.positioned).first {
                                Text("Nejčastěji \(top.label)")
                                    .font(.headline)
                            }
                            Text("\(stats.positioned.count) šipek na terči")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Label("Otevřít mapu", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .surface()
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Rekordy

    @ViewBuilder
    private func records(_ stats: PlayerStats) -> some View {
        let items = recordItems(stats)
        if !items.isEmpty {
            block("Rekordy", symbol: "rosette") {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(items, id: \.title) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: item.icon)
                                    .font(.title2)
                                    .foregroundStyle(item.tint)
                                Spacer(minLength: 0)
                                Text(item.value)
                                    .font(.system(.title, design: .rounded).weight(.heavy))
                                    .monospacedDigit()
                                Text(item.title)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 128, height: 136, alignment: .leading)
                            .surface()
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollClipDisabled()
            }
        }
    }

    private func recordItems(_ stats: PlayerStats) -> [(title: String, value: String, icon: String, tint: Color)] {
        var items: [(title: String, value: String, icon: String, tint: Color)] = []
        if let best = stats.bestMatchAverage, best > 0 { items.append(("Průměr zápasu", String(format: "%.1f", best), "chart.line.uptrend.xyaxis", .blue)) }
        if stats.bestVisit > 0 { items.append(("Nejlepší kolo", "\(stats.bestVisit)", "flame.fill", .red)) }
        if stats.checkout.highest > 0 { items.append(("Nejvyšší zavření", "\(stats.checkout.highest)", "checkmark.seal.fill", Theme.positive)) }
        if let legDarts = stats.bestLegDarts { items.append(("Šipek na leg", "\(legDarts)", "stopwatch.fill", .orange)) }
        return items
    }

    // MARK: Kariéra

    private func career(_ stats: PlayerStats) -> some View {
        block("Celkem", symbol: "sum") {
            Grid(horizontalSpacing: 0, verticalSpacing: 16) {
                GridRow {
                    total("\(stats.matches)", "zápasů")
                    total("\(stats.wins)", "výher")
                    total("\(stats.legsPlayed)", "legů")
                }
                Divider()
                GridRow {
                    total("\(stats.darts)", "šipek")
                    total("\(stats.visits)", "kol")
                    total("\(stats.points)", "bodů")
                }
            }
            .surface()
        }
    }

    private func total(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Milníky

    // MARK: Čas

    @ViewBuilder
    private var playTime: some View {
        if let id = store.profile?.id {
            let range = period.range(from: customFrom, to: customTo)
            let time = PlayTime.make(matches: store.matches, playerID: id, range: range)
            if time.matchCount > 0 {
                block("Čas u terče", symbol: "clock.fill", trailing: "všechny režimy") {
                    PlayTimeCard(time: time, range: range, periodTitle: periodTitle)
                }
            }
        }
    }

    private var milestones: some View {
        let bestCheckout = store.ownVisits.filter(\.checkout).map(\.credited).max() ?? 0
        let trained180 = store.trainingHistory.reduce(0) { $0 + ($1.result?.oneEighties ?? 0) }
        var items: [(String, String, Bool)] = [
            ("První zápas", "shoeprints.fill", !store.matches.isEmpty),
            ("První výhra", "trophy.fill", store.wins > 0),
            ("Maximum 180", "flame.fill", store.n180 + trained180 > 0),
            ("Zavření 100+", "sparkles", bestCheckout >= 100),
            ("20 zápasů", "medal.fill", store.matches.count >= 20)
        ]
        items += TrainingAchievements.keys.map { key in
            (TrainingAchievements.title(key), TrainingAchievements.symbol(key), store.trainingUnlocked(key))
        }
        return block("Milníky", symbol: "star.circle.fill", trailing: "\(items.filter(\.2).count)/\(items.count)") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(items, id: \.0) { item in
                        VStack(spacing: 8) {
                            Image(systemName: item.2 ? item.1 : "lock.fill")
                                .font(.title3)
                                .foregroundStyle(item.2 ? Theme.onAccent : .secondary)
                                .frame(width: 50, height: 50)
                                .background(item.2 ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Color.primary.opacity(0.07)), in: Circle())
                            Text(item.0)
                                .font(.caption2.weight(.medium))
                                .multilineTextAlignment(.center)
                                .foregroundStyle(item.2 ? .primary : .secondary)
                                .frame(width: 72)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(item.2 ? "Splněno" : "Zamčeno")
                    }
                }
            }
            .surface()
        }
    }

    // MARK: Stavební prvky

    private func percent(_ value: Double) -> String { "\(Int(value.rounded())) %" }

    private func block<Content: View>(_ title: String, symbol: String, trailing: String? = nil, trailingTint: Color = .secondary, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                    .labelStyle(BlockLabelStyle())
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(trailingTint)
                }
            }
            content()
        }
    }
}

/// Čas u terče: celkem, podíl podle soupeřů a průběh po dnech.
private struct PlayTimeCard: View {
    var time: PlayTime
    var range: Range<Date>?
    var periodTitle: String

    private func tint(_ kind: PlayTime.Kind) -> Color {
        switch kind {
        case .training: return Theme.positive
        case .bots: return .orange
        case .friends: return .blue
        }
    }

    /// Konec a délka grafu. Krátká období ukážou celý rozsah, dlouhá posledních 14 dní.
    private var window: (end: Date, count: Int) {
        let now = Date()
        guard let range, range.upperBound < .distantFuture else { return (now, 14) }
        let end = min(now, range.upperBound.addingTimeInterval(-1))
        let days = (Calendar.current.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 14)
        return (end, min(31, max(7, days)))
    }

    var body: some View {
        let kinds = PlayTime.Kind.allCases.filter { (time.seconds[$0] ?? 0) > 0 }
        let window = window
        let days = time.days(ending: window.end, count: window.count)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 18) {
                ZStack {
                    Chart(kinds) { kind in
                        SectorMark(angle: .value("Čas", time.seconds[kind] ?? 0), innerRadius: .ratio(0.68), angularInset: 2)
                            .cornerRadius(4)
                            .foregroundStyle(tint(kind))
                    }
                    VStack(spacing: 0) {
                        Text(PlayTime.format(time.total))
                            .font(.system(.headline, design: .rounded).weight(.heavy))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("celkem").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 18)
                }
                .frame(width: 128, height: 128)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Celkem \(PlayTime.format(time.total))")

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(PlayTime.Kind.allCases) { kind in
                        let seconds = time.seconds[kind] ?? 0
                        HStack(spacing: 8) {
                            Circle().fill(tint(kind).opacity(seconds > 0 ? 1 : 0.25)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(kind.title).font(.subheadline.weight(.semibold))
                                Text("\(time.matches[kind] ?? 0) her · \(Int((time.share(kind) * 100).rounded())) %")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Spacer(minLength: 4)
                            Text(PlayTime.format(seconds))
                                .font(.system(.subheadline, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(seconds > 0 ? .primary : .secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            HStack(spacing: 0) {
                fact(PlayTime.format(time.perMatch), "na hru")
                Divider().frame(height: 30)
                fact(PlayTime.format(time.longest), "nejdelší hra")
                Divider().frame(height: 30)
                fact("\(time.activeDays)", time.activeDays == 1 ? "den u terče" : "dní u terče")
            }
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Po dnech").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("posledních \(window.count) dní").font(.caption).foregroundStyle(.secondary)
                }
                Chart(days) { day in
                    BarMark(x: .value("Den", day.date, unit: .day), y: .value("Minuty", day.seconds / 60))
                        .foregroundStyle(tint(day.kind))
                        .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel { if let minutes = value.as(Double.self) { Text("\(Int(minutes)) min") } }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: window.count > 14 ? 7 : 2)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                    }
                }
                .frame(height: 130)
                .accessibilityLabel("Čas po dnech za posledních \(window.count) dní")
            }

            let modes = GameMode.allCases.filter { (time.byMode[$0] ?? 0) > 0 }
            if modes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(modes) { mode in
                            Label("\(mode.shortTitle) \(PlayTime.format(time.byMode[mode] ?? 0))", systemImage: mode.symbol)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                    }
                }
            }

            Text("\(periodTitle). Čas běží, dokud máš otevřenou hru. Pauza, odchod ze hry a appka na pozadí se nepočítají.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .surface()
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct BlockLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
            configuration.title
        }
    }
}

/// Celá mapa dopadů s rozpadem podle typu pole.
struct HeatmapView: View {
    let darts: [Dart]
    let title: String
    @State private var zoomed = false

    var body: some View {
        let triples = darts.filter { $0.multiplier == 3 }.count
        let doubles = darts.filter { $0.multiplier == 2 && $0.segment != 25 }.count
        let bulls = darts.filter { $0.segment == 25 }.count
        let misses = darts.filter { $0.segment == 0 }.count
        let singles = darts.count - triples - doubles - bulls - misses
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ZoomableDartboard(marks: darts, zoomed: $zoomed)
                    .padding(8)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .environment(\.colorScheme, .dark)
                Text("Roztáhni prsty nebo dvakrát klepni pro detail segmentu.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    share("Triple", triples, .red)
                    share("Double", doubles, Theme.positive)
                    share("Single", singles, .blue)
                    share("Bull", bulls, .orange)
                    share("Vedle", misses, .secondary)
                }
                .surface()

                Text("Nejčastější pole").font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(Self.topFields(darts), id: \.label) { field in
                        HStack {
                            Text(field.label).font(.headline)
                            Spacer()
                            Text("\(field.count)×")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .surface()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDisabled(zoomed)
        .screen()
        .navigationTitle("Mapa dopadů")
        .navigationSubtitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func share(_ label: String, _ count: Int, _ tint: Color) -> some View {
        let fraction = Double(count) / Double(max(1, darts.count))
        return HStack(spacing: 12) {
            Text(label).font(.subheadline.weight(.medium)).frame(width: 56, alignment: .leading)
            ProgressView(value: fraction).tint(tint)
            Text("\(Int((fraction * 100).rounded())) %")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    static func topFields(_ darts: [Dart]) -> [(label: String, count: Int)] {
        var counts: [String: Int] = [:]
        for dart in darts { counts[dart.label, default: 0] += 1 }
        let fields: [(label: String, count: Int)] = counts.map { (label: $0.key, count: $0.value) }
        let sorted = fields.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.label < rhs.label : lhs.count > rhs.count
        }
        return Array(sorted.prefix(8))
    }
}

/// Výběr vlastního rozsahu: první klepnutí je začátek, druhé konec.
private struct DateRangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date?
    @State private var end: Date?
    @State private var month: Date
    let playedDays: Set<Date>
    let onApply: (Date, Date) -> Void

    private let calendar = Calendar.current
    private var today: Date { calendar.startOfDay(for: Date()) }

    init(from: Date, to: Date, playedDays: Set<Date>, onApply: @escaping (Date, Date) -> Void) {
        let cal = Calendar.current
        let lower = cal.startOfDay(for: min(from, to)), upper = cal.startOfDay(for: max(from, to))
        _start = State(initialValue: lower)
        _end = State(initialValue: upper)
        _month = State(initialValue: cal.dateInterval(of: .month, for: upper)?.start ?? upper)
        self.playedDays = playedDays
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    presets
                    calendarCard
                }
                .padding(16)
            }
            .screen()
            .navigationTitle("Vlastní rozsah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zrušit", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Použít", systemImage: "checkmark") {
                        guard let start else { return }
                        onApply(start, end ?? start)
                        dismiss()
                    }
                    .disabled(start == nil)
                }
            }
            .sensoryFeedback(.selection, trigger: start)
            .sensoryFeedback(.selection, trigger: end)
        }
    }

    // MARK: Souhrn

    private var summary: some View {
        HStack(spacing: 0) {
            edge("Od", start, active: end != nil || start == nil)
            Image(systemName: "arrow.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            edge("Do", end ?? start, active: start != nil && end == nil)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(dayCount)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(dayCount == 1 ? "den" : dayCount < 5 ? "dny" : "dní")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .surface()
        .animation(.snappy, value: dayCount)
        .accessibilityElement(children: .combine)
    }

    private func edge(_ title: String, _ date: Date?, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(active ? Theme.accent : .secondary)
            Text(date?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "Vyber den")
                .font(.headline)
                .foregroundStyle(date == nil ? .secondary : .primary)
        }
    }

    private var dayCount: Int {
        guard let start else { return 0 }
        let last = end ?? start
        return (calendar.dateComponents([.day], from: start, to: last).day ?? 0) + 1
    }

    // MARK: Rychlé volby

    private var presets: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                preset("Tento týden") { interval(.weekOfYear, offset: 0) }
                preset("Minulý týden") { interval(.weekOfYear, offset: -1) }
                preset("Tento měsíc") { interval(.month, offset: 0) }
                preset("Minulý měsíc") { interval(.month, offset: -1) }
                preset("Letos") { interval(.year, offset: 0) }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func preset(_ title: String, range: @escaping () -> (Date, Date)?) -> some View {
        let value = range()
        let selected = value.map { $0.0 == start && $0.1 == (end ?? start) } ?? false
        return Button {
            guard let value else { return }
            withAnimation(.snappy) {
                start = value.0
                end = value.1
                month = calendar.dateInterval(of: .month, for: value.1)?.start ?? value.1
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? AnyShapeStyle(Theme.accentFill) : AnyShapeStyle(Theme.card), in: Capsule())
                .foregroundStyle(selected ? Theme.onAccent : .primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Celé období (týden, měsíc, rok) posunuté o `offset`, oříznuté na dnešek.
    private func interval(_ unit: Calendar.Component, offset: Int) -> (Date, Date)? {
        guard let anchor = calendar.date(byAdding: unit, value: offset, to: today),
              let period = calendar.dateInterval(of: unit, for: anchor) else { return nil }
        let last = calendar.date(byAdding: .day, value: -1, to: period.end) ?? period.start
        return (period.start, min(last, today))
    }

    // MARK: Kalendář

    private var calendarCard: some View {
        let canGoForward = month < (calendar.dateInterval(of: .month, for: today)?.start ?? today)
        return VStack(spacing: 12) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()).capitalized)
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }
                    .accessibilityLabel("Předchozí měsíc")
                Button { shiftMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }
                    .disabled(!canGoForward)
                    .accessibilityLabel("Další měsíc")
            }
            .font(.body.weight(.semibold))
            .tint(Theme.accent)

            let symbols = weekdaySymbols
            HStack(spacing: 0) {
                ForEach(symbols.indices, id: \.self) { index in
                    Text(symbols[index])
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 6) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 44) }
                }
            }
            .id(month)
            .transition(.opacity)

            if !playedDays.isEmpty {
                HStack(spacing: 6) {
                    Circle().fill(Theme.positive).frame(width: 6, height: 6)
                    Text("den, kdy jsi hrál").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .surface()
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            if value.translation.width < -40, canGoForward { shiftMonth(1) }
            if value.translation.width > 40 { shiftMonth(-1) }
        })
    }

    private func dayCell(_ day: Date) -> some View {
        let future = day > today
        let isStart = day == start
        let isEnd = day == (end ?? start)
        let inRange = start.map { day >= $0 && day <= (end ?? $0) } ?? false
        let endpoint = isStart || isEnd
        let lower = start, upper = end
        return Button { select(day) } label: {
            ZStack {
                if inRange, let lower, let upper, lower != upper {
                    HStack(spacing: 0) {
                        Rectangle().fill(day == lower ? .clear : Theme.brand.opacity(0.28))
                        Rectangle().fill(day == upper ? .clear : Theme.brand.opacity(0.28))
                    }
                    .frame(height: 40)
                }
                if endpoint {
                    Circle().fill(Theme.accentFill).frame(width: 40, height: 40)
                } else if calendar.isDate(day, inSameDayAs: today) {
                    Circle().strokeBorder(Theme.accent, lineWidth: 1.5).frame(width: 40, height: 40)
                }
                Text("\(calendar.component(.day, from: day))")
                    .font(.body.weight(endpoint ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(endpoint ? Theme.onAccent : future ? Color.secondary.opacity(0.5) : .primary)
                if playedDays.contains(day) {
                    Circle()
                        .fill(endpoint ? Theme.onAccent : Theme.positive)
                        .frame(width: 5, height: 5)
                        .offset(y: 13)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(day.formatted(date: .long, time: .omitted))
        .accessibilityValue(endpoint ? (isStart ? "Začátek rozsahu" : "Konec rozsahu") : inRange ? "V rozsahu" : "")
        .accessibilityAddTraits(endpoint ? .isSelected : [])
    }

    private func select(_ day: Date) {
        withAnimation(.snappy(duration: 0.25)) {
            if let start, end == nil, day >= start {
                end = day
            } else {
                start = day
                end = nil
            }
        }
    }

    private func shiftMonth(_ value: Int) {
        guard let next = calendar.date(byAdding: .month, value: value, to: month) else { return }
        withAnimation(.snappy) { month = next }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Dny měsíce zarovnané podle prvního dne týdne; `nil` = prázdné pole.
    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let days = range.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        return Array(repeating: nil, count: leading) + days.map { Optional($0) }
    }
}
