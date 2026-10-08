import XCTest
import simd
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

    private struct Scene {
        var width = 300
        var height = 420
        var center = SIMD2<Double>(150, 200)
        var radius = 100.0
        var rotation = 0.0
        var tilt = SIMD2<Double>(0, 0)

        var matrix: [Double] {
            let c = cos(rotation * .pi / 180) * radius
            let s = sin(rotation * .pi / 180) * radius
            return [c, -s, center.x, s, c, center.y, tilt.x, tilt.y, 1]
        }

        var frame: VisionFrame {
            VisionFrame(bufferWidth: Double(width), bufferHeight: Double(height), previewWidth: Double(width), previewHeight: Double(height))
        }

        func image() -> ChromaImage {
            let inverse = PlaneFit.invert(matrix)!
            var cb = [UInt8](repeating: 128, count: width * height)
            var cr = [UInt8](repeating: 128, count: width * height)
            for y in 0..<height {
                for x in 0..<width {
                    guard let board = PlaneFit.project(inverse, SIMD2(Double(x) + 0.5, Double(y) + 0.5)) else { continue }
                    let r = simd_length(board)
                    let index = y * width + x
                    var red: Bool?
                    if r <= BoardGeometry.innerBull {
                        red = true
                    } else if r <= BoardGeometry.outerBull {
                        red = false
                    } else if (BoardGeometry.tripleInner...BoardGeometry.tripleOuter).contains(r) || (BoardGeometry.doubleInner...1).contains(r) {
                        var angle = atan2(board.y, board.x) + .pi / 2 + .pi / 20
                        angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
                        if angle < 0 { angle += 2 * .pi }
                        red = Int(angle / (.pi / 10)) % 2 == 0
                    }
                    if let red {
                        cb[index] = red ? 100 : 90
                        cr[index] = red ? 205 : 70
                    } else {
                        cb[index] = UInt8(126 + (x * 7 + y * 3) % 5)
                        cr[index] = UInt8(126 + (x * 3 + y * 5) % 5)
                    }
                }
            }
            return ChromaImage(width: width, height: height, cb: cb, cr: cr)
        }

        func normalized(boardX: Double, boardY: Double) -> NormPoint {
            let point = PlaneFit.project(matrix, SIMD2(boardX, boardY))!
            return NormPoint(x: point.x / Double(width), y: point.y / Double(height))
        }

        func solve(numbers: [BoardDetector.Number] = []) -> BoardSolution? {
            BoardVision.solve(BoardDetector.detect(image(), numbers: numbers), frame: frame)
        }
    }

    private func assertMapsEverySegment(_ scene: Scene, rotatedBy offset: Int = 0, file: StaticString = #filePath, line: UInt = #line) throws {
        let solution = try XCTUnwrap(scene.solve(), file: file, line: line)
        let calibration = try XCTUnwrap(solution.calibration, file: file, line: line)
        let mapper = BoardMapper(calibration: calibration)
        XCTAssertTrue(mapper.isReady, file: file, line: line)
        for (index, segment) in BoardGeometry.sectors.enumerated() {
            let angle = -Double.pi / 2 + Double(index + offset) * Double.pi / 10
            for (radius, multiplier) in [(0.8, 1), (0.606, 3), (0.976, 2), (0.3, 1)] as [(Double, Int)] {
                let image = scene.normalized(boardX: cos(angle) * radius, boardY: sin(angle) * radius)
                XCTAssertEqual(mapper.dart(at: image), Dart(segment, multiplier), "\(segment)x\(multiplier)", file: file, line: line)
            }
        }
        XCTAssertEqual(mapper.dart(at: scene.normalized(boardX: 0, boardY: 0)), Dart(25, 2), file: file, line: line)
        XCTAssertEqual(mapper.dart(at: scene.normalized(boardX: 0.065, boardY: 0)), Dart(25, 1), file: file, line: line)
    }

    func testColorsFindAnUprightBoard() throws {
        try assertMapsEverySegment(Scene())
    }

    func testColorsFindATiltedBoard() throws {
        try assertMapsEverySegment(Scene(rotation: 7, tilt: SIMD2(0.18, -0.12)))
    }

    func testNumbersPickTheTwentyOnASidewaysBoard() throws {
        var scene = Scene()
        scene.rotation = 90
        let numbers = [20, 1, 5].compactMap { value -> BoardDetector.Number? in
            guard let index = BoardGeometry.sectors.firstIndex(of: value) else { return nil }
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 10
            let point = scene.normalized(boardX: cos(angle) * 1.12, boardY: sin(angle) * 1.12)
            return BoardDetector.Number(value: value, point: SIMD2(point.x, point.y))
        }
        let solution = try XCTUnwrap(scene.solve(numbers: numbers))
        let mapper = BoardMapper(calibration: try XCTUnwrap(solution.calibration))
        XCTAssertEqual(mapper.dart(at: scene.normalized(boardX: 0, boardY: -0.8)).segment, 20)
    }

    func testEmptyFrameFindsNothing() {
        let blank = ChromaImage(width: 200, height: 200, cb: Array(repeating: 128, count: 40_000), cr: Array(repeating: 128, count: 40_000))
        XCTAssertNil(BoardDetector.detect(blank))
    }

    func testTrackLocksSavesAndTurnsTheNumbers() throws {
        let scene = Scene()
        let solution = try XCTUnwrap(scene.solve())
        var track = BoardTrack()
        track.ingest(solution)
        XCTAssertNotEqual(track.readiness, .aligned)
        for _ in 0..<8 { track.ingest(solution) }
        XCTAssertEqual(track.readiness, .aligned)
        XCTAssertTrue(track.wantsSave)
        let top = scene.normalized(boardX: 0, boardY: -0.8)
        XCTAssertEqual(BoardMapper(calibration: track.calibration).dart(at: top).segment, 20)
        track.rotate(by: 1)
        XCTAssertEqual(BoardMapper(calibration: track.calibration).dart(at: top).segment, 5)
        track.rotate(by: -1)
        XCTAssertEqual(BoardMapper(calibration: track.calibration).dart(at: top).segment, 20)
    }

    func testHomographyCalibrationRoundTrips() throws {
        let calibration = try XCTUnwrap(Scene(rotation: 4, tilt: SIMD2(0.1, 0.05)).solve()?.calibration)
        let data = try JSONEncoder().encode(calibration)
        let decoded = try JSONDecoder().decode(BoardCalibration.self, from: data)
        XCTAssertEqual(decoded.homography?.count, 9)
        let point = NormPoint(x: 0.52, y: 0.31)
        XCTAssertEqual(BoardMapper(calibration: decoded).dart(at: point), BoardMapper(calibration: calibration).dart(at: point))
    }


    func testCameraMapFitsAnyPreviewSize() throws {
        let scene = Scene(rotation: 3, tilt: SIMD2(0.08, -0.05))
        var calibration = try XCTUnwrap(scene.solve()?.calibration)
        calibration.camera = PlaneFit.multiply(PlaneFit.invert(BoardVision.previewTransform(scene.frame))!, calibration.homography!)
        calibration.cameraAspect = scene.frame.bufferAspect
        calibration.calibratedAt = Date()
        let decoded = try JSONDecoder().decode(BoardCalibration.self, from: JSONEncoder().encode(calibration))
        XCTAssertTrue(decoded.isCameraMapped)

        for (width, height) in [(390.0, 844.0), (360.0, 460.0), (300.0, 420.0)] {
            let frame = VisionFrame(bufferWidth: Double(scene.width), bufferHeight: Double(scene.height), previewWidth: width, previewHeight: height)
            let mapper = BoardMapper(calibration: decoded.fitted(previewWidth: width, previewHeight: height))
            for (boardX, boardY, expected) in [(0.0, -0.8, Dart(20)), (0.606, 0.0, Dart(6, 3)), (0.0, 0.976, Dart(3, 2)), (0.0, 0.0, Dart(25, 2))] {
                let preview = frame.previewPoint(scene.normalized(boardX: boardX, boardY: boardY))
                XCTAssertEqual(mapper.dart(at: preview), expected, "\(width)x\(height)")
            }
        }
    }

    func testCorrectionsTeachTheMapAConsistentOffset() throws {
        var calibration = try XCTUnwrap(Scene().solve()?.calibration)
        calibration.camera = calibration.homography
        calibration.cameraAspect = 1
        calibration.calibratedAt = Date()
        let mapper = BoardMapper(calibration: calibration)
        let shift = SIMD2(0.0, 0.05)
        var samples: [DartSample] = []
        for (index, segment) in BoardGeometry.sectors.enumerated() where index % 2 == 0 {
            let angle = -Double.pi / 2 + Double(index) * Double.pi / 10
            let truth = SIMD2(cos(angle), sin(angle)) * 0.976
            let seen = PlaneFit.project(calibration.camera!, truth + shift)!
            samples.append(DartSample(x: seen.x, y: seen.y, segment: segment, multiplier: 2, corrected: true))
        }
        let first = samples[0]
        let before = mapper.dart(at: NormPoint(x: first.x, y: first.y))
        XCTAssertNotEqual(before, Dart(20, 2))

        let learned = DartLearning.learn(calibration, adding: samples)
        XCTAssertNotNil(learned.learned)
        let taught = BoardMapper(calibration: learned)
        var right = 0
        for sample in samples where taught.dart(at: NormPoint(x: sample.x, y: sample.y)) == Dart(sample.segment, sample.multiplier) {
            right += 1
        }
        XCTAssertGreaterThanOrEqual(right, samples.count - 1)
        let decoded = try JSONDecoder().decode(BoardCalibration.self, from: JSONEncoder().encode(learned))
        XCTAssertEqual(decoded.samples?.count, samples.count)
        XCTAssertEqual(decoded.learned?.count, 6)
    }

    func testConfirmedHitsAloneDoNotMoveTheMap() throws {
        var calibration = try XCTUnwrap(Scene().solve()?.calibration)
        calibration.camera = calibration.homography
        calibration.cameraAspect = 1
        let learned = DartLearning.learn(calibration, adding: [DartSample(x: 0.5, y: 0.3, segment: 20, multiplier: 1, corrected: false)])
        XCTAssertNil(learned.learned)
        XCTAssertEqual(learned.samples?.count, 1)
    }

    func testTipIsTheEndTowardsTheVanishingPoint() {
        let empty = Array(repeating: UInt8(0), count: 32 * 32)
        var current = empty
        for y in 4...12 { current[y * 32 + 16] = 80 }
        let up = DartBlobs.tips(current: current, reference: empty, width: 32, height: 32, center: NormPoint(x: 0.5, y: 0.9), vanish: NormPoint(x: 0.5, y: 0))
        XCTAssertEqual(try XCTUnwrap(up.first).y, 4.5 / 32, accuracy: 0.04)
        let down = DartBlobs.tips(current: current, reference: empty, width: 32, height: 32, center: NormPoint(x: 0.5, y: 0.1), vanish: NormPoint(x: 0.5, y: 1))
        XCTAssertEqual(try XCTUnwrap(down.first).y, 12.5 / 32, accuracy: 0.04)
    }

    func testFrontalCameraLooksStraightIntoTheBoard() throws {
        let camera = [0.3, 0, 0.5, 0, 0.17, 0.45, 0, 0, 1]
        let vanish = try XCTUnwrap(DartAxis.vanishingPoint(camera: camera, aspect: 0.5625))
        XCTAssertEqual(vanish.x, 0.5, accuracy: 0.01)
        XCTAssertEqual(vanish.y, 0.5, accuracy: 0.01)
    }

    func testBrightnessChangeIsNotADart() {
        var watch = DartWatch()
        let frame = VisionFrame(bufferWidth: 32, bufferHeight: 32, previewWidth: 32, previewHeight: 32)
        let empty = Array(repeating: UInt8(80), count: 32 * 32)
        let brighter = Array(repeating: UInt8(130), count: 32 * 32)
        for _ in 0..<4 { _ = watch.ingest(luma: empty, width: 32, height: 32, frame: frame, center: NormPoint(x: 0.5, y: 0.5), accept: { _ in true }) }
        for _ in 0..<8 {
            XCTAssertNil(watch.ingest(luma: brighter, width: 32, height: 32, frame: frame, center: NormPoint(x: 0.5, y: 0.5), accept: { _ in true }))
        }
    }

    func testHandInFrameResetsTheEmptyBoard() {
        var watch = DartWatch()
        let frame = VisionFrame(bufferWidth: 32, bufferHeight: 32, previewWidth: 32, previewHeight: 32)
        let empty = Array(repeating: UInt8(20), count: 32 * 32)
        var hand = empty
        for y in 4..<28 { for x in 4..<28 { hand[y * 32 + x] = 200 } }
        var leftover = empty
        for y in 4...12 { leftover[y * 32 + 16] = 200 }
        let ingest = { (watch: inout DartWatch, luma: [UInt8]) in
            watch.ingest(luma: luma, width: 32, height: 32, frame: frame, center: NormPoint(x: 0.5, y: 0.5), accept: { _ in true })
        }
        for _ in 0..<4 { _ = ingest(&watch, empty) }
        for _ in 0..<3 { XCTAssertNil(ingest(&watch, hand)) }
        XCTAssertTrue(watch.disturbed)
        for _ in 0..<8 { XCTAssertNil(ingest(&watch, leftover)) }
        XCTAssertFalse(watch.disturbed)
    }

    func testMotionOutsideTheBoardIsIgnored() {
        var watch = DartWatch()
        let frame = VisionFrame(bufferWidth: 32, bufferHeight: 32, previewWidth: 32, previewHeight: 32)
        let empty = Array(repeating: UInt8(20), count: 32 * 32)
        var region = Array(repeating: false, count: 32 * 32)
        for y in 0..<32 { for x in 16..<32 { region[y * 32 + x] = true } }
        var outside = empty
        for y in 4...12 { outside[y * 32 + 5] = 200 }
        for _ in 0..<4 { _ = watch.ingest(luma: empty, width: 32, height: 32, frame: frame, center: NormPoint(x: 0.5, y: 0.5), region: region, accept: { _ in true }) }
        for _ in 0..<8 {
            XCTAssertNil(watch.ingest(luma: outside, width: 32, height: 32, frame: frame, center: NormPoint(x: 0.5, y: 0.5), region: region, accept: { _ in true }))
        }
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
