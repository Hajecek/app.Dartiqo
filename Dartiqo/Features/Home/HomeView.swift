import SwiftUI
import UIKit

/// Lobby ve stylu herní aplikace. Navigace a tab bar zůstávají systémové.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var preview: LockedPreview?
    @State private var showDaily = false
    @State private var showStreak = false
    @State private var openLocalSetup = false
    @State private var showQuickPlay = false
    @State private var quickSetup: SetupDraft?
    @State private var openQuickSetup = false
    @State private var launchQuickMatch = false

    private let canvas = Color.black

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileRow
                actionGrid
                wideCards
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(canvas.ignoresSafeArea())
        .navigationTitle("Dartiqo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("Logo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .accessibilityLabel("Dartiqo")
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                dailyToolbarButton
                streakToolbarButton
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $preview) { item in
            FeaturePreview(preview: item)
        }
        .sheet(isPresented: $showDaily) {
            DailyChallengeSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showStreak) {
            StreakSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showQuickPlay) {
            QuickPlaySheet(
                onPick: { draft in
                    showQuickPlay = false
                    quickSetup = draft
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 280_000_000)
                        openQuickSetup = true
                    }
                },
                onResume: {
                    showQuickPlay = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 280_000_000)
                        launchQuickMatch = true
                    }
                }
            )
            .environmentObject(store)
        }
        .fullScreenCover(isPresented: $launchQuickMatch) {
            NavigationStack { MatchView() }
                .environmentObject(store)
        }
        .navigationDestination(isPresented: $openLocalSetup) {
            SetupView(mode: .x01, preset: store.lastSetup, coversLiveBar: true)
        }
        .navigationDestination(isPresented: $openQuickSetup) {
            SetupView(
                mode: quickSetup?.config.mode ?? .x01,
                preset: quickSetup,
                coversLiveBar: true,
                startAtOpening: true
            )
        }
    }

    private var streakToolbarButton: some View {
        let streak = store.trainingStreak
        return Button {
            showStreak = true
        } label: {
            Image(systemName: "flame.fill")
                .badge(streak)
        }
        .tint(Theme.brand)
        .accessibilityLabel(streak == 0 ? "Série, žádný den v řadě" : "Série, \(trainingDayCount(streak)) v řadě")
    }

    private var dailyToolbarButton: some View {
        let tasks = TrainingDaily.tasks(in: store.trainingHistory, profile: store.profile?.id)
        let done = tasks.filter(\.done).count
        let left = tasks.count - done
        return Button {
            showDaily = true
        } label: {
            Image(systemName: "flag.fill")
                .badge(left)
        }
        .tint(Theme.brand)
        .accessibilityLabel(left == 0 ? "Denní výzva, splněno" : "Denní výzva, \(done) z \(tasks.count)")
    }

    private var profileRow: some View {
        let progress = store.levelProgress
        return NavigationLink {
            ProfileView()
        } label: {
            HStack(spacing: 14) {
                Avatar(name: store.profile?.name ?? "", size: 76, photo: store.profile?.photoJPEG)
                    .environment(\.colorScheme, .dark)
                    .overlay(Circle().stroke(Theme.brand, lineWidth: 2))
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.profile?.name ?? "Hráč")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    levelBadge(progress: progress.fraction, xpInLevel: progress.intoLevel, needed: progress.needed)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Ø")
                            .font(.title2.weight(.bold))
                            .accessibilityHidden(true)
                        Text(averageText)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.brand)
                    Text("průměr")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.profile?.name ?? "Hráč"), level \(store.level), \(progress.intoLevel) z \(progress.needed) XP, průměr \(averageText)")
    }

    private func levelBadge(progress: Double, xpInLevel: Int, needed: Int) -> some View {
        HStack(spacing: 8) {
            Text("\(store.level)")
                .font(AppFont.body(14, weight: .heavy))
                .monospacedDigit()
                .foregroundStyle(Theme.onAccent)
                .frame(width: 28, height: 28)
                .background(Theme.brand, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Level")
                    .font(AppFont.caption(11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                        Capsule()
                            .fill(Theme.brand)
                            .frame(width: max(5, geo.size.width * progress))
                    }
                }
                .frame(width: 72, height: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Level \(store.level), \(xpInLevel) z \(needed) XP")
    }

    private var averageText: String {
        store.ownVisits.isEmpty ? "—" : String(format: "%.1f", store.average)
    }

    private var actionGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                LobbyCard(
                    title: "Hrát lokálně",
                    detail: "X01 s kamarády nebo boty",
                    symbol: "target",
                    colors: [Color(red: 1.0, green: 0.42, blue: 0.29), Color(red: 0.86, green: 0.20, blue: 0.20)],
                    height: 190
                )
                .overlay {
                    TapOrHoldOverlay(
                        onTap: { openLocalSetup = true },
                        onLongPress: {
                            store.tapHaptic(.medium)
                            showQuickPlay = true
                        }
                    )
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Podrž pro rychlou hru")
                .accessibilityAction(.default) { openLocalSetup = true }
                .accessibilityAction(named: "Rychlá hra") {
                    showQuickPlay = true
                }
                NavigationLink { TrainingCenterView() } label: {
                    LobbyCard(
                        title: "Trénovat",
                        detail: store.trainingStreak > 0 ? "\(trainingDayCount(store.trainingStreak)) v řadě" : "Přesnost, výzvy a rekordy",
                        symbol: "scope",
                        colors: [Color(red: 1.0, green: 0.72, blue: 0.20), Color(red: 0.95, green: 0.48, blue: 0.08)],
                        height: 190
                    )
                }
            }
            HStack(spacing: 12) {
                Button { preview = .online } label: {
                    LobbyCard(
                        title: "Hrát online",
                        detail: "Uzamčeno · zápas s hráčem na dálku",
                        symbol: "globe",
                        colors: [Color(red: 0.18, green: 0.48, blue: 0.98), Color(red: 0.08, green: 0.22, blue: 0.72)],
                        height: 190,
                        locked: true
                    )
                }
                .accessibilityHint("Otevře, co v online hře přibude")
                Button { preview = .tournaments } label: {
                    LobbyCard(
                        title: "Turnaje",
                        detail: "Uzamčeno · tabulka, pavouk a ceny",
                        symbol: "flag.2.crossed",
                        colors: [Color(red: 0.58, green: 0.28, blue: 0.96), Color(red: 0.34, green: 0.12, blue: 0.70)],
                        height: 190,
                        locked: true
                    )
                }
                .accessibilityHint("Otevře, co v turnajích přibude")
            }
        }
        .buttonStyle(.plain)
    }

    private var wideCards: some View {
        Button { preview = .career } label: {
            LobbyCard(
                title: "Kariéra",
                detail: "Uzamčeno · hodnosti, výzvy a odměny",
                symbol: "trophy.fill",
                colors: [Color(red: 0.28, green: 0.24, blue: 0.08), Color(red: 0.12, green: 0.10, blue: 0.05)],
                height: 136,
                wide: true,
                locked: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Otevře, co v kariéře přibude")
    }
}

/// Klepnutí a podržení na kartě ve scrollu. SwiftUI gesto na tlačítku scroll polyká.
private struct TapOrHoldOverlay: UIViewRepresentable {
    var onTap: () -> Void
    var onLongPress: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isAccessibilityElement = false

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.allowableMovement = 12
        longPress.cancelsTouchesInView = true
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onLongPress = onLongPress
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onLongPress: onLongPress)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        var onLongPress: () -> Void
        private var held = false

        init(onTap: @escaping () -> Void, onLongPress: @escaping () -> Void) {
            self.onTap = onTap
            self.onLongPress = onLongPress
        }

        @objc func longPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            held = true
            onLongPress()
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            if held {
                held = false
                return
            }
            onTap()
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            other is UIPanGestureRecognizer
        }
    }
}

/// Barevná karta s velkým symbolem v pozadí, text v systémovém písmu.
private struct LobbyCard: View {
    let title: String
    let detail: String
    let symbol: String
    let colors: [Color]
    var height: CGFloat
    var wide = false
    var locked = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .padding(.trailing, wide ? 96 : 0)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol)
                    .font(.system(size: wide ? 120 : 110, weight: .bold))
                    .foregroundStyle(.white.opacity(0.14))
                    .rotationEffect(.degrees(-12))
                    .offset(x: wide ? -8 : 28, y: wide ? 22 : 30)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: colors.first?.opacity(0.35) ?? .clear, radius: 12, y: 6)
        .overlay(alignment: .topTrailing) {
            Group {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(Theme.brand, in: Circle())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(16)
            .accessibilityHidden(true)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

/// Rychlý lokální zápas — výběr formátu, pak stejný start jako u běžného zápasu.
private struct QuickPlaySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var onPick: (SetupDraft) -> Void
    var onResume: () -> Void

    @State private var replace = false
    @State private var pending: SetupDraft?

    private var options: [QuickPlayOption] {
        QuickPlayOption.build(store: store)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Vyber formát. Pak zvolíš, kdo hází první — stejně jako u běžného zápasu.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ForEach(options) { option in
                            Button {
                                pick(option.draft)
                            } label: {
                                optionRow(option)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Rychlá hra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                    }
                    .accessibilityLabel("Zavřít")
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .confirmationDialog("Máš rozehraný zápas", isPresented: $replace, titleVisibility: .visible) {
            Button("Pokračovat v rozehraném") {
                pending = nil
                onResume()
            }
            Button("Zahodit rozehraný a spustit nový", role: .destructive) {
                if let draft = pending {
                    pending = nil
                    onPick(draft)
                }
            }
            Button("Zrušit", role: .cancel) { pending = nil }
        }
    }

    private func optionRow(_ option: QuickPlayOption) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return HStack(spacing: 14) {
            Image(systemName: option.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(colors: option.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(option.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.45))
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: shape)
        .overlay(shape.stroke(.white.opacity(0.1), lineWidth: 1))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otevře výběr, kdo hází první")
    }

    private func pick(_ draft: SetupDraft) {
        store.tapHaptic(.medium)
        if let active = store.activeMatch, !active.finished {
            pending = draft
            replace = true
        } else {
            onPick(draft)
        }
    }
}

private struct QuickPlayOption: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let colors: [Color]
    let draft: SetupDraft

    static func build(store: AppStore) -> [QuickPlayOption] {
        var items: [QuickPlayOption] = []
        let botLevel = preferredBotLevel(store: store)

        if let last = store.lastSetup, store.canStartLocalMatch(from: last) {
            items.append(QuickPlayOption(
                id: "last",
                title: "Poslední sestava",
                detail: last.config.summary,
                symbol: "arrow.counterclockwise",
                colors: [Color(red: 1.0, green: 0.42, blue: 0.29), Color(red: 0.86, green: 0.20, blue: 0.20)],
                draft: last
            ))
        }

        for preset in store.presets where store.canStartLocalMatch(from: preset.setup) {
            items.append(QuickPlayOption(
                id: "preset-\(preset.id.uuidString)",
                title: preset.name,
                detail: preset.setup.config.summary,
                symbol: "bookmark.fill",
                colors: [Color(red: 0.95, green: 0.72, blue: 0.22), Color(red: 0.85, green: 0.45, blue: 0.10)],
                draft: preset.setup
            ))
        }

        items.append(contentsOf: [
            QuickPlayOption(
                id: "501",
                title: "501",
                detail: "1 leg · Double out · proti botovi",
                symbol: "target",
                colors: [Color(red: 1.0, green: 0.42, blue: 0.29), Color(red: 0.86, green: 0.20, blue: 0.20)],
                draft: quickDraft(mode: .x01, score: 501, botLevel: botLevel)
            ),
            QuickPlayOption(
                id: "301",
                title: "301",
                detail: "1 leg · Double out · proti botovi",
                symbol: "target",
                colors: [Color(red: 0.98, green: 0.55, blue: 0.22), Color(red: 0.88, green: 0.28, blue: 0.14)],
                draft: quickDraft(mode: .x01, score: 301, botLevel: botLevel)
            ),
            QuickPlayOption(
                id: "cricket",
                title: "Cricket",
                detail: "1 leg · s body · proti botovi",
                symbol: GameMode.cricket.symbol,
                colors: [Color(red: 0.22, green: 0.72, blue: 0.48), Color(red: 0.10, green: 0.48, blue: 0.32)],
                draft: quickDraft(mode: .cricket, botLevel: botLevel)
            ),
            QuickPlayOption(
                id: "clock",
                title: "Kolem hodin",
                detail: "1–20 + bull · proti botovi",
                symbol: GameMode.aroundClock.symbol,
                colors: [Color(red: 0.28, green: 0.55, blue: 0.98), Color(red: 0.12, green: 0.28, blue: 0.78)],
                draft: quickDraft(mode: .aroundClock, botLevel: botLevel)
            ),
            QuickPlayOption(
                id: "countup",
                title: "Count Up",
                detail: "Nejvyšší skóre · proti botovi",
                symbol: GameMode.countUp.symbol,
                colors: [Color(red: 0.62, green: 0.36, blue: 0.96), Color(red: 0.38, green: 0.16, blue: 0.72)],
                draft: quickDraft(mode: .countUp, botLevel: botLevel)
            ),
        ])
        return items
    }

    private static func preferredBotLevel(store: AppStore) -> Int {
        if let last = store.lastSetup,
           let bot = last.seats.first(where: \.isBot) {
            return min(BotDifficulty.count, max(1, bot.level))
        }
        if let id = store.profile?.id {
            return AdaptiveBotEngine.recommendedLevel(matches: store.matches, playerID: id)
        }
        return 3
    }

    private static func quickDraft(mode: GameMode, score: Int = 501, botLevel: Int) -> SetupDraft {
        var draft = SetupDraft(mode: mode)
        draft.config.startingScore = score
        draft.config.outRule = .double
        draft.config.legsToWin = 1
        draft.config.setsToWin = 1
        draft.config.format = .firstTo
        draft.seats = [
            SeatDraft(name: "Já"),
            SeatDraft(name: "Bot", isBot: true, level: botLevel, adaptiveBot: true),
        ]
        return draft
    }
}

/// Obsah náhledu uzamčeného režimu v lobby.
private struct LockedPreview: Identifiable {
    let id: String
    let title: String
    let headline: String
    let summary: String
    let items: [(symbol: String, title: String, detail: String)]

    static let online = LockedPreview(
        id: "online",
        title: "Hrát online",
        headline: "Online hra je zatím uzamčená",
        summary: "Online zápas spojí dva hráče na dálku ve stejném kole. Zatím si ho můžeš jen prohlédnout.",
        items: [
            ("person.2.fill", "Soupeři", "Najdeš hráče se stejnou úrovní a zahraješ si X01 na dálku."),
            ("link", "Pozvánka", "Pošleš odkaz kamarádovi a zápas začne bez hledání soupeře."),
            ("chart.bar.fill", "Žebříček", "Online průměr a pořadí mezi hráči Dartiqo."),
            ("bolt.fill", "Živý zápas", "Skóre se počítá u obou hráčů ve stejném kole.")
        ]
    )

    static let tournaments = LockedPreview(
        id: "tournaments",
        title: "Turnaje",
        headline: "Turnaje jsou zatím uzamčené",
        summary: "Turnaj sjednotí víc zápasů do tabulky nebo pavouka. Zatím si ho můžeš jen prohlédnout.",
        items: [
            ("person.3.fill", "Startovní listina", "Přihláška, kapacita a rozlosování hráčů."),
            ("arrow.triangle.branch", "Pavouk", "Vyřazovací zápasy až do finále."),
            ("list.number", "Tabulka", "Skupiny, body a vzájemné zápasy."),
            ("trophy.fill", "Ceny", "Pořadí, odznaky a odměny pro nejlepší.")
        ]
    )

    static let career = LockedPreview(
        id: "career",
        title: "Kariéra",
        headline: "Kariéra je zatím uzamčená",
        summary: "Kariéra spojí level, hodnost a milníky do jednoho postupu. Zatím si ji můžeš jen prohlédnout.",
        items: [
            ("crown.fill", "Hodnosti", "Postup od začátečníka po experta podle nasbíraných XP."),
            ("flag.fill", "Výzvy", "Denní a týdenní úkoly navázané na tvoje zápasy."),
            ("medal.fill", "Odznaky", "Milníky za 180, vysoká zavření a série výher."),
            ("calendar", "Sezóny", "Žebříček a odměny, které se s novou sezónou obnoví.")
        ]
    )
}

/// Denní výzva z lišty. Žlutý souhrn a karty úkolů se stavem.
private struct DailyChallengeSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let tasks = TrainingDaily.tasks(in: store.trainingHistory, profile: store.profile?.id)
        let done = tasks.filter(\.done).count
        let complete = done == tasks.count && !tasks.isEmpty
        let nextID = tasks.first { !$0.done }?.id
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero(tasks: tasks, done: done, complete: complete)
                    VStack(spacing: 10) {
                        ForEach(tasks) { task in
                            taskCard(task, featured: task.id == nextID)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Zavřít")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
    }

    private func hero(tasks: [TrainingDailyTask], done: Int, complete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Denní výzva")
                    .font(.caption.weight(.bold))
                Spacer(minLength: 8)
                Text("+50 XP")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.1), in: Capsule())
            }
            .foregroundStyle(.black.opacity(0.58))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(complete ? "Hotovo" : "\(done)")
                    .font(.system(size: complete ? 42 : 58, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                if !complete {
                    Text("/ \(tasks.count)")
                        .font(.title.weight(.bold))
                        .foregroundStyle(.black.opacity(0.34))
                }
                Spacer(minLength: 0)
                Image(systemName: complete ? "checkmark.seal.fill" : "flag.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black.opacity(complete ? 0.9 : 0.22))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 6) {
                ForEach(tasks) { task in
                    Capsule()
                        .fill(task.done ? Color.black : Color.black.opacity(0.16))
                        .frame(height: 7)
                }
            }
            .accessibilityHidden(true)

            Text(complete
                 ? "Všechny dnešní úkoly jsou hotové. Zítra přijde úplně nová trojice her."
                 : "Každý den jiná náhodná trojice. Splň všechny tři — za úkol spuštěný odtud přibude 50 XP.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.black.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(complete ? "Denní výzva hotová" : "Denní výzva, \(done) z \(tasks.count)")
    }

    private func taskCard(_ task: TrainingDailyTask, featured: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(task.done || featured ? Theme.brand : Color.white.opacity(0.08))
                        .frame(width: 48, height: 48)
                    Image(systemName: task.done ? "checkmark" : task.symbol)
                        .font(.body.weight(.bold))
                        .foregroundStyle(task.done || featured ? Color.black : Color.white)
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(task.detail)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(task.done ? 0.48 : 0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if task.done {
                    Text("Hotovo")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.brand, in: Capsule())
                }
            }
            if !task.done {
                NavigationLink {
                    TrainingHomeView(gameIDs: [task.gameID], marksDaily: true)
                } label: {
                    Text(featured ? "Hrát teď" : "Hrát")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(featured ? Color.black : Theme.brand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, featured ? 13 : 11)
                        .background {
                            if featured {
                                Capsule().fill(Theme.brand)
                            } else {
                                Capsule().strokeBorder(Theme.brand.opacity(0.55), lineWidth: 1.5)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background((task.done ? Theme.brand.opacity(0.07) : Color.white.opacity(featured ? 0.07 : 0.04)), in: shape)
        .overlay(shape.stroke(stroke(done: task.done, featured: featured), lineWidth: featured && !task.done ? 1.5 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title), \(task.done ? "hotovo" : "zbývá"). \(task.detail)")
    }

    private func stroke(done: Bool, featured: Bool) -> Color {
        if done { return Theme.brand.opacity(0.28) }
        if featured { return Theme.brand.opacity(0.9) }
        return .white.opacity(0.08)
    }
}

/// Série z lišty. Stejné okno jako denní výzva: žlutý souhrn a jak se počítá.
private struct StreakSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    private var streak: Int { store.trainingStreak }
    private var todayDone: Bool { trained(on: Date()) }
    private var days: [StreakDay] { recentDays() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    hero
                    VStack(spacing: 10) {
                        infoCard(
                            symbol: "flame.fill",
                            title: "Jeden den, jeden trénink",
                            detail: "Počítá se dokončená hra. Rozehraný trénink sérii nedrží."
                        )
                        infoCard(
                            symbol: "calendar",
                            title: "Bez přerušení",
                            detail: "Den bez tréninku sérii vynuluje. Dnešek máš čas do půlnoci."
                        )
                        infoCard(
                            symbol: "medal.fill",
                            title: "Sedm dní",
                            detail: streak >= 7 ? "Odznak Sedm dní v řadě už máš." : "Za sedm dní v řadě získáš odznak."
                        )
                    }
                    if !todayDone {
                        NavigationLink {
                            TrainingCenterView()
                        } label: {
                            Text(streak == 0 ? "Začít sérii" : "Udržet sérii")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Theme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(.white.opacity(0.14), in: Circle())
                    }
                    .accessibilityLabel("Zavřít")
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
        .presentationCornerRadius(28)
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Série")
                    .font(.caption.weight(.bold))
                Spacer(minLength: 8)
                Text(todayDone ? "Dnes hotovo" : "Dnes chybí")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.1), in: Capsule())
            }
            .foregroundStyle(.black.opacity(0.58))

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(streak)")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.black)
                Text(streak == 1 ? "den" : (2...4).contains(streak) ? "dny" : "dní")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.black.opacity(0.34))
                Spacer(minLength: 0)
                Image(systemName: "flame.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.black.opacity(streak == 0 ? 0.22 : 0.9))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 0) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        Text(day.label)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black.opacity(day.isToday ? 0.9 : 0.42))
                        Circle()
                            .fill(day.trained ? Color.black : Color.black.opacity(0.16))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if day.trained {
                                    Image(systemName: "checkmark")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Theme.brand)
                                } else if day.isToday {
                                    Circle()
                                        .strokeBorder(Color.black.opacity(0.45), lineWidth: 1.5)
                                }
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.label), \(day.trained ? "trénink hotový" : "bez tréninku")\(day.isToday ? ", dnes" : "")")
                }
            }

            Text(summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.black.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.brand, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(streak == 0 ? "Série, žádný den v řadě" : "Série, \(trainingDayCount(streak)) v řadě")
    }

    private var summary: String {
        if streak == 0 {
            return "Série se počítá za každý den s dokončeným tréninkem. Vynecháš den a začínáš znovu od nuly."
        }
        if todayDone {
            return "Dnešek je v sérii. Zítra navážeš dalším tréninkem."
        }
        return "Dnešek ještě chybí. Dokonči trénink a série \(trainingDayCount(streak)) zůstane."
    }

    private func infoCard(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.brand)
                    .frame(width: 48, height: 48)
                Image(systemName: symbol)
                    .font(.body.weight(.bold))
                    .foregroundStyle(.black)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func trained(on date: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return store.trainingHistory.contains { session in
            guard session.status == .completed, let finished = session.finishedAt else { return false }
            return calendar.isDate(finished, inSameDayAs: day)
        }
    }

    private func recentDays() -> [StreakDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return StreakDay(
                date: date,
                label: Self.weekday.string(from: date).prefix(2).uppercased(),
                trained: trained(on: date),
                isToday: offset == 0
            )
        }
    }

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "cs_CZ")
        formatter.dateFormat = "EE"
        return formatter
    }()
}

private struct StreakDay: Identifiable {
    var date: Date
    var label: String
    var trained: Bool
    var isToday: Bool
    var id: Date { date }
}

/// Náhled uzamčeného režimu. Okno jen říká, co přibude.
private struct FeaturePreview: View {
    @Environment(\.dismiss) private var dismiss
    let preview: LockedPreview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(width: 52, height: 52)
                            .background(Theme.brand, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Připravujeme")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.brand)
                            Text(preview.headline)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                        }
                    }

                    Text(preview.summary)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ForEach(preview.items, id: \.title) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.brand)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.brand.opacity(0.14), in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(item.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.72))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 8)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zavřít") { dismiss() }
                        .tint(Theme.brand)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}

#if DEBUG
#Preview {
    NavigationStack { HomeView() }.dartiqoPreview(PreviewSupport.store(activeMatch: true))
}
#endif
