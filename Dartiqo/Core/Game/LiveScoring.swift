import Foundation

extension Match {
    public var currentDarts: [Dart] { pendingDarts ?? [] }
    /// Committed state plus the persisted, unfinished visit. Never writes history twice.
    public var liveProjection: Match {
        guard !currentDarts.isEmpty else { return self }
        var copy = self
        copy.pendingDarts = nil
        try? copy.submit(currentDarts, allowPartial: true)
        copy.active = active
        copy.finished = finished
        copy.winner = winner
        copy.legWinner = legWinner
        copy.completedAt = completedAt
        return copy
    }
    /// One tap is one dart. The third dart, bust or checkout ends a visit automatically.
    public mutating func recordDart(_ dart: Dart) throws {
        guard !finished else { throw GameError.finished }
        guard legWinner == nil, !needsBullOff else { throw GameError.legEnded }
        guard dart.isValid, currentDarts.count < 3 else { throw GameError.invalidDarts }
        let input = currentDarts + [dart]
        var next = self
        next.pendingDarts = nil
        try next.submit(input, allowPartial: true)
        let visit = next.visits.last
        if input.count == 3 || visit?.bust == true || visit?.checkout == true {
            self = next
        } else {
            pendingDarts = input
        }
    }
    /// Undo one dart from the open visit, or reopen the last completed visit one dart at a time.
    /// Works for human and bot throws alike.
    public mutating func undoLastInput() {
        if !currentDarts.isEmpty {
            let next = Array(currentDarts.dropLast())
            pendingDarts = next.isEmpty ? nil : next
            return
        }
        if undoStack.last?.visitCount == visits.count { undo(); return }
        guard let last = visits.last else { return }
        let retained = last.enteredAsTotal == true ? [] : Array(last.darts.dropLast())
        undo()
        pendingDarts = retained.isEmpty ? nil : retained
    }
}

/// Normalised geometry shared by rendering and hit testing. 20 is centred at twelve o'clock.
public enum BoardGeometry {
    public static let sectors = [20,1,18,4,13,6,10,15,2,17,3,19,7,16,8,11,14,9,12,5]
    public static let innerBull = 0.03735
    public static let outerBull = 0.09353
    public static let tripleInner = 0.58235
    public static let tripleOuter = 0.62941
    public static let doubleInner = 0.95294
    public static func hit(x: Double, y: Double) -> Dart {
        guard x.isFinite, y.isFinite else { return .miss }
        let radius = hypot(x, y)
        guard radius <= 1 else { return Dart(0, 1, x: x, y: y) }
        if radius <= innerBull { return Dart(25, 2, x: x, y: y) }
        if radius <= outerBull { return Dart(25, 1, x: x, y: y) }
        var angle = atan2(y, x) + Double.pi / 2 + Double.pi / 20
        angle.formTruncatingRemainder(dividingBy: 2 * Double.pi)
        if angle < 0 { angle += 2 * Double.pi }
        let segment = sectors[min(19, Int(angle / (2 * Double.pi / 20)))]
        let multiplier = radius >= doubleInner ? 2 : (tripleInner...tripleOuter).contains(radius) ? 3 : 1
        return Dart(segment, multiplier, x: x, y: y)
    }
    public static func marker(for dart: Dart) -> (x: Double, y: Double)? {
        if let x = dart.x, let y = dart.y, x.isFinite, y.isFinite { return (x, y) }
        if dart.segment == 0 { return nil }
        if dart.segment == 25 { return dart.multiplier == 2 ? (0, 0) : (0, -0.068) }
        guard let index = sectors.firstIndex(of: dart.segment) else { return nil }
        let angle = -Double.pi / 2 + Double(index) * Double.pi / 10
        let radius = dart.multiplier == 2 ? 0.976 : dart.multiplier == 3 ? 0.606 : 0.79
        return (cos(angle) * radius, sin(angle) * radius)
    }
}
