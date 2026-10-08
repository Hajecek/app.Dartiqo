import CoreVideo
import Foundation
import simd
import Vision

nonisolated enum VisionMode: Equatable {
    case calibrate, score
}

nonisolated struct VisionNumber: @unchecked Sendable {
    var value: Int
    var x: Double
    var y: Double
}

nonisolated struct VisionPacket: @unchecked Sendable {
    var bufferWidth: Double
    var bufferHeight: Double
    var previewWidth: Double
    var previewHeight: Double
    var circleX: Double
    var circleY: Double
    var circleRadius: Double
    var residual: Double
    var hasCircle: Bool
    var numbers: [VisionNumber]
    var luma: [UInt8]
    var lumaWidth: Int
    var lumaHeight: Int
}

/// Vision najde kruhový okraj a přečte čísla. Rozdíl jasu pak ukáže novou šipku.
nonisolated final class BoardFrameAnalyzer: @unchecked Sendable {
    private let contours = VNDetectContoursRequest()
    private let text = VNRecognizeTextRequest()
    private var cachedNumbers: [VisionNumber] = []
    private var frameIndex = 0

    init() {
        contours.contrastAdjustment = 1.8
        contours.detectsDarkOnLight = true
        contours.maximumImageDimension = 640
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        text.recognitionLanguages = ["en-US"]
        text.customWords = (1...20).map { "\($0)" }
        text.minimumTextHeight = 0.012
    }

    func reset() {
        cachedNumbers = []
        frameIndex = 0
    }

    func makePacket(_ buffer: CVPixelBuffer, preview: CGSize, mode: VisionMode) -> VisionPacket {
        let width = Double(CVPixelBufferGetWidth(buffer))
        let height = Double(CVPixelBufferGetHeight(buffer))
        if mode == .score {
            let grid = LumaGrid.sample(buffer, columns: 64, rows: 64)
            return VisionPacket(
                bufferWidth: width, bufferHeight: height,
                previewWidth: Double(preview.width), previewHeight: Double(preview.height),
                circleX: 0, circleY: 0, circleRadius: 0, residual: 1,
                hasCircle: false, numbers: [],
                luma: grid.samples, lumaWidth: grid.width, lumaHeight: grid.height
            )
        }

        frameIndex += 1
        var circle: FittedCircle?
        var numbers = cachedNumbers
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        if (try? handler.perform([contours])) != nil, let observation = contours.results?.first {
            circle = Self.bestCircle(in: observation, aspect: width / max(height, 1))
        }
        let readText = frameIndex % 3 == 1 || cachedNumbers.isEmpty
        if readText, let circle {
            let aspect = width / max(height, 1)
            let roi = Self.ring(around: circle, aspect: aspect)
            if roi.width > 0.04, roi.height > 0.04 { text.regionOfInterest = roi }
            let reader = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
            if (try? reader.perform([text])) != nil {
                numbers = Self.numbers(in: text.results ?? [], circle: circle, aspect: aspect)
                cachedNumbers = numbers
            }
        }
        return VisionPacket(
            bufferWidth: width, bufferHeight: height,
            previewWidth: Double(preview.width), previewHeight: Double(preview.height),
            circleX: circle?.x ?? 0, circleY: circle?.y ?? 0,
            circleRadius: circle?.radius ?? 0, residual: circle?.residual ?? 1,
            hasCircle: circle != nil, numbers: numbers,
            luma: [], lumaWidth: 0, lumaHeight: 0
        )
    }

    private struct FittedCircle {
        var x: Double
        var y: Double
        var radius: Double
        var residual: Double
    }

    private static func bestCircle(in observation: VNContoursObservation, aspect: Double) -> FittedCircle? {
        var fitted: [FittedCircle] = []
        func consider(_ contour: VNContour) {
            guard contour.pointCount >= 36, let circle = fit(contour, aspect: aspect), circle.residual <= 0.045 else { return }
            guard (0.08...0.55).contains(circle.radius) else { return }
            fitted.append(circle)
        }
        for contour in observation.topLevelContours {
            consider(contour)
            if (1...12).contains(contour.childContourCount) {
                for child in contour.childContours { consider(child) }
            }
        }
        guard var edge = fitted.max(by: { score($0) < score($1) }) else { return nil }
        if let bull = fitted.filter({ candidate in
            candidate.radius < edge.radius * 0.22 && hypot(candidate.x - edge.x, (candidate.y - edge.y) / max(aspect, 0.01)) < edge.radius * 0.12
        }).min(by: { $0.radius < $1.radius }) {
            edge.x = bull.x
            edge.y = bull.y
        }
        return edge
    }

    private static func score(_ circle: FittedCircle) -> Double {
        circle.radius * (1 - min(circle.residual, 0.045) / 0.045)
    }

    /// Body kontury jsou v souřadnicích Vision (dole vlevo). Vrací střed v souřadnicích shora vlevo a poloměr jako zlomek šířky.
    private static func fit(_ contour: VNContour, aspect: Double) -> FittedCircle? {
        let count = contour.pointCount
        let pointer = contour.normalizedPoints
        let step = max(1, count / 80)
        var samples: [(Double, Double)] = []
        samples.reserveCapacity(80)
        var index = 0
        while index < count {
            let point = pointer[index]
            let x = Double(point.x)
            let y = (1 - Double(point.y)) / max(aspect, 0.000_1)
            samples.append((x, y))
            index += step
        }
        guard samples.count >= 12 else { return nil }
        let meanX = samples.reduce(0) { $0 + $1.0 } / Double(samples.count)
        let meanY = samples.reduce(0) { $0 + $1.1 } / Double(samples.count)
        var xx = 0.0, xy = 0.0, yy = 0.0, x = 0.0, y = 0.0, n = 0.0
        var bx = 0.0, by = 0.0, bn = 0.0
        for sample in samples {
            let px = sample.0 - meanX
            let py = sample.1 - meanY
            let weight = px * px + py * py
            xx += px * px; xy += px * py; yy += py * py
            x += px; y += py; n += 1
            bx -= weight * px; by -= weight * py; bn -= weight
        }
        guard let solution = solve3(a: [xx, xy, x, xy, yy, y, x, y, n], b: [bx, by, bn]) else { return nil }
        let d = solution.0, e = solution.1, f = solution.2
        let cx = -d / 2
        let cy = -e / 2
        let radius = (cx * cx + cy * cy - f).squareRoot()
        guard radius.isFinite, radius > 0.01 else { return nil }
        let residual = samples.reduce(0.0) { partial, sample in
            partial + abs(hypot(sample.0 - meanX - cx, sample.1 - meanY - cy) - radius)
        } / Double(samples.count) / radius
        return FittedCircle(x: cx + meanX, y: (cy + meanY) * aspect, radius: radius, residual: residual)
    }

    private static func solve3(a: [Double], b: [Double]) -> (Double, Double, Double)? {
        var m = a
        var r = b
        for column in 0..<3 {
            var pivot = column
            for row in (column + 1)..<3 where abs(m[row * 3 + column]) > abs(m[pivot * 3 + column]) { pivot = row }
            guard abs(m[pivot * 3 + column]) > 1e-10 else { return nil }
            if pivot != column {
                for index in 0..<3 { m.swapAt(column * 3 + index, pivot * 3 + index) }
                r.swapAt(column, pivot)
            }
            let divisor = m[column * 3 + column]
            for index in column..<3 { m[column * 3 + index] /= divisor }
            r[column] /= divisor
            for row in 0..<3 where row != column {
                let factor = m[row * 3 + column]
                if factor == 0 { continue }
                for index in column..<3 { m[row * 3 + index] -= factor * m[column * 3 + index] }
                r[row] -= factor * r[column]
            }
        }
        guard r.allSatisfy(\.isFinite) else { return nil }
        return (r[0], r[1], r[2])
    }

    private static func ring(around circle: FittedCircle, aspect: Double) -> CGRect {
        let ry = circle.radius * aspect
        let rect = CGRect(x: circle.x - circle.radius * 1.3, y: (1 - circle.y) - ry * 1.3, width: circle.radius * 2.6, height: ry * 2.6)
        return rect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private static func numbers(in observations: [VNRecognizedTextObservation], circle: FittedCircle, aspect: Double) -> [VisionNumber] {
        var best: [Int: VisionNumber] = [:]
        var confidence: [Int: Float] = [:]
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let raw = candidate.string
                .uppercased()
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "I", with: "1")
                .replacingOccurrences(of: "L", with: "1")
                .trimmingCharacters(in: .whitespaces)
            guard let value = Int(raw), raw == "\(value)", (1...20).contains(value), candidate.confidence >= 0.3 else { continue }
            let box = observation.boundingBox
            let center = VisionNumber(value: value, x: box.midX, y: 1 - box.midY)
            let dx = center.x - circle.x
            let dy = (center.y - circle.y) / max(aspect, 0.000_1)
            let ratio = hypot(dx, dy) / max(circle.radius, 0.000_1)
            guard (0.55...1.45).contains(ratio) else { continue }
            if confidence[value, default: 0] < candidate.confidence {
                confidence[value] = candidate.confidence
                best[value] = center
            }
        }
        return Array(best.values)
    }
}

private enum LumaGrid {
    static func sample(_ buffer: CVPixelBuffer, columns: Int, rows: Int) -> (samples: [UInt8], width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let format = CVPixelBufferGetPixelFormatType(buffer)
        if format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            return read(plane: 0, of: buffer, columns: columns, rows: rows, bgra: false)
        }
        return read(plane: 0, of: buffer, columns: columns, rows: rows, bgra: format == kCVPixelFormatType_32BGRA)
    }

    private static func read(plane: Int, of buffer: CVPixelBuffer, columns: Int, rows: Int, bgra: Bool) -> (samples: [UInt8], width: Int, height: Int) {
        let width = CVPixelBufferGetWidthOfPlane(buffer, plane)
        let height = CVPixelBufferGetHeightOfPlane(buffer, plane)
        guard width > 1, height > 1, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) else { return ([], 0, 0) }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, plane)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        var samples = Array(repeating: UInt8(0), count: columns * rows)
        for row in 0..<rows {
            let y = min(height - 1, row * height / rows)
            for column in 0..<columns {
                let x = min(width - 1, column * width / columns)
                if bgra {
                    let pixel = pointer + y * rowBytes + x * 4
                    let luma = (Int(pixel[2]) * 77 + Int(pixel[1]) * 150 + Int(pixel[0]) * 29) >> 8
                    samples[row * columns + column] = UInt8(min(255, luma))
                } else {
                    samples[row * columns + column] = pointer[y * rowBytes + x]
                }
            }
        }
        return (samples, columns, rows)
    }
}
