import Foundation
import simd

/// Barevná rovina snímku (Cb, Cr), řádek po řádku, počátek vlevo nahoře.
nonisolated struct ChromaImage: Sendable {
    var width: Int
    var height: Int
    var cb: [UInt8]
    var cr: [UInt8]
}

/// Nalezený terč v souřadnicích snímku (0…1, vlevo nahoře).
nonisolated struct BoardDetection: Sendable, Equatable {
    var center: SIMD2<Double>
    /// Střed vnějšího doublu po obvodu.
    var rim: [SIMD2<Double>]
    /// Matice 3×3 deska → snímek. Deska: vnější double má poloměr 1, 20 je nahoře, y roste dolů.
    var homography: [Double]?
    /// Průměrná odchylka bodů od mapy jako zlomek poloměru.
    var error: Double
    var boundaries: Int
}

/// Terč pozná podle barev: červeno-zelený double a triple. Střídání barev na doublu dá hranice 20 segmentů
/// a z nich perspektivní mapu, takže sedí i při šikmém pohledu.
nonisolated enum BoardDetector {
    static let sectors = [20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5]
    static let doubleMid = (1 + 0.95294) / 2
    static let tripleMid = (0.58235 + 0.62941) / 2
    static let rayCount = 720

    struct Ray: Sendable {
        var index: Int
        var triple: Double
        var double: Double
        var red: Bool
    }

    struct Scan: Sendable {
        var width: Int
        var height: Int
        var center: SIMD2<Double>
        /// Medián poloměru středu doublu v pixelech.
        var radius: Double
        var rays: [Ray]
    }

    struct Number: Sendable {
        var value: Int
        /// Střed čísla ve snímku (0…1, vlevo nahoře).
        var point: SIMD2<Double>
    }

    static func detect(_ image: ChromaImage, numbers: [Number] = []) -> BoardDetection? {
        guard let scan = scan(image) else { return nil }
        return solve(scan, numbers: numbers)
    }

    // MARK: Barvy

    /// 0 = nic, 1 = červená, 2 = zelená. Prahy jsou proti mediánu snímku, takže snesou teplé i studené světlo.
    static func tones(_ image: ChromaImage) -> [UInt8] {
        let count = image.width * image.height
        guard count > 0, image.cb.count == count, image.cr.count == count else { return [] }
        var histCb = [Int](repeating: 0, count: 256)
        var histCr = [Int](repeating: 0, count: 256)
        for index in 0..<count {
            histCb[Int(image.cb[index])] += 1
            histCr[Int(image.cr[index])] += 1
        }
        let midCb = median(histCb, total: count)
        let midCr = median(histCr, total: count)
        var histSaturation = [Int](repeating: 0, count: 182)
        for index in 0..<count {
            let db = Double(image.cb[index]) - midCb
            let dr = Double(image.cr[index]) - midCr
            histSaturation[min(181, Int((db * db + dr * dr).squareRoot()))] += 1
        }
        var strong = 0.0
        var above = 0
        for value in stride(from: 181, through: 0, by: -1) {
            above += histSaturation[value]
            if above * 1000 >= count * 4 { strong = Double(value); break }
        }
        let scale = min(1.2, max(0.3, strong / 80))
        let redShift = 26 * scale, redSaturation = 30 * scale
        let greenShift = 14 * scale, greenSaturation = 20 * scale
        var table = [UInt8](repeating: 0, count: 65_536)
        for cb in 0..<256 {
            let db = Double(cb) - midCb
            for cr in 0..<256 {
                let dr = Double(cr) - midCr
                let saturation = (db * db + dr * dr).squareRoot()
                var tone: UInt8 = 0
                if dr >= redShift, saturation >= redSaturation, db <= dr * 0.45, db >= -dr * 0.85 {
                    tone = 1
                } else if dr <= -greenShift, saturation >= greenSaturation {
                    let green = -dr
                    if db <= green * 0.6, db >= -green * 3.7 { tone = 2 }
                }
                table[cb << 8 | cr] = tone
            }
        }
        var tones = [UInt8](repeating: 0, count: count)
        for index in 0..<count {
            tones[index] = table[Int(image.cb[index]) << 8 | Int(image.cr[index])]
        }
        return tones
    }

    private static func median(_ histogram: [Int], total: Int) -> Double {
        var seen = 0
        for (value, amount) in histogram.enumerated() {
            seen += amount
            if seen * 2 >= total { return Double(value) }
        }
        return 128
    }

    // MARK: Okraj

    static func scan(_ image: ChromaImage) -> Scan? {
        let tones = tones(image)
        guard !tones.isEmpty else { return nil }
        let width = image.width
        let height = image.height
        var colored: [SIMD2<Double>] = []
        colored.reserveCapacity(tones.count / 8)
        for y in 0..<height {
            for x in 0..<width where tones[y * width + x] != 0 {
                colored.append(SIMD2(Double(x) + 0.5, Double(y) + 0.5))
            }
        }
        guard colored.count >= max(60, tones.count / 400) else { return nil }

        var center = colored.reduce(SIMD2<Double>.zero, +) / Double(colored.count)
        var radius = spread(colored, around: center)
        for _ in 0..<5 {
            let window = radius * 1.3
            let near = colored.filter { simd_distance($0, center) <= window }
            guard near.count >= 40 else { return nil }
            center = near.reduce(SIMD2<Double>.zero, +) / Double(near.count)
            radius = spread(near, around: center)
        }
        guard radius > 12 else { return nil }
        let blob = bullBlob(tones, width: width, height: height, near: center, radius: radius)
        center = blob ?? bull(colored, near: center, radius: radius) ?? center

        guard var rays = cast(tones, width: width, height: height, from: center, reach: radius * 2.2) else { return nil }
        var mid = medianRadius(rays)
        let rim = rays.map { ray -> SIMD2<Double> in
            let angle = Double(ray.index) * 2 * .pi / Double(rayCount)
            return center + SIMD2(cos(angle), sin(angle)) * ray.double
        }
        let middle = rim.reduce(SIMD2<Double>.zero, +) / Double(rim.count)
        if blob == nil,
           let refined = bullBlob(tones, width: width, height: height, near: middle, radius: mid) ?? bull(colored, near: middle, radius: mid),
           simd_distance(refined, center) > mid * 0.015 {
            if let again = cast(tones, width: width, height: height, from: refined, reach: mid * 2.2) {
                rays = again
                center = refined
                mid = medianRadius(rays)
            }
        }
        return Scan(width: width, height: height, center: center, radius: mid, rays: rays)
    }

    /// Poloměr středu doublu z rozptylu barevných bodů (double a triple mají plochy 0,29 a 0,18).
    private static func spread(_ points: [SIMD2<Double>], around center: SIMD2<Double>) -> Double {
        guard !points.isEmpty else { return 0 }
        let squared = points.reduce(0.0) { $0 + simd_distance_squared($1, center) } / Double(points.count)
        return (squared / 0.73).squareRoot()
    }

    /// Bull je jediná barva v okolí středu. Těžiště červeného středu a zeleného kroužku je střed terče i v perspektivě.
    private static func bull(_ colored: [SIMD2<Double>], near center: SIMD2<Double>, radius: Double) -> SIMD2<Double>? {
        let reach = radius * 0.14
        let inside = colored.filter { simd_distance($0, center) <= reach }
        guard inside.count >= 6 else { return nil }
        return inside.reduce(SIMD2<Double>.zero, +) / Double(inside.count)
    }

    /// Bull jako samostatná kulatá skvrna (červený střed se zeleným kroužkem). Těžiště barev se v perspektivě posouvá, bull ne.
    private static func bullBlob(_ tones: [UInt8], width: Int, height: Int, near guess: SIMD2<Double>, radius: Double) -> SIMD2<Double>? {
        let reach = radius * 0.7
        let minX = max(0, Int(guess.x - reach)), maxX = min(width - 1, Int(guess.x + reach))
        let minY = max(0, Int(guess.y - reach)), maxY = min(height - 1, Int(guess.y + reach))
        guard minX < maxX, minY < maxY else { return nil }
        var seen = Set<Int>()
        var best: (distance: Double, center: SIMD2<Double>)?
        for y in minY...maxY {
            for x in minX...maxX {
                let start = y * width + x
                guard tones[start] != 0, !seen.contains(start) else { continue }
                var stack = [start]
                seen.insert(start)
                var sum = SIMD2<Double>.zero
                var area = 0
                var red = 0
                var low = SIMD2(Int.max, Int.max), high = SIMD2(Int.min, Int.min)
                while let index = stack.popLast() {
                    let px = index % width, py = index / width
                    sum += SIMD2(Double(px) + 0.5, Double(py) + 0.5)
                    area += 1
                    if tones[index] == 1 { red += 1 }
                    low = SIMD2(min(low.x, px), min(low.y, py))
                    high = SIMD2(max(high.x, px), max(high.y, py))
                    for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)]
                    where nx >= minX && ny >= minY && nx <= maxX && ny <= maxY {
                        let next = ny * width + nx
                        if tones[next] != 0, !seen.contains(next) {
                            seen.insert(next)
                            stack.append(next)
                        }
                    }
                }
                let size = Double(max(high.x - low.x, high.y - low.y) + 1)
                let small = Double(min(high.x - low.x, high.y - low.y) + 1)
                guard (radius * 0.07...radius * 0.4).contains(size), small >= size * 0.45 else { continue }
                guard Double(area) >= size * small * 0.35, red > 0, red < area else { continue }
                let center = sum / Double(area)
                let distance = simd_distance(center, guess)
                if best == nil || distance < best!.distance { best = (distance, center) }
            }
        }
        return best?.center
    }

    private static func medianRadius(_ rays: [Ray]) -> Double {
        let sorted = rays.map(\.double).sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    private struct Run {
        var start: Double
        var end: Double
        var red = 0
        var green = 0
        var mid: Double { (start + end) / 2 }
        var isRed: Bool { red >= green }
        var isPure: Bool { Double(max(red, green)) >= Double(red + green) * 0.7 }
    }

    /// Paprsky ze středu. Na každém hledá dvojici triple + double se správným poměrem poloměrů a tloušťkou.
    private static func cast(_ tones: [UInt8], width: Int, height: Int, from center: SIMD2<Double>, reach: Double) -> [Ray]? {
        let step = 0.5
        var found: [Ray?] = Array(repeating: nil, count: rayCount)
        for index in 0..<rayCount {
            let angle = Double(index) * 2 * .pi / Double(rayCount)
            let direction = SIMD2(cos(angle), sin(angle))
            var runs: [Run] = []
            var open: Run?
            var gap = 0
            var distance = 2.0
            while distance < reach {
                let point = center + direction * distance
                let x = Int(point.x)
                let y = Int(point.y)
                guard point.x >= 0, point.y >= 0, x < width, y < height else { break }
                let tone = tones[y * width + x]
                if tone != 0 {
                    if open == nil { open = Run(start: distance, end: distance) }
                    open?.end = distance
                    if tone == 1 { open?.red += 1 } else { open?.green += 1 }
                    gap = 0
                } else if let run = open {
                    gap += 1
                    if gap > 3 {
                        runs.append(run)
                        open = nil
                        gap = 0
                    }
                }
                distance += step
            }
            if let open { runs.append(open) }
            found[index] = pair(runs)
                .map { Ray(index: index, triple: $0.triple, double: $0.double, red: $0.red) }
        }

        let valid = found.compactMap { $0 }
        guard valid.count >= rayCount / 2 else { return nil }
        let global = medianRadius(valid)
        var kept: [Ray] = []
        for ray in valid where (global * 0.5...global * 2.0).contains(ray.double) {
            var neighbours: [Double] = []
            for offset in -6...6 where offset != 0 {
                if let other = found[(ray.index + offset + rayCount) % rayCount] { neighbours.append(other.double) }
            }
            guard neighbours.count >= 4 else { continue }
            neighbours.sort()
            let local = neighbours[neighbours.count / 2]
            if abs(ray.double / local - 1) < 0.08 { kept.append(ray) }
        }
        return kept.count >= rayCount / 2 ? kept : nil
    }

    private static func pair(_ runs: [Run]) -> (triple: Double, double: Double, red: Bool)? {
        let expected = doubleMid / tripleMid
        var best: (score: Double, triple: Double, double: Double, red: Bool)?
        for (outer, double) in runs.enumerated() where double.isPure && double.mid > 10 {
            for triple in runs[..<outer] where triple.isPure && triple.isRed == double.isRed {
                let ratio = double.mid / max(triple.mid, 0.1)
                guard (1.36...1.95).contains(ratio) else { continue }
                let thickTriple = (triple.end - triple.start + 0.5) / double.mid
                let thickDouble = (double.end - double.start + 0.5) / double.mid
                guard (0.012...0.14).contains(thickTriple), (0.012...0.14).contains(thickDouble) else { continue }
                guard triple.start > double.mid * 0.35 else { continue }
                let score = abs(log(ratio / expected)) + 3 * abs(thickTriple - 0.048) + 3 * abs(thickDouble - 0.048)
                if best == nil || score < best!.score {
                    best = (score, triple.mid, double.mid, double.isRed)
                }
            }
        }
        guard let best, best.score < 0.35 else { return nil }
        return (best.triple, best.double, best.red)
    }

    // MARK: Segmenty a mapa

    static func solve(_ scan: Scan, numbers: [Number]) -> BoardDetection {
        let width = Double(scan.width)
        let height = Double(scan.height)
        let rim = scan.rays.enumerated().compactMap { offset, ray -> SIMD2<Double>? in
            guard offset % 3 == 0 else { return nil }
            let point = scan.center + direction(ray.index) * ray.double
            return SIMD2(point.x / width, point.y / height)
        }
        var detection = BoardDetection(
            center: SIMD2(scan.center.x / width, scan.center.y / height),
            rim: rim,
            homography: nil,
            error: 1,
            boundaries: 0
        )

        let rays = scan.rays
        let count = rays.count
        var red = rays.map(\.red)
        for index in 0..<count {
            var votes = 0
            for offset in -3...3 where rays[(index + offset + count) % count].red { votes += 1 }
            red[index] = votes >= 4
        }

        struct Edge { var angle: Double; var gap: Double }
        var edges: [Edge] = []
        for index in 0..<count {
            let next = (index + 1) % count
            guard red[index] != red[next] else { continue }
            let from = Double(rays[index].index)
            var to = Double(rays[next].index)
            if to <= from { to += Double(rayCount) }
            let unit = 2 * Double.pi / Double(rayCount)
            edges.append(Edge(angle: wrap((from + to) / 2 * unit), gap: (to - from) * unit))
        }
        detection.boundaries = edges.count
        guard edges.count == 20 else { return detection }
        edges.sort { $0.angle < $1.angle }

        let widths = (0..<20).map { span(edges[$0].angle, edges[($0 + 1) % 20].angle) }
        guard widths.allSatisfy({ (6.0 * .pi / 180...34.0 * .pi / 180).contains($0) }) else { return detection }
        let middles = (0..<20).map { wrap(edges[$0].angle + widths[$0] / 2) }
        let sectorRed = middles.map { middle -> Bool in
            let nearest = rays.indices.min { lhs, rhs in
                abs(angleDelta(angle(rays[lhs].index), middle)) < abs(angleDelta(angle(rays[rhs].index), middle))
            } ?? 0
            return red[nearest]
        }
        let candidates = (0..<20).filter { sectorRed[$0] }
        guard candidates.count == 10 else { return detection }

        let up = -Double.pi / 2
        let upright = candidates.min { abs(angleDelta(middles[$0], up)) < abs(angleDelta(middles[$1], up)) } ?? 0
        func agreement(_ twenty: Int) -> Int {
            numbers.reduce(0) { total, number in
                let point = SIMD2(number.point.x * width, number.point.y * height) - scan.center
                let ratio = simd_length(point) / max(scan.radius, 1)
                guard (0.9...1.7).contains(ratio) else { return total }
                let theta = atan2(point.y, point.x)
                guard let sector = (0..<20).first(where: { span(edges[$0].angle, theta) < widths[$0] }) else { return total }
                return sectors[(sector - twenty + 20) % 20] == number.value ? total + 1 : total
            }
        }
        var twenty = upright
        if !numbers.isEmpty {
            let scored = candidates.map { ($0, agreement($0)) }
            if let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 2, best.1 > agreement(upright) { twenty = best.0 }
        }

        var board: [SIMD2<Double>] = []
        var image: [SIMD2<Double>] = []
        for (index, edge) in edges.enumerated() where edge.gap <= 6 * .pi / 180 {
            guard let radii = radii(at: edge.angle, in: rays) else { continue }
            let boardIndex = (index - twenty + 20) % 20
            let boardAngle = (-90 + 18 * Double(boardIndex) - 9) * .pi / 180
            let along = SIMD2(cos(edge.angle), sin(edge.angle))
            let across = SIMD2(cos(boardAngle), sin(boardAngle))
            board.append(across * doubleMid)
            image.append(scan.center + along * radii.double)
            board.append(across * tripleMid)
            image.append(scan.center + along * radii.triple)
        }
        guard board.count >= 24 else { return detection }
        for _ in 0..<4 {
            board.append(.zero)
            image.append(scan.center)
        }

        guard var matrix = PlaneFit.homography(board: board, image: image) else { return detection }
        var errors = zip(board, image).map { PlaneFit.distance(matrix, $0, $1) }
        let typical = errors.sorted()[errors.count / 2]
        let keep = errors.indices.filter { errors[$0] <= max(typical * 3, scan.radius * 0.01) }
        if keep.count < errors.count, keep.count >= 20,
           let refit = PlaneFit.homography(board: keep.map { board[$0] }, image: keep.map { image[$0] }) {
            matrix = refit
            errors = keep.map { PlaneFit.distance(matrix, board[$0], image[$0]) }
        }
        let rms = (errors.reduce(0) { $0 + $1 * $1 } / Double(errors.count)).squareRoot()
        detection.error = rms / max(scan.radius, 1)
        guard detection.error < 0.03 else { return detection }
        let scale: [Double] = [1 / width, 0, 0, 0, 1 / height, 0, 0, 0, 1]
        detection.homography = PlaneFit.multiply(scale, matrix)
        return detection
    }

    private static func radii(at theta: Double, in rays: [Ray]) -> (triple: Double, double: Double)? {
        var before: (Ray, Double)?
        var after: (Ray, Double)?
        for ray in rays {
            let delta = angleDelta(angle(ray.index), theta)
            if delta <= 0, delta > -5 * .pi / 180, before == nil || delta > before!.1 { before = (ray, delta) }
            if delta > 0, delta < 5 * .pi / 180, after == nil || delta < after!.1 { after = (ray, delta) }
        }
        guard let before, let after else { return nil }
        let total = after.1 - before.1
        let weight = total > 0 ? -before.1 / total : 0.5
        return (
            before.0.triple + (after.0.triple - before.0.triple) * weight,
            before.0.double + (after.0.double - before.0.double) * weight
        )
    }

    private static func angle(_ index: Int) -> Double { wrap(Double(index) * 2 * .pi / Double(rayCount)) }
    private static func direction(_ index: Int) -> SIMD2<Double> {
        let value = angle(index)
        return SIMD2(cos(value), sin(value))
    }

    static func wrap(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 2 * .pi)
        if result > .pi { result -= 2 * .pi }
        if result <= -.pi { result += 2 * .pi }
        return result
    }

    private static func angleDelta(_ value: Double, _ reference: Double) -> Double { wrap(value - reference) }

    /// Úhel od `from` po směru hodin do `to`, 0…2π.
    private static func span(_ from: Double, _ to: Double) -> Double {
        var result = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
        if result < 0 { result += 2 * .pi }
        return result
    }
}

/// Perspektivní mapa z libovolného počtu dvojic bodů (nejmenší čtverce).
nonisolated enum PlaneFit {
    static func homography(board: [SIMD2<Double>], image: [SIMD2<Double>]) -> [Double]? {
        guard board.count == image.count, board.count >= 4 else { return nil }
        let (boardNorm, boardT) = normalize(board)
        let (imageNorm, imageT) = normalize(image)
        guard let boardT, let imageT else { return nil }
        var normal = [Double](repeating: 0, count: 64)
        var rhs = [Double](repeating: 0, count: 8)
        for (source, target) in zip(boardNorm, imageNorm) {
            let x = source.x, y = source.y, u = target.x, v = target.y
            let rows: [([Double], Double)] = [
                ([x, y, 1, 0, 0, 0, -u * x, -u * y], u),
                ([0, 0, 0, x, y, 1, -v * x, -v * y], v)
            ]
            for (row, value) in rows {
                for i in 0..<8 {
                    rhs[i] += row[i] * value
                    for j in 0..<8 { normal[i * 8 + j] += row[i] * row[j] }
                }
            }
        }
        guard let h = solve(normal, rhs, size: 8) else { return nil }
        let fitted = [h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1]
        guard let imageInverse = invert(imageT) else { return nil }
        let result = multiply(imageInverse, multiply(fitted, boardT))
        guard result.allSatisfy(\.isFinite), abs(result[8]) > 1e-12 else { return nil }
        return result.map { $0 / result[8] }
    }

    static func project(_ m: [Double], _ point: SIMD2<Double>) -> SIMD2<Double>? {
        let w = m[6] * point.x + m[7] * point.y + m[8]
        guard abs(w) > 1e-10 else { return nil }
        let result = SIMD2((m[0] * point.x + m[1] * point.y + m[2]) / w, (m[3] * point.x + m[4] * point.y + m[5]) / w)
        return result.x.isFinite && result.y.isFinite ? result : nil
    }

    static func distance(_ m: [Double], _ board: SIMD2<Double>, _ image: SIMD2<Double>) -> Double {
        guard let projected = project(m, board) else { return .infinity }
        return simd_distance(projected, image)
    }

    static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var result = [Double](repeating: 0, count: 9)
        for row in 0..<3 {
            for column in 0..<3 {
                result[row * 3 + column] = a[row * 3] * b[column] + a[row * 3 + 1] * b[3 + column] + a[row * 3 + 2] * b[6 + column]
            }
        }
        return result
    }

    static func invert(_ m: [Double]) -> [Double]? {
        let a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
        let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        guard abs(det) > 1e-14, det.isFinite else { return nil }
        return [
            (e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
            (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
            (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det
        ]
    }

    private static func normalize(_ points: [SIMD2<Double>]) -> ([SIMD2<Double>], [Double]?) {
        let mean = points.reduce(SIMD2<Double>.zero, +) / Double(points.count)
        let average = points.reduce(0.0) { $0 + simd_distance($1, mean) } / Double(points.count)
        guard average > 1e-9 else { return (points, nil) }
        let s = 2.0.squareRoot() / average
        return (points.map { ($0 - mean) * s }, [s, 0, -s * mean.x, 0, s, -s * mean.y, 0, 0, 1])
    }

    private static func solve(_ matrix: [Double], _ rhs: [Double], size n: Int) -> [Double]? {
        var a = matrix
        var b = rhs
        for column in 0..<n {
            var pivot = column
            for row in (column + 1)..<n where abs(a[row * n + column]) > abs(a[pivot * n + column]) { pivot = row }
            guard abs(a[pivot * n + column]) > 1e-12 else { return nil }
            if pivot != column {
                for k in 0..<n { a.swapAt(column * n + k, pivot * n + k) }
                b.swapAt(column, pivot)
            }
            let divisor = a[column * n + column]
            for k in column..<n { a[column * n + k] /= divisor }
            b[column] /= divisor
            for row in 0..<n where row != column {
                let factor = a[row * n + column]
                guard factor != 0 else { continue }
                for k in column..<n { a[row * n + k] -= factor * a[column * n + k] }
                b[row] -= factor * b[column]
            }
        }
        return b.allSatisfy(\.isFinite) ? b : nil
    }
}
