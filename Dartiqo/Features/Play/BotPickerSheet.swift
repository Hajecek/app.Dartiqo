import SwiftUI

/// Výběr úrovně bota s orientačními statistikami.
struct BotPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var initialLevel: Int
    var title: String = "Nastavení bota"
    var confirmTitle: String = "Potvrdit"
    var onConfirm: (Int) -> Void

    @State private var level: Int
    @State private var appeared = false

    init(initialLevel: Int = 3, title: String = "Nastavení bota", confirmTitle: String = "Potvrdit", onConfirm: @escaping (Int) -> Void) {
        self.initialLevel = initialLevel
        self.title = title
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        _level = State(initialValue: min(10, max(1, initialLevel)))
    }

    private var info: BotLevel { BotLevel.get(level) }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.32) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    levelBlock
                    statsCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                confirmBar
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(motion) { appeared = true }
        }
        .sensoryFeedback(.selection, trigger: level)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Avatar(name: info.persona, bot: true, size: 112, asset: info.photo)
                .id(info.photo)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
                .opacity(appeared || reduceMotion ? 1 : 0)
                .shadow(color: Theme.positive.opacity(0.28), radius: 18, y: 8)
                .animation(motion, value: info.photo)

            VStack(spacing: 4) {
                Text(info.persona)
                    .font(.title2.bold())
                    .contentTransition(.opacity)
                Text("„\(info.nickname)“ · \(info.name)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .multilineTextAlignment(.center)
            .animation(motion, value: level)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var levelBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Úroveň a statistiky", systemImage: "cpu")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack {
                Text("Úroveň obtížnosti")
                    .font(.body.weight(.semibold))
                Spacer()
                Text("Lv. \(level)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.positive, in: Capsule())
                    .contentTransition(.numericText(value: Double(level)))
            }

            VStack(spacing: 8) {
                Slider(value: Binding(
                    get: { Double(level) },
                    set: { value in
                        withAnimation(motion) { level = Int(value.rounded()) }
                    }
                ), in: 1...10, step: 1)
                .tint(Theme.action)
                .accessibilityLabel("Úroveň bota")
                .accessibilityValue("\(level), \(info.persona), \(info.name)")

                HStack {
                    Text("1")
                    Spacer()
                    Text("5")
                    Spacer()
                    Text("10")
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Theme.action)
                }
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private var statsCard: some View {
        VStack(spacing: 0) {
            statRow(
                title: "Průměr 3 šipek",
                value: info.averageText,
                hint: "Orientační rozsah průměru v X01 na této úrovni."
            )
            Divider().padding(.leading, 16)
            statRow(
                title: "Tempo odhozu",
                value: info.throwTempoText,
                hint: "Jak rychle bot hází šipky mezi sebou při svém tahu."
            )
            Divider().padding(.leading, 16)
            statRow(
                title: "Úspěšnost zavření",
                value: info.checkoutText,
                hint: "Orientační šance, že bot zavře, když má checkout."
            )
            Divider().padding(.leading, 16)
            statRow(
                title: "180 na leg",
                value: info.maxVisitText,
                hint: "Orientační počet maxim na leg — u průměrného PDC profíka kolem 0,3."
            )
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .animation(motion, value: level)
    }

    private func statRow(title: String, value: String, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "questionmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.action.opacity(0.85))
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityHint(hint)
            Spacer(minLength: 8)
            Text(value)
                .font(.body.weight(.bold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(hint)")
    }

    private var confirmBar: some View {
        GlassEffectContainer(spacing: 10) {
            Button {
                onConfirm(level)
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
