import Foundation
import simd

/// Jeden hod z kamery: kde ho kamera viděla (obraz kamery 0…1) a jaké pole to opravdu bylo.
public struct DartSample: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var segment: Int
    public var multiplier: Int
    /// Hráč pole opravil. Potvrzené hody mají menší váhu, jen drží mapu na místě.
    public var corrected: Bool

    public init(x: Double, y: Double, segment: Int, multiplier: Int, corrected: Bool) {
        self.x = x
        self.y = y
        self.segment = segment
        self.multiplier = multiplier
        self.corrected = corrected
    }
}

/// Učí se z oprav. Každá oprava řekne, do kterého pole bod z kamery patří. Z nich se spočítá
/// korekce mapy (posun, otočení, zkosení), stažená k původní mapě, aby pár oprav nic nerozhodilo.
enum DartLearning {
    static let limit = 80
    static let stiffness = 0.5

    static func learn(_ calibration: BoardCalibration, adding new: [DartSample]) -> BoardCalibration {
        var next = calibration
        let samples = Array(((calibration.samples ?? []) + new).suffix(limit))
        next.samples = samples
        if let camera = calibration.camera {
            next.learned = correction(samples: samples, camera: camera)
        }
        return next
    }

    static func correction(samples: [DartSample], camera: [Double]) -> [Double]? {
        guard samples.contains(where: \.corrected), let inverse = PlaneFit.invert(camera) else { return nil }
        let points = samples.compactMap { sample -> (DartSample, SIMD2<Double>)? in
            PlaneFit.project(inverse, SIMD2(sample.x, sample.y)).map { (sample, $0) }
        }
        var affine = [1.0, 0, 0, 0, 1, 0]
        for _ in 0..<6 {
            let pairs = points.map { sample, raw -> (point: SIMD2<Double>, target: SIMD2<Double>, weight: Double) in
                let moved = SIMD2(affine[0] * raw.x + affine[1] * raw.y + affine[2], affine[3] * raw.x + affine[4] * raw.y + affine[5])
                let target = Self.target(segment: sample.segment, multiplier: sample.multiplier, near: moved)
                return (raw, target, sample.corrected ? 1 : 0.35)
            }
            guard let next = fit(pairs) else { return nil }
            affine = next
        }
        guard abs(affine[0] - 1) <= 0.2, abs(affine[1]) <= 0.2, abs(affine[3]) <= 0.2, abs(affine[4] - 1) <= 0.2,
              abs(affine[2]) <= 0.12, abs(affine[5]) <= 0.12 else { return nil }
        return affine
    }

    private static func fit(_ pairs: [(point: SIMD2<Double>, target: SIMD2<Double>, weight: Double)]) -> [Double]? {
        var rows: [[Double]] = []
        for (axis, identity) in [[1.0, 0, 0], [0, 1.0, 0]].enumerated() {
            var normal = [Double](repeating: 0, count: 9)
            var rhs = identity.map { $0 * stiffness }
            for index in 0..<3 { normal[index * 3 + index] = stiffness }
            for pair in pairs {
                let p = [pair.point.x, pair.point.y, 1]
                let value = axis == 0 ? pair.target.x : pair.target.y
                for i in 0..<3 {
                    rhs[i] += pair.weight * p[i] * value
                    for j in 0..<3 { normal[i * 3 + j] += pair.weight * p[i] * p[j] }
                }
            }
            guard let inverseNormal = PlaneFit.invert(normal) else { return nil }
            rows.append((0..<3).map { i in (0..<3).reduce(0) { $0 + inverseNormal[i * 3 + $1] * rhs[$1] } })
        }
        let affine = rows[0] + rows[1]
        return affine.allSatisfy(\.isFinite) ? affine : nil
    }

    /// Nejbližší bod uvnitř opraveného pole (s malým okrajem od drátů).
    static func target(segment: Int, multiplier: Int, near point: SIMD2<Double>) -> SIMD2<Double> {
        let radius = simd_length(point)
        var theta = radius > 1e-6 ? atan2(point.y, point.x) : -Double.pi / 2
        var range: ClosedRange<Double>
        switch segment {
        case 25:
            range = multiplier == 2 ? 0...BoardGeometry.innerBull * 0.6 : BoardGeometry.innerBull * 1.3...BoardGeometry.outerBull * 0.85
        case 0:
            range = 1.05...max(1.05, radius)
        default:
            guard let index = BoardGeometry.sectors.firstIndex(of: segment) else { return point }
            let center = (-90 + 18 * Double(index)) * .pi / 180
            let spread = 6.5 * .pi / 180
            let delta = BoardDetector.wrap(theta - center)
            theta = center + min(max(delta, -spread), spread)
            switch multiplier {
            case 2: range = 0.962...0.99
            case 3: range = 0.59...0.62
            default:
                let inner = BoardGeometry.outerBull * 1.15...BoardGeometry.tripleInner * 0.97
                let outer = BoardGeometry.tripleOuter * 1.02...BoardGeometry.doubleInner * 0.985
                range = abs(radius - inner.clamped(radius)) <= abs(radius - outer.clamped(radius)) ? inner : outer
            }
        }
        let clamped = range.clamped(radius)
        return SIMD2(cos(theta), sin(theta)) * clamped
    }
}

private extension ClosedRange where Bound == Double {
    func clamped(_ value: Double) -> Double { Swift.min(Swift.max(value, lowerBound), upperBound) }
}
