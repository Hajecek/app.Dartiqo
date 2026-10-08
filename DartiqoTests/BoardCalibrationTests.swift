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

    func testPreviewMappingRoundTripsTheCenter() {
        let frame = VisionFrame(bufferWidth: 1080, bufferHeight: 1920, previewWidth: 390, previewHeight: 844)
        let center = NormPoint(x: 0.5, y: 0.42)
        let preview = frame.previewPoint(center)
        let back = frame.bufferPoint(preview)
        XCTAssertEqual(back.x, center.x, accuracy: 0.001)
        XCTAssertEqual(back.y, center.y, accuracy: 0.001)
        XCTAssertEqual(preview.x, 0.5, accuracy: 0.02)
    }

    func testTwentyAboveLocksUprightBoard() {
        let frame = VisionFrame(bufferWidth: 1000, bufferHeight: 1000, previewWidth: 1000, previewHeight: 1000)
        let solution = BoardVision.solve(
            circle: .init(center: NormPoint(x: 0.5, y: 0.5), radius: 0.25, residual: 0.01),
            numbers: [
                .init(value: 20, center: NormPoint(x: 0.5, y: 0.22)),
                .init(value: 6, center: NormPoint(x: 0.78, y: 0.5))
            ],
            frame: frame
        )
        let solved = try! XCTUnwrap(solution)
        XCTAssertEqual(solved.readiness, .aligned)
        XCTAssertEqual(solved.calibration.rotationDegrees, 0, accuracy: 1)
        XCTAssertEqual(solved.calibration.radius, 0.25, accuracy: 0.01)
        let mapper = BoardMapper(calibration: solved.calibration)
        let single20 = NormPoint(x: 0.5, y: 0.5 - 0.25 * 0.8)
        XCTAssertEqual(mapper.dart(at: single20).segment, 20)
        XCTAssertEqual(mapper.dart(at: single20).multiplier, 1)
    }

    func testTwentyOnTheRightRotatesTheSpider() {
        let frame = VisionFrame(bufferWidth: 1000, bufferHeight: 1000, previewWidth: 1000, previewHeight: 1000)
        let solution = BoardVision.solve(
            circle: .init(center: NormPoint(x: 0.5, y: 0.5), radius: 0.25, residual: 0.01),
            numbers: [.init(value: 20, center: NormPoint(x: 0.78, y: 0.5))],
            frame: frame
        )
        let solved = try! XCTUnwrap(solution)
        XCTAssertEqual(solved.calibration.rotationDegrees, 90, accuracy: 1)
        let mapper = BoardMapper(calibration: solved.calibration)
        XCTAssertEqual(mapper.dart(at: NormPoint(x: 0.7, y: 0.5)).segment, 20)
    }

    func testNumbersInsideTheRimShrinkTheScoringRadius() {
        let frame = VisionFrame(bufferWidth: 1000, bufferHeight: 1000, previewWidth: 1000, previewHeight: 1000)
        let solution = BoardVision.solve(
            circle: .init(center: NormPoint(x: 0.5, y: 0.5), radius: 0.40, residual: 0.01),
            numbers: [.init(value: 20, center: NormPoint(x: 0.5, y: 0.16))],
            frame: frame
        )
        let solved = try! XCTUnwrap(solution)
        XCTAssertEqual(solved.edgeRadius, 0.40, accuracy: 0.001)
        XCTAssertEqual(solved.calibration.radius, 0.40 * 0.85 / BoardVision.numberOverDouble, accuracy: 0.01)
    }

    func testDisagreeingNumbersStayOnTheEdge() {
        let frame = VisionFrame(bufferWidth: 1000, bufferHeight: 1000, previewWidth: 1000, previewHeight: 1000)
        let solution = BoardVision.solve(
            circle: .init(center: NormPoint(x: 0.5, y: 0.5), radius: 0.25, residual: 0.01),
            numbers: [
                .init(value: 20, center: NormPoint(x: 0.5, y: 0.22)),
                .init(value: 5, center: NormPoint(x: 0.5, y: 0.22))
            ],
            frame: frame
        )
        XCTAssertEqual(solution?.readiness, .edge)
    }

    func testPartialCircleIsRejected() {
        let frame = VisionFrame(bufferWidth: 1000, bufferHeight: 1000, previewWidth: 1000, previewHeight: 1000)
        let solution = BoardVision.solve(
            circle: .init(center: NormPoint(x: 0.1, y: 0.5), radius: 0.25, residual: 0.01),
            numbers: [],
            frame: frame
        )
        XCTAssertNil(solution)
    }

    func testEdgeTurnsGreenBeforeTheSegmentsLock() {
        var track = BoardTrack()
        let frame = VisionFrame(bufferWidth: 1000, bufferHeight: 1000, previewWidth: 1000, previewHeight: 1000)
        let edge = BoardVision.solve(
            circle: .init(center: NormPoint(x: 0.5, y: 0.5), radius: 0.25, residual: 0.01),
            numbers: [],
            frame: frame
        )
        for _ in 0..<3 { track.ingest(edge) }
        XCTAssertEqual(track.readiness, .edge)
        XCTAssertFalse(track.wantsSave)
        let aligned = BoardVision.solve(
            circle: .init(center: NormPoint(x: 0.5, y: 0.5), radius: 0.25, residual: 0.01),
            numbers: [.init(value: 20, center: NormPoint(x: 0.5, y: 0.22))],
            frame: frame
        )
        for _ in 0..<8 { track.ingest(aligned) }
        XCTAssertEqual(track.readiness, .aligned)
        XCTAssertTrue(track.wantsSave)
    }

    func testDartTipIsTheCellClosestToTheBull() {
        let width = 32
        let height = 32
        let empty = Array(repeating: UInt8(0), count: width * height)
        var current = empty
        for y in 4...12 { current[y * width + 16] = 80 }
        let tips = DartBlobs.tips(current: current, reference: empty, width: width, height: height, center: NormPoint(x: 0.5, y: 0.5))
        let tip = try! XCTUnwrap(tips.first)
        XCTAssertEqual(tip.x, 16.5 / 32, accuracy: 0.001)
        XCTAssertEqual(tip.y, 12.5 / 32, accuracy: 0.001)
    }

    func testWatchAcceptsADartOnlyAfterTheBoardIsStill() {
        var watch = DartWatch()
        let frame = VisionFrame(bufferWidth: 32, bufferHeight: 32, previewWidth: 32, previewHeight: 32)
        let empty = Array(repeating: UInt8(20), count: 32 * 32)
        var thrown = empty
        for y in 4...12 { thrown[y * 32 + 16] = 200 }
        for _ in 0..<4 {
            XCTAssertNil(watch.ingest(luma: empty, width: 32, height: 32, frame: frame, center: NormPoint(x: 0.5, y: 0.5), accept: { _ in true }))
        }
        XCTAssertFalse(watch.phaseIsSettling)
        var accepted: NormPoint?
        for _ in 0..<6 {
            accepted = watch.ingest(luma: thrown, width: 32, height: 32, frame: frame, center: NormPoint(x: 0.5, y: 0.5), accept: { _ in true }) ?? accepted
        }
        let point = try! XCTUnwrap(accepted)
        watch.confirm()
        XCTAssertEqual(watch.known.count, 1)
        XCTAssertEqual(point.x, 16.5 / 32, accuracy: 0.05)
        let again = watch.ingest(luma: thrown, width: 32, height: 32, frame: frame, center: NormPoint(x: 0.5, y: 0.5), accept: { _ in true })
        XCTAssertNil(again)
    }
}
