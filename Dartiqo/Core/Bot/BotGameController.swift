import Foundation

/// Záměr a skutečný zásah jedné šipky.
public struct SimulatedDart: Equatable {
    public var aim: Dart
    public var result: Dart
}

/// Řídí návštěvu bota: forma, tlak, cíl, pak fyzický hod. Každá šipka se zapisuje zvlášť.
public enum BotGameController {
    public static func profile(for game: Match, override: BotProfile? = nil) -> BotProfile {
        override ?? BotProfile.from(player: game.currentPlayer)
    }

    public static func nextDart<R: RandomNumberGenerator>(in game: Match, profile override: BotProfile? = nil, using rng: inout R) -> Dart {
        simulateDart(in: game, profile: override, form: nil, using: &rng).result
    }

    /// `game` je skutečný stav včetně rozehraných šipek. Zbývající skóre se čte z projekce,
    /// forma zůstává u nedokončené návštěvy, aby se tři šipky nerozjely jiným rozptylem.
    public static func simulateDart<R: RandomNumberGenerator>(
        in game: Match,
        profile override: BotProfile? = nil,
        form fixed: BotVisitForm? = nil,
        using rng: inout R
    ) -> SimulatedDart {
        let profile = profile(for: game, override: override)
        let form = fixed ?? BotFormEngine.form(in: game, profile: profile)
        // Projekce spočítá zbývající skóre, ale smaže pending šipky — ty předáme zvlášť kvůli rotaci terci.
        let thrown = game.currentDarts
        let projected = game.liveProjection
        let dartsLeft = 3 - thrown.count
        let aim = BotTargetSelector.aim(
            in: projected,
            dartsLeft: dartsLeft,
            profile: profile,
            thrown: thrown,
            using: &rng
        )
        let state = projected.currentState
        let shift = BotCheckoutEngine.safetyShift(
            aim: aim,
            remaining: state.remaining,
            rule: projected.config.outRule(for: projected.active),
            sigma: profile.sigma(for: aim)
        )
        let result = DartThrowSimulator.throw(
            at: aim,
            profile: profile,
            form: form,
            pressure: BotFormEngine.pressure(in: projected, profile: profile),
            radialBias: shift,
            using: &rng
        )
        return SimulatedDart(aim: aim, result: result)
    }

    /// Až tři šipky. Po přehozu nebo zavření končí, stejně jako živý zápas.
    public static func simulateVisit<R: RandomNumberGenerator>(
        in game: Match,
        profile override: BotProfile? = nil,
        using rng: inout R
    ) -> [SimulatedDart] {
        var played = game
        let profile = profile(for: game, override: override)
        let form = BotFormEngine.form(in: game, profile: profile)
        var thrown: [SimulatedDart] = []
        for _ in 0..<3 {
            if played.finished || played.legWinner != nil || played.needsBullOff || played.needsDecidingStarter { break }
            let shot = simulateDart(in: played, profile: profile, form: form, using: &rng)
            thrown.append(shot)
            let before = played.visits.count
            do { try played.recordDart(shot.result) } catch { break }
            if played.visits.count > before { break }
        }
        return thrown
    }

    public static func visit<R: RandomNumberGenerator>(in game: Match, profile: BotProfile? = nil, using rng: inout R) -> [Dart] {
        simulateVisit(in: game, profile: profile, using: &rng).map(\.result)
    }
}
