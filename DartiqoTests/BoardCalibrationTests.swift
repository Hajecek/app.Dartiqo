import XCTest
@testable import Dartiqo

final class BoardCalibrationTests: XCTestCase {
    private func circularCalibration(centerX: Double = 0.5, centerY: Double = 0.42, radius: Double = 0.28, rotation: Double = 0, aspect: Double = 0.46) -> BoardCalibration {
        BoardCalibration(
            center: NormPoint(x: centerX, y: centerY),
            radius: radius,
            rotationDegrees: rotation,
            previewAspect: aspect,
            calibratedAt: Date()
        )
    }

    func testPerfectCircleMapsEverySegmentAndRing() {
        let mapper = BoardMapper(calibration: circularCalibration())
        XCTAssertTrue(mapper.isReady)
        XCTAssertTrue(mapper.quality.isReady)

        for (index, segment) in BoardGeometry.sectors.enumerated() {
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 10
            for (radius, multiplier) in [(0.8, 1), (0.606, 3), (0.976, 2)] as [(Double, Int)] {
                let boardX = cos(angle) * radius
                let boardY = sin(angle) * radius
                let image = try! XCTUnwrap(mapper.imagePoint(boardX: boardX, boardY: boardY))
                XCTAssertEqual(mapper.dart(at: image), Dart(segment, multiplier), "\(segment)x\(multiplier)")
            }
        }
        XCTAssertEqual(mapper.dart(at: try! XCTUnwrap(mapper.imagePoint(boardX: 0, boardY: 0))), Dart(25, 2))
        let outerBull = try! XCTUnwrap(mapper.imagePoint(boardX: 0, boardY: -0.07))
        XCTAssertEqual(mapper.dart(at: outerBull), Dart(25, 1))
        let miss = try! XCTUnwrap(mapper.imagePoint(boardX: 0, boardY: -1.15))
        XCTAssertEqual(mapper.dart(at: miss), .miss)
    }

    func testRotationMovesSegmentClassification() {
        let mapper = BoardMapper(calibration: circularCalibration(rotation: 9))
        let image = try! XCTUnwrap(mapper.imagePoint(boardX: 0, boardY: -0.8))
        let dart = mapper.dart(at: image)
        XCTAssertEqual(dart.segment, 20)
        XCTAssertEqual(dart.multiplier, 1)
    }

    func testLegacyAnchorsDecodeToCircle() throws {
        let json = """
        {"anchors":{"bull":{"x":0.5,"y":0.4},"outer20":{"x":0.5,"y":0.12},"outer6":{"x":0.78,"y":0.4},"outer3":{"x":0.5,"y":0.68},"outer11":{"x":0.22,"y":0.4}},"rotationDegrees":0,"previewAspect":0.46,"calibratedAt":0}
        """
        let decoded = try JSONDecoder().decode(BoardCalibration.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.center.x, 0.5, accuracy: 0.001)
        XCTAssertGreaterThan(decoded.radius, 0.1)
        XCTAssertTrue(BoardMapper(calibration: decoded).isReady)
    }

    func testSanitizedClampsCorruptValues() {
        var calibration = circularCalibration()
        calibration.rotationDegrees = 900
        calibration.radius = 9
        calibration.center = NormPoint(x: .nan, y: 2)
        let clean = calibration.sanitized()
        XCTAssertEqual(clean.rotationDegrees, 180)
        XCTAssertEqual(clean.radius, 0.7)
        XCTAssertTrue(clean.center.isUsable)
    }

    func testPersistenceRoundTrip() throws {
        var calibration = circularCalibration()
        calibration.rotationDegrees = -12.5
        let data = try JSONEncoder().encode(calibration)
        let decoded = try JSONDecoder().decode(BoardCalibration.self, from: data)
        XCTAssertEqual(decoded.center, calibration.center)
        XCTAssertEqual(decoded.radius, calibration.radius, accuracy: 1e-9)
        XCTAssertEqual(decoded.rotationDegrees, calibration.rotationDegrees, accuracy: 1e-9)
        XCTAssertTrue(BoardMapper(calibration: decoded).isReady)
    }

    func testLegacyStoredDataWithoutCalibrationStillDecodes() throws {
        let json = #"{"version":1,"profiles":[],"matches":[],"activeMatches":{},"haptics":true,"voice":false,"appearance":"dark","biometricLock":false}"#
        let stored = try JSONDecoder().decode(StoredData.self, from: Data(json.utf8))
        XCTAssertNil(stored.boardCalibration)
    }
}
