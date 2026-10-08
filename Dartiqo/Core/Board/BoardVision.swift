import Foundation
import simd

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
    var center: NormPoint
    /// Vnější double v náhledu. Kreslí se, dokud nesedí segmenty.
    var rim: [NormPoint]
    /// Hotová mapa, když barvy segmentů daly všech 20 hranic.
    var calibration: BoardCalibration?
}

/// Převede nález z kamery do souřadnic náhledu.
enum BoardVision {
    static func solve(_ detection: BoardDetection?, frame: VisionFrame) -> BoardSolution? {
        guard let detection, detection.rim.count >= 12 else { return nil }
        let preview = { (point: SIMD2<Double>) in frame.previewPoint(NormPoint(x: point.x, y: point.y)) }
        var solution = BoardSolution(center: preview(detection.center), rim: detection.rim.map(preview), calibration: nil)
        if let matrix = detection.homography {
            solution.calibration = BoardCalibration(
                homography: PlaneFit.multiply(previewTransform(frame), matrix),
                previewAspect: frame.previewAspect
            )
        }
        return solution
    }

    /// `previewPoint` je po osách lineární, takže jde zapsat jako matice.
    static func previewTransform(_ frame: VisionFrame) -> [Double] {
        let origin = frame.previewPoint(NormPoint(x: 0, y: 0))
        let right = frame.previewPoint(NormPoint(x: 1, y: 0))
        let down = frame.previewPoint(NormPoint(x: 0, y: 1))
        return [right.x - origin.x, 0, origin.x, 0, down.y - origin.y, origin.y, 0, 0, 1]
    }

    static func wrap(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }
}

struct BoardTrack: Equatable {
    var calibration = BoardCalibration.draft
    var rim: [NormPoint] = []
    var readiness: BoardReadiness = .searching
    var status = "Namiř kameru na celý terč."
    var wantsSave = false
    /// Ruční posun o celé segmenty, kdyby 20 nebyla nahoře.
    private(set) var turn = 0
    private var keypoints: [SIMD2<Double>] = []
    private var edgeStreak = 0
    private var segmentStreak = 0
    private var saved = false

    /// Body desky, přes které se mapa vyhlazuje mezi snímky: bull, double a triple na každém drátu.
    private static let anchors: [SIMD2<Double>] = {
        var points: [SIMD2<Double>] = [.zero]
        for index in 0..<20 {
            let angle = (-90 + 18 * Double(index) - 9) * .pi / 180
            points.append(SIMD2(cos(angle), sin(angle)))
            points.append(SIMD2(cos(angle), sin(angle)) * 0.6)
        }
        return points
    }()

    var hasMap: Bool { calibration.homography != nil && readiness == .aligned }

    /// Body desky pro porovnání dvou map.
    static var boardAnchors: [SIMD2<Double>] { anchors }

    mutating func reset() { self = BoardTrack() }

    mutating func markSaved() {
        saved = true
        wantsSave = false
        if readiness == .aligned { status = "Terč je nastavený. Telefon už nepřemisťuj." }
    }

    /// Otočí čísla o jeden segment. Mapa zůstane, jen se přejmenují pole.
    mutating func rotate(by steps: Int) {
        turn = (turn + steps + 20) % 20
        saved = false
        refit()
        if readiness == .aligned { wantsSave = true }
    }

    mutating func ingest(_ solution: BoardSolution?) {
        if let solution {
            edgeStreak = min(edgeStreak + 1, 12)
            rim = solution.rim
        } else {
            edgeStreak = max(0, edgeStreak - 1)
        }

        if let matrix = solution?.calibration?.homography {
            let next = Self.anchors.compactMap { PlaneFit.project(matrix, $0) }
            if next.count == Self.anchors.count {
                if keypoints.count == next.count, Self.deviation(keypoints, next) < 0.03 {
                    let gain = segmentStreak < 3 ? 0.5 : 0.25
                    keypoints = zip(keypoints, next).map { $0 + ($1 - $0) * gain }
                    segmentStreak = min(segmentStreak + 1, 12)
                } else {
                    keypoints = next
                    segmentStreak = 1
                    saved = false
                }
                calibration.previewAspect = solution?.calibration?.previewAspect ?? calibration.previewAspect
                refit()
            }
        } else {
            segmentStreak = max(0, segmentStreak - 1)
        }

        if segmentStreak >= 3 {
            readiness = .aligned
        } else if edgeStreak >= 2 {
            readiness = .edge
        } else if edgeStreak == 0, segmentStreak == 0 {
            readiness = .searching
        }

        switch readiness {
        case .searching:
            status = "Namiř kameru na celý terč."
        case .edge:
            status = "Terč vidím. Hledám hranice segmentů."
        case .aligned:
            if !saved, segmentStreak >= 8 { wantsSave = true }
            status = saved ? "Terč je nastavený. Telefon už nepřemisťuj." : "Mapa sedí na drátech. Můžeš uložit."
        }
    }

    private mutating func refit() {
        guard keypoints.count == Self.anchors.count,
              var matrix = PlaneFit.homography(board: Self.anchors, image: keypoints) else { return }
        if turn != 0 {
            let angle = Double(turn) * 18 * .pi / 180
            matrix = PlaneFit.multiply(matrix, [cos(angle), -sin(angle), 0, sin(angle), cos(angle), 0, 0, 0, 1])
        }
        if let next = BoardCalibration(homography: matrix, previewAspect: calibration.previewAspect) {
            calibration = next.sanitized()
        }
    }

    private static func deviation(_ lhs: [SIMD2<Double>], _ rhs: [SIMD2<Double>]) -> Double {
        zip(lhs, rhs).reduce(0) { $0 + simd_distance($1.0, $1.1) } / Double(max(lhs.count, 1))
    }
}

struct CalibrationGauge: Equatable, Identifiable {
    var id: String { title }
    var title: String
    /// 0…1
    var value: Double
    var hint: String
    var isGood: Bool { value >= 0.7 }
}

/// Navádění při kalibraci: jak velký je terč ve snímku, jestli je uprostřed a jestli telefon míří čelně.
enum CalibrationGuide {
    static func gauges(for track: BoardTrack) -> [CalibrationGauge] {
        let calibration = track.calibration
        let aspect = max(calibration.previewAspect, 0.01)
        var center: NormPoint?
        var radius = 0.0
        if track.readiness == .aligned {
            center = calibration.center
            radius = calibration.radius
        } else if track.readiness == .edge, track.rim.count > 8 {
            let mean = NormPoint(
                x: track.rim.map(\.x).reduce(0, +) / Double(track.rim.count),
                y: track.rim.map(\.y).reduce(0, +) / Double(track.rim.count)
            )
            center = mean
            radius = track.rim.map { hypot($0.x - mean.x, ($0.y - mean.y) / aspect) }.reduce(0, +) / Double(track.rim.count)
        }
        guard let center else {
            return [
                CalibrationGauge(title: "Rámeček", value: 0, hint: "Hledám terč"),
                CalibrationGauge(title: "Střed", value: 0, hint: "Hledám terč"),
                CalibrationGauge(title: "Úhel", value: 0, hint: "Hledám terč")
            ]
        }

        let fill = radius * 1.25 * 2
        let frame = clamp(1 - abs(fill - 0.9) / 0.45)
        let frameHint = fill < 0.72 ? "Přibliž" : fill > 1.05 ? "Oddal" : "Vypadá dobře"

        let dx = center.x - 0.5
        let dy = (center.y - 0.5) / aspect
        let middle = clamp(1 - hypot(dx, dy) / 0.3)
        let middleHint: String
        if middle >= 0.8 {
            middleHint = "Vypadá dobře"
        } else if abs(dx) >= abs(dy) {
            middleHint = dx < 0 ? "Namiř doleva" : "Namiř doprava"
        } else {
            middleHint = dy < 0 ? "Namiř výš" : "Namiř níž"
        }

        guard track.readiness == .aligned else {
            return [
                CalibrationGauge(title: "Rámeček", value: frame, hint: frameHint),
                CalibrationGauge(title: "Střed", value: middle, hint: middleHint),
                CalibrationGauge(title: "Úhel", value: 0, hint: "Čtu segmenty")
            ]
        }
        let rotation = BoardVision.wrap(calibration.rotationDegrees - Double(track.turn) * 18)
        let tilt = calibration.tiltRatio
        let turnScore = clamp(1 - abs(rotation) / 15)
        let tiltScore = clamp((tilt - 0.6) / 0.35)
        let angleHint: String
        if abs(rotation) > 3, turnScore <= tiltScore {
            angleHint = rotation > 0 ? "Otoč doprava" : "Otoč doleva"
        } else if tilt < 0.9 {
            angleHint = "Postav čelněji"
        } else {
            angleHint = "Vypadá dobře"
        }
        return [
            CalibrationGauge(title: "Rámeček", value: frame, hint: frameHint),
            CalibrationGauge(title: "Střed", value: middle, hint: middleHint),
            CalibrationGauge(title: "Úhel", value: min(turnScore, tiltScore), hint: angleHint)
        ]
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

/// Šipky trčí z terče kolmo. V obraze tak všechny míří k jednomu úběžníku kolmice na terč a hrot je konec blíž k němu.
enum DartAxis {
    /// Ohnisko širokého objektivu iPhonu v jednotkách delší strany obrazu.
    static let focal = 0.73

    /// Úběžník kolmice na terč v obrazu kamery (0…1). Nil, když je telefon skoro přesně čelně.
    static func vanishingPoint(camera: [Double], aspect: Double, zoom: Double = 1) -> NormPoint? {
        guard camera.count == 9, aspect > 0 else { return nil }
        let long = max(aspect, 1)
        let sx = aspect / long, sy = 1 / long
        let toCentered = [sx, 0, -0.5 * sx, 0, sy, -0.5 * sy, 0, 0, 1]
        let m = PlaneFit.multiply(toCentered, camera)
        let f = focal * max(1, zoom)
        func ray(_ column: Int) -> SIMD3<Double> {
            simd_normalize(SIMD3(m[column] / f, m[3 + column] / f, m[6 + column]))
        }
        let normal = simd_cross(ray(0), ray(1))
        guard abs(normal.z) > 1e-6 else { return nil }
        let x = f * normal.x / normal.z
        let y = f * normal.y / normal.z
        guard x.isFinite, y.isFinite, hypot(x, y) < 50 else { return nil }
        return NormPoint(x: x / sx + 0.5, y: y / sy + 0.5)
    }
}

enum DartBlobs {
    struct Tip: Equatable {
        var x: Double
        var y: Double
    }

    /// Typický posun jasu proti referenci. Odečte se, aby změna světla nebo expozice nevypadala jako šipka.
    static func shift(_ current: [UInt8], _ reference: [UInt8], region: [Bool]? = nil) -> Int {
        guard current.count == reference.count, !current.isEmpty else { return 0 }
        var histogram = [Int](repeating: 0, count: 511)
        var total = 0
        for index in current.indices where region?[index] ?? true {
            histogram[Int(current[index]) - Int(reference[index]) + 255] += 1
            total += 1
        }
        var seen = 0
        for (value, amount) in histogram.enumerated() {
            seen += amount
            if seen * 2 >= total { return value - 255 }
        }
        return 0
    }

    static func changedCount(_ current: [UInt8], _ reference: [UInt8], threshold: UInt8 = 32, region: [Bool]? = nil) -> Int {
        guard current.count == reference.count, region.map({ $0.count == current.count }) ?? true else { return Int.max }
        let offset = shift(current, reference, region: region)
        var count = 0
        for index in current.indices where region?[index] ?? true {
            if abs(Int(current[index]) - Int(reference[index]) - offset) >= Int(threshold) { count += 1 }
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
        maxCells: Int = 180,
        region: [Bool]? = nil,
        vanish: NormPoint? = nil
    ) -> [Tip] {
        guard width > 1, height > 1, current.count == width * height, reference.count == current.count else { return [] }
        guard region.map({ $0.count == current.count }) ?? true else { return [] }
        let offset = shift(current, reference, region: region)
        var changed = Array(repeating: false, count: current.count)
        for index in current.indices where region?[index] ?? true {
            changed[index] = abs(Int(current[index]) - Int(reference[index]) - offset) >= Int(threshold)
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
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let next = ny * width + nx
                        guard changed[next], !seen[next] else { continue }
                        seen[next] = true
                        stack.append(next)
                    }
                }
            }
            guard (minCells...maxCells).contains(cells.count) else { continue }
            let minX = cells.map(\.0).min() ?? 0
            let maxX = cells.map(\.0).max() ?? 0
            let minY = cells.map(\.1).min() ?? 0
            let maxY = cells.map(\.1).max() ?? 0
            if maxX - minX > width * 2 / 5, maxY - minY > height * 2 / 5 { continue }
            if let vanish {
                let centroid = cells.reduce(SIMD2<Double>.zero) { $0 + SIMD2(Double($1.0) + 0.5, Double($1.1) + 0.5) } / Double(cells.count)
                let target = SIMD2(vanish.x * Double(width), vanish.y * Double(height))
                let toward = target - centroid
                if simd_length(toward) > 2 {
                    let direction = simd_normalize(toward)
                    let reach = cells.map { simd_dot(SIMD2(Double($0.0) + 0.5, Double($0.1) + 0.5) - centroid, direction) }.max() ?? 0
                    let front = cells.filter { simd_dot(SIMD2(Double($0.0) + 0.5, Double($0.1) + 0.5) - centroid, direction) >= reach - 1.5 }
                    let tip = front.reduce(SIMD2<Double>.zero) { $0 + SIMD2(Double($1.0) + 0.5, Double($1.1) + 0.5) } / Double(max(front.count, 1))
                    found.append(Tip(x: tip.x / Double(width), y: tip.y / Double(height)))
                    continue
                }
            }
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
/// Velká změna (ruka, vytahování šipek, člověk před terčem) se nepočítá. Po ní si vezme nový prázdný terč.
struct DartWatch {
    private(set) var phaseIsSettling = true
    private(set) var disturbed = false
    private(set) var known: [NormPoint] = []
    private var reference: [UInt8]?
    private var previous: [UInt8]?
    private var calm = 0
    private var pending: [(x: Double, y: Double, streak: Int)] = []
    private var latched: NormPoint?
    private var suppressed: [(point: NormPoint, life: Int)] = []
    private var gridWidth = 0
    private var gridHeight = 0

    /// Nic se neděje: žádná šipka nečeká na potvrzení a terč je volný.
    var isIdle: Bool { !phaseIsSettling && !disturbed && pending.isEmpty && latched == nil }

    var status: String {
        if disturbed { return "Čekám, až bude terč volný." }
        if phaseIsSettling { return "Drž telefon v klidu. Beru si prázdný terč." }
        return known.isEmpty ? "Házej. Šipka se zapíše sama." : "Čekám na další šipku."
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
        disturbed = false
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
        region: [Bool]? = nil,
        vanish: NormPoint? = nil,
        accept: (NormPoint) -> Bool
    ) -> NormPoint? {
        guard width > 1, height > 1, luma.count == width * height else { return nil }
        let region = region.flatMap { $0.count == luma.count ? $0 : nil }
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
        let cells = region?.reduce(0) { $1 ? $0 + 1 : $0 } ?? luma.count
        if let previous, previous.count == luma.count {
            calm = DartBlobs.changedCount(luma, previous, threshold: 24, region: region) < max(12, cells / 120) ? calm + 1 : 0
        }
        previous = luma
        guard latched == nil else { return nil }

        guard let reference else {
            phaseIsSettling = true
            if calm >= 3 {
                reference = luma
                phaseIsSettling = false
            }
            return nil
        }
        phaseIsSettling = false

        let moved = DartBlobs.changedCount(luma, reference, threshold: 24, region: region)
        if moved > max(60, cells / 12) {
            disturbed = true
            pending.removeAll()
            return nil
        }
        if disturbed {
            guard calm >= 3 else { return nil }
            self.reference = luma
            disturbed = false
            pending.removeAll()
            return nil
        }
        guard known.count < 3 else { return nil }

        let bufferCenter = frame.bufferPoint(center)
        let tips = DartBlobs.tips(
            current: luma, reference: reference, width: width, height: height, center: bufferCenter,
            threshold: 24, minCells: max(4, cells / 2500), maxCells: max(180, cells / 15), region: region, vanish: vanish
        )
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
        hypot(lhs.x - rhs.x, lhs.y - rhs.y) < 0.03
    }
}
