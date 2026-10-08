import SwiftUI
import UIKit

/// SF Rounded. Velikosti drží Dynamic Type tam, kde jde o text rozhraní.
enum AppFont {
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func title(_ size: CGFloat = 22, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func body(_ size: CGFloat = 17, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func caption(_ size: CGFloat = 13, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static var score: Font { .system(size: 56, weight: .bold, design: .rounded) }
}

/// Dartiqo — značková žlutá #FEFC03 a černá, zelená jen pro úspěch.
/// Pozadí jsou systémová, aby seděl světlý i tmavý režim, zvýšený kontrast a materiály.
enum Theme {
    /// Značková žlutá #FEFC03.
    static let brand = Color(red: 254 / 255, green: 252 / 255, blue: 3 / 255)
    static let brandBlack = Color.black

    /// Text a ikony. Žlutá na bílém pozadí není čitelná, proto ve světlém režimu černá.
    static let accent = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 254 / 255, green: 252 / 255, blue: 3 / 255, alpha: 1)
            : .black
    })
    /// Výplň tlačítek a zvýraznění.
    static let accentFill = brand
    /// Text na `accentFill`.
    static let onAccent = Color.black
    /// Úspěch, výhra, průběh. Nezávislá na akcentu, aby barva nebyla jediný signál u ikon s textem.
    static let positive = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.85, blue: 0.52, alpha: 1)   // #4DD984
            : UIColor(red: 0.05, green: 0.48, blue: 0.28, alpha: 1)   // #0D7A47
    })

    static let background = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let stroke = Color(uiColor: .separator).opacity(0.35)
    /// Tmavé plátno kamery. Není to barva textu.
    static let ink = Color.black

    static let action = accent
    /// Barva hráče podle pořadí v zápase. Všechny jsou světlé, text na nich je černý.
    static let playerColors: [Color] = [
        brand,
        Color(red: 0.35, green: 0.78, blue: 1),
        Color(red: 1, green: 0.55, blue: 0.25),
        Color(red: 0.95, green: 0.45, blue: 0.85)
    ]
    static func playerColor(_ index: Int) -> Color { playerColors[((index % playerColors.count) + playerColors.count) % playerColors.count] }
    static let mint = positive
    static let volt = positive

    static let heroWash = LinearGradient(
        colors: [Color(white: 0.14), .black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(Theme.onAccent)
            .background(Theme.accentFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct Surface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.5)
            )
    }
}

extension View {
    func surface() -> some View { modifier(Surface()) }
    func screen() -> some View { frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.background) }
}

struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.title.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Theme.positive)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }
}

struct Avatar: View {
    var name: String
    var bot = false
    var size: CGFloat = 44
    var photo: Data?
    /// Obrázek z assetů, třeba portrét bota.
    var asset: String?
    var body: some View {
        ZStack {
            Circle()
                .fill(bot ? Theme.positive.opacity(0.18) : Theme.accent.opacity(0.16))
            if let asset {
                Image(asset)
                    .resizable()
                    .scaledToFill()
            } else if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if bot {
                Image(systemName: "cpu")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(Theme.positive)
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct DartboardArt: View {
    var body: some View {
        Canvas { context, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.46
            func wedge(_ inner: Double, _ outer: Double, _ a: Double, _ b: Double) -> Path {
                var p = Path()
                p.addArc(center: c, radius: r * outer, startAngle: .degrees(a), endAngle: .degrees(b), clockwise: false)
                p.addArc(center: c, radius: r * inner, startAngle: .degrees(b), endAngle: .degrees(a), clockwise: true)
                p.closeSubpath()
                return p
            }
            for i in 0..<20 {
                let a = Double(i) * 18 - 99
                let b = a + 18
                let base = i % 2 == 0 ? Color.white.opacity(0.08) : Color.white.opacity(0.18)
                let band = i % 2 == 0 ? Theme.brand : Color.white.opacity(0.85)
                context.fill(wedge(0.12, 0.93, a, b), with: .color(base))
                context.fill(wedge(0.87, 0.94, a, b), with: .color(band))
                context.fill(wedge(0.53, 0.60, a, b), with: .color(band))
                context.stroke(wedge(0.12, 0.94, a, b), with: .color(.white.opacity(0.16)), lineWidth: 0.8)
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.10, y: c.y - r * 0.10, width: r * 0.20, height: r * 0.20)), with: .color(.white.opacity(0.85)))
            context.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.04, y: c.y - r * 0.04, width: r * 0.08, height: r * 0.08)), with: .color(Theme.brand))
        }
        .accessibilityHidden(true)
    }
}

struct EmptyCard: View {
    var title: String
    var subtitle: String
    var symbol = "target"
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(subtitle))
            .frame(maxWidth: .infinity)
    }
}
