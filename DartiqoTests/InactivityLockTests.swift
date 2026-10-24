import XCTest
@testable import Dartiqo

final class InactivityLockTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testShortAbsenceDoesNotAsk() {
        let away = now.addingTimeInterval(-59)
        XCTAssertFalse(InactivityLock.shouldPrompt(
            enabled: true, hasProfile: true, locked: false,
            inactiveAt: away, now: now, sceneIsActive: true, grace: 60
        ))
    }

    func testAbsenceAtTheLimitAsks() {
        let away = now.addingTimeInterval(-60)
        XCTAssertTrue(InactivityLock.shouldPrompt(
            enabled: true, hasProfile: true, locked: false,
            inactiveAt: away, now: now, sceneIsActive: true, grace: 60
        ))
    }

    func testImmediateGraceLocksAnyBackground() {
        XCTAssertTrue(InactivityLock.shouldPrompt(
            enabled: true, hasProfile: true, locked: false,
            inactiveAt: now, now: now, sceneIsActive: true, grace: 0
        ))
    }

    func testDisabledLockNeverAsks() {
        XCTAssertFalse(InactivityLock.shouldPrompt(
            enabled: false, hasProfile: true, locked: false,
            inactiveAt: now.addingTimeInterval(-600), now: now, sceneIsActive: true, grace: 60
        ))
    }

    func testAlreadyLockedStaysLocked() {
        XCTAssertTrue(InactivityLock.shouldPrompt(
            enabled: true, hasProfile: true, locked: true,
            inactiveAt: nil, now: now, sceneIsActive: false, grace: 60
        ))
    }

    func testBackgroundDoesNotPromptUntilReturn() {
        XCTAssertFalse(InactivityLock.shouldPrompt(
            enabled: true, hasProfile: true, locked: false,
            inactiveAt: now.addingTimeInterval(-600), now: now, sceneIsActive: false, grace: 60
        ))
    }

    func testLaunchWithoutTimestampLocks() {
        XCTAssertTrue(InactivityLock.shouldLockOnLaunch(
            enabled: true, hasProfile: true, backgroundedAt: nil, now: now, grace: 60
        ))
    }

    func testLaunchInsideGraceStaysOpen() {
        XCTAssertFalse(InactivityLock.shouldLockOnLaunch(
            enabled: true, hasProfile: true,
            backgroundedAt: now.addingTimeInterval(-20), now: now, grace: 60
        ))
    }

    func testLaunchAfterGraceLocks() {
        XCTAssertTrue(InactivityLock.shouldLockOnLaunch(
            enabled: true, hasProfile: true,
            backgroundedAt: now.addingTimeInterval(-61), now: now, grace: 60
        ))
    }

    @MainActor
    func testLegacySaveWithoutGraceUsesOneMinute() throws {
        let json = #"{"version":1,"profiles":[],"matches":[],"activeMatches":{},"haptics":true,"voice":false,"appearance":"dark","biometricLock":true}"#
        let stored = try JSONDecoder().decode(StoredData.self, from: Data(json.utf8))
        XCTAssertNil(stored.lockGraceSeconds)
        XCTAssertEqual(InactivityLock.grace(seconds: stored.lockGraceSeconds), 60)
    }
}
