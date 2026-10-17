import Foundation

/// Dlouhodobé cíle a rozptyl dvaceti úrovní pro 501 double out.
/// Sigma je směrodatná odchylka v souřadnicích terče (1 = poloměr bodované plochy).
/// Hodnoty se kalibrují úpravou rozptylu, nikdy úpravou už hozeného skóre.
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
        let start = levels[count - 1].doubleSigma
        let floor = 0.0045
        let t = (clamped - cap) / (1 - cap)
        let sigma = exp(log(start) * (1 - t) + log(floor) * t)
        return (sigma, sigma * 1.08)
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
        let doubles = [0.02, 0.03, 0.04, 0.06, 0.08, 0.10, 0.12, 0.15, 0.18, 0.21, 0.24, 0.27, 0.30, 0.33, 0.36, 0.39, 0.42, 0.45, 0.48, 0.52]
        // Monotónní rozptyl. Vyšší úroveň má vždy menší sigma, ať síla na T20 roste.
        let tripleSigma = [0.168, 0.150, 0.128, 0.118, 0.108, 0.088, 0.077, 0.069, 0.066, 0.055, 0.051, 0.049, 0.044, 0.040, 0.037, 0.033, 0.030, 0.028, 0.025, 0.023]
        let doubleSigma = [0.340, 0.240, 0.200, 0.165, 0.152, 0.120, 0.112, 0.092, 0.086, 0.073, 0.066, 0.059, 0.054, 0.049, 0.044, 0.041, 0.037, 0.034, 0.031, 0.027]
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
                throwSeconds: 2.5 - t * 1.85
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
