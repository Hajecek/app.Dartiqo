import SwiftUI

/// Velký portrét bota — fotka v zaobleném rámu, ne oříznutá do drobného kolečka.
struct BotPortrait: View {
    var level: Int
    var size: CGFloat = 96
    var selected = false
    var showsLevelBadge = true

    private var info: BotLevel { BotLevel.get(level) }
    private var corner: CGFloat { max(14, size * 0.22) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(info.photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, .clear, Color.black.opacity(0.35)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(
                            selected ? Theme.brand : Color.white.opacity(0.14),
                            lineWidth: selected ? 2.5 : 1
                        )
                )
                .shadow(color: selected ? Theme.brand.opacity(0.35) : .black.opacity(0.25), radius: selected ? 12 : 6, y: 4)

            if showsLevelBadge {
                Text("\(info.id)")
                    .font(.system(size: max(11, size * 0.16), weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, max(6, size * 0.08))
                    .padding(.vertical, max(3, size * 0.04))
                    .background(Theme.brand, in: Capsule())
                    .offset(x: 4, y: 4)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Výběr bota galerií portrétů — bez slideru.
struct BotPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var initialLevel: Int
    var title: String = "Vyber soupeře"
    var confirmTitle: String = "Potvrdit"
    var adaptiveEnabled: Bool
    var suggestedLevel: Int
    var initialStyle: BotPlayingStyle
    var initialAdaptive: Bool
    var onConfirm: (BotChoice) -> Void

    @State private var level: Int
    @State private var style: BotPlayingStyle
    @State private var adaptive: Bool
    @State private var appeared = false

    init(
        initialLevel: Int = 3,
        title: String = "Vyber soupeře",
        confirmTitle: String = "Potvrdit",
        adaptiveEnabled: Bool = true,
        suggestedLevel: Int = 4,
        initialStyle: BotPlayingStyle = .balanced,
        initialAdaptive: Bool = false,
        onConfirm: @escaping (BotChoice) -> Void
    ) {
        self.initialLevel = initialLevel
        self.title = title
        self.confirmTitle = confirmTitle
        self.adaptiveEnabled = adaptiveEnabled
        self.suggestedLevel = min(BotDifficulty.count, max(1, suggestedLevel))
        self.initialStyle = initialStyle
        self.initialAdaptive = initialAdaptive && adaptiveEnabled
        self.onConfirm = onConfirm
        _level = State(initialValue: min(BotDifficulty.count, max(1, initialLevel)))
        _style = State(initialValue: initialStyle)
        _adaptive = State(initialValue: initialAdaptive && adaptiveEnabled)
    }

    private var info: BotLevel { BotLevel.get(level) }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.28) }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    gallery
                    statsRow
                    stylePicker
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .padding(.bottom, 100)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { confirmBar }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(motion) { appeared = true }
        }
        .sensoryFeedback(.selection, trigger: level)
        .sensoryFeedback(.selection, trigger: style)
        .sensoryFeedback(.selection, trigger: adaptive)
        .animation(motion, value: level)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            BotPortrait(level: adaptive ? suggestedLevel : level, size: 168, selected: true, showsLevelBadge: true)
                .id(adaptive ? "adaptive-\(suggestedLevel)" : info.photo)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                .opacity(appeared || reduceMotion ? 1 : 0)

            VStack(spacing: 5) {
                Text(adaptive ? "Adaptive AI" : info.persona)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                Text(adaptive ? "Podle posledních legů" : "„\(info.nickname)“")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.action)
                Text(adaptive ? BotLevel.get(suggestedLevel).name : info.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Úroveň 1–20")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if adaptiveEnabled {
                Button {
                    withAnimation(motion) { adaptive = true }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.and.arrow.left.and.arrow.right")
                            .font(.subheadline.weight(.bold))
                            .frame(width: 36, height: 36)
                            .background(Theme.brand.opacity(adaptive ? 0.22 : 0.1), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adaptive AI")
                                .font(.subheadline.weight(.bold))
                            Text("Teď asi úroveň \(suggestedLevel). Mezi zápasy se přepočítá.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                        if adaptive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.brand)
                        }
                    }
                    .padding(10)
                    .background(adaptive ? Theme.brand.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Adaptive AI, navrhovaná úroveň \(suggestedLevel)")
                .accessibilityAddTraits(adaptive ? .isSelected : [])
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(BotLevel.all) { bot in
                    Button {
                        withAnimation(motion) {
                            adaptive = false
                            level = bot.id
                        }
                    } label: {
                        VStack(spacing: 6) {
                            BotPortrait(
                                level: bot.id,
                                size: 58,
                                selected: !adaptive && bot.id == level,
                                showsLevelBadge: false
                            )
                            Text("Lv \(bot.id)")
                                .font(.caption2.weight(.heavy).monospacedDigit())
                                .foregroundStyle(!adaptive && bot.id == level ? Theme.brand : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(bot.persona), úroveň \(bot.id)")
                    .accessibilityAddTraits(!adaptive && bot.id == level ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            statChip("Průměr", shown.averageText)
            statChip("Double", shown.checkoutText)
            statChip("Tempo", shown.throwTempoLabel)
        }
    }

    private var shown: BotLevel { adaptive ? BotLevel.get(suggestedLevel) : info }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Herní styl")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(BotPlayingStyle.allCases) { item in
                    Button {
                        withAnimation(motion) { style = item }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(style == item ? Theme.brand : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(style == item ? Theme.brand.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(style == item ? .isSelected : [])
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func statChip(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private var confirmBar: some View {
        GlassEffectContainer(spacing: 10) {
            Button {
                onConfirm(BotChoice(level: adaptive ? suggestedLevel : level, style: style, adaptive: adaptive))
                dismiss()
            } label: {
                Text(confirmTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Theme.brand).interactive(), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
}

#if DEBUG
#Preview {
    BotPickerSheet(initialLevel: 5, onConfirm: { _ in })
        .preferredColorScheme(.dark)
}
#endif
