import Foundation

/// Postup levelů: každý další level chce o `growth` víc XP než předchozí.
///
/// 1→2: 500 · 2→3: 575 · 3→4: 661 · 4→5: 760 · …
public enum PlayerLevel {
    public static let baseXP = 500
    /// +15 % XP na každý další level.
    public static let growth = 0.15

    /// Kolik XP stojí přechod z `level` na `level + 1` (level je 1-based).
    public static func xpToAdvance(from level: Int) -> Int {
        let safe = max(1, level)
        let raw = Double(baseXP) * pow(1 + growth, Double(safe - 1))
        return max(baseXP, Int(raw.rounded()))
    }

    /// Celkové XP potřebné na dosažení daného levelu (level 1 = 0).
    public static func totalXP(toReach level: Int) -> Int {
        let safe = max(1, level)
        guard safe > 1 else { return 0 }
        var total = 0
        for current in 1..<(safe) {
            total += xpToAdvance(from: current)
        }
        return total
    }

    public static func level(forXP xp: Int) -> Int {
        let safe = max(0, xp)
        var level = 1
        var spent = 0
        while true {
            let need = xpToAdvance(from: level)
            if spent + need > safe { return level }
            spent += need
            level += 1
            if level > 10_000 { return level }
        }
    }

    public static func progress(forXP xp: Int) -> (level: Int, intoLevel: Int, needed: Int, fraction: Double) {
        let level = level(forXP: xp)
        let floor = totalXP(toReach: level)
        let needed = xpToAdvance(from: level)
        let into = max(0, min(needed, max(0, xp) - floor))
        let fraction = needed == 0 ? 1 : Double(into) / Double(needed)
        return (level, into, needed, fraction)
    }

    /// Text „+15 %“ pro UI.
    public static var growthLabel: String {
        let pct = Int((growth * 100).rounded())
        return "+\(pct) %"
    }
}
