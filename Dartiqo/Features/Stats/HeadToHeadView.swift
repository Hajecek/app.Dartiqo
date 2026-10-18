import SwiftUI

/// Barva bilance: výhra zelená, prohra červená, remíza oranžová.
private func h2hStandingTint(mine: Int, theirs: Int) -> Color {
    if mine > theirs { return Theme.positive }
    if mine < theirs { return Color.red.opacity(0.85) }
    return .orange
}

/// Hub vzájemných zápasů — seznam soupeřů a bilancí.
struct HeadToHeadListView: View {
    @EnvironmentObject private var store: AppStore

    private var rivals: [HeadToHead] {
        guard let me = store.profile?.id else { return [] }
        return HeadToHead.rivals(from: store.matches, me: me)
    }

    private var totalWins: Int { rivals.reduce(0) { $0 + $1.myWins } }
    private var totalLosses: Int { rivals.reduce(0) { $0 + $1.theirWins } }
    private var standingTint: Color { h2hStandingTint(mine: totalWins, theirs: totalLosses) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if rivals.isEmpty {
                    ContentUnavailableView(
                        "Zatím žádné vzájemné zápasy",
                        systemImage: "person.2",
                        description: Text("Až dohraješ proti příteli, botovi nebo ghostovi, uvidíš tu bilanci.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    hubHero
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Soupeři")
                            .font(.title3.bold())
                        ForEach(rivals) { series in
                            NavigationLink {
                                HeadToHeadDetailView(rivalKey: series.key)
                            } label: {
                                RivalRow(series: series)
                            }
                            .buttonStyle(.plain)
                        }
                        Text("Bilance jen ze zápasů, kde jsi hrál ty. Boti se sčítají podle úrovně.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("Head-to-Head")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hubHero: some View {
        let played = rivals.reduce(0) { $0 + $1.played }
        let decided = max(totalWins + totalLosses, 1)
        let winShare = CGFloat(totalWins) / CGFloat(decided)
        let tied = totalWins == totalLosses
        return VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("CELKEM")
                    .font(.caption.weight(.heavy))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Text("\(totalWins) : \(totalLosses)")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(standingTint)
                Text(tied ? "Vyrovnáno" : (totalWins > totalLosses ? "Vedeš" : "Prohráváš"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(standingTint)
                Text(rivals.count == 1 ? "1 soupeř" : "\(rivals.count) soupeřů")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            GeometryReader { geo in
                HStack(spacing: 3) {
                    Capsule()
                        .fill(tied ? Color.orange : Theme.positive)
                        .frame(width: max(totalWins > 0 ? 8 : 0, geo.size.width * winShare))
                    Capsule()
                        .fill(tied ? Color.orange.opacity(0.65) : Color.red.opacity(0.55))
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            .background(Capsule().fill(Color.primary.opacity(0.06)))

            HStack(spacing: 0) {
                hubFact("\(totalWins)", "výher", Theme.positive)
                Divider().frame(height: 36)
                hubFact("\(totalLosses)", "proher", Color.red.opacity(0.8))
                Divider().frame(height: 36)
                hubFact("\(played)", "zápasů", Theme.accent)
            }
            .padding(.vertical, 12)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(standingTint.opacity(0.35), lineWidth: 1.2)
        )
    }

    private func hubFact(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Detail souboje s grafy a přehledem.
struct HeadToHeadDetailView: View {
    @EnvironmentObject private var store: AppStore
    let rivalKey: RivalKey
    @State private var selectedMatch: UUID?

    private var series: HeadToHead? {
        guard let me = store.profile?.id else { return nil }
        return HeadToHead.series(from: store.matches, me: me, key: rivalKey)
    }

    var body: some View {
        Group {
            if let series, let me = store.profile?.id {
                ScrollView {
                    HeadToHeadStandingView(
                        series: series,
                        me: me,
                        myName: store.profile?.name ?? "Já",
                        myPhoto: store.profile?.photoJPEG,
                        theirPhoto: opponentPhoto(series),
                        style: .light,
                        onSelectMatch: { selectedMatch = $0 }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView(
                    "Soupeř nenalezen",
                    systemImage: "person.slash",
                    description: Text("K tomuto soupeři už nemáš žádný uložený zápas.")
                )
            }
        }
        .screen()
        .navigationTitle("Head-to-Head")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedMatch) { id in
            if let match = store.matches.first(where: { $0.id == id }) {
                MatchDetailView(match: match, profileID: store.profile?.id, showsHeadToHeadLink: false)
            }
        }
    }

    private func opponentPhoto(_ series: HeadToHead) -> Data? {
        guard case .person(let id) = series.key.kind else { return nil }
        return store.photo(for: id)
    }
}

/// Obrazovka před startem — bilance, nebo úplně jiný plakát, když je to první vzájemný zápas.
struct HeadToHeadPregameView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var series: HeadToHead
    var myName: String
    var myPhoto: Data?
    var theirPhoto: Data?
    var onContinue: () -> Void
    var onCancel: (() -> Void)?

    @State private var progress: CGFloat = 0
    @State private var appeared = false
    @State private var didContinue = false
    @State private var autoToken = UUID()

    private let canvas = Color(red: 0.055, green: 0.10, blue: 0.08)
    private let accent = Color(red: 1, green: 0.60, blue: 0.10)

    private var isDebut: Bool { series.played == 0 }
    private var duration: Double { reduceMotion ? 1.2 : 3.5 }
    private var opponentIsBot: Bool { series.opponentBotLevel != nil || series.isGhost }
    private var opponentAsset: String? { series.opponentBotLevel.map { BotLevel.get($0).photo } }

    var body: some View {
        ZStack {
            if isDebut { debutBackground } else { background }
            Group {
                if isDebut {
                    debutLayout
                } else {
                    rivalryLayout
                }
            }
            .frame(maxWidth: isDebut ? 520 : 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .foregroundStyle(.white)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(.dark)
        .onAppear(perform: startAutoContinue)
        .onDisappear { autoToken = UUID() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Klepni Začít hru nebo počkej")
    }

    private var accessibilityLabel: String {
        if isDebut {
            return "První vzájemný zápas proti \(series.opponentName). Bilance se teprve založí."
        }
        return "Head-to-Head proti \(series.opponentName). \(series.standingTitle) \(series.recordLine)."
    }

    /// Čistý list: žlutá plocha nahoře, černý seznam hráčů dole. Žádné skóre ani souboj portrétů.
    private var debutLayout: some View {
        VStack(spacing: 0) {
            debutHero
            debutSheet
        }
        .offset(y: appeared || reduceMotion ? 0 : 28)
    }

    private var debutHero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ČISTÝ LIST")
                .font(.caption.weight(.heavy))
                .tracking(1.8)
            Text("První\nzápas")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.45)
                .lineLimit(2)
            Text("S \(series.opponentName) ještě nemáte ani jeden společný výsledek.")
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity, alignment: .bottomLeading)
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 28)
    }

    private var debutSheet: some View {
        VStack(spacing: 0) {
            debutRow(
                kicker: "Ty",
                name: myName,
                photo: myPhoto,
                bot: false,
                asset: nil,
                badge: nil
            )
            Rectangle()
                .fill(Theme.brand.opacity(0.45))
                .frame(height: 1)
                .padding(.leading, 78)
            debutRow(
                kicker: opponentKicker,
                name: series.opponentName,
                photo: theirPhoto,
                bot: opponentIsBot,
                asset: opponentAsset,
                badge: opponentBadge
            )
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 32,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 32,
                style: .continuous
            )
            .fill(Color.black)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var opponentKicker: String {
        if series.isGhost { return "Ghost" }
        if series.opponentBotLevel != nil { return "Bot" }
        return "Soupeř"
    }

    private var opponentBadge: String? {
        series.opponentBotLevel.map { "Lv. \($0)" }
    }

    private func debutRow(kicker: String, name: String, photo: Data?, bot: Bool, asset: String?, badge: String?) -> some View {
        HStack(spacing: 14) {
            Avatar(name: name, bot: bot, size: 58, photo: photo, asset: asset)
                .overlay(Circle().strokeBorder(Theme.brand, lineWidth: 2))
            VStack(alignment: .leading, spacing: 2) {
                Text(kicker.uppercased())
                    .font(.caption2.weight(.heavy))
                    .tracking(1.1)
                    .foregroundStyle(Theme.brand)
                Text(name)
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 8)
            if let badge {
                Text(badge)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.brand, in: Capsule())
            }
        }
        .padding(.vertical, 16)
    }

    private var debutBackground: some View {
        ZStack(alignment: .topTrailing) {
            Theme.brand
            Text("0")
                .font(.system(size: 220, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.08))
                .offset(x: 40, y: 12)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    private var rivalryLayout: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            h2hPill
            if let me = store.profile?.id {
                ScrollView {
                    standing(me: me)
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
    }

    private var h2hPill: some View {
        Label("Head-to-Head", systemImage: "person.2.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(accent)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(accent.opacity(0.16), in: Capsule())
    }

    private func standing(me: UUID) -> some View {
        HeadToHeadStandingView(
            series: series,
            me: me,
            myName: myName,
            myPhoto: myPhoto,
            theirPhoto: theirPhoto,
            style: .ceremony,
            compact: true,
            onSelectMatch: nil
        )
    }

    private var background: some View {
        ZStack {
            canvas
            RadialGradient(colors: [accent.opacity(0.42), .clear], center: .top, startRadius: 0, endRadius: 560)
            RadialGradient(colors: [accent.opacity(0.12), .clear], center: .bottom, startRadius: 0, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    /// Stejná spodní lišta jako setup — glass menu, progress animace uvnitř tlačítka.
    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if onCancel != nil {
                    Button(action: cancel) {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 56, height: 56)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("Zavřít")
                }

                Button(action: continueNow) {
                    HStack(spacing: 8) {
                        Text("Začít hru")
                            .font(.headline)
                        Image(systemName: "play.fill")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                    .background {
                        // Stejná progress animace jako u zavřeného legu — uvnitř kapsle.
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Theme.brand
                                Rectangle()
                                    .fill(.white.opacity(0.34))
                                    .frame(width: geo.size.width * progress)
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Začít hru")
                .accessibilityHint("Nebo počkej, hra začne sama")
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func startAutoContinue() {
        progress = 0
        didContinue = false
        let token = UUID()
        autoToken = token
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)) {
            appeared = true
        }
        withAnimation(.linear(duration: duration)) { progress = 1 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard autoToken == token else { return }
            continueNow()
        }
    }

    private func continueNow() {
        guard !didContinue else { return }
        didContinue = true
        autoToken = UUID()
        onContinue()
    }

    private func cancel() {
        autoToken = UUID()
        didContinue = true
        onCancel?()
    }
}

// MARK: - Přehled bilance

struct HeadToHeadStandingView: View {
    enum Style { case light, ceremony }

    @EnvironmentObject private var store: AppStore
    var series: HeadToHead
    var me: UUID
    var myName: String
    var myPhoto: Data?
    var theirPhoto: Data?
    var style: Style
    var compact = false
    var onSelectMatch: ((UUID) -> Void)?

    private var isBehind: Bool { series.myWins < series.theirWins }
    private var isAhead: Bool { series.myWins > series.theirWins }
    private var isDebut: Bool { series.played == 0 }

    private var leadAmber: Color { Color(red: 1, green: 0.60, blue: 0.10) }
    private var lossRed: Color {
        style == .ceremony ? Color(red: 1, green: 0.38, blue: 0.32) : Color.red.opacity(0.85)
    }

    private var myTint: Color {
        if isBehind { return lossRed }
        if isAhead { return Theme.positive }
        return style == .ceremony ? leadAmber : .orange
    }
    private var theirTint: Color {
        if isBehind { return Theme.positive }
        if isAhead {
            return style == .ceremony ? Color.white.opacity(0.45) : Color.secondary.opacity(0.55)
        }
        return style == .ceremony ? Color.white.opacity(0.55) : Color.secondary.opacity(0.55)
    }
    private var cardFill: Color { style == .ceremony ? Color.white.opacity(0.07) : Theme.card }
    private var secondaryText: Color { style == .ceremony ? Color.white.opacity(0.55) : Color.secondary }
    private var primaryText: Color { style == .ceremony ? Color.white : Color.primary }
    private var historyMatches: [Match] {
        Array(series.matches.prefix(compact ? 4 : 30))
    }

    var body: some View {
        VStack(spacing: compact ? 14 : 20) {
            header
            // Pregame je jen rychlý přehled bilance — výkon patří do profilového H2H.
            if style == .light {
                performanceCard
            }
            if !historyMatches.isEmpty || !compact {
                resultsCard
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack(spacing: 0) {
                playerSide(name: myName, photo: myPhoto, bot: false, asset: nil, badge: nil, align: .leading, highlighted: !isDebut && !isBehind, completion: store.completionCaption(for: me), reservesCompletion: showsCompletion)
                if isDebut {
                    debutMark
                } else {
                    VStack(spacing: 4) {
                        Text(series.recordLine)
                            .font(.system(size: compact ? 34 : 40, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(myTint)
                        Text(series.standingTitle.uppercased())
                            .font(.caption.weight(.heavy))
                            .tracking(0.6)
                            .foregroundStyle(myTint.opacity(style == .ceremony ? 0.95 : 0.9))
                    }
                    .frame(minWidth: 96)
                }
                playerSide(
                    name: series.opponentName,
                    photo: theirPhoto,
                    bot: series.opponentBotLevel != nil || series.isGhost,
                    asset: series.opponentBotLevel.map { BotLevel.get($0).photo },
                    badge: series.opponentBotLevel.map { "Lv. \($0)" },
                    align: .trailing,
                    highlighted: !isDebut && isBehind,
                    completion: opponentCompletion,
                    reservesCompletion: showsCompletion
                )
            }

            if isDebut {
                debutNote
            } else {
                shareBar

                HStack(spacing: 0) {
                    metric("\(series.played)", "zápasů")
                    metricDivider
                    metric("\(series.myWins)", "výher", tint: series.myWins > 0 ? Theme.positive : nil)
                    metricDivider
                    metric("\(series.theirWins)", "proher", tint: series.theirWins > 0 ? lossRed : nil)
                    metricDivider
                    metric(
                        winRateLabel,
                        "úspěšnost",
                        tint: series.myWins + series.theirWins > 0 ? myTint : nil
                    )
                }
                .padding(.vertical, 10)
                .background(
                    (style == .light ? Theme.background : cardFill),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
        .padding(compact ? 14 : 16)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(headerStroke, lineWidth: style == .ceremony && !isBehind && !isAhead ? 1 : 1.2)
        )
    }

    private var headerStroke: Color {
        if isDebut { return leadAmber.opacity(style == .ceremony ? 0.45 : 0.35) }
        if isBehind { return lossRed.opacity(style == .ceremony ? 0.55 : 0.28) }
        if isAhead { return Theme.positive.opacity(style == .ceremony ? 0.45 : 0.28) }
        if style == .ceremony { return Color.white.opacity(0.08) }
        return Color.orange.opacity(0.4)
    }

    /// Zarovná „VS“ na portréty, ne mezi jméno a odznak.
    private var debutMark: some View {
        let mark: CGFloat = compact ? 52 : 58
        return VStack(spacing: 8) {
            Color.clear.frame(height: 18)
            ZStack {
                Circle().fill(leadAmber.opacity(style == .ceremony ? 0.18 : 0.12))
                Circle().strokeBorder(leadAmber.opacity(0.7), lineWidth: 1.5)
                Text("VS")
                    .font(.system(size: compact ? 15 : 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(leadAmber)
            }
            .frame(width: mark, height: mark)
            Color.clear.frame(height: 18)
        }
        .frame(minWidth: 72)
        .accessibilityHidden(true)
    }

    private var debutNote: some View {
        VStack(spacing: 4) {
            Text("První vzájemný zápas")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(primaryText)
            Text("Bilance se zapíše, až ho dohrajete.")
                .font(.caption)
                .foregroundStyle(secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            leadAmber.opacity(style == .ceremony ? 0.14 : 0.10),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    private var metricDivider: some View {
        Divider().frame(height: 32).overlay(style == .ceremony ? Color.white.opacity(0.12) : Color.primary.opacity(0.1))
    }

    private var winRateLabel: String {
        guard series.myWins + series.theirWins > 0 else { return "—" }
        return "\(Int((series.myWinRate * 100).rounded())) %"
    }

    private var opponentCompletion: String? {
        guard case .person(let id) = series.key.kind else { return nil }
        return store.completionCaption(for: id)
    }

    private var showsCompletion: Bool {
        store.completionCaption(for: me) != nil || opponentCompletion != nil
    }

    private func playerSide(
        name: String,
        photo: Data?,
        bot: Bool,
        asset: String?,
        badge: String?,
        align: HorizontalAlignment,
        highlighted: Bool,
        completion: String? = nil,
        reservesCompletion: Bool = false
    ) -> some View {
        VStack(alignment: align, spacing: 8) {
            if let badge {
                Text(badge)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(style == .ceremony ? Color.white.opacity(0.92) : Theme.brand, in: Capsule())
                    .foregroundStyle(.black)
            } else {
                Color.clear.frame(height: 18)
            }
            Avatar(name: name, bot: bot, size: compact ? 56 : 64, photo: photo, asset: asset)
                .overlay(
                    Circle().strokeBorder(playerRing(highlighted: highlighted), lineWidth: highlighted && style == .light ? 2.5 : 2)
                )
            Text(name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
            if completion != nil || reservesCompletion {
                Text(completion ?? " ")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(style == .ceremony ? Color.white.opacity(0.72) : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
                    .opacity(completion == nil ? 0 : 1)
                    .accessibilityHidden(completion == nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: align == .leading ? .leading : .trailing)
        .opacity(!highlighted && (isAhead || isBehind) ? 0.72 : 1)
    }

    private func playerRing(highlighted: Bool) -> Color {
        if highlighted { return Theme.positive }
        if isBehind { return lossRed.opacity(0.7) }
        if style == .ceremony { return .white.opacity(0.25) }
        return Theme.stroke
    }

    private var shareBar: some View {
        let total = max(series.myWins + series.theirWins + series.draws, 1)
        let mine = CGFloat(series.myWins) / CGFloat(total)
        let draws = CGFloat(series.draws) / CGFloat(total)
        let tied = !isAhead && !isBehind && series.myWins + series.theirWins > 0
        let myColor: Color = isBehind ? lossRed : (isAhead ? Theme.positive : leadAmber)
        let theirColor: Color = {
            if isBehind { return Theme.positive }
            if tied { return leadAmber.opacity(0.7) }
            return style == .ceremony ? Color.white.opacity(0.28) : Color.red.opacity(0.45)
        }()
        return GeometryReader { geo in
            HStack(spacing: 3) {
                Capsule().fill(myColor).frame(width: max(geo.size.width * mine, series.myWins > 0 ? 8 : 0))
                if series.draws > 0 {
                    Capsule().fill(leadAmber.opacity(0.85)).frame(width: max(geo.size.width * draws, 6))
                }
                Capsule().fill(theirColor)
            }
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityLabel("Podíl výher \(series.myWins) ku \(series.theirWins)")
    }

    private func metric(_ value: String, _ label: String, tint: Color? = nil) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(tint ?? primaryText)
            Text(label)
                .font(.caption2)
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func dotColor(_ outcome: H2HOutcome) -> Color {
        switch outcome {
        case .win: return Theme.positive
        case .loss: return lossRed
        case .draw: return leadAmber
        }
    }

    private var performanceCard: some View {
        let myAvg = series.myAverage(me: me)
        let theirAvg = series.theirAverage(me: me)
        let myCheck = series.myCheckout(me: me)
        let theirCheck = series.theirCheckout(me: me)
        let hasAvg = myAvg != nil || theirAvg != nil
        let hasCheck = myCheck.hasData || theirCheck.hasData

        return VStack(alignment: .leading, spacing: style == .light ? 18 : 14) {
            if style == .light {
                Label("Výkon", systemImage: "chart.bar.fill")
                    .font(.headline)
                    .foregroundStyle(primaryText)
            } else {
                Text("Výkon")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(secondaryText)
            }

            if !hasAvg && !hasCheck {
                Text("Po X01 zápasech tu uvidíš průměr a zavírání.")
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
            } else if style == .light {
                VStack(spacing: 10) {
                    if hasAvg {
                        duelRow(
                            title: "Průměr",
                            symbol: "target",
                            mine: myAvg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                            theirs: theirAvg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                            mineValue: myAvg ?? 0,
                            theirValue: theirAvg ?? 0
                        )
                    }
                    if hasCheck {
                        duelRow(
                            title: "Zavírání",
                            symbol: "checkmark.seal.fill",
                            mine: myCheck.percentage.map { "\(Int($0.rounded())) %" } ?? "—",
                            theirs: theirCheck.percentage.map { "\(Int($0.rounded())) %" } ?? "—",
                            mineValue: myCheck.percentage ?? 0,
                            theirValue: theirCheck.percentage ?? 0
                        )
                    }
                    if myCheck.hasData || theirCheck.hasData {
                        duelRow(
                            title: "Zásahy na double",
                            symbol: "scope",
                            mine: "\(myCheck.hits)/\(myCheck.attempts)",
                            theirs: "\(theirCheck.hits)/\(theirCheck.attempts)",
                            mineValue: myCheck.attempts > 0 ? Double(myCheck.hits) / Double(myCheck.attempts) : 0,
                            theirValue: theirCheck.attempts > 0 ? Double(theirCheck.hits) / Double(theirCheck.attempts) : 0
                        )
                    }
                    if myCheck.highest > 0 || theirCheck.highest > 0 {
                        duelRow(
                            title: "Nejvyšší checkout",
                            symbol: "trophy.fill",
                            mine: myCheck.highest > 0 ? "\(myCheck.highest)" : "—",
                            theirs: theirCheck.highest > 0 ? "\(theirCheck.highest)" : "—",
                            mineValue: Double(myCheck.highest),
                            theirValue: Double(theirCheck.highest)
                        )
                    }
                }
            } else {
                if hasAvg {
                    ceremonyMetric(
                        title: "Průměr X01",
                        mine: myAvg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                        theirs: theirAvg.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                        mineRatio: relativeRatio(myAvg, theirAvg),
                        theirRatio: relativeRatio(theirAvg, myAvg)
                    )
                }
                if hasCheck {
                    ceremonyMetric(
                        title: "Zavírání",
                        mine: myCheck.percentage.map { "\(Int($0.rounded())) %" } ?? "—",
                        theirs: theirCheck.percentage.map { "\(Int($0.rounded())) %" } ?? "—",
                        mineRatio: relativeRatio(myCheck.percentage, theirCheck.percentage),
                        theirRatio: relativeRatio(theirCheck.percentage, myCheck.percentage)
                    )
                }
            }
        }
        .padding(compact ? 14 : 16)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style == .ceremony ? Color.white.opacity(0.08) : Theme.stroke, lineWidth: style == .ceremony ? 1 : 0.5)
        )
    }

    private func relativeRatio(_ a: Double?, _ b: Double?) -> Double {
        let left = a ?? 0
        let right = b ?? 0
        let ceiling = max(left, right, 1)
        return left / ceiling
    }

    /// Ty | metrika | soupeř — přehledné srovnání s pruhem uprostřed.
    private func duelRow(
        title: String,
        symbol: String,
        mine: String,
        theirs: String,
        mineValue: Double,
        theirValue: Double
    ) -> some View {
        let ceiling = max(mineValue, theirValue, 1)
        let mineLead = mineValue > theirValue
        let theirLead = theirValue > mineValue
        return VStack(spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ty")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(mine)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(mineLead ? Theme.positive : (theirLead ? Color.red.opacity(0.85) : .primary))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(series.opponentName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(theirs)
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(theirLead ? Theme.positive : (mineLead ? Color.secondary : .primary))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            GeometryReader { geo in
                let mid = geo.size.width / 2 - 1
                let mineW = mid * CGFloat(mineValue / ceiling)
                let theirW = mid * CGFloat(theirValue / ceiling)
                HStack(spacing: 2) {
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Capsule()
                            .fill(mineLead ? Theme.positive : Color.red.opacity(0.55))
                            .frame(width: max(mineW, mineValue > 0 ? 8 : 0))
                    }
                    .frame(width: mid)
                    HStack(spacing: 0) {
                        Capsule()
                            .fill(theirLead ? Theme.positive : Color.secondary.opacity(0.4))
                            .frame(width: max(theirW, theirValue > 0 ? 8 : 0))
                        Spacer(minLength: 0)
                    }
                    .frame(width: mid)
                }
                .frame(maxHeight: .infinity)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
            }
            .frame(height: 8)
            .clipShape(Capsule())
        }
        .padding(14)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func ceremonyMetric(title: String, mine: String, theirs: String, mineRatio: Double, theirRatio: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(primaryText)
            compareRow(label: "Ty", value: mine, ratio: mineRatio, tint: myTint)
            compareRow(label: series.opponentName, value: theirs, ratio: theirRatio, tint: theirTint)
        }
    }

    private func compareRow(label: String, value: String, ratio: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(primaryText)
                    .lineLimit(1)
                Spacer()
                Text(value)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(geo.size.width * CGFloat(min(max(ratio, 0), 1)), value == "—" ? 0 : 6))
                }
            }
            .frame(height: 8)
        }
    }

    private var resultsCard: some View {
        let matches = historyMatches
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                if style == .light {
                    Label("Historie zápasů", systemImage: "clock.arrow.circlepath")
                        .font(.headline)
                        .foregroundStyle(primaryText)
                } else {
                    Text("POSLEDNÍ ZÁPASY")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(secondaryText)
                }
                Spacer()
                if series.played > matches.count {
                    Text("posledních \(matches.count)")
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                }
            }

            if matches.isEmpty {
                Text("Zatím žádný společný zápas")
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                        resultRow(match)
                        if index < matches.count - 1 {
                            Divider()
                                .overlay(style == .ceremony ? Color.white.opacity(0.08) : Color.primary.opacity(0.08))
                        }
                    }
                }
            }
        }
        .padding(compact ? 14 : 16)
        .background(cardFill, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(style == .ceremony ? Color.white.opacity(0.08) : Theme.stroke, lineWidth: style == .ceremony ? 1 : 0.5)
        )
    }

    @ViewBuilder
    private func resultRow(_ match: Match) -> some View {
        let outcome = series.outcome(of: match, me: me)
        let date = match.completedAt ?? match.createdAt
        let tone = dotColor(outcome)
        let content = HStack(spacing: 12) {
            Text(outcome.short)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tone, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(series.scoreLine(of: match, me: me))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tone)
                Text("\(match.config.mode.shortTitle) · \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(secondaryText)
            }
            Spacer(minLength: 8)
            if onSelectMatch != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(secondaryText)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        if let onSelectMatch {
            Button { onSelectMatch(match.id) } label: { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }
}

// MARK: - Seznam / náhledy

private struct RivalRow: View {
    @EnvironmentObject private var store: AppStore
    let series: HeadToHead

    private var tint: Color { h2hStandingTint(mine: series.myWins, theirs: series.theirWins) }
    private var tied: Bool { series.myWins == series.theirWins }

    private var opponentPhoto: Data? {
        guard case .person(let id) = series.key.kind else { return nil }
        return store.photo(for: id)
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Avatar(
                    name: series.opponentName,
                    bot: series.opponentBotLevel != nil || series.isGhost,
                    size: 56,
                    photo: opponentPhoto,
                    asset: series.opponentBotLevel.map { BotLevel.get($0).photo }
                )
                .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 2.5))
                if let level = series.opponentBotLevel {
                    Text("Lv.\(level)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.brand, in: Capsule())
                        .offset(x: 4, y: 4)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(series.opponentName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                formDots

                let total = max(series.myWins + series.theirWins, 1)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Capsule()
                            .fill(tied ? Color.orange : Theme.positive)
                            .frame(width: max(series.myWins > 0 ? 6 : 0, geo.size.width * CGFloat(series.myWins) / CGFloat(total)))
                        Capsule()
                            .fill(tied ? Color.orange.opacity(0.65) : Color.red.opacity(0.5))
                    }
                }
                .frame(height: 5)
                .clipShape(Capsule())
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text(series.recordLine)
                    .font(.title2.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(series.standingTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(tint)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(series.opponentName), \(series.myWins) ku \(series.theirWins), \(series.standingTitle)")
    }

    private var formDots: some View {
        let outcomes = Array(series.outcomesChronological(me: store.profile?.id ?? UUID()).suffix(5))
        return HStack(spacing: 4) {
            ForEach(Array(outcomes.enumerated()), id: \.offset) { _, outcome in
                Circle()
                    .fill(dot(outcome))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }

    private func dot(_ outcome: H2HOutcome) -> Color {
        switch outcome {
        case .win: return Theme.positive
        case .loss: return Color.red.opacity(0.8)
        case .draw: return .orange
        }
    }

    private var subtitle: String {
        let games = series.played == 1 ? "1 zápas" : "\(series.played) zápasů"
        if let level = series.opponentBotLevel { return "Bot · Lv. \(level) · \(games)" }
        if series.isGhost { return "Ghost · \(games)" }
        return games
    }
}

/// Kompaktní náhled vzájemné bilance (např. v detailu zápasu).
struct HeadToHeadPreviewCard: View {
    let series: HeadToHead

    private var tint: Color { h2hStandingTint(mine: series.myWins, theirs: series.theirWins) }

    var body: some View {
        HStack(spacing: 14) {
            Avatar(
                name: series.opponentName,
                bot: series.opponentBotLevel != nil || series.isGhost,
                size: 44,
                asset: series.opponentBotLevel.map { BotLevel.get($0).photo }
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(series.opponentName)
                    .font(.headline)
                    .lineLimit(1)
                Text("\(series.standingTitle) · \(series.recordLine)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }
}

/// Vstup do H2H hubu z Profilu.
struct HeadToHeadProfileEntry: View {
    @EnvironmentObject private var store: AppStore

    private var rivals: [HeadToHead] {
        guard let me = store.profile?.id else { return [] }
        return HeadToHead.rivals(from: store.matches, me: me)
    }

    private var totalWins: Int { rivals.reduce(0) { $0 + $1.myWins } }
    private var totalLosses: Int { rivals.reduce(0) { $0 + $1.theirWins } }
    private var standingTint: Color { h2hStandingTint(mine: totalWins, theirs: totalLosses) }

    var body: some View {
        NavigationLink {
            HeadToHeadListView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Head-to-Head")
                    .font(.headline)

                Spacer(minLength: 8)

                if !rivals.isEmpty {
                    Text("\(totalWins) : \(totalLosses)")
                        .font(.title3.weight(.heavy))
                        .monospacedDigit()
                        .foregroundStyle(standingTint)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Otevře vzájemné bilance")
    }

    private var accessibilityLabel: String {
        if rivals.isEmpty { return "Head-to-Head" }
        return "Head-to-Head, \(totalWins) ku \(totalLosses)"
    }
}

#if DEBUG
#Preview("Seznam") {
    NavigationStack { HeadToHeadListView() }.dartiqoPreview()
}
#Preview("Detail") {
    NavigationStack {
        HeadToHeadDetailView(rivalKey: PreviewSupport.sampleHeadToHead.key)
    }
    .dartiqoPreview()
}
#Preview("Před zápasem") {
    HeadToHeadPregameView(
        series: PreviewSupport.sampleHeadToHead,
        myName: "Ty",
        myPhoto: nil,
        theirPhoto: nil,
        onContinue: {},
        onCancel: {}
    )
    .dartiqoPreview()
}
#Preview("První vzájemný zápas") {
    HeadToHeadPregameView(
        series: .empty(key: RivalKey(kind: .person(UUID())), name: "Novák"),
        myName: "Ty",
        myPhoto: nil,
        theirPhoto: nil,
        onContinue: {},
        onCancel: {}
    )
    .dartiqoPreview()
}
#endif
