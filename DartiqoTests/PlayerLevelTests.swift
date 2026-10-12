import XCTest
@testable import Dartiqo

final class PlayerLevelTests: XCTestCase {
    func testLevelsGrowByFifteenPercent() {
        XCTAssertEqual(PlayerLevel.xpToAdvance(from: 1), 500)
        // 500 * 1.15 = 575
        XCTAssertEqual(PlayerLevel.xpToAdvance(from: 2), 575)
        // 500 * 1.15² ≈ 661.25 → 661
        XCTAssertEqual(PlayerLevel.xpToAdvance(from: 3), 661)
        // 500 * 1.15³ ≈ 760.4375 → 760
        XCTAssertEqual(PlayerLevel.xpToAdvance(from: 4), 760)
        // Každý další je cca +15 % oproti předchozímu.
        let a = Double(PlayerLevel.xpToAdvance(from: 5))
        let b = Double(PlayerLevel.xpToAdvance(from: 6))
        XCTAssertEqual(b / a, 1.15, accuracy: 0.01)
    }

    func testLevelFromTotalXP() {
        XCTAssertEqual(PlayerLevel.level(forXP: 0), 1)
        XCTAssertEqual(PlayerLevel.level(forXP: 499), 1)
        XCTAssertEqual(PlayerLevel.level(forXP: 500), 2)
        // 500 + 575 = 1075 → level 3
        XCTAssertEqual(PlayerLevel.level(forXP: 1074), 2)
        XCTAssertEqual(PlayerLevel.level(forXP: 1075), 3)
    }

    func testProgressInsideLevel() {
        let mid = PlayerLevel.progress(forXP: 250)
        XCTAssertEqual(mid.level, 1)
        XCTAssertEqual(mid.intoLevel, 250)
        XCTAssertEqual(mid.needed, 500)
        XCTAssertEqual(mid.fraction, 0.5, accuracy: 0.0001)

        let intoTwo = PlayerLevel.progress(forXP: 500 + 100)
        XCTAssertEqual(intoTwo.level, 2)
        XCTAssertEqual(intoTwo.intoLevel, 100)
        XCTAssertEqual(intoTwo.needed, 575)
    }

    func testTotalXPToReachMatchesSum() {
        XCTAssertEqual(PlayerLevel.totalXP(toReach: 1), 0)
        XCTAssertEqual(PlayerLevel.totalXP(toReach: 2), 500)
        XCTAssertEqual(PlayerLevel.totalXP(toReach: 3), 500 + 575)
        XCTAssertEqual(PlayerLevel.totalXP(toReach: 4), 500 + 575 + 661)
    }
}
