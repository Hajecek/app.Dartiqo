import Foundation

/// Výběr pole před odpalem. X01 řeší checkout, ostatní režimy drží původní cíle.
public enum BotTargetSelector {
    public static func aim<R: RandomNumberGenerator>(
        in game: Match,
        dartsLeft: Int,
        profile: BotProfile,
        thrown: [Dart]? = nil,
        using rng: inout R
    ) -> Dart {
        let visitDarts = thrown ?? game.currentDarts
        switch game.config.mode {
        case .x01:
            let state = game.currentState
            return BotCheckoutEngine.aim(
                remaining: state.remaining,
                dartsLeft: dartsLeft,
                rule: game.config.outRule(for: game.active),
                opened: state.opened,
                profile: profile,
                thrown: visitDarts,
                opponentAboveCheckout: rivalAboveCheckout(in: game),
                using: &rng
            )
        case .countUp:
            return countUpAim(in: game, profile: profile, thrown: visitDarts, using: &rng)
        case .cricket, .aroundClock:
            return modeAim(in: game, dartsLeft: dartsLeft)
        }
    }

    /// Stejné cíle jako dřív u kriketu, hodin a count-upu. U X01 optimální cesta bez náhodného zjednodušení.
    public static func deterministicAim(in game: Match, dartsLeft: Int, thrown: [Dart]? = nil) -> Dart {
        let visitDarts = thrown ?? game.currentDarts
        switch game.config.mode {
        case .x01:
            let profile = BotProfile.reference(level: game.currentPlayer.botLevel ?? 10)
            let state = game.currentState
            return BotCheckoutEngine.planned(
                remaining: state.remaining,
                dartsLeft: dartsLeft,
                rule: game.config.outRule(for: game.active),
                opened: state.opened,
                profile: profile,
                thrown: visitDarts
            )
        case .countUp:
            let profile = BotProfile.reference(level: game.currentPlayer.botLevel ?? 10)
            return BotCheckoutEngine.scoringAim(
                remaining: 501,
                rule: .straight,
                profile: profile,
                thrown: visitDarts
            )
        default:
            return modeAim(in: game, dartsLeft: dartsLeft)
        }
    }

    /// Soupeř je nad zavíráním, když ještě nemá checkout v příštích třech šipkách.
    private static func rivalAboveCheckout(in game: Match) -> Bool {
        let rivals = game.states.enumerated().filter { $0.offset != game.active }
        guard let rival = rivals.min(by: { $0.element.remaining < $1.element.remaining }) else { return true }
        let rule = game.config.outRule(for: rival.offset)
        let score = rival.element.remaining
        return score > 170 || !Checkout.canFinish(score, rule: rule, darts: 3)
    }

    private static func countUpAim<R: RandomNumberGenerator>(
        in game: Match,
        profile: BotProfile,
        thrown: [Dart],
        using rng: inout R
    ) -> Dart {
        BotCheckoutEngine.scoringAim(
            remaining: 501,
            rule: .straight,
            profile: profile,
            thrown: thrown,
            using: &rng
        )
    }

    private static func modeAim(in game: Match, dartsLeft: Int) -> Dart {
        let state = game.currentState
        switch game.config.mode {
        case .x01:
            return deterministicAim(in: game, dartsLeft: dartsLeft)
        case .cricket:
            let numbers = [20, 19, 18, 17, 16, 15, 25]
            if let open = numbers.first(where: { state.marks[$0, default: 0] < 3 }) {
                return Dart(open, open == 25 ? 2 : 3)
            }
            if let scoring = numbers.first(where: { number in
                game.states.indices.contains { $0 != game.active && game.states[$0].marks[number, default: 0] < 3 }
            }) {
                return Dart(scoring, scoring == 25 ? 2 : 3)
            }
            return Dart(25, 2)
        case .aroundClock:
            if state.clockTarget == 21 {
                return Dart(25, game.config.settings.clockStyle == .any ? 1 : 2)
            }
            let segment = min(20, state.clockTarget)
            switch game.config.settings.clockStyle {
            case .any: return Dart(segment)
            case .doubles: return Dart(segment, 2)
            case .triples: return Dart(segment, 3)
            }
        case .countUp:
            return deterministicAim(in: game, dartsLeft: dartsLeft)
        }
    }
}
