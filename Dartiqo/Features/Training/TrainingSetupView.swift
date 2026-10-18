import SwiftUI

struct TrainingSetupView: View {
    @EnvironmentObject private var store: AppStore
    var definition: TrainingDefinition

    @State private var level: TrainingLevel = .advanced
    @State private var rounds = 8
    @State private var darts = 30
    @State private var seconds = 60
    @State private var lives = 3
    @State private var target = 100
    @State private var accuracy = 0.4
    @State private var showCheckouts = true
    @State private var players = 1
    @State private var secondName = ""
    @State private var useGhost = false
    @State private var segments: Set<Int> = []

    private var ghost: [Dart]? { store.ghostThrows(for: definition.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(definition.summary).font(AppFont.body())
                    Text(definition.rules).font(AppFont.body(15)).foregroundStyle(.secondary)
                    HStack {
                        Text(definition.listed.title)
                        Text("·")
                        Text("\(definition.minutes) min")
                        Text("·")
                        Text(definition.category.title)
                    }
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                    if let best = store.bestTrainingResult(for: definition.id) {
                        Text(best.higherIsBetter ? "Rekord \(best.score)" : "Rekord \(best.score) šipek")
                            .font(AppFont.body(16, weight: .bold))
                    } else {
                        Text("Bez odehrané session zatím není rekord.")
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }
                .surface()

                options
                NavigationLink {
                    TrainingPlayView(definition: definition, config: config)
                } label: {
                    Text("Start")
                }
                .buttonStyle(PrimaryButton())
            }
            .padding(16)
        }
        .screen()
        .navigationTitle(definition.title)
        .onAppear {
            if segments.isEmpty, let defaults = cricketDefaults {
                segments = Set(defaults)
            }
        }
        .toolbar {
            Button {
                store.toggleTrainingFavorite(definition.id)
            } label: {
                Image(systemName: store.isFavoriteTraining(definition.id) ? "heart.fill" : "heart")
            }
            .accessibilityLabel("Oblíbené")
        }
    }

    @ViewBuilder
    private var options: some View {
        let flags = definition.options
        VStack(alignment: .leading, spacing: 14) {
            if flags.level {
                Picker("Obtížnost", selection: $level) {
                    ForEach(TrainingLevel.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
            }
            if flags.rounds {
                Stepper("Kola: \(rounds)", value: $rounds, in: 1...30)
            }
            if flags.darts {
                Stepper("Šipky: \(darts)", value: $darts, in: 3...120)
            }
            if flags.time {
                Stepper("Čas: \(seconds) s", value: $seconds, in: 20...180, step: 10)
            }
            if flags.lives {
                Stepper("Životy: \(lives)", value: $lives, in: 1...6)
            }
            if flags.target {
                Stepper("Cílové skóre: \(target)", value: $target, in: 20...300, step: 10)
            }
            if flags.accuracy {
                VStack(alignment: .leading) {
                    Text("Požadovaná úspěšnost \(Int((accuracy * 100).rounded())) %")
                    Slider(value: $accuracy, in: 0.1...0.9, step: 0.05)
                }
            }
            if flags.checkouts {
                Toggle("Nápověda checkoutu", isOn: $showCheckouts)
            }
            if flags.multiplayer {
                Picker("Hráči", selection: $players) {
                    Text("Sólo").tag(1)
                    Text("Lokálně ve dvou").tag(2)
                }
                if players == 2 {
                    TextField("Jméno druhého hráče", text: $secondName)
                        .textFieldStyle(.roundedBorder)
                }
            }
            if flags.ghost, ghost != nil {
                Toggle("Porovnat s uloženým průběhem", isOn: $useGhost)
            }
            if cricketDefaults != nil {
                Text("Zapni čísla, která se hrají. Ve hře uvidíš jen ta.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                numberGrid(Array(1...20) + [25])
            } else if flags.segments {
                Text("Segmenty. Prázdný výběr nechá výchozí sadu hry.")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                numberGrid(Array(1...20))
            }
        }
        .surface()
    }

    private var config: TrainingConfig {
        var value = TrainingConfig(level: level)
        let flags = definition.options
        if flags.rounds { value.rounds = rounds }
        if flags.darts { value.dartCount = darts }
        if flags.time { value.timeLimit = TimeInterval(seconds) }
        if flags.lives { value.lives = lives }
        if flags.target { value.targetScore = target }
        if flags.accuracy { value.requiredAccuracy = accuracy }
        if flags.checkouts { value.showCheckouts = showCheckouts }
        if flags.multiplayer { value.players = players; value.secondName = secondName }
        if flags.ghost, useGhost { value.ghostDarts = ghost }
        if let defaults = cricketDefaults {
            let source = segments.isEmpty ? defaults : Array(segments)
            value.segments = MatchOptions.orderedCricketNumbers(source)
        } else if flags.segments, !segments.isEmpty {
            value.segments = segments.sorted()
        }
        return value
    }

    private var cricketDefaults: [Int]? {
        if case .cricket(let numbers, _) = definition.kind { return numbers }
        return nil
    }

    private func numberGrid(_ values: [Int]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
            ForEach(values, id: \.self) { number in
                let on = segments.contains(number)
                let last = cricketDefaults != nil && on && segments.count == 1
                Button(number == 25 ? "B" : "\(number)") { toggle(number) }
                    .font(AppFont.body(15, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(on ? Theme.onAccent : .primary)
                    .background(on ? Theme.accentFill : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    .disabled(last)
                    .accessibilityLabel(number == 25 ? "Bull" : "\(number)")
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func toggle(_ number: Int) {
        if segments.contains(number) {
            if cricketDefaults != nil, segments.count == 1 { return }
            segments.remove(number)
        } else {
            segments.insert(number)
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        TrainingSetupView(definition: PreviewSupport.sampleTraining)
    }
    .dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
