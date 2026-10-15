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
            "Peter Wrighton", "Gerwin Pryce", "Gary Andersen", "Luke Litler", "Phil Tayler",
            "Marek Holý", "Tereza Nováková", "Adam Říha", "Eva Šťastná", "Filip Král",
            "Nina Horáková", "Tomáš Sedlák", "Klára Veselá", "Ondřej Malý", "Viktor Hájek"
        ]
        let nicknames = [
            "Kapsa", "Jednička", "Pivko", "Double", "Plamen",
            "Snakebyte", "Ice-Man", "Flying Skot", "Nukeboy", "Powerhouse",
            "Klín", "Treble", "Drát", "Osmnáctka", "Ocel",
            "Sto", "Devítka", "Centrum", "Koruna", "Legenda"
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
