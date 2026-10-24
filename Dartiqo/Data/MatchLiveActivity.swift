import ActivityKit
import Foundation
import UIKit

/// Live Activity rozehraného zápasu na zamčené obrazovce a v Dynamic Islandu.
/// Spouští se jen v popředí, aktualizuje se jen při změně a po dohrání zůstane chvíli vidět výsledek.
@MainActor final class MatchLiveActivity {
    static let shared = MatchLiveActivity()

    private typealias Attributes = MatchActivityAttributes
    private typealias State = MatchActivityAttributes.ContentState

    private struct Request {
        var match: Match?
        var paused: Bool
        var played: Int
        var running: Bool
    }

    /// Bez aktualizace se aktivita po této době ukáže jako neaktuální.
    private static let staleAfter: TimeInterval = 30 * 60
    /// Výsledek dohraného zápasu zůstane na zamčené obrazovce.
    private static let resultLingers: TimeInterval = 30 * 60

    private var activity: Activity<Attributes>?
    private var sentState: State?
    /// Zápasy, jejichž aktivitu hráč sám smazal. Pro stejný zápas se znovu nespustí.
    private var dismissedMatches = Set<UUID>()
    private var adopted = false
    private var latest: Request?
    private var working = false

    private init() {}

    func update(_ match: Match?, paused: Bool, played: Int, running: Bool) {
        latest = Request(match: match, paused: paused, played: played, running: running)
        guard !working else { return }
        Task { await drain() }
    }

    /// Volání ActivityKit jsou asynchronní. Běží vždy jen jedno a novější stav přepíše čekající.
    private func drain() async {
        working = true
        defer { working = false }
        while let request = latest {
            latest = nil
            await apply(request)
        }
    }

    private func apply(_ request: Request) async {
        await adoptRunningActivity(for: request.match?.id)
        forgetClosedActivity()

        guard let match = request.match else {
            await endCurrent(immediately: true)
            return
        }
        if let activity, activity.attributes.matchID != match.id {
            await endCurrent(immediately: true)
        }

        let state = Self.state(for: match, paused: request.paused, played: request.played, running: request.running)

        if let activity {
            if match.finished {
                await activity.end(
                    ActivityContent(state: state, staleDate: nil, relevanceScore: 100),
                    dismissalPolicy: .after(Date().addingTimeInterval(Self.resultLingers))
                )
                self.activity = nil
                sentState = nil
                return
            }
            guard state != sentState else { return }
            await activity.update(content(state))
            sentState = state
            return
        }

        guard !match.finished, !dismissedMatches.contains(match.id),
              ActivityAuthorizationInfo().areActivitiesEnabled,
              UIApplication.shared.applicationState == .active else { return }
        // Výsledek po vrácení posledního hodu nesmí zůstat vedle nové aktivity stejného zápasu
        for old in Activity<Attributes>.activities where old.attributes.matchID == match.id {
            await old.end(nil, dismissalPolicy: .immediate)
        }
        do {
            activity = try Activity.request(attributes: Self.attributes(for: match), content: content(state), pushType: nil)
            sentState = state
        } catch {
            activity = nil
            sentState = nil
        }
    }

    private func content(_ state: State) -> ActivityContent<State> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter), relevanceScore: 100)
    }

    /// Po restartu aplikace převezme běžící aktivitu svého zápasu. Ostatní ukončí.
    private func adoptRunningActivity(for matchID: UUID?) async {
        guard !adopted else { return }
        adopted = true
        for running in Activity<Attributes>.activities where [.active, .stale].contains(running.activityState) {
            if activity == nil, running.attributes.matchID == matchID {
                activity = running
            } else if running.id != activity?.id {
                await running.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Aktivitu mohl odstranit hráč nebo systém (po osmi hodinách). Hráčovo rozhodnutí se respektuje.
    private func forgetClosedActivity() {
        guard let activity else { return }
        switch activity.activityState {
        case .active, .stale:
            return
        case .dismissed:
            dismissedMatches.insert(activity.attributes.matchID)
        default:
            break
        }
        self.activity = nil
        sentState = nil
    }

    private func endCurrent(immediately: Bool) async {
        guard let activity else { return }
        self.activity = nil
        sentState = nil
        await activity.end(nil, dismissalPolicy: immediately ? .immediate : .default)
    }

    // MARK: - Stav z modelu zápasu

    private static func attributes(for match: Match) -> Attributes {
        let config = match.config
        let rules: String
        switch config.mode {
        case .x01:
            var parts = ["\(config.startingScore)", config.outRule.shortTitle]
            if config.doubleIn { parts.append("Double in") }
            rules = parts.joined(separator: " · ")
        case .cricket:
            rules = config.settings.cricketNoScore ? "Bez bodů" : "S body"
        case .aroundClock:
            rules = config.settings.clockStyle.title
        case .countUp:
            rules = "\(config.settings.countUpRounds) kol"
        }
        let length = [.x01, .cricket].contains(config.mode) ? config.lengthLine : ""
        return Attributes(
            matchID: match.id,
            mode: config.mode.title,
            rules: rules,
            length: length,
            players: match.players.indices.map {
                Attributes.Player(name: match.players[$0].name, bot: match.players[$0].botLevel != nil || match.isGhost($0))
            },
            playsSets: config.playsSets
        )
    }

    private static func state(for match: Match, paused: Bool, played: Int, running: Bool) -> State {
        let live = match.liveProjection
        let config = match.config
        let phase: State.Phase
        if match.finished { phase = .finished }
        else if match.legWinner != nil { phase = .legWon }
        else if match.needsBullOff { phase = .bullOff }
        else if match.needsDecidingStarter { phase = .decidingStarter }
        else { phase = .playing }

        var hint: String?
        var hintIsCheckout = false
        let left = 3 - match.currentDarts.count
        if phase == .playing, config.mode == .x01, left > 0 {
            let remaining = live.states[live.active].remaining
            let rule = config.outRule(for: live.active)
            if let route = Checkout.route(for: remaining, rule: rule, darts: left) {
                hint = route.map(\.label).joined(separator: " ")
                hintIsCheckout = true
            } else if let setup = Checkout.setup(for: remaining, rule: rule, darts: left) {
                hint = "\(setup.darts.map(\.label).joined(separator: " ")) → \(setup.leaveLabel)"
            }
        }

        let isRunning = running && !paused && !match.finished
        let seconds = max(0, played)
        return State(
            phase: phase,
            lines: live.states.indices.map { index in
                State.Line(
                    score: figure(live.states[index], mode: config.mode),
                    legs: live.states[index].legs,
                    sets: live.states[index].sets,
                    last: match.lastTurnScore(for: index)
                )
            },
            active: live.active,
            leg: live.leg,
            set: config.playsSets ? min(live.states.reduce(0) { $0 + $1.sets } + 1, config.shownSets) : 1,
            darts: phase == .playing ? match.currentDarts.map(\.label) : [],
            hint: hint,
            hintIsCheckout: hintIsCheckout,
            legWinner: match.legWinner,
            winner: match.winner,
            paused: paused && !match.finished,
            played: seconds,
            clockStart: isRunning ? Date().addingTimeInterval(-TimeInterval(seconds)) : nil
        )
    }

    private static func figure(_ state: PlayerState, mode: GameMode) -> String {
        switch mode {
        case .x01: return "\(state.remaining)"
        case .cricket, .countUp: return "\(state.points)"
        case .aroundClock: return state.clockTarget > 20 ? "Bull" : "\(state.clockTarget)"
        }
    }
}
