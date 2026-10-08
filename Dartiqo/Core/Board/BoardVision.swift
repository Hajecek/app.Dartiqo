import Foundation

/// Obraz z kamery (po otočení na výšku) a výřez, který vidí náhled s `resizeAspectFill`.
struct VisionFrame: Equatable {
    var bufferWidth: Double
    var bufferHeight: Double
    var previewWidth: Double
    var previewHeight: Double

    var bufferAspect: Double { bufferWidth / max(bufferHeight, 1) }
    var previewAspect: Double { previewWidth / max(previewHeight, 1) }
    private var cropsSides: Bool { bufferAspect > previewAspect + 0.000_1 }

    func previewPoint(_ buffer: NormPoint) -> NormPoint {
        if cropsSides {
            let scale = bufferAspect / previewAspect
            return NormPoint(x: buffer.x * scale - (scale - 1) / 2, y: buffer.y)
        }
        let scale = previewAspect / max(bufferAspect, 0.000_1)
        return NormPoint(x: buffer.x, y: buffer.y * scale - (scale - 1) / 2)
    }

    func bufferPoint(_ preview: NormPoint) -> NormPoint {
        if cropsSides {
            let scale = bufferAspect / previewAspect
            return NormPoint(x: (preview.x + (scale - 1) / 2) / scale, y: preview.y)
        }
        let scale = previewAspect / max(bufferAspect, 0.000_1)
        return NormPoint(x: preview.x, y: (preview.y + (scale - 1) / 2) / scale)
    }

    func previewRadius(bufferRadius: Double) -> Double {
        guard cropsSides else { return bufferRadius }
        return bufferRadius * (bufferAspect / previewAspect)
    }
}

enum BoardReadiness: Equatable {
    case searching, edge, aligned
}

struct BoardSolution: Equatable {
    var calibration: BoardCalibration
    /// Detekovaný okraj jako zlomek šířky náhledu. Zelený kruh sedí na něm.
    var edgeRadius: Double
    var readiness: BoardReadiness
    var numberCount: Int
}

/// Z kontury a přečtených čísel složí mapu terče. Čísla určují otočení a jestli je okraj vnější věnec, nebo double.
enum BoardVision {
    struct CircleSample: Equatable {
        var center: NormPoint
        var radius: Double
        var residual: Double
    }

    struct NumberSample: Equatable {
        var value: Int
        var center: NormPoint
    }

    static let maxResidual = 0.04
    /// Střed čísel na standardním terči je dál než vnější double.
    static let numberOverDouble = 1.12

    static func solve(circle: CircleSample, numbers: [NumberSample], frame: VisionFrame) -> BoardSolution? {
        guard circle.residual <= maxResidual, circle.radius.isFinite else { return nil }
        guard (0.12...0.48).contains(circle.radius) else { return nil }
        let vertical = circle.radius * frame.bufferAspect
        guard circle.center.x - circle.radius > 0.02,
              circle.center.x + circle.radius < 0.98,
              circle.center.y - vertical > 0.02,
              circle.center.y + vertical < 0.98 else { return nil }

        let placed = placements(circle: circle, numbers: numbers, frame: frame)
        let rotation = agreedRotation(placed)
        let edge = frame.previewRadius(bufferRadius: circle.radius)
        let scoring: Double
        if let rotation {
            let used = placed.filter { abs(delta(rotation, $0.degrees)) <= 8 }
            scoring = scoringRadius(detected: edge, placements: used)
        } else {
            scoring = edge
        }
        var calibration = BoardCalibration(
            center: frame.previewPoint(circle.center),
            radius: scoring,
            rotationDegrees: rotation ?? 0,
            previewAspect: frame.previewAspect
        ).sanitized()
        calibration.calibratedAt = rotation == nil ? nil : Date()
        return BoardSolution(
            calibration: calibration,
            edgeRadius: edge,
            readiness: rotation == nil ? .edge : .aligned,
            numberCount: placed.count
        )
    }

    private struct Placement {
        var value: Int
        var degrees: Double
        var ratio: Double
    }

    private static func placements(circle: CircleSample, numbers: [NumberSample], frame: VisionFrame) -> [Placement] {
        let width = frame.bufferWidth
        let height = frame.bufferHeight
        let radiusPx = circle.radius * width
        guard radiusPx > 1 else { return [] }
        return numbers.compactMap { number in
            guard BoardGeometry.sectors.contains(number.value) else { return nil }
            let dx = (number.center.x - circle.center.x) * width
            let dy = (number.center.y - circle.center.y) * height
            let distance = hypot(dx, dy)
            let ratio = distance / radiusPx
            guard (0.55...1.45).contains(ratio) else { return nil }
            guard let index = BoardGeometry.sectors.firstIndex(of: number.value) else { return nil }
            let expected = -90.0 + Double(index) * 18.0
            let observed = atan2(dy, dx) * 180 / .pi
            return Placement(value: number.value, degrees: wrap(observed - expected), ratio: ratio)
        }
    }

    private static func agreedRotation(_ placed: [Placement]) -> Double? {
        guard !placed.isEmpty else { return nil }
        var best: [Placement] = []
        for candidate in placed {
            let group = placed.filter { abs(delta(candidate.degrees, $0.degrees)) <= 8 }
            if group.count > best.count { best = group }
        }
        let trusted = best.count >= 2 || (best.count == 1 && best[0].value == 20 && placed.count == 1)
        guard trusted else { return nil }
        let radians = best.map { $0.degrees * .pi / 180 }
        let mean = atan2(radians.reduce(0) { $0 + sin($1) }, radians.reduce(0) { $0 + cos($1) })
        return wrap(mean * 180 / .pi)
    }

    private static func scoringRadius(detected: Double, placements: [Placement]) -> Double {
        guard !placements.isEmpty else { return detected }
        let ratios = placements.map(\.ratio).sorted()
        let median = ratios[ratios.count / 2]
        if median > 1.02 { return detected }
        if median < 0.98 { return detected * median / numberOverDouble }
        return detected
    }

    static func wrap(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private static func delta(_ a: Double, _ b: Double) -> Double { wrap(a - b) }
}

struct BoardTrack: Equatable {
    var calibration = BoardCalibration.draft
    var edgeRadius = 0.0
    var readiness: BoardReadiness = .searching
    var status = "Namiř kameru na celý terč."
    var showsFit = false
    var wantsSave = false
    private var edgeStreak = 0
    private var segmentStreak = 0
    private var saved = false

    mutating func reset() { self = BoardTrack() }

    mutating func markSaved() {
        saved = true
        wantsSave = false
        if readiness == .aligned { status = "Terč je nastavený. Telefon už nepřemisťuj." }
    }

    mutating func ingest(_ solution: BoardSolution?) {
        if let solution, solution.readiness != .searching {
            edgeStreak = min(edgeStreak + 1, 12)
            blend(solution)
            showsFit = true
        } else {
            edgeStreak = max(0, edgeStreak - 1)
        }
        if solution?.readiness == .aligned {
            segmentStreak = min(segmentStreak + 1, 12)
        } else {
            segmentStreak = max(0, segmentStreak - 1)
        }

        if segmentStreak >= 3, showsFit {
            readiness = .aligned
        } else if edgeStreak >= 3, showsFit {
            readiness = .edge
        } else if edgeStreak == 0 {
            readiness = .searching
            if !showsFit { status = "Namiř kameru na celý terč." }
        }

        switch readiness {
        case .searching:
            status = edgeStreak > 0 ? "Hledám okraj terče." : "Namiř kameru na celý terč."
        case .edge:
            status = "Okraj je vidět. Čtu čísla segmentů."
        case .aligned:
            if !saved, segmentStreak >= 8 { wantsSave = true }
            status = saved ? "Terč je nastavený. Telefon už nepřemisťuj." : "Segmenty sedí. Ukládám kalibraci."
        }
    }

    private mutating func blend(_ solution: BoardSolution) {
        let gain = edgeStreak < 3 ? 0.55 : 0.28
        let current = calibration
        let next = solution.calibration
        calibration = BoardCalibration(
            center: NormPoint(
                x: mix(current.center.x, next.center.x, gain),
                y: mix(current.center.y, next.center.y, gain)
            ),
            radius: mix(showsFit ? current.radius : next.radius, next.radius, gain),
            rotationDegrees: BoardVision.wrap(current.rotationDegrees + BoardVision.wrap(next.rotationDegrees - current.rotationDegrees) * (solution.readiness == .aligned ? gain : 0)),
            previewAspect: next.previewAspect,
            calibratedAt: next.calibratedAt
        ).sanitized()
        edgeRadius = mix(showsFit ? edgeRadius : solution.edgeRadius, solution.edgeRadius, gain)
    }

    private func mix(_ from: Double, _ to: Double, _ gain: Double) -> Double { from + (to - from) * gain }
}

enum DartBlobs {
    struct Tip: Equatable {
        var x: Double
        var y: Double
    }

    static func changedCount(_ current: [UInt8], _ reference: [UInt8], threshold: UInt8 = 32) -> Int {
        guard current.count == reference.count else { return Int.max }
        var count = 0
        for index in current.indices where abs(Int(current[index]) - Int(reference[index])) >= Int(threshold) {
            count += 1
        }
        return count
    }

    static func tips(
        current: [UInt8],
        reference: [UInt8],
        width: Int,
        height: Int,
        center: NormPoint,
        threshold: UInt8 = 32,
        minCells: Int = 5,
        maxCells: Int = 180
    ) -> [Tip] {
        guard width > 1, height > 1, current.count == width * height, reference.count == current.count else { return [] }
        var changed = Array(repeating: false, count: current.count)
        for index in current.indices where abs(Int(current[index]) - Int(reference[index])) >= Int(threshold) {
            changed[index] = true
        }
        var seen = Array(repeating: false, count: current.count)
        var found: [Tip] = []
        let targetX = center.x * Double(width)
        let targetY = center.y * Double(height)
        for start in changed.indices where changed[start] && !seen[start] {
            var stack = [start]
            var cells: [(Int, Int)] = []
            seen[start] = true
            while let index = stack.popLast() {
                let x = index % width
                let y = index / width
                cells.append((x, y))
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let next = ny * width + nx
                    guard changed[next], !seen[next] else { continue }
                    seen[next] = true
                    stack.append(next)
                }
            }
            guard (minCells...maxCells).contains(cells.count) else { continue }
            let minX = cells.map(\.0).min() ?? 0
            let maxX = cells.map(\.0).max() ?? 0
            let minY = cells.map(\.1).min() ?? 0
            let maxY = cells.map(\.1).max() ?? 0
            if maxX - minX > width * 2 / 5, maxY - minY > height * 2 / 5 { continue }
            guard let tip = cells.min(by: { lhs, rhs in
                let left = pow(Double(lhs.0) + 0.5 - targetX, 2) + pow(Double(lhs.1) + 0.5 - targetY, 2)
                let right = pow(Double(rhs.0) + 0.5 - targetX, 2) + pow(Double(rhs.1) + 0.5 - targetY, 2)
                return left < right
            }) else { continue }
            found.append(Tip(x: (Double(tip.0) + 0.5) / Double(width), y: (Double(tip.1) + 0.5) / Double(height)))
        }
        return found.sorted { hypot($0.x - center.x, $0.y - center.y) < hypot($1.x - center.x, $1.y - center.y) }
    }
}

/// Prázdný terč si vezme až po klidném obrazu. Nová šipka je rozdíl proti němu a musí chvíli držet na místě.
struct DartWatch {
    private(set) var phaseIsSettling = true
    private(set) var known: [NormPoint] = []
    private var reference: [UInt8]?
    private var previous: [UInt8]?
    private var calm = 0
    private var pending: [(x: Double, y: Double, streak: Int)] = []
    private var latched: NormPoint?
    private var suppressed: [(point: NormPoint, life: Int)] = []
    private var gridWidth = 0
    private var gridHeight = 0

    var status: String {
        phaseIsSettling ? "Drž telefon v klidu. Beru si prázdný terč." : (known.isEmpty ? "Házej. Šipka se zapíše sama." : "Čekám na další šipku.")
    }

    mutating func reset() { self = DartWatch() }

    mutating func undo(steps: Int) {
        let drop = min(max(0, steps), known.count)
        if drop > 0 { known.removeLast(drop) }
        pending.removeAll()
        latched = nil
        reference = nil
        previous = nil
        calm = 0
        phaseIsSettling = true
    }

    mutating func confirm() {
        if let latched { known.append(latched) }
        if let latched { pending.removeAll { Self.near(NormPoint(x: $0.x, y: $0.y), latched) } }
        latched = nil
    }

    mutating func reject() {
        if let latched { suppressed.append((latched, 8)) }
        latched = nil
    }

    mutating func ingest(
        luma: [UInt8],
        width: Int,
        height: Int,
        frame: VisionFrame,
        center: NormPoint,
        accept: (NormPoint) -> Bool
    ) -> NormPoint? {
        guard width > 1, height > 1, luma.count == width * height else { return nil }
        if width != gridWidth || height != gridHeight {
            let kept = known
            self = DartWatch()
            known = kept
            gridWidth = width
            gridHeight = height
        }
        suppressed = suppressed.compactMap { item in
            let life = item.life - 1
            return life > 0 ? (item.point, life) : nil
        }
        if let previous, previous.count == luma.count {
            calm = DartBlobs.changedCount(luma, previous, threshold: 28) < 18 ? calm + 1 : 0
        }
        previous = luma
        guard latched == nil, known.count < 3 else { return nil }

        if reference == nil {
            if calm >= 3 {
                reference = luma
                phaseIsSettling = false
            } else {
                phaseIsSettling = true
            }
            return nil
        }
        phaseIsSettling = false
        guard let reference else { return nil }
        let bufferCenter = frame.bufferPoint(center)
        let tips = DartBlobs.tips(current: luma, reference: reference, width: width, height: height, center: bufferCenter)
            .map { frame.previewPoint(NormPoint(x: $0.x, y: $0.y)) }
            .filter { tip in
                accept(tip)
                    && !suppressed.contains { Self.near(tip, $0.point) }
                    && !known.contains { Self.near(tip, $0) }
            }

        var used = Array(repeating: false, count: tips.count)
        var next: [(x: Double, y: Double, streak: Int)] = []
        for item in pending {
            if let index = tips.indices.first(where: { !used[$0] && Self.near(tips[$0], NormPoint(x: item.x, y: item.y)) }) {
                used[index] = true
                next.append((tips[index].x, tips[index].y, item.streak + 1))
            } else if item.streak > 1 {
                next.append((item.x, item.y, item.streak - 1))
            }
        }
        for index in tips.indices where !used[index] {
            next.append((tips[index].x, tips[index].y, 1))
        }
        pending = next
        guard let ready = pending.first(where: { $0.streak >= 4 }) else { return nil }
        let point = NormPoint(x: ready.x, y: ready.y)
        latched = point
        return point
    }

    private static func near(_ lhs: NormPoint, _ rhs: NormPoint) -> Bool {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y) < 0.035
    }
}
