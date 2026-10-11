import SwiftUI
import Combine

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.needsRecovery { StorageRecoveryView() }
            else if store.locked { LockView() }
            else if store.profile == nil { WelcomeView() }
            else { MainTabView() }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var store: AppStore
    @State private var resumeMatch = false

    var body: some View {
        TabView(selection: $store.section) {
            NavigationStack { HomeView() }
                .id(store.homeGeneration)
                .tabItem { Label("Domů", systemImage: "house.fill") }
                .tag(AppSection.home)
            NavigationStack {
                SetupView(mode: .x01) {
                    store.section = .home
                }
            }
                .id(store.homeGeneration)
                .tabItem { Label("Hrát", systemImage: "target") }
                .tag(AppSection.play)
            NavigationStack { TrainingCenterView() }
                .id(store.homeGeneration)
                .tabItem { Label("Trénink", systemImage: "scope") }
                .tag(AppSection.training)
            NavigationStack { HistoryView() }
                .tabItem { Label("Moje hry", systemImage: "clock.arrow.circlepath") }
                .tag(AppSection.games)
            NavigationStack { ProfileView() }
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppSection.profile)
        }
        .tabViewBottomAccessory(isEnabled: store.activeMatch != nil && store.section != .play && !store.localSetupCoversBar) {
            if let match = store.activeMatch {
                MatchTabAccessory(match: match) {
                    store.tapHaptic()
                    resumeMatch = true
                }
            }
        }
        .fullScreenCover(isPresented: $resumeMatch) {
            NavigationStack { MatchView() }
                .environmentObject(store)
        }
        .onChange(of: store.homeGeneration) { _, _ in
            resumeMatch = false
            store.localSetupCoversBar = false
        }
        .onChange(of: store.activeMatch == nil) { _, gone in
            if gone { resumeMatch = false }
        }
    }
}

/// Plovoucí stav rozehraného zápasu nad tab barem. V nové hře i u Hrát lokálně je schovaný — návrat je v horní liště.
private struct MatchTabAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    var match: Match
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            switch placement {
            case .inline:
                inline
            case .expanded, .none:
                expanded
            @unknown default:
                expanded
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var expanded: some View {
        HStack(spacing: 12) {
            Image(systemName: match.finished ? "flag.checkered" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.brand)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(matchup)
                    .font(AppFont.body(15, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(AppFont.caption(12))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !match.finished {
                Text(scoreText)
                    .font(AppFont.title(22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.brand)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 4)
    }

    private var inline: some View {
        HStack(spacing: 6) {
            Image(systemName: match.finished ? "flag.checkered" : "play.fill")
            Text(match.finished ? "Výsledek" : scoreText)
                .monospacedDigit()
        }
        .font(AppFont.caption(13, weight: .bold))
        .lineLimit(1)
        .foregroundStyle(Theme.brand)
    }

    private var matchup: String {
        switch match.players.count {
        case 1: return match.players[0].name
        case 2: return "\(match.players[0].name) vs \(match.players[1].name)"
        default: return match.players.map(\.name).joined(separator: " · ")
        }
    }

    private var detail: String {
        if match.finished {
            if let winner = match.winner, match.players.indices.contains(winner) {
                return "Vyhrál \(match.players[winner].name)"
            }
            return "Zápas skončil"
        }
        if match.players.count == 1 { return "Skóre \(liveScore)" }
        return "\(liveScore) · na tahu \(match.currentPlayer.name)"
    }

    private var scoreText: String {
        figure(match.currentState)
    }

    /// Skóre všech hráčů v pořadí sestavy. U dvou hráčů jako „321 : 180“.
    private var liveScore: String {
        let values = match.states.map(figure)
        if match.players.count <= 2 {
            return values.joined(separator: " : ")
        }
        return match.players.indices.map { "\(match.players[$0].name) \(values[$0])" }.joined(separator: " · ")
    }

    private func figure(_ state: PlayerState) -> String {
        switch match.config.mode {
        case .x01:
            return "\(state.remaining)"
        case .cricket, .countUp:
            return "\(state.points)"
        case .aroundClock:
            return state.clockTarget > 20 ? "Bull" : "\(state.clockTarget)"
        }
    }

    private var accessibilityLabel: String {
        if match.finished { return "\(matchup). \(detail). Zobrazit výsledek." }
        return "Rozehraný zápas. \(matchup). \(detail). Pokračovat ve hře."
    }
}

#if DEBUG
#Preview("Bez zápasu") {
    RootView().dartiqoPreview(PreviewSupport.store(activeMatch: false))
}

#Preview("Rozehraný zápas") {
    RootView().dartiqoPreview(PreviewSupport.store(activeMatch: true))
}
#endif
