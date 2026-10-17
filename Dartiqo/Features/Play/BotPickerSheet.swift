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

/// Výběr soupeře: hotová úroveň, Adaptive AI, nebo vlastní průměr a double.
struct BotPickerSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case roster, adaptive, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .roster: return "Úrovně"
            case .adaptive: return "Adaptive"
            case .custom: return "Vlastní"
            }
        }
        var symbol: String {
            switch self {
            case .roster: return "person.3.fill"
            case .adaptive: return "arrow.triangle.2.circlepath"
            case .custom: return "slider.horizontal.3"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var nameFocused: Bool

    var title: String = "Vyber soupeře"
    var confirmTitle: String = "Potvrdit"
    var adaptiveEnabled: Bool
    var reading: AdaptiveReading
    var onConfirm: (BotChoice) -> Void

    @State private var mode: Mode
    @State private var level: Int
    @State private var style: BotPlayingStyle
    @State private var average: Double
    @State private var checkout: Double
    @State private var stability: Double
    @State private var nerve: Double
    @State private var tactics: Double
    @State private var customName: String
    @State private var customTouched: Bool
    @State private var appeared = false

    init(
        initial: BotChoice = BotChoice(level: 3),
        title: String = "Vyber soupeře",
        confirmTitle: String = "Potvrdit",
        adaptiveEnabled: Bool = true,
        reading: AdaptiveReading = AdaptiveReading(
            legs: 0,
            threeDartAverage: 0,
            first9Average: 0,
            checkoutPercentage: 0,
            dartsPerLeg: 0,
            stability: 0,
            recentWinRate: nil,
            recommendedLevel: AdaptiveBotEngine.fallbackLevel
        ),
        onConfirm: @escaping (BotChoice) -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.adaptiveEnabled = adaptiveEnabled
        self.reading = reading
        self.onConfirm = onConfirm
        let start: Mode = initial.isCustom ? .custom : (initial.adaptive && adaptiveEnabled ? .adaptive : .roster)
        let seed = BotDifficulty.level(initial.level)
        let played = initial.isCustom
            ? BotProfile.custom(
                average: initial.customAverage ?? seed.targetAverage,
                checkout: initial.customCheckout ?? seed.targetDoubleHit,
                style: initial.style,
                consistency: initial.customConsistency,
                pressure: initial.customPressure,
                intelligence: initial.customIntelligence
            )
            : nil
        _mode = State(initialValue: start)
        _level = State(initialValue: min(BotDifficulty.count, max(1, initial.level)))
        _style = State(initialValue: initial.style)
        _average = State(initialValue: initial.customAverage ?? seed.targetAverage)
        _checkout = State(initialValue: (initial.customCheckout ?? seed.targetDoubleHit) * 100)
        _stability = State(initialValue: (played?.consistency ?? seed.consistency) * 100)
        _nerve = State(initialValue: (played?.pressureResistance ?? seed.pressureResistance) * 100)
        _tactics = State(initialValue: (played?.checkoutIntelligence ?? seed.intelligence) * 100)
        _customName = State(initialValue: initial.customName ?? "Vlastní")
        _customTouched = State(initialValue: initial.isCustom)
    }

    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.28) }
    private var modes: [Mode] { adaptiveEnabled ? Mode.allCases : [.roster, .custom] }
    private var shownLevel: Int {
        switch mode {
        case .roster: return level
        case .adaptive: return reading.recommendedLevel
        case .custom: return BotDifficulty.nearestLevel(forAverage: average)
        }
    }
    private var shown: BotLevel { BotLevel.get(shownLevel) }
    private var averageText: String { average.formatted(.number.precision(.fractionLength(1))) }
    private var checkoutText: String { "\(Int(checkout.rounded())) %" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modeBar
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                ScrollView {
                    VStack(spacing: 16) {
                        hero
                        switch mode {
                        case .roster: roster
                        case .adaptive: adaptiveGuide
                        case .custom: customDials
                        }
                        if mode != .custom { abilityCard }
                        stylePicker
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Hotovo") { nameFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { confirmBar }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if mode == .adaptive, !adaptiveEnabled { mode = .roster }
            withAnimation(motion) { appeared = true }
        }
        .onChange(of: mode) { _, new in
            guard new == .custom, !customTouched else { return }
            let spec = BotDifficulty.level(level)
            average = spec.targetAverage
            checkout = spec.targetDoubleHit * 100
            stability = spec.consistency * 100
            nerve = spec.pressureResistance * 100
            tactics = spec.intelligence * 100
        }
        .sensoryFeedback(.selection, trigger: mode)
        .sensoryFeedback(.selection, trigger: level)
        .sensoryFeedback(.selection, trigger: style)
        .animation(motion, value: level)
        .animation(motion, value: mode)
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(modes) { item in
                Button {
                    withAnimation(motion) { mode = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.subheadline.weight(.bold))
                        Text(item.title)
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(mode == item ? Color.black : .primary)
                    .background(
                        mode == item ? Theme.brand : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(cardStroke(18))
    }

    private var hero: some View {
        VStack(spacing: 12) {
            BotPortrait(level: shownLevel, size: 148, selected: true)
                .id(shown.photo)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
                .opacity(appeared || reduceMotion ? 1 : 0)

            VStack(spacing: 5) {
                heroTitle
                Text(heroSubtitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.action)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                Text(shown.name)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var heroTitle: some View {
        if mode == .custom {
            TextField("Jméno", text: $customName)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .focused($nameFocused)
                .submitLabel(.done)
                .onChange(of: customName) { _, new in
                    if new.count > 24 { customName = String(new.prefix(24)) }
                }
                .accessibilityLabel("Jméno vlastního bota")
        } else {
            Text(mode == .adaptive ? "Adaptive AI" : shown.persona)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
        }
    }

    private var heroSubtitle: String {
        switch mode {
        case .roster:
            return "„\(shown.nickname)“"
        case .adaptive:
            return "Úroveň \(shownLevel) · \(shown.persona)"
        case .custom:
            return "Blízko úrovni \(shownLevel) · \(shown.persona)"
        }
    }

    private var roster: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Úroveň \(level) z 20")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                HStack(spacing: 8) {
                    stepButton("chevron.left", enabled: level > 1) { level = max(1, level - 1) }
                    stepButton("chevron.right", enabled: level < BotDifficulty.count) { level = min(BotDifficulty.count, level + 1) }
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(BotLevel.all) { bot in
                            Button {
                                withAnimation(motion) { level = bot.id }
                            } label: {
                                VStack(spacing: 6) {
                                    BotPortrait(level: bot.id, size: 72, selected: bot.id == level, showsLevelBadge: false)
                                    Text("\(bot.id)")
                                        .font(.caption.weight(.heavy).monospacedDigit())
                                        .foregroundStyle(bot.id == level ? Theme.accent : .secondary)
                                }
                                .frame(width: 76)
                            }
                            .buttonStyle(.plain)
                            .id(bot.id)
                            .accessibilityLabel("\(bot.persona), úroveň \(bot.id)")
                            .accessibilityAddTraits(bot.id == level ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onAppear { proxy.scrollTo(level, anchor: .center) }
                .onChange(of: level) { _, new in
                    withAnimation(motion) { proxy.scrollTo(new, anchor: .center) }
                }
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke(22))
    }

    private var adaptiveGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Jak se úroveň vybírá")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            VStack(alignment: .leading, spacing: 12) {
                guideRow("list.bullet", "Bere až 20 posledních dokončených legů ve hře X01.")
                guideRow("chart.bar.fill", "Základem je tříšipkový průměr. Když je prvních devět šipek aspoň o 10 bodů výš, čtvrtina úrovně vychází z nich.")
                guideRow("arrow.up.arrow.down", "U vyrovnané série přidá úroveň od 60 % výher a ubere ji do 35 % výher v těch samých legách.")
                guideRow("waveform.path", "Rozptyl průměrů nad 18 bodů ten posun vynechá, ať jeden rozkolísaný večer neposadí mnohem silnějšího soupeře.")
                guideRow("lock.fill", "Úroveň se určí před zápasem a během něj zůstane stejná. Příště se spočítá znovu.")
            }
            readingSummary
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke(22))
    }

    @ViewBuilder
    private var readingSummary: some View {
        if reading.legs >= 3 {
            VStack(alignment: .leading, spacing: 8) {
                Text("Z tvých posledních \(reading.legs) legů")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    statChip("Průměr", reading.threeDartAverage.formatted(.number.precision(.fractionLength(1))))
                    statChip("Zavírání", "\(Int(reading.checkoutPercentage.rounded())) %")
                    statChip("Úroveň", "\(reading.recommendedLevel)")
                }
                if let rate = reading.recentWinRate {
                    Text("Výhry v těch legách \(Int((rate * 100).rounded())) %.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Dokončené X01 legy: \(reading.legs). Od tří legů se úroveň odvíjí od tvého průměru. Do té doby nastoupí úroveň \(AdaptiveBotEngine.fallbackLevel).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func guideRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.action)
                .frame(width: 22, height: 22)
                .background(Theme.brand.opacity(0.14), in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var customDials: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Přesné nastavení")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            dial(
                title: "Průměr",
                value: averageText,
                caption: "Cíl na tři šipky. Jednotlivá kola se od něj odchýlí.",
                range: "\(Int(BotDifficulty.minimumAverage))–\(Int(BotDifficulty.maximumAverage))",
                canDecrease: average > BotDifficulty.minimumAverage,
                canIncrease: average < BotDifficulty.maximumAverage,
                decrease: { touchCustom(); average = max(BotDifficulty.minimumAverage, average - 0.5) },
                increase: { touchCustom(); average = min(BotDifficulty.maximumAverage, average + 0.5) }
            ) {
                Slider(value: $average, in: BotDifficulty.minimumAverage...BotDifficulty.maximumAverage, step: 0.5) { editing in
                    if editing { touchCustom() }
                }
                .tint(Theme.brand)
                .accessibilityLabel("Průměr")
                .accessibilityValue(averageText)
            }
            dial(
                title: "Zavírání",
                value: checkoutText,
                caption: "Úspěšnost double, na který bot míří. Sto procent skoro nezaváhá.",
                range: "2–100 %",
                canDecrease: checkout > 2,
                canIncrease: checkout < 100,
                decrease: { touchCustom(); checkout = max(2, checkout - 1) },
                increase: { touchCustom(); checkout = min(100, checkout + 1) }
            ) {
                Slider(value: $checkout, in: 2...100, step: 1) { editing in
                    if editing { touchCustom() }
                }
                .tint(Theme.brand)
                .accessibilityLabel("Úspěšnost double")
                .accessibilityValue(checkoutText)
            }
            percentSlider("Stabilita", value: $stability, caption: "Jak moc se po sobě jdoucí kola podobají.")
            percentSlider("Nervy", value: $nerve, caption: "Jak drží rozptyl, když je zavření blízko.")
            percentSlider("Taktika", value: $tactics, caption: "Jak čistě si staví zavření a vybírá double.")
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke(22))
    }

    private func touchCustom() {
        customTouched = true
    }

    private func dial<Control: View>(
        title: String,
        value: String,
        caption: String,
        range: String,
        canDecrease: Bool,
        canIncrease: Bool,
        decrease: @escaping () -> Void,
        increase: @escaping () -> Void,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            HStack(spacing: 10) {
                nudge("minus", enabled: canDecrease, action: decrease)
                control()
                nudge("plus", enabled: canIncrease, action: increase)
            }
            HStack {
                Text(caption)
                Spacer(minLength: 8)
                Text(range)
                    .monospacedDigit()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func nudge(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(enabled ? .primary : .tertiary)
                .background(Color.primary.opacity(enabled ? 0.06 : 0.03), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private var abilityCard: some View {
        let spec = BotDifficulty.level(shownLevel)
        let span = BotDifficulty.maximumAverage - BotDifficulty.minimumAverage
        return VStack(alignment: .leading, spacing: 12) {
            Text("Schopnosti")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            meter("Skóre", fraction: (spec.targetAverage - BotDifficulty.minimumAverage) / span, value: spec.targetAverage.formatted(.number.precision(.fractionLength(1))))
            meter("Zavírání", fraction: spec.targetDoubleHit, value: "\(Int((spec.targetDoubleHit * 100).rounded())) %")
            meter("Stabilita", fraction: spec.consistency, value: "\(Int((spec.consistency * 100).rounded()))")
            meter("Nervy", fraction: spec.pressureResistance, value: "\(Int((spec.pressureResistance * 100).rounded()))")
            meter("Taktika", fraction: spec.intelligence, value: "\(Int((spec.intelligence * 100).rounded()))")
            Text("Vlastní bot umí tyhle osy nastavit zvlášť. Zavírání jde až na 100 %.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(cardStroke(22))
    }

    private func meter(_ title: String, fraction: Double, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption.weight(.bold))
                Spacer()
                Text(value)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(4, geo.size.width * min(1, max(0, fraction))))
                }
            }
            .frame(height: 7)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value)")
    }

    private func percentSlider(_ title: String, value: Binding<Double>, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("\(Int(value.wrappedValue.rounded()))")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            Slider(value: value, in: 0...100, step: 1) { editing in
                if editing { touchCustom() }
            }
            .tint(Theme.brand)
            .accessibilityLabel(title)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var stylePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Herní styl")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(styleNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(BotPlayingStyle.allCases) { item in
                    Button {
                        withAnimation(motion) { style = item }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(style == item ? Theme.accent : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(styleDetail(item))
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
        .overlay(cardStroke(22))
    }

    private func styleDetail(_ item: BotPlayingStyle) -> String {
        guard mode == .custom else { return item.detail }
        switch item {
        case .scoringSpecialist: return "Míří na vysoké skóre a míň řeší stavbu zavření."
        case .checkoutSpecialist: return "Staví si zavření a drží se oblíbených doublů."
        default: return item.detail
        }
    }

    private var styleNote: String {
        switch mode {
        case .roster:
            return "Stejná úroveň může hrát jinak. Styl posouvá skóre, double, výkyvy a stavbu zavření."
        case .adaptive:
            return "Úroveň volí Adaptive AI. Styl k ní přidáš ty a v zápasu zůstane."
        case .custom:
            return "Průměr, zavírání, stabilita, nervy a taktika drží nastavená čísla. Styl mění, na co bot míří a jak si staví zavření."
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .frame(width: 32, height: 32)
                .foregroundStyle(enabled ? .primary : .tertiary)
                .background(Color.primary.opacity(0.06), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
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
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(cardStroke(16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func cardStroke(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(Theme.stroke, lineWidth: 1)
    }

    private var confirmBar: some View {
        GlassEffectContainer(spacing: 10) {
            Button {
                onConfirm(confirmedChoice)
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

    private var confirmedChoice: BotChoice {
        switch mode {
        case .roster:
            return BotChoice(level: level, style: style)
        case .adaptive:
            return BotChoice(level: reading.recommendedLevel, style: style, adaptive: true)
        case .custom:
            return BotChoice(
                level: shownLevel,
                style: style,
                customAverage: average,
                customCheckout: checkout / 100,
                customName: customName,
                customConsistency: stability / 100,
                customPressure: nerve / 100,
                customIntelligence: tactics / 100
            )
        }
    }
}

#if DEBUG
#Preview {
    BotPickerSheet(
        initial: BotChoice(level: 5),
        reading: AdaptiveReading(
            legs: 8,
            threeDartAverage: 52,
            first9Average: 64,
            checkoutPercentage: 28,
            dartsPerLeg: 22,
            stability: 9,
            recentWinRate: 0.62,
            recommendedLevel: 8
        ),
        onConfirm: { _ in }
    )
    .preferredColorScheme(.dark)
}
#endif
