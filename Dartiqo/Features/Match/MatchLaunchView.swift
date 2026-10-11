import SwiftUI

/// Úvod s logem před novým zápasem. Po krátké chvíli se rovnou otevře hra.
struct MatchLaunchView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var intro = true

    @State private var ready = false
    @State private var pulse = false
    @State private var appeared = false

    private let canvas = Color(red: 0.04, green: 0.07, blue: 0.06)
    private let glow = Color(red: 1, green: 0.72, blue: 0.12)
    /// Dostat času na sestavení MatchView a animaci splash.
    private let introDuration: UInt64 = 2_400_000_000

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
        .animation(.easeInOut(duration: 0.45), value: ready)
        .task {
            guard intro, !ready else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86)) {
                appeared = true
            }
            pulse = true
            try? await Task.sleep(nanoseconds: introDuration)
            ready = true
        }
    }

    private var splash: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                logoMark
                    .padding(.top, 28)
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                    .opacity(appeared || reduceMotion ? 1 : 0)

                Spacer(minLength: 20)

                if let match = store.activeMatch {
                    matchup(match)
                        .padding(.horizontal, 24)
                        .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                        .opacity(appeared || reduceMotion ? 1 : 0)
                }

                Spacer(minLength: 20)

                loadingFooter
                    .padding(.bottom, 36)
                    .opacity(appeared || reduceMotion ? 1 : 0)
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySplashLabel)
    }

    private var accessibilitySplashLabel: String {
        guard let match = store.activeMatch else { return "Načítám hru" }
        let starter = match.players[match.starter].name
        return "Načítám hru. \(match.players.map(\.name).joined(separator: " proti ")). Začíná \(starter)."
    }

    private var background: some View {
        ZStack {
            canvas
            RadialGradient(
                colors: [glow.opacity(0.38), glow.opacity(0.08), .clear],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [Theme.brand.opacity(0.14), .clear],
                center: UnitPoint(x: 0.15, y: 0.85),
                startRadius: 10,
                endRadius: 320
            )
            RadialGradient(
                colors: [Color(red: 0.12, green: 0.28, blue: 0.18).opacity(0.55), .clear],
                center: UnitPoint(x: 0.9, y: 0.55),
                startRadius: 20,
                endRadius: 380
            )
            DartboardArt()
                .opacity(0.07)
                .scaleEffect(1.35)
                .offset(y: 40)
                .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    private var logoMark: some View {
        GlassEffectContainer(spacing: 0) {
            Image("Logo")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .padding(14)
                .contentShape(Circle())
        }
        .glassEffect(.regular, in: Circle())
        .scaleEffect(pulse && !reduceMotion ? 1.04 : 0.98)
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true),
            value: pulse
        )
        .accessibilityLabel("Dartiqo")
    }

    private func matchup(_ match: Match) -> some View {
        VStack(spacing: 22) {
            if match.players.count == 2 {
                HStack(spacing: 10) {
                    playerTile(match.players[0], starts: match.starter == 0)
                    Text("VS")
                        .font(AppFont.caption(13, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 28)
                    playerTile(match.players[1], starts: match.starter == 1)
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(Array(match.players.enumerated()), id: \.offset) { index, player in
                        playerTile(player, starts: index == match.starter, compact: true)
                    }
                }
            }

            Text(caption(match))
                .font(AppFont.caption(14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func playerTile(_ player: Player, starts: Bool, compact: Bool = false) -> some View {
        let look = avatarLook(for: player)
        return VStack(spacing: compact ? 8 : 10) {
            Avatar(
                name: player.name,
                bot: look.bot,
                size: compact ? 56 : 72,
                photo: look.photo,
                asset: look.asset
            )
            .overlay(
                Circle()
                    .strokeBorder(starts ? Theme.brand : Color.white.opacity(0.18), lineWidth: starts ? 3 : 1.5)
            )
            .shadow(color: starts ? Theme.brand.opacity(0.35) : .clear, radius: 10, y: 2)

            Text(player.name)
                .font(AppFont.caption(14, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)

            Text(starts ? "ZAČÍNÁ" : " ")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(starts ? Theme.brand : .clear)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(starts ? Theme.brand.opacity(0.16) : Color.clear, in: Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private func avatarLook(for player: Player) -> (photo: Data?, asset: String?, bot: Bool) {
        if let level = player.botLevel {
            return (nil, BotLevel.get(level).photo, true)
        }
        return (store.photo(for: player.id), nil, false)
    }

    private var loadingFooter: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.brand)
            Text("Načítám hru")
                .font(AppFont.caption(15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
                .tracking(0.4)
        }
    }

    private func caption(_ match: Match) -> String {
        let mode = match.config.mode
        if mode == .x01 || mode == .cricket { return "\(mode.shortTitle) · \(match.config.lengthLine)" }
        return match.config.summary
    }
}
