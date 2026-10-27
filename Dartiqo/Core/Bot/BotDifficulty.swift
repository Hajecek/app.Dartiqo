import Foundation

/// Dlouhodobé cíle a rozptyl dvaceti úrovní pro 501 double out.
/// Sigma je směrodatná odchylka v souřadnicích terče (1 = poloměr bodované plochy).
/// Kalibrace mění jen rozptyl, nikdy už hozené skóre. Triple odpovídá očekávanému
/// průměru při míření na T20, double samostatné úspěšnosti zásahu.
public enum BotDifficulty {
    public static let count = 20

    public struct Level: Identifiable, Equatable {
        public var id: Int { level }
        public var level: Int
        public var name: String
        public var persona: String
        public var nickname: String
        public var targetAverage: Double
        public var targetDoubleHit: Double
        /// Rozptyl při míření na triple.
        public var tripleSigma: Double
        /// Rozptyl při míření na double.
        public var doubleSigma: Double
        /// Rozptyl při míření na bull.
        public var bullSigma: Double
        public var consistency: Double
        public var intelligence: Double
        public var pressureResistance: Double
        public var throwSeconds: Double
        /// Odhad z návštěv na T20 se sdílenou formou, přepočtený na šipky v legu 501.
        public var oneEightiesPerLeg: Double

        public var singleSigma: Double { tripleSigma }
        /// Horizontální složka skórovacího rozptylu.
        public var horizontalDispersion: Double { tripleSigma }
        /// Vertikální složka je o něco větší — šipka padá.
        public var verticalDispersion: Double { tripleSigma * BotThrowModel.verticalScale }
    }

    public static let minimumAverage = 17.5
    public static let maximumAverage = 112.5
    public static let minimumCheckout = 0.02
    /// Vlastní bot může mířit na double skoro pokaždé. Tabulka úrovní končí níž.
    public static let maximumCheckout = 1.0

    /// Úroveň, jejíž kalibrovaný průměr je nastavené hodnotě nejblíž. Slouží portrétu a srovnání.
    public static func nearestLevel(forAverage average: Double) -> Int {
        Int(index(forAverage: average).rounded()) + 1
    }

    static func index(forAverage average: Double) -> Double {
        let clamped = min(maximumAverage, max(minimumAverage, average))
        return (clamped - minimumAverage) / 5
    }

    static func index(forCheckout rate: Double) -> Double {
        let values = levels.map(\.targetDoubleHit)
        let clamped = min(values[count - 1], max(values[0], rate))
        if clamped >= values[count - 1] { return Double(count - 1) }
        for i in 0..<(count - 1) {
            let lo = values[i]
            let hi = values[i + 1]
            if clamped <= hi {
                let span = hi - lo
                return Double(i) + (span == 0 ? 0 : (clamped - lo) / span)
            }
        }
        return Double(count - 1)
    }

    /// Šipky, které na leg stojí jeden očekávaný pokus na double. Změřeno simulací vlastních botů:
    /// lepší double než obvyklý k průměru šetří i nastřelovací šipky, horší stojí zhruba jen ten pokus.
    static func dartsPerDoubleAttempt(average: Double, checkout: Double) -> Double {
        checkout > checkoutRate(at: index(forAverage: average)) ? 1.25 : 1.0
    }

    /// Index skórovací přesnosti pro vlastního bota. Leg 501 má 1503 / průměr šipek.
    /// Šipky mimo double ubývají se skórováním, pokusy na double dělá úspěšnost. Lepší double proto
    /// potřebuje horší skóre, jinak by bot hrál nad nastavený průměr.
    /// Index může přesáhnout tabulku: průměr 110 s 30 % na double potřebuje skóre nad legendu.
    static func scoringIndex(forAverage average: Double, checkout: Double) -> Double {
        let average = min(maximumAverage, max(minimumAverage, average))
        let checkout = min(maximumCheckout, max(minimumCheckout, checkout))
        let weight = dartsPerDoubleAttempt(average: average, checkout: checkout)
        let need = 1503 / average - weight / checkout
        func otherDarts(_ index: Double) -> Double {
            let level = 1503 / (minimumAverage + index * 5)
            return level - weight / checkoutRate(at: index)
        }
        var lo = scoringIndexRange.lowerBound
        var hi = scoringIndexRange.upperBound
        if need >= otherDarts(lo) { return lo }
        if need <= otherDarts(hi) { return hi }
        for _ in 0..<48 {
            let mid = (lo + hi) / 2
            if otherDarts(mid) > need { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    static let scoringIndexRange = -2.0...24.0

    /// Rozptyl na triple podle indexu. Mimo tabulku pokračuje stejným poměrem jako krajní úrovně.
    static func scoringSigma(at index: Double) -> Double {
        let last = count - 1
        if index > Double(last) {
            let step = levels[last].tripleSigma / levels[last - 1].tripleSigma
            return levels[last].tripleSigma * pow(step, index - Double(last))
        }
        if index < 0 {
            let step = levels[0].tripleSigma / levels[1].tripleSigma
            return levels[0].tripleSigma * pow(step, -index)
        }
        return blend(at: index).tripleSigma
    }

    static func checkoutRate(at index: Double) -> Double {
        let last = count - 1
        if index > Double(last) {
            let step = levels[last].targetDoubleHit - levels[last - 1].targetDoubleHit
            return min(0.95, levels[last].targetDoubleHit + step * (index - Double(last)))
        }
        if index < 0 {
            let step = levels[1].targetDoubleHit - levels[0].targetDoubleHit
            return max(0.008, levels[0].targetDoubleHit + step * index)
        }
        let lo = Int(index.rounded(.down))
        let hi = min(last, lo + 1)
        let t = index - Double(lo)
        return levels[lo].targetDoubleHit * (1 - t) + levels[hi].targetDoubleHit * t
    }

    struct Blend {
        var tripleSigma: Double
        var doubleSigma: Double
        var bullSigma: Double
        var consistency: Double
        var intelligence: Double
        var pressureResistance: Double
        var throwSeconds: Double
    }

    /// Rozptyl double. Do tabulky úrovní se bere kalibrace, nad ni klesá až k téměř jistému zásahu.
    static func finishingSpread(forCheckout rate: Double) -> (doubleSigma: Double, bullSigma: Double) {
        let cap = levels[count - 1].targetDoubleHit
        let clamped = min(maximumCheckout, max(minimumCheckout, rate))
        if clamped <= cap {
            let sample = blend(at: index(forCheckout: clamped))
            return (sample.doubleSigma, sample.bullSigma)
        }
        // Změřená úspěšnost ve hře podle rozptylu na double. Nad 95 % už jde jen o drobné zúžení.
        let measured: [(rate: Double, sigma: Double)] = [
            (cap, levels[count - 1].doubleSigma),
            (0.55, 0.0290), (0.61, 0.0250), (0.70, 0.0210), (0.79, 0.0180),
            (0.86, 0.0150), (0.95, 0.0120), (0.975, 0.0100), (0.995, 0.0080), (1.0, 0.0055)
        ]
        for i in 1..<measured.count where clamped <= measured[i].rate {
            let a = measured[i - 1]
            let b = measured[i]
            let t = b.rate == a.rate ? 0 : (clamped - a.rate) / (b.rate - a.rate)
            let sigma = exp(log(a.sigma) * (1 - t) + log(b.sigma) * t)
            return (sigma, sigma * 1.08)
        }
        let last = measured[measured.count - 1].sigma
        return (last, last * 1.08)
    }

    static func blend(at index: Double) -> Blend {
        let clamped = min(Double(count - 1), max(0, index))
        let lo = Int(clamped.rounded(.down))
        let hi = min(count - 1, lo + 1)
        let t = clamped - Double(lo)
        let a = levels[lo]
        let b = levels[hi]
        func mix(_ x: Double, _ y: Double) -> Double { x * (1 - t) + y * t }
        return Blend(
            tripleSigma: mix(a.tripleSigma, b.tripleSigma),
            doubleSigma: mix(a.doubleSigma, b.doubleSigma),
            bullSigma: mix(a.bullSigma, b.bullSigma),
            consistency: mix(a.consistency, b.consistency),
            intelligence: mix(a.intelligence, b.intelligence),
            pressureResistance: mix(a.pressureResistance, b.pressureResistance),
            throwSeconds: mix(a.throwSeconds, b.throwSeconds)
        )
    }

    public static func level(_ value: Int) -> Level {
        levels[min(count - 1, max(0, value - 1))]
    }

    public static let levels: [Level] = {
        let names = [
            "Úplný nováček", "Začátečník", "Učící se hráč", "Hobby hráč", "Příležitostný hráč",
            "Mírně pokročilý", "Pokročilý amatér", "Klubový začátečník", "Klubový hráč", "Zkušený klubový hráč",
            "Silný amatér", "Ligový hráč", "Výborný ligový hráč", "Regionální špička", "Semiprofesionál",
            "Profesionální úroveň", "Velmi silný profesionál", "Světová úroveň", "Elitní profesionál", "Legenda"
        ]
        let personas = [
            "Pepa Mráz", "Jana Malá", "Franta Beran", "Lucie Dvořáková", "Honza Kos",
            "Fallon Sherrok", "Mensur Suljovicz", "Dimitri van den Berg", "Jonny Claytom", "Dave Chisnell",
            "Nathan Aspinell", "Rob Crosse", "Gerwyn Pryce", "Peter Wryght", "Gary Andersom",
            "Michael Smyth", "Luke Humphrie", "Luke Littlar", "Michael van Gerwyn", "Phil Tayler"
        ]
        let nicknames = [
            "Kapsa", "Jednička", "Pivko", "Double", "Plamen",
            "Palác", "Gentle", "Dreamaker", "Feret", "Chizy",
            "Asp", "Voltage", "Iceman", "Snakebyt", "Flying Scot",
            "Bullyboy", "Cool Hand", "Nuke", "Mighty Mik", "The Powr"
        ]
        // Úspěšnost šipky mířené na double podle reálných amatérských i PDC statistik pro daný průměr.
        let doubles = [0.025, 0.04, 0.06, 0.08, 0.10, 0.12, 0.14, 0.17, 0.20, 0.22, 0.245, 0.27, 0.295, 0.32, 0.345, 0.37, 0.395, 0.42, 0.45, 0.48]
        // Rozptyl je fit na očekávané skóre, ne na dojem. Střední sigma jinak drží šipku v dvacítce
        // (spousta S20) a bot s průměrem 57.5 hází jako 70+. Triple proto odpovídá 3-šipkovému
        // průměru při míření na T20 včetně formy návštěvy, o 2.5–5 bodů nad tabulkou (první devítka).
        // Double je samostatně fitovaný na zásah D20 se stejnou formou.
        let tripleSigma = [0.5547, 0.4119, 0.2923, 0.2132, 0.1631, 0.1347, 0.1147, 0.1015, 0.0911, 0.0820, 0.0751, 0.0685, 0.0632, 0.0581, 0.0534, 0.0487, 0.0448, 0.0411, 0.0376, 0.0344]
        let doubleSigma = [0.2993, 0.2327, 0.1836, 0.1559, 0.1345, 0.1179, 0.1051, 0.0910, 0.0807, 0.0735, 0.0666, 0.0607, 0.0559, 0.0515, 0.0475, 0.0437, 0.0410, 0.0385, 0.0359, 0.0332]
        let oneEighties = [0, 0, 0, 0.002, 0.003, 0.006, 0.011, 0.015, 0.022, 0.033, 0.049, 0.066, 0.084, 0.108, 0.134, 0.180, 0.231, 0.284, 0.352, 0.433]
        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            return Level(
                level: index + 1,
                name: names[index],
                persona: personas[index],
                nickname: nicknames[index],
                targetAverage: 17.5 + Double(index) * 5,
                targetDoubleHit: doubles[index],
                tripleSigma: tripleSigma[index],
                doubleSigma: doubleSigma[index],
                bullSigma: doubleSigma[index] * 1.08,
                consistency: 0.30 + t * 0.58,
                intelligence: 0.22 + t * 0.73,
                pressureResistance: 0.28 + t * 0.60,
                throwSeconds: 2.5 - t * 1.85,
                oneEightiesPerLeg: oneEighties[index]
            )
        }
    }()
}

enum BotThrowModel {
    static let horizontalScale = 1.0
    static let verticalScale = 1.12
    /// Podíl rozptylu, který patří chybě míření. Zbytek je vypuštění. Součet rozptylů zůstává sigma².
    static let aimShare = 0.45
}
