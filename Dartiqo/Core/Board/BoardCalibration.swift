import Foundation

/// Point in a full-screen camera preview. Origin top-left, both axes 0…1.
public struct NormPoint: Codable, Equatable, Hashable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var isUsable: Bool { x.isFinite && y.isFinite }
}

/// Bull + outer double at 20 / 6 / 3 / 11. Built from a circle fit for the mapper.
public struct BoardAnchors: Codable, Equatable {
    public var bull: NormPoint
    public var outer20: NormPoint
    public var outer6: NormPoint
    public var outer3: NormPoint
    public var outer11: NormPoint
    public init(bull: NormPoint, outer20: NormPoint, outer6: NormPoint, outer3: NormPoint, outer11: NormPoint) {
        self.bull = bull; self.outer20 = outer20; self.outer6 = outer6; self.outer3 = outer3; self.outer11 = outer11
    }
    public var outers: [NormPoint] { [outer20, outer6, outer3, outer11] }
}

/// Official WDF ring radii (outer double wire = 1). No manual per-ring tweaking in the UI.
public enum BoardRings {
    public static let innerBull = BoardGeometry.innerBull
    public static let outerBull = BoardGeometry.outerBull
    public static let tripleInner = BoardGeometry.tripleInner
    public static let tripleOuter = BoardGeometry.tripleOuter
    public static let doubleInner = BoardGeometry.doubleInner
}

/// Circle-based board fit. Same idea as Autodarts / GRAN: center, outer ring, rotate onto 20.
public struct BoardCalibration: Codable, Equatable {
    /// Bull / board center in the live preview (0…1).
    public var center: NormPoint
    /// Outer double radius as a fraction of preview **width**.
    public var radius: Double
    /// Degrees. Positive rotates the spider clockwise. 0 = 20 at twelve o’clock.
    public var rotationDegrees: Double
    /// Preview width / height when calibrated.
    public var previewAspect: Double
    public var calibratedAt: Date?
    /// Perspektivní mapa deska → náhled (3×3). Když je, má přednost před kruhem a otočením.
    public var homography: [Double]?
    /// Stejná mapa vůči obrazu kamery (0…1). Nezávisí na velikosti náhledu.
    public var camera: [Double]?
    /// Šířka / výška obrazu kamery.
    public var cameraAspect: Double?

    /// Přiblížení kamery při kalibraci. Zápas musí použít stejné.
    public var zoom: Double?
    /// Naučená korekce v souřadnicích desky (afinní 2×3) z oprav hráče.
    public var learned: [Double]?
    /// Hody z kamery, ze kterých se korekce učí. Nová kalibrace začíná od nuly.
    public var samples: [DartSample]?

    public var isCameraMapped: Bool { camera != nil && (cameraAspect ?? 0) > 0 }

    /// Poměr nejkratšího a nejdelšího poloměru terče na displeji. 1 = telefon přesně čelně.
    public var tiltRatio: Double {
        guard let matrix = homography, let center = PlaneFit.project(matrix, .zero) else { return 1 }
        let aspect = max(previewAspect, 0.01)
        let radii = (0..<24).compactMap { index -> Double? in
            let angle = Double(index) / 24 * 2 * .pi
            guard let point = PlaneFit.project(matrix, SIMD2(cos(angle), sin(angle))) else { return nil }
            return hypot(point.x - center.x, (point.y - center.y) / aspect)
        }
        guard let low = radii.min(), let high = radii.max(), high > 0 else { return 1 }
        return low / high
    }

    /// Mapa pro konkrétní náhled. Kalibrace z celé obrazovky tak sedí i v menším okně v zápase.
    public func fitted(previewWidth: Double, previewHeight: Double) -> BoardCalibration {
        guard let camera, let cameraAspect, cameraAspect > 0, previewWidth > 1, previewHeight > 1 else { return self }
        let frame = VisionFrame(bufferWidth: cameraAspect, bufferHeight: 1, previewWidth: previewWidth, previewHeight: previewHeight)
        guard var next = BoardCalibration(
            homography: PlaneFit.multiply(BoardVision.previewTransform(frame), camera),
            previewAspect: previewWidth / previewHeight,
            calibratedAt: calibratedAt
        ) else { return self }
        next.camera = camera
        next.cameraAspect = cameraAspect
        next.zoom = zoom
        next.learned = learned
        next.samples = samples
        return next
    }

    public init(center: NormPoint, radius: Double, rotationDegrees: Double = 0, previewAspect: Double = 0.46, calibratedAt: Date? = nil) {
        self.center = center
        self.radius = radius
        self.rotationDegrees = rotationDegrees
        self.previewAspect = previewAspect
        self.calibratedAt = calibratedAt
    }

    /// Z perspektivní mapy dopočítá i střed, poloměr a otočení pro starší části aplikace.
    public init?(homography matrix: [Double], previewAspect: Double, calibratedAt: Date? = nil) {
        guard matrix.count == 9, matrix.allSatisfy(\.isFinite),
              let center = PlaneFit.project(matrix, .zero),
              let top = PlaneFit.project(matrix, SIMD2(0, -1)) else { return nil }
        let aspect = max(previewAspect, 0.01)
        let rim = (0..<24).compactMap { index -> Double? in
            let angle = Double(index) / 24 * 2 * .pi
            guard let point = PlaneFit.project(matrix, SIMD2(cos(angle), sin(angle))) else { return nil }
            return hypot(point.x - center.x, (point.y - center.y) / aspect)
        }
        guard rim.count == 24 else { return nil }
        self.center = NormPoint(x: center.x, y: center.y)
        radius = rim.reduce(0, +) / Double(rim.count)
        rotationDegrees = atan2(top.x - center.x, -(top.y - center.y) / aspect) * 180 / .pi
        self.previewAspect = previewAspect
        self.calibratedAt = calibratedAt
        homography = matrix
    }

    public var isCalibrated: Bool { calibratedAt != nil }

    public static var draft: BoardCalibration {
        BoardCalibration(center: NormPoint(x: 0.5, y: 0.40), radius: 0.36, rotationDegrees: 0, previewAspect: 0.46)
    }

    /// Four outer double points + bull derived from the circle (visually round on screen).
    public var anchors: BoardAnchors {
        let rx = radius
        let ry = radius * previewAspect
        return BoardAnchors(
            bull: center,
            outer20: NormPoint(x: center.x, y: center.y - ry),
            outer6: NormPoint(x: center.x + rx, y: center.y),
            outer3: NormPoint(x: center.x, y: center.y + ry),
            outer11: NormPoint(x: center.x - rx, y: center.y)
        )
    }

    public func sanitized() -> BoardCalibration {
        var copy = self
        copy.center = NormPoint(
            x: center.x.finiteOr(0.5).clamped(0.05, 0.95),
            y: center.y.finiteOr(0.4).clamped(0.05, 0.95)
        )
        copy.radius = radius.finiteOr(0.36).clamped(0.08, 0.7)
        copy.rotationDegrees = rotationDegrees.finiteOr(0).clamped(-180, 180)
        copy.previewAspect = previewAspect.isFinite && previewAspect > 0.2 ? previewAspect.clamped(0.3, 2.4) : 0.46
        if let matrix = homography, matrix.count != 9 || !matrix.allSatisfy(\.isFinite) || PlaneFit.invert(matrix) == nil {
            copy.homography = nil
        }
        if let matrix = camera, matrix.count != 9 || !matrix.allSatisfy(\.isFinite) || PlaneFit.invert(matrix) == nil
            || !(cameraAspect ?? 0).isFinite || (cameraAspect ?? 0) <= 0 {
            copy.camera = nil
            copy.cameraAspect = nil
        }
        if let learned, learned.count != 6 || !learned.allSatisfy(\.isFinite) { copy.learned = nil }
        if let zoom, !zoom.isFinite || zoom < 1 { copy.zoom = nil }
        return copy
    }

    enum CodingKeys: String, CodingKey {
        case center, radius, rotationDegrees, previewAspect, calibratedAt, homography, camera, cameraAspect, zoom, learned, samples
        case anchors, rings, wireOffsets, lensK1
    }

    public init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        calibratedAt = try box.decodeIfPresent(Date.self, forKey: .calibratedAt)
        homography = try box.decodeIfPresent([Double].self, forKey: .homography)
        camera = try box.decodeIfPresent([Double].self, forKey: .camera)
        cameraAspect = try box.decodeIfPresent(Double.self, forKey: .cameraAspect)
        zoom = try box.decodeIfPresent(Double.self, forKey: .zoom)
        learned = try box.decodeIfPresent([Double].self, forKey: .learned)
        samples = try box.decodeIfPresent([DartSample].self, forKey: .samples)
        rotationDegrees = try box.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0
        previewAspect = try box.decodeIfPresent(Double.self, forKey: .previewAspect) ?? 0.46
        if let center = try box.decodeIfPresent(NormPoint.self, forKey: .center),
           let radius = try box.decodeIfPresent(Double.self, forKey: .radius) {
            self.center = center
            self.radius = radius
            return
        }
        // Legacy 5-point saves → circle fit
        let legacy = try box.decode(BoardAnchors.self, forKey: .anchors)
        let bull = legacy.bull
        let aspect = previewAspect
        let distances = legacy.outers.map { hypot($0.x - bull.x, ($0.y - bull.y) / max(aspect, 0.01)) }
        center = bull
        radius = (distances.reduce(0, +) / Double(max(distances.count, 1))).clamped(0.08, 0.7)
    }

    public func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(center, forKey: .center)
        try box.encode(radius, forKey: .radius)
        try box.encode(rotationDegrees, forKey: .rotationDegrees)
        try box.encode(previewAspect, forKey: .previewAspect)
        try box.encodeIfPresent(calibratedAt, forKey: .calibratedAt)
        try box.encodeIfPresent(homography, forKey: .homography)
        try box.encodeIfPresent(camera, forKey: .camera)
        try box.encodeIfPresent(cameraAspect, forKey: .cameraAspect)
        try box.encodeIfPresent(zoom, forKey: .zoom)
        try box.encodeIfPresent(learned, forKey: .learned)
        try box.encodeIfPresent(samples, forKey: .samples)
    }
}

public struct CalibrationQuality: Equatable {
    public var isReady: Bool
    public var title: String
    public var detail: String
}

/// Maps a camera preview point onto a dart using the circle fit + standard WDF rings.
public struct BoardMapper {
    public let calibration: BoardCalibration
    private let homography: Homography?
    private let scale: Double
    private let rotation: Double
    private let correction: [Double]?
    private let correctionInverse: [Double]?

    public init(calibration: BoardCalibration) {
        let clean = calibration.sanitized()
        self.calibration = clean
        if let matrix = clean.homography, let fit = Homography(matrix: matrix) {
            homography = fit
            scale = 1
            rotation = 0
            let affine = clean.learned.map { [$0[0], $0[1], $0[2], $0[3], $0[4], $0[5], 0, 0, 1] }
            let inverse = affine.flatMap(PlaneFit.invert)
            correction = inverse == nil ? nil : affine
            correctionInverse = inverse
            return
        }
        correction = nil
        correctionInverse = nil
        rotation = clean.rotationDegrees
        let image = clean.anchors.outers.map { ($0.x, $0.y) }
        let board = [(0.0, -1.0), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0)]
        let fit = Homography.fit(board: board, image: image)
        homography = fit
        if let fit {
            let radii = image.compactMap { point -> Double? in
                guard let raw = fit.unproject(u: point.0, v: point.1) else { return nil }
                return hypot(raw.x, raw.y)
            }
            let mean = radii.isEmpty ? 0 : radii.reduce(0, +) / Double(radii.count)
            scale = mean > 0.2 ? mean : 0
        } else {
            scale = 0
        }
    }

    public var isReady: Bool { homography != nil && scale > 0.2 }

    public var quality: CalibrationQuality {
        guard isReady else {
            return CalibrationQuality(isReady: false, title: "Terč ještě nesedí", detail: "Zvětši kruh na vnější double a střed dej do bull.")
        }
        return CalibrationQuality(isReady: true, title: "Mapa terče je hotová", detail: "Otoč na 20 a ověř klepnutím, že pole sedí.")
    }

    public func boardPoint(from image: NormPoint) -> (x: Double, y: Double)? {
        guard isReady, image.isUsable, let homography else { return nil }
        guard let raw = homography.unproject(u: image.x, v: image.y) else { return nil }
        let point = SIMD2(raw.x / scale, raw.y / scale)
        guard let correction, let corrected = PlaneFit.project(correction, point) else { return (point.x, point.y) }
        return (corrected.x, corrected.y)
    }

    public func imagePoint(boardX: Double, boardY: Double) -> NormPoint? {
        guard isReady, boardX.isFinite, boardY.isFinite, let homography else { return nil }
        var boardX = boardX, boardY = boardY
        if let correctionInverse, let raw = PlaneFit.project(correctionInverse, SIMD2(boardX, boardY)) {
            boardX = raw.x
            boardY = raw.y
        }
        // Apply spider rotation around bull in board space.
        let rad = rotation * Double.pi / 180
        let cosR = cos(rad), sinR = sin(rad)
        let rx = boardX * cosR - boardY * sinR
        let ry = boardX * sinR + boardY * cosR
        guard let raw = homography.project(x: rx * scale, y: ry * scale) else { return nil }
        return NormPoint(x: raw.x, y: raw.y)
    }

    public func dart(at image: NormPoint) -> Dart {
        guard let point = boardPoint(from: image) else { return .miss }
        // Inverse-rotate into unrotated board space for standard hit testing.
        let rad = -rotation * Double.pi / 180
        let cosR = cos(rad), sinR = sin(rad)
        let x = point.x * cosR - point.y * sinR
        let y = point.x * sinR + point.y * cosR
        return BoardGeometry.hit(x: x, y: y)
    }

    public func circle(radius: Double, samples: Int = 64) -> [NormPoint] {
        (0..<samples).compactMap { index in
            let angle = Double(index) / Double(samples) * 2 * Double.pi
            return imagePoint(boardX: cos(angle) * radius, boardY: sin(angle) * radius)
        }
    }

    public func wire(at index: Int) -> (inner: NormPoint, outer: NormPoint)? {
        guard (0..<20).contains(index) else { return nil }
        let hitAngle = Double(index) * (2 * Double.pi / 20)
        let atan = hitAngle - Double.pi / 2 - Double.pi / 20
        guard let inner = imagePoint(boardX: cos(atan) * BoardRings.outerBull, boardY: sin(atan) * BoardRings.outerBull),
              let outer = imagePoint(boardX: cos(atan) * 1.02, boardY: sin(atan) * 1.02) else { return nil }
        return (inner, outer)
    }

    public func numberSpots() -> [(label: String, point: NormPoint)] {
        (0..<20).compactMap { index in
            let mid = (Double(index) + 0.5) * (2 * Double.pi / 20)
            let atan = mid - Double.pi / 2 - Double.pi / 20
            guard let point = imagePoint(boardX: cos(atan) * 1.12, boardY: sin(atan) * 1.12) else { return nil }
            return ("\(BoardGeometry.sectors[index])", point)
        }
    }

    public func bandOutline(segment: Int, multiplier: Int) -> [NormPoint]? {
        if segment == 25 {
            return circle(radius: multiplier == 2 ? BoardRings.innerBull : BoardRings.outerBull, samples: 40)
        }
        guard let index = BoardGeometry.sectors.firstIndex(of: segment) else { return nil }
        let start = Double(index) * (2 * Double.pi / 20)
        let end = start + (2 * Double.pi / 20)
        let (innerR, outerR): (Double, Double)
        switch multiplier {
        case 2: (innerR, outerR) = (BoardRings.doubleInner, 1)
        case 3: (innerR, outerR) = (BoardRings.tripleInner, BoardRings.tripleOuter)
        default: (innerR, outerR) = (BoardRings.outerBull, BoardRings.doubleInner)
        }
        let outer = arc(radius: outerR, from: start, to: end)
        let inner = arc(radius: innerR, from: start, to: end)
        guard outer.count > 2, inner.count > 2 else { return nil }
        return outer + inner.reversed()
    }

    private func arc(radius: Double, from start: Double, to end: Double, samples: Int = 12) -> [NormPoint] {
        (0...samples).compactMap { step in
            let hitAngle = start + (end - start) * Double(step) / Double(samples)
            let atan = hitAngle - Double.pi / 2 - Double.pi / 20
            return imagePoint(boardX: cos(atan) * radius, boardY: sin(atan) * radius)
        }
    }
}

struct Homography {
    private var forward: [Double]
    private var inverse: [Double]

    init?(matrix: [Double]) {
        guard matrix.count == 9, let inverse = PlaneFit.invert(matrix) else { return nil }
        forward = matrix
        self.inverse = inverse
    }

    private init(forward: [Double], inverse: [Double]) {
        self.forward = forward
        self.inverse = inverse
    }

    func project(x: Double, y: Double) -> (x: Double, y: Double)? { Self.apply(forward, x: x, y: y) }
    func unproject(u: Double, v: Double) -> (x: Double, y: Double)? { Self.apply(inverse, x: u, y: v) }

    static func fit(board: [(Double, Double)], image: [(Double, Double)]) -> Homography? {
        guard board.count == 4, image.count == 4 else { return nil }
        guard let (boardPoints, boardTransform) = normalize(board), let (imagePoints, imageTransform) = normalize(image) else { return nil }
        var matrix = Array(repeating: Array(repeating: 0.0, count: 8), count: 8)
        var rhs = Array(repeating: 0.0, count: 8)
        for index in 0..<4 {
            let x = boardPoints[index].0
            let y = boardPoints[index].1
            let u = imagePoints[index].0
            let v = imagePoints[index].1
            matrix[index * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y]
            rhs[index * 2] = u
            matrix[index * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y]
            rhs[index * 2 + 1] = v
        }
        guard let solution = LinearSolve.system(matrix, rhs) else { return nil }
        let normalized = [
            solution[0], solution[1], solution[2],
            solution[3], solution[4], solution[5],
            solution[6], solution[7], 1
        ]
        guard let imageInverse = invert(imageTransform) else { return nil }
        let fitted = multiply(imageInverse, multiply(normalized, boardTransform))
        guard let backward = invert(fitted) else { return nil }
        return Homography(forward: fitted, inverse: backward)
    }

    private static func apply(_ matrix: [Double], x: Double, y: Double) -> (x: Double, y: Double)? {
        let weight = matrix[6] * x + matrix[7] * y + matrix[8]
        guard abs(weight) > 1e-8 else { return nil }
        let u = (matrix[0] * x + matrix[1] * y + matrix[2]) / weight
        let v = (matrix[3] * x + matrix[4] * y + matrix[5]) / weight
        guard u.isFinite, v.isFinite else { return nil }
        return (u, v)
    }

    private static func normalize(_ points: [(Double, Double)]) -> (points: [(Double, Double)], transform: [Double])? {
        guard points.allSatisfy({ $0.0.isFinite && $0.1.isFinite }) else { return nil }
        let count = Double(points.count)
        let cx = points.reduce(0) { $0 + $1.0 } / count
        let cy = points.reduce(0) { $0 + $1.1 } / count
        let average = points.reduce(0) { $0 + hypot($1.0 - cx, $1.1 - cy) } / count
        guard average > 1e-6 else { return nil }
        let s = sqrt(2) / average
        let mapped = points.map { (($0.0 - cx) * s, ($0.1 - cy) * s) }
        return (mapped, [s, 0, -s * cx, 0, s, -s * cy, 0, 0, 1])
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var result = Array(repeating: 0.0, count: 9)
        for row in 0..<3 {
            for column in 0..<3 {
                result[row * 3 + column] = a[row * 3] * b[column] + a[row * 3 + 1] * b[3 + column] + a[row * 3 + 2] * b[6 + column]
            }
        }
        return result
    }

    private static func invert(_ m: [Double]) -> [Double]? {
        let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        guard abs(det) > 1e-10 else { return nil }
        return [
            (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
            (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
            (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det
        ]
    }
}

enum LinearSolve {
    static func system(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
        let n = rhs.count
        guard matrix.count == n, matrix.allSatisfy({ $0.count == n }) else { return nil }
        var a = matrix
        var b = rhs
        for column in 0..<n {
            var pivot = column
            for row in (column + 1)..<n where abs(a[row][column]) > abs(a[pivot][column]) { pivot = row }
            guard abs(a[pivot][column]) > 1e-10 else { return nil }
            if pivot != column {
                a.swapAt(column, pivot)
                b.swapAt(column, pivot)
            }
            let divisor = a[column][column]
            for index in column..<n { a[column][index] /= divisor }
            b[column] /= divisor
            for row in 0..<n where row != column {
                let factor = a[row][column]
                if factor == 0 { continue }
                for index in column..<n { a[row][index] -= factor * a[column][index] }
                b[row] -= factor * b[column]
            }
        }
        return b.allSatisfy(\.isFinite) ? b : nil
    }
}

private extension Double {
    func clamped(_ lower: Double, _ upper: Double) -> Double { min(max(self, lower), upper) }
    func finiteOr(_ fallback: Double) -> Double { isFinite ? self : fallback }
}
