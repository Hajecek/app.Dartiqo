import SwiftUI

struct PlayView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Eyebrow(text: "Match room")
                Text("Jak dnes\nzahraješ?").font(.system(size: 38, weight: .bold, design: .rounded))
                Text("Vyber hru. Sestav soupeře. Hraj po svém.").foregroundStyle(.secondary)
                ForEach(GameMode.allCases) { mode in
                    NavigationLink { SetupView(mode: mode) } label: {
                        HStack(spacing: 18) {
                            Image(systemName: mode.symbol).font(.title2).foregroundStyle(Theme.action).frame(width: 52, height: 58).background(Theme.action.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 7) { Text(mode.shortTitle).font(.title3.bold()); Text(mode.detail).font(.caption).foregroundStyle(.secondary) }
                            Spacer(minLength: 0); Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }.foregroundStyle(.primary).surface()
                    }.buttonStyle(.plain)
                }
                if !store.presets.isEmpty {
                    Text("Tvoje předvolby").font(.title2.bold())
                    ForEach(store.presets) { preset in
                        NavigationLink { SetupView(mode: preset.setup.config.mode, preset: preset.setup) } label: {
                            HStack { Image(systemName: "bookmark.fill").foregroundStyle(Theme.action); VStack(alignment: .leading, spacing: 5) { Text(preset.name).bold(); Text(preset.setup.config.summary).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right") }.foregroundStyle(.primary).surface()
                        }.buttonStyle(.plain).contextMenu { Button("Odstranit předvolbu", role: .destructive) { store.deletePreset(preset.id) } }
                    }
                }
                Label("Hra a všechny předvolby fungují offline.", systemImage: "wifi.slash").font(.caption).foregroundStyle(.secondary)
            }.padding(22).frame(maxWidth: 760)
        }.screen().navigationTitle("Hrát").navigationBarTitleDisplayMode(.inline)
    }
}
struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: SetupDraft
    @State private var step = 0
    @State private var live = false
    @State private var replace = false
    @State private var savePreset = false
    @State private var presetName = "Moje 501"
    private var options: Binding<MatchOptions> { Binding(get: { draft.config.settings }, set: { draft.config.options = $0 }) }
    init(mode: GameMode, preset: SetupDraft? = nil) { _draft = State(initialValue: preset ?? SetupDraft(mode: mode)) }
    private var canContinue: Bool { !draft.seats.dropFirst().contains { !$0.isBot && $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                progress
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Krok \(step + 1) ze 3")
                    Text(["Tvoje hra.\nTvoje pravidla.", "Kdo se postaví\nk terči?", "Dolaď detaily.\nA jdeme hrát."][step]).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(["Začni režimem, na který máš náladu.", "Až čtyři hráči. Kamarádi i boti v jednom zápase.", "Zkontroluj nastavení a ulož si ho na příště."][step]).font(.subheadline).foregroundStyle(.secondary)
                }
                if step == 0 { gameStep }
                else if step == 1 { rosterStep }
                else { rulesStep }
            }.id("setup-top").padding(22).frame(maxWidth: 760)
        }.onChange(of: step) { _, _ in proxy.scrollTo("setup-top", anchor: .top) }
        }.screen().scrollDismissesKeyboard(.interactively)
            .navigationTitle("Nový zápas").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { footer }
            .confirmationDialog("Máš rozehraný zápas", isPresented: $replace, titleVisibility: .visible) {
                Button("Pokračovat v rozehraném") { live = true }
                Button("Zahodit rozehraný a spustit nový", role: .destructive) { start() }
                Button("Zrušit", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $live) { NavigationStack { MatchView() }.environmentObject(store) }
    }
    private var progress: some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { n in
                Button { if n <= step { setStep(n) } } label: {
                    HStack(spacing: 8) { Image(systemName: n < step ? "checkmark.circle.fill" : "\(n + 1).circle.fill"); Text(["Hra", "Hráči", "Pravidla"][n]).font(.caption.bold()) }.foregroundStyle(n <= step ? Theme.action : .secondary).frame(maxWidth: .infinity).padding(.vertical, 12).background(n == step ? Theme.action.opacity(0.12) : Theme.card, in: Capsule())
                }.buttonStyle(.plain).disabled(n > step)
            }
        }
    }
    private var gameStep: some View {
        VStack(spacing: 12) {
            ForEach(GameMode.allCases) { mode in
                ChoiceCard(title: mode.shortTitle, detail: mode.detail, symbol: mode.symbol, selected: draft.config.mode == mode) { draft.config.mode = mode }
            }
            if let id = store.profile?.id.uuidString, let last = store.data.lastSetups?[id] {
                Button { draft = last; setStep(2) } label: { Label("Použít poslední nastavení", systemImage: "clock.arrow.circlepath").font(.subheadline.bold()).frame(maxWidth: .infinity).padding(16) }.foregroundStyle(Theme.action)
            }
        }
    }
    private var rosterStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                quickRoster("S botem", icon: "cpu", kind: 0)
                quickRoster("Kamarádi", icon: "person.2", kind: 1)
                quickRoster("Sólo", icon: "person", kind: 2)
            }
            HStack { Avatar(name: store.profile?.name ?? "Já"); VStack(alignment: .leading, spacing: 5) { Text(store.profile?.name ?? "Já").font(.headline); Text("Tvůj profil · statistiky se ukládají").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("TY").font(.caption.bold()).foregroundStyle(Theme.action) }.surface()
            ForEach(Array(draft.seats.indices.dropFirst()), id: \.self) { i in seatCard(i) }
            if draft.seats.count < 4 {
                Button { draft.seats.append(SeatDraft(name: "Hráč \(draft.seats.count + 1)")) } label: { Label("Přidat hráče nebo bota", systemImage: "plus.circle").font(.headline).frame(maxWidth: .infinity).padding(18).background(Theme.action.opacity(0.07), in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.action.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5,4]))) }.foregroundStyle(Theme.action)
            }
            if draft.seats.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Kdo začíná první leg?").font(.headline)
                    Picker("Začínající hráč", selection: $draft.starter) {
                        Text("Náhodný los").tag(-1)
                        ForEach(draft.seats.indices, id: \.self) { i in Text(seatName(i)).tag(i) }
                    }.pickerStyle(.menu)
                    Text("V dalších lezích se začínající hráč střídá.").font(.caption).foregroundStyle(.secondary)
                }.surface()
            }
            Text("Všichni lidští hráči zapisují na tomto telefonu. Online hra není součástí této verze.").font(.caption).foregroundStyle(.secondary)
        }
    }
    private func quickRoster(_ title: String, icon: String, kind: Int) -> some View {
        Button {
            draft.seats = [SeatDraft(name: "Já")]
            if kind != 2 { draft.seats.append(SeatDraft(name: kind == 0 ? "Bot" : "Kamarád", isBot: kind == 0)) }
            draft.starter = 0
        } label: { Label(title, systemImage: icon).font(.caption.bold()).frame(maxWidth: .infinity).padding(.vertical, 15).background(Theme.card, in: RoundedRectangle(cornerRadius: 14)) }.buttonStyle(.plain)
    }
    private func seatCard(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Avatar(name: draft.seats[i].name, bot: draft.seats[i].isBot)
                Picker("Typ hráče", selection: $draft.seats[i].isBot) { Text("Kamarád").tag(false); Text("Bot").tag(true) }.pickerStyle(.segmented)
                Button { draft.seats.remove(at: i); draft.starter = 0 } label: { Image(systemName: "minus.circle").frame(width: 44, height: 44) }.foregroundStyle(.secondary).accessibilityLabel("Odebrat hráče \(i + 1)")
            }
            if draft.seats[i].isBot {
                HStack { VStack(alignment: .leading, spacing: 4) { Text(BotLevel.get(draft.seats[i].level).name).font(.title3.bold()); Text("Přesnější skórování i zavírání s vyšší úrovní").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(draft.seats[i].level)").font(.system(size: 32, weight: .bold, design: .rounded)).foregroundStyle(Theme.action) }
                Slider(value: Binding(get: { Double(draft.seats[i].level) }, set: { draft.seats[i].level = Int($0) }), in: 1...10, step: 1).tint(Theme.action).accessibilityLabel("Úroveň bota \(i + 1)")
                HStack { Text("ZAČÁTEČNÍK"); Spacer(); Text("LEGENDA") }.font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
            } else { TextField("Jméno kamaráda", text: $draft.seats[i].name).textFieldStyle(.roundedBorder).autocorrectionDisabled() }
        }.surface()
    }
    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Label(draft.config.mode.shortTitle, systemImage: draft.config.mode.symbol).font(.title2.bold())
                if draft.config.mode == .x01 {
                    Text("Startovní skóre").font(.subheadline.bold())
                    HStack(spacing: 6) { ForEach([101,301,501,701,1001], id: \.self) { score in ChoicePill(title: "\(score)", selected: draft.config.startingScore == score) { draft.config.startingScore = score } } }
                    Picker("Zavření", selection: $draft.config.outRule) { ForEach(OutRule.allCases) { Text($0.title).tag($0) } }
                    Toggle("Otevřít doublem", isOn: $draft.config.doubleIn).tint(Theme.action)
                    Text(draft.config.outRule == .double ? "Poslední šipka musí být double nebo bull 50." : draft.config.outRule == .master ? "Zavírá double, triple nebo bull 50." : "Zavřít můžeš jakýmkoli platným zásahem.").font(.caption).foregroundStyle(.secondary)
                }
                if draft.config.mode == .x01 || draft.config.mode == .cricket {
                    Divider()
                    Stepper(value: $draft.config.legsToWin, in: 1...9) { VStack(alignment: .leading, spacing: 5) { Text("Na \(draft.config.legsToWin) vítězné legy").font(.headline); Text(draft.seats.count == 2 ? "Nejvýše \(draft.config.legsToWin * 2 - 1) legů" : "První hráč s cílovým počtem legů vítězí").font(.caption).foregroundStyle(.secondary) } }
                }
                if draft.config.mode == .cricket {
                    Toggle("Cricket bez bodů", isOn: options.cricketNoScore).tint(Theme.action)
                    Text(draft.config.settings.cricketNoScore ? "Rozhoduje pouze to, kdo první zavře 15–20 a bull." : "Zavři všechna čísla a měj alespoň tolik bodů jako soupeři.").font(.caption).foregroundStyle(.secondary)
                }
                if draft.config.mode == .countUp {
                    Text("Délka tréninku").font(.subheadline.bold())
                    HStack { ForEach([5,10,15,20,30], id: \.self) { rounds in ChoicePill(title: "\(rounds)", selected: draft.config.settings.countUpRounds == rounds) { options.wrappedValue.countUpRounds = rounds } } }
                    Text("\(draft.config.settings.countUpRounds * 3) šipek na hráče").font(.caption).foregroundStyle(.secondary)
                }
                if draft.config.mode == .aroundClock {
                    Picker("Požadovaný zásah", selection: options.clockStyle) { ForEach(ClockStyle.allCases) { Text($0.title).tag($0) } }
                    Text("Postupně 1–20. Na závěr libovolný bull; u tréninku doublů nebo triplů bull 50.").font(.caption).foregroundStyle(.secondary)
                }
            }.surface()
            VStack(alignment: .leading, spacing: 18) {
                Text("Průběh hry").font(.headline)
                if draft.config.mode == .x01 && !draft.config.doubleIn {
                    Picker("Zápis skóre", selection: options.entry) { ForEach(EntryStyle.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    Text("Po šipkách: klepnutí ihned mění skóre, třetí šipka automaticky předá tah. Součet: rychlé hodnoty odečítají celé kolo; při zavření potvrdíš počet šipek.").font(.caption).foregroundStyle(.secondary)
                } else { Label("Zápis po jednotlivých šipkách", systemImage: "scope").font(.subheadline).foregroundStyle(.secondary) }
                if draft.seats.contains(where: \.isBot) {
                    Picker("Tempo šipek bota", selection: options.botDelay) { Text("Rychlé · 0,5 s").tag(0.5); Text("Plynulé · 1,5 s").tag(1.5); Text("Klidné · 3 s").tag(3.0) }
                }
                if draft.config.mode == .x01 { Toggle("Nápověda zavření", isOn: options.checkoutHints).tint(Theme.action) }
                Toggle("Nezhasínat displej při hře", isOn: options.keepAwake).tint(Theme.action)
            }.surface()
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow(text: "Připraveno ke hře")
                Text((0..<draft.seats.count).map(seatName).joined(separator: "  ·  ")).font(.headline)
                Text(draft.config.summary).font(.subheadline).foregroundStyle(.secondary)
                Toggle("Uložit jako předvolbu", isOn: $savePreset).tint(Theme.action)
                if savePreset { TextField("Název předvolby", text: $presetName).textFieldStyle(.roundedBorder) }
            }.surface()
        }
    }
    private var footer: some View {
        HStack(spacing: 14) {
            if step > 0 { Button { setStep(step - 1) } label: { Image(systemName: "arrow.left").font(.headline).frame(width: 52, height: 54).background(Theme.card, in: RoundedRectangle(cornerRadius: 18)) }.buttonStyle(.plain).accessibilityLabel("Předchozí krok") }
            Button {
                if step < 2 { setStep(step + 1) }
                else if store.activeMatch != nil { replace = true }
                else { start() }
            } label: { HStack { Text(step < 2 ? "Pokračovat" : "Spustit zápas"); Spacer(); Image(systemName: step < 2 ? "arrow.right" : "play.fill") }.padding(.horizontal, 20) }.buttonStyle(PrimaryButton()).disabled(step > 0 && !canContinue)
        }.padding(.horizontal, 22).padding(.vertical, 12).background(.regularMaterial)
    }
    private func setStep(_ value: Int) { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { step = value } }
    private func seatName(_ i: Int) -> String { i == 0 ? store.profile?.name ?? "Já" : draft.seats[i].isBot ? "Bot \(i) · L\(draft.seats[i].level)" : draft.seats[i].name }
    private func start() {
        guard let profile = store.profile, canContinue else { return }
        var players = [Player(id: profile.id, name: profile.name)]
        for i in draft.seats.indices.dropFirst() {
            let seat = draft.seats[i]
            players.append(Player(name: seat.isBot ? "Bot \(i) · L\(seat.level)" : String(seat.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)), botLevel: seat.isBot ? seat.level : nil))
        }
        if [.aroundClock,.countUp].contains(draft.config.mode) { draft.config.legsToWin = 1 }
        let first = draft.starter == -1 ? Int.random(in: players.indices) : min(max(0,draft.starter),players.count - 1)
        store.remember(draft)
        if savePreset { store.addPreset(name: presetName, setup: draft); savePreset = false }
        store.activeMatch = Match(config: draft.config, players: players, firstPlayer: first)
        store.feedback(); live = true
    }
}
struct ChoiceCard: View {
    var title: String; var detail: String; var symbol: String; var selected: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title2).frame(width: 46, height: 52).foregroundStyle(Theme.action)
                VStack(alignment: .leading, spacing: 7) { Text(title).font(.title3.bold()); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0); Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.action : .secondary)
            }.foregroundStyle(.primary).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(selected ? Theme.action.opacity(0.09) : Theme.card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(selected ? Theme.action : Theme.stroke, lineWidth: selected ? 1.5 : 1))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
struct ChoicePill: View {
    var title: String; var selected: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).font(.system(.subheadline, design: .rounded, weight: .bold)).frame(maxWidth: .infinity).frame(minHeight: 44).foregroundStyle(selected ? Theme.onAccent : .primary).background(selected ? Theme.accentFill : Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
