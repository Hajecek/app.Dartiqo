import Foundation

/// Geometrie standardního terče. Používá stejné poměry a pořadí čísel jako kreslený terč,
/// takže simulovaný zásah sedí na pole, které hráč vidí.
public enum DartboardGeometry {
    public static let segmentOrder = BoardGeometry.sectors
    public static let scoringRadius = 1.0
    public static let innerBull = BoardGeometry.innerBull
    public static let outerBull = BoardGeometry.outerBull
    public static let tripleInner = BoardGeometry.tripleInner
    public static let tripleOuter = BoardGeometry.tripleOuter
    public static let doubleInner = BoardGeometry.doubleInner

    public static func hit(x: Double, y: Double) -> Dart {
        BoardGeometry.hit(x: x, y: y)
    }

    /// Střed pole, na které bot míří. Odpovídá `BoardGeometry.marker`.
    public static func aim(segment: Int, multiplier: Int) -> (x: Double, y: Double) {
        let dart = Dart(segment, multiplier)
        if let point = BoardGeometry.marker(for: dart) { return point }
        return (0, 1.08)
    }

    public static func index(of segment: Int) -> Int? {
        segmentOrder.firstIndex(of: segment)
    }

    /// Sousedé po směru hodin a proti nim.
    public static func neighbors(of segment: Int) -> (clockwise: Int, counterClockwise: Int)? {
        guard let index = index(of: segment) else { return nil }
        let clockwise = segmentOrder[(index + 1) % segmentOrder.count]
        let counter = segmentOrder[(index + segmentOrder.count - 1) % segmentOrder.count]
        return (clockwise, counter)
    }
}
