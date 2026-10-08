import CoreVideo
import Foundation
import Vision

nonisolated enum VisionMode: Equatable {
    case calibrate, score
}

nonisolated struct VisionPacket: @unchecked Sendable {
    var bufferWidth: Double
    var bufferHeight: Double
    var previewWidth: Double
    var previewHeight: Double
    var detection: BoardDetection?
    var luma: [UInt8]
    var lumaWidth: Int
    var lumaHeight: Int
}

/// Terč najde podle barev doublu a triplu. Čísla čte jen občas, aby potvrdila, kde je 20.
nonisolated final class BoardFrameAnalyzer: @unchecked Sendable {
    private let text = VNRecognizeTextRequest()
    private var cachedNumbers: [BoardDetector.Number] = []
    private var frameIndex = 0

    init() {
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
        var packet = VisionPacket(
            bufferWidth: width, bufferHeight: height,
            previewWidth: Double(preview.width), previewHeight: Double(preview.height),
            detection: nil, luma: [], lumaWidth: 0, lumaHeight: 0
        )
        frameIndex += 1
        if mode == .score {
            let columns = 160
            let rows = max(32, min(340, Int((Double(columns) * height / max(width, 1)).rounded())))
            let grid = LumaGrid.sample(buffer, columns: columns, rows: rows)
            packet.luma = grid.samples
            packet.lumaWidth = grid.width
            packet.lumaHeight = grid.height
            if frameIndex % 12 == 0, let chroma = ChromaPlane.read(buffer, maxWidth: 320) {
                packet.detection = BoardDetector.detect(chroma)
            }
            return packet
        }

        guard let chroma = ChromaPlane.read(buffer, maxWidth: 320), let scan = BoardDetector.scan(chroma) else {
            return packet
        }
        if frameIndex % 4 == 1 {
            cachedNumbers = readNumbers(buffer, scan: scan)
        }
        packet.detection = BoardDetector.solve(scan, numbers: cachedNumbers)
        return packet
    }

    private func readNumbers(_ buffer: CVPixelBuffer, scan: BoardDetector.Scan) -> [BoardDetector.Number] {
        let cx = scan.center.x / Double(scan.width)
        let cy = scan.center.y / Double(scan.height)
        let rx = scan.radius / Double(scan.width) * 1.6
        let ry = scan.radius / Double(scan.height) * 1.6
        let roi = CGRect(x: cx - rx, y: (1 - cy) - ry, width: rx * 2, height: ry * 2)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard roi.width > 0.05, roi.height > 0.05 else { return [] }
        text.regionOfInterest = roi
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        guard (try? handler.perform([text])) != nil else { return [] }
        var best: [Int: (confidence: Float, number: BoardDetector.Number)] = [:]
        for observation in text.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, candidate.confidence >= 0.3 else { continue }
            let raw = candidate.string
                .uppercased()
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "I", with: "1")
                .replacingOccurrences(of: "L", with: "1")
                .trimmingCharacters(in: .whitespaces)
            guard let value = Int(raw), raw == "\(value)", (1...20).contains(value) else { continue }
            let box = observation.boundingBox
            let number = BoardDetector.Number(value: value, point: SIMD2(box.midX, 1 - box.midY))
            if best[value].map({ $0.confidence < candidate.confidence }) ?? true {
                best[value] = (candidate.confidence, number)
            }
        }
        return best.values.map(\.number)
    }
}

/// Druhá rovina YUV bufferu: střídavě Cb a Cr v poloviční velikosti.
private enum ChromaPlane {
    nonisolated static func read(_ buffer: CVPixelBuffer, maxWidth: Int) -> ChromaImage? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(buffer) >= 2 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planeWidth = CVPixelBufferGetWidthOfPlane(buffer, 1)
        let planeHeight = CVPixelBufferGetHeightOfPlane(buffer, 1)
        guard planeWidth > 8, planeHeight > 8, let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let pointer = base.assumingMemoryBound(to: UInt8.self)
        let step = max(1, Int((Double(planeWidth) / Double(maxWidth)).rounded(.up)))
        let width = planeWidth / step
        let height = planeHeight / step
        var cb = [UInt8](repeating: 0, count: width * height)
        var cr = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let line = pointer + row * step * rowBytes
            for column in 0..<width {
                let offset = column * step * 2
                cb[row * width + column] = line[offset]
                cr[row * width + column] = line[offset + 1]
            }
        }
        return ChromaImage(width: width, height: height, cb: cb, cr: cr)
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
        let taps = 4
        for row in 0..<rows {
            let top = row * height / rows
            let cellHeight = max(1, (row + 1) * height / rows - top)
            for column in 0..<columns {
                let left = column * width / columns
                let cellWidth = max(1, (column + 1) * width / columns - left)
                var sum = 0
                for ty in 0..<taps {
                    let y = min(height - 1, top + (ty * 2 + 1) * cellHeight / (taps * 2))
                    for tx in 0..<taps {
                        let x = min(width - 1, left + (tx * 2 + 1) * cellWidth / (taps * 2))
                        if bgra {
                            let pixel = pointer + y * rowBytes + x * 4
                            sum += (Int(pixel[2]) * 77 + Int(pixel[1]) * 150 + Int(pixel[0]) * 29) >> 8
                        } else {
                            sum += Int(pointer[y * rowBytes + x])
                        }
                    }
                }
                samples[row * columns + column] = UInt8(min(255, sum / (taps * taps)))
            }
        }
        return (samples, columns, rows)
    }
}
