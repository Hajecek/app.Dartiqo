import SwiftUI

/// Nastavení otevřené z ozubeného kola během zápasu.
struct MatchSettingsSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Binding var paused: Bool
    var options: Binding<MatchOptions>
    var mode: GameMode
    var showsBotTempo: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button(paused ? "Pokračovat ve hře" : "Pozastavit hru", systemImage: paused ? "play.fill" : "pause.fill") {
                        paused.toggle()
                        dismiss()
                    }
                }

                if mode == .x01 {
                    averageSection
                    extraNumbersSection
                }

                Section {
                    if mode == .x01 {
                        Toggle("Nápověda zavření", isOn: options.checkoutHints)
                    }
                    Toggle("Nezhasínat displej", isOn: options.keepAwake)
                } header: {
                    Text("Obrazovka")
                } footer: {
                    Text(mode == .x01
                         ? "Nápověda ukáže cestu na zavření u volných polí. Displej zůstane rozsvícený, dokud ze zápasu neodejdeš."
                         : "Displej zůstane rozsvícený, dokud ze zápasu neodejdeš.")
                }

                if showsBotTempo {
                    Section {
                        Picker("Tempo", selection: options.botDelay) {
                            Text("Rychlé").tag(0.5)
                            Text("Plynulé").tag(1.5)
                            Text("Klidné").tag(3.0)
                        }
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Bot")
                    } footer: {
                        Text("Rychlé je 0,5 s mezi šipkami, plynulé 1,5 s a klidné 3 s. U terče jde hod zrychlit, dokud tempo nevrátíš.")
                    }
                }

                Section {
                    Toggle("Hlasové skóre", isOn: $store.data.voice)
                    Toggle("Haptika", isOn: $store.data.haptics)
                } header: {
                    Text("Odezva")
                } footer: {
                    Text("Hlas čte dosažené skóre. Zápis mikrofonem se volí dole ve hře a je nezávislý.")
                }

                Section {
                    Text("Každý zásah z čísel nebo terče se odečte hned. Třetí šipka, přehoz nebo zavření kolo ukončí.")
                    Text("Klepnutí na terč zapíše pole. Podržení otevře zvětšený terč.")
                    Text("Po kole obrazovka chvíli zůstane, pak přejde na dalšího hráče. Po legu klepni, nebo počkej.")
                    Text("Zpět vrací jednu šipku, i během kontroly hodu bota.")
                } header: {
                    Text("Zápis")
                }
            }
            .navigationTitle("Nastavení zápasu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                }
            }
        }
        .tint(MatchColors.green)
        .preferredColorScheme(.dark)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .onDisappear { store.save() }
    }

    private var averageSection: some View {
        Section {
            ForEach(AverageScope.allCases) { item in
                Button {
                    scope.wrappedValue = item
                    store.selectionHaptic()
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: item.symbol)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(scope.wrappedValue == item ? MatchColors.green : .secondary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .foregroundStyle(.primary)
                            Text(item.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if scope.wrappedValue == item {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.bold))
                                .foregroundStyle(MatchColors.green)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scope.wrappedValue == item ? .isSelected : [])
            }
        } header: {
            Text("Průměr")
        } footer: {
            Text("Průměr je na tři šipky, včetně šipek před otevřením a při přehozu. Celý zápas sčítá všechny legy. Leg je jedna hra.")
        }
    }

    private var extraNumbersSection: some View {
        Section {
            Toggle("Prvních 9", isOn: flag(\.showFirst9))
            Toggle("Poslední kolo", isOn: flag(\.showLastVisit))
            Toggle("Nejlepší kolo", isOn: flag(\.showBestVisit))
            Toggle("Počet šipek v legu", isOn: flag(\.showDartCount))
        } header: {
            Text("Další čísla")
        } footer: {
            Text("Prvních 9 je průměr úvodních tří kol v rozehraném legu. Poslední a nejlepší kolo berou jen dokončenou návštěvu. Šipky počítají tento leg.")
        }
    }

    private var scope: Binding<AverageScope> {
        Binding(
            get: { store.data.matchDisplay?.scope ?? .match },
            set: { value in
                var display = store.data.matchDisplay ?? MatchDisplay()
                display.averageScope = value
                store.data.matchDisplay = display
            }
        )
    }

    private func flag(_ keyPath: WritableKeyPath<MatchDisplay, Bool?>) -> Binding<Bool> {
        Binding(
            get: { store.data.matchDisplay?[keyPath: keyPath] == true },
            set: { value in
                var display = store.data.matchDisplay ?? MatchDisplay()
                display[keyPath: keyPath] = value
                store.data.matchDisplay = display
            }
        )
    }
}
