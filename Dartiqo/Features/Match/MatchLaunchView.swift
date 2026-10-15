import SwiftUI

/// Úvod před novým zápasem — černé plátno, žlutý pás a sestava, pak rovnou hra.
struct MatchLaunchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var intro = true

    @State private var ready = false
    @State private var showContent = false
    @State private var floorUp = false
    @State private var loadProgress: CGFloat = 0

    private let introSeconds: Double = 2.4

    var body: some View {
        ZStack {
            if ready || !intro {
                NavigationStack { MatchView() }
                    .transition(.opacity)
            } else {
                splash
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: ready)
        .task { await runIntro() }
    }

    private func runIntro() async {
        guard intro, !ready else { return }

        if reduceMotion {
            floorUp = true
            showContent = true
            loadProgress = 1
#if DEBUG
            if PreviewSupport.isXcodePreview { return }
#endif
            try? await Task.sleep(nanoseconds: UInt64(introSeconds * 0.4 * 1_000_000_000))
            ready = true
            return
        }

        withAnimation(.spring(response: 0.7, dampingFraction: 0.88)) { floorUp = true }
        try? await Task.sleep(nanoseconds: 160_000_000)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { showContent = true }

#if DEBUG
        if PreviewSupport.isXcodePreview {
            withAnimation(.linear(duration: 1.1)) { loadProgress = 0.7 }
            return
        }
#endif

        withAnimation(.linear(duration: introSeconds)) { loadProgress = 1 }
        try? await Task.sleep(nanoseconds: UInt64(introSeconds * 1_000_000_000))
        ready = true
    }

    private var splash: some View {
        ZStack(alignment: .bottom) {
            Color.black.ignoresSafeArea()

            // Velký watermark režimu — jediná dekorace na černém plátně.
            if let match = store.activeMatch {
                Text(watermark(match))
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.045))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 96)
                    .offset(y: showContent || reduceMotion ? 0 : 24)
                    .opacity(showContent || reduceMotion ? 1 : 0)
                    .accessibilityHidden(true)
            }

            VStack(spacing: 0) {
                brandHeader
                    .padding(.top, 28)
                    .opacity(showContent || reduceMotion ? 1 : 0)
                    .offset(y: showContent || reduceMotion ? 0 : -12)

                Spacer(minLength: 20)

                if let match = store.activeMatch {
                    matchup(match)
                        .padding(.horizontal, 24)
                        .opacity(showContent || reduceMotion ? 1 : 0)
                        .scaleEffect(showContent || reduceMotion ? 1 : 0.96)
                }

                Spacer(minLength: 20)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 108)

            yellowFloor
                .offset(y: floorUp || reduceMotion ? 0 : 120)
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySplashLabel)
    }

    private var accessibilitySplashLabel: String {
        guard let match = store.activeMatch else { return "Načítám hru" }
        let starter = match.players[match.starter].name
        return "Načítám hru. \(match.players.map(\.name).joined(separator: " proti ")). Začíná \(starter)."
    }

    // MARK: - Brand

    private var brandHeader: some View {
        HStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 40, height: 40)
                .clipShape(Circle())

            Text("Dartiqo")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .tracking(-0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Dartiqo")
    }

    // MARK: - Matchup

    private func matchup(_ match: Match) -> some View {
        VStack(spacing: 28) {
            Text(caption(match))
                .font(AppFont.caption(13, weight: .bold))
                .foregroundStyle(Theme.brand)
                .tracking(1.4)
                .textCase(.uppercase)

            switch match.players.count {
            case 1: solo(match.players[0])
            case 2: duel(match)
            case 4: quartet(match)
            default: trio(match)
            }

            if let starter = match.players[safe: match.starter] {
                Text("Začíná \(starter.name)")
                    .font(AppFont.body(17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }

    private func duel(_ match: Match) -> some View {
        HStack(alignment: .center, spacing: 8) {
            playerBlock(match.players[0], index: 0, starts: match.starter == 0)
            Text("–")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))
                .frame(width: 36)
            playerBlock(match.players[1], index: 1, starts: match.starter == 1)
        }
    }

    private func solo(_ player: Player) -> some View {
        playerBlock(player, index: 0, starts: true, size: 120)
    }

    private func trio(_ match: Match) -> some View {
        VStack(spacing: 22) {
            playerBlock(match.players[0], index: 0, starts: match.starter == 0, size: 88)
            HStack(spacing: 36) {
                playerBlock(match.players[1], index: 1, starts: match.starter == 1, size: 78)
                playerBlock(match.players[2], index: 2, starts: match.starter == 2, size: 78)
            }
        }
    }

    private func quartet(_ match: Match) -> some View {
        VStack(spacing: 26) {
            HStack(spacing: 40) {
                playerBlock(match.players[0], index: 0, starts: match.starter == 0, size: 84)
                playerBlock(match.players[1], index: 1, starts: match.starter == 1, size: 84)
            }
            HStack(spacing: 40) {
                playerBlock(match.players[2], index: 2, starts: match.starter == 2, size: 84)
                playerBlock(match.players[3], index: 3, starts: match.starter == 3, size: 84)
            }
        }
    }

    private func playerBlock(_ player: Player, index: Int, starts: Bool, size: CGFloat = 96) -> some View {
        let look = avatarLook(for: player)
        let bot = player.botLevel.map(BotLevel.get)
        let badge = max(22, size * 0.26)
        return VStack(spacing: bot == nil ? 12 : 14) {
            Avatar(
                name: player.name,
                bot: look.bot,
                size: size,
                photo: look.photo,
                asset: look.asset
            )
            .overlay(
                Circle()
                    .strokeBorder(starts ? Theme.brand : Color.white.opacity(0.2), lineWidth: starts ? 3 : 1)
            )
            .overlay(alignment: .bottom) {
                if let bot {
                    Text("\(bot.id)")
                        .font(AppFont.caption(badge * 0.42, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: badge, height: badge)
                        .background(
                            Circle()
                                .fill(Theme.brand)
                                .shadow(color: Theme.brand.opacity(0.45), radius: 6, y: 2)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black, lineWidth: 2.5)
                        )
                        .offset(y: badge * 0.28)
                        .accessibilityLabel("Level \(bot.id)")
                }
            }
            .padding(.bottom, bot == nil ? 0 : badge * 0.22)

            VStack(spacing: 5) {
                Text(player.name)
                    .font(AppFont.title(size > 90 ? 20 : 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if let bot {
                    levelMeter(bot.id, width: min(92, size * 0.9))
                    Text(player.adaptiveBot == true ? "Adaptive · \(bot.name)" : bot.name)
                        .font(AppFont.caption(11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.48))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Text(starts ? "první hod" : " ")
                    .font(AppFont.caption(12, weight: .semibold))
                    .foregroundStyle(starts ? Theme.brand : .clear)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(showContent || reduceMotion ? 1 : 0)
        .offset(y: showContent || reduceMotion ? 0 : 16)
        .animation(
            reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86).delay(Double(index) * 0.05),
            value: showContent
        )
    }

    private func levelMeter(_ level: Int, width: CGFloat) -> some View {
        let level = min(BotDifficulty.count, max(1, level))
        return Capsule()
            .fill(Color.white.opacity(0.14))
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(Theme.brand)
                    .frame(width: max(6, width * CGFloat(level) / CGFloat(BotDifficulty.count)))
            }
            .frame(width: width, height: 6)
            .accessibilityHidden(true)
    }

    private func avatarLook(for player: Player) -> (photo: Data?, asset: String?, bot: Bool) {
        if let level = player.botLevel {
            return (nil, BotLevel.get(level).photo, true)
        }
        return (store.photo(for: player.id), nil, false)
    }

    // MARK: - Floor

    private var yellowFloor: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.black.opacity(0.18))
                    Capsule()
                        .fill(Color.black)
                        .frame(width: max(10, geo.size.width * loadProgress))
                }
            }
            .frame(height: 5)

            Text("Připravuju hru")
                .font(AppFont.caption(14, weight: .bold))
                .foregroundStyle(Color.black.opacity(0.72))
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
        .background(Theme.brand.ignoresSafeArea(edges: .bottom))
    }

    private func caption(_ match: Match) -> String {
        let mode = match.config.mode
        if mode == .x01 || mode == .cricket { return "\(mode.shortTitle) · \(match.config.lengthLine)" }
        return match.config.summary
    }

    private func watermark(_ match: Match) -> String {
        switch match.config.mode {
        case .x01: return "\(match.config.startingScore)"
        case .cricket: return "CRI"
        default: return match.config.mode.shortTitle.uppercased()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#if DEBUG
#Preview("1v1") {
    MatchLaunchView().dartiqoPreview(PreviewSupport.store(players: 2))
}
#Preview("Sólo") {
    MatchLaunchView().dartiqoPreview(PreviewSupport.store(players: 1))
}
#Preview("3 hráči") {
    MatchLaunchView().dartiqoPreview(PreviewSupport.store(players: 3))
}
#Preview("4 hráči") {
    MatchLaunchView().dartiqoPreview(PreviewSupport.store(players: 4))
}
#endif
