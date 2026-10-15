import Foundation

/// Jedna šipka: záměr → odchylka v X/Y → skutečné pole. Skóre návštěvy se odtud neskládá.
public enum DartThrowSimulator {
    /// Mimo drát se šipka uloží těsně za bodovanou plochu, ať jde na terči vidět.
    static let missDisplayRadius = 1.08

    public static func `throw`<R: RandomNumberGenerator>(
        at target: Dart,
        profile: BotProfile,
        form: BotVisitForm = .neutral,
        pressure: Double = 1,
        radialBias: Double = 0,
        using rng: inout R
    ) -> Dart {
        let point = DartboardGeometry.aim(segment: target.segment, multiplier: target.multiplier)
        let shifted = shiftedAim(point, segment: target.segment, bias: radialBias)
        let sigma = profile.sigma(for: target) * form.sigmaScale * pressure
        let aimPart = BotThrowModel.aimShare
        let releasePart = (1 - aimPart * aimPart).squareRoot()
        let aimX = Gaussian.sample(&rng) * sigma * aimPart
        let aimY = Gaussian.sample(&rng) * sigma * aimPart
        let releaseX = Gaussian.sample(&rng) * sigma * releasePart * profile.horizontalScale
        let releaseY = Gaussian.sample(&rng) * sigma * releasePart * profile.verticalScale
        let x = shifted.x + form.biasX + aimX + releaseX
        let y = shifted.y + form.biasY + aimY + releaseY
        return placed(DartboardGeometry.hit(x: x, y: y), x: x, y: y)
    }

    /// Posun středu míření po poloměru. Kladná hodnota jde k okraji, ať treble neskončí přehozem.
    static func shiftedAim(_ point: (x: Double, y: Double), segment: Int, bias: Double) -> (x: Double, y: Double) {
        guard bias != 0, (1...20).contains(segment) else { return point }
        let radius = hypot(point.x, point.y)
        guard radius > 0.01 else { return point }
        let next = min(1.2, max(0.2, radius + bias))
        let scale = next / radius
        return (point.x * scale, point.y * scale)
    }

    static func placed(_ dart: Dart, x: Double, y: Double) -> Dart {
        guard x.isFinite, y.isFinite else { return .miss }
        guard dart.segment == 0 else { return dart }
        let radius = hypot(x, y)
        guard radius > missDisplayRadius, radius > 0 else { return Dart(0, 1, x: x, y: y) }
        let scale = missDisplayRadius / radius
        return Dart(0, 1, x: x * scale, y: y * scale)
    }
}
