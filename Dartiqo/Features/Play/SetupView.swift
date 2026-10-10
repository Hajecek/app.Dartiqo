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

private enum Opening {
    case random, pick, bull
}

struct SetupView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    private let onHome: (() -> Void)?
    @State private var draft: SetupDraft
    @State private var step = 0
    @State private var live = false
    @State private var launchIntro = true
    @State private var replace = false
    @State private var savePreset = false
    @State private var presetName = "Moje 501"
    @State private var scoreText = "501"
    @State private var scoreExact = false
    @State private var limitCustom = false
    @State private var openRule: RuleKey? = .start
    @State private var showFriends = false
    @FocusState private var focusedGuest: UUID?
    private enum RuleKey: Hashable { case start, finish, mode, length, limit, handicap, flow }
    @State private var opening: Opening?
    @State private var pickedStarter: Int?
    @State private var bullWinner: Int?
    @State private var showBullOff = false
    @State private var bullLaunched = false
    private let presetScores = [101, 301, 501, 701, 1001]
    private var options: Binding<MatchOptions> { Binding(get: { draft.config.settings }, set: { draft.config.options = $0 }) }
    init(mode: GameMode, preset: SetupDraft? = nil, onHome: (() -> Void)? = nil) {
        self.onHome = onHome
        _draft = State(initialValue: preset ?? SetupDraft(mode: mode))
    }
    private var canContinue: Bool {
        !draft.seats.isEmpty && !draft.seats.indices.contains { !isMe($0) && !draft.seats[$0].isBot && draft.seats[$0].name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var showsOpening: Bool { draft.seats.count > 1 }
    private var stepCount: Int { showsOpening ? 5 : 4 }
    private var stepTitles: [String] { showsOpening ? ["Hra", "Hráči", "Pravidla", "Souhrn", "Start"] : ["Hra", "Hráči", "Pravidla", "Souhrn"] }
    private var isLastStep: Bool { step >= stepCount - 1 }
    private var canPlay: Bool {
        guard canContinue else { return false }
        guard showsOpening else { return true }
        switch opening {
        case .random: return true
        case .pick: return pickedStarter != nil
        case .bull: return bullWinner != nil
        case nil: return false
        }
    }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.38) }
    private var sectionMotion: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.46, dampingFraction: 0.88) }
    private var usingExactScore: Bool { scoreExact || !presetScores.contains(draft.config.startingScore) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    progress
                    VStack(alignment: .leading, spacing: 6) {
                        Text(headline)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Group {
                        if step == 0 { gameStep }
                        else if step == 1 { rosterStep }
                        else if step == 2 { rulesStep }
                        else if step == 3 { summaryStep }
                        else { openingStep }
                    }
                    .id(step)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                }
                .id("setup-top")
                .padding(22)
                .frame(maxWidth: 760)
            }
            .onChange(of: step) { _, _ in
                proxy.scrollTo("setup-top", anchor: .top)
            }
            .onChange(of: openRule) { _, key in
                guard let key, step == 2 else { return }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    withAnimation(sectionMotion) { proxy.scrollTo(key, anchor: .top) }
                }
            }
        }
        .animation(motion, value: step)
        .safeAreaInset(edge: .bottom, spacing: 0) { setupBar }
        .toolbar(.hidden, for: .tabBar)
        .screen()
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Nový zápas")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step > 0)
        .toolbar {
            if step > 0 {
                ToolbarItem(placement: .topBarLeading) {
                    Button { setStep(step - 1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel("Předchozí krok")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: step)
        .onAppear {
            scoreText = "\(draft.config.startingScore)"
            if !presetScores.contains(draft.config.startingScore) { scoreExact = true }
        }
        .onChange(of: showsOpening) { _, shown in
            if !shown, step > 3 { setStep(3) }
        }
        .onChange(of: showBullOff) { _, shown in
            if !shown { bullLaunched = false }
        }
        .confirmationDialog("Máš rozehraný zápas", isPresented: $replace, titleVisibility: .visible) {
            Button("Pokračovat v rozehraném") { launchIntro = false; live = true }
            Button("Zahodit rozehraný a spustit nový", role: .destructive) { start() }
            Button("Zrušit", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $live) { MatchLaunchView(intro: launchIntro).environmentObject(store) }
        .onChange(of: store.homeGeneration) { _, _ in
            live = false
            showBullOff = false
        }
        .fullScreenCover(isPresented: $showBullOff) {
            ZStack {
                if bullLaunched {
                    MatchLaunchView(intro: true)
                        .transition(.opacity)
                } else {
                    BullOffView(names: draft.seats.indices.map(seatName), bots: draft.seats.indices.map { index in
                        isMe(index) ? nil : (draft.seats[index].isBot ? draft.seats[index].level : nil)
                    }) { winner in
                        bullWinner = winner
                        opening = .bull
                        commitScoreFromField()
                        if let active = store.activeMatch, !active.finished {
                            showBullOff = false
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                replace = true
                            }
                        } else if makeMatch() {
                            withAnimation(.easeInOut(duration: 0.35)) { bullLaunched = true }
                        } else {
                            showBullOff = false
                        }
                    } onCancel: {
                        showBullOff = false
                        if bullWinner == nil { opening = nil }
                    }
                    .transition(.opacity)
                }
            }
            .environmentObject(store)
        }
    }

    private var headline: String {
        switch step {
        case 0: return "Jaká hra?"
        case 1: return "Kdo hraje?"
        case 2: return "Jak se hraje?"
        case 3: return "Všechno sedí?"
        default: return "Kdo začíná?"
        }
    }

    private var subtitle: String {
        switch step {
        case 0: return "Vyber režim. Ostatní doladíš v dalším kroku."
        case 1: return "Ty a až tři soupeři. Pozvi přátele, přidej hosta, nebo bota."
        case 2: return "Klepni na sekci a nastav ji. Ostatní zůstanou sbalené."
        case 3: return "Kdo hraje a podle jakých pravidel. Klepnutím na řádek ho změníš."
        default: return "Rozhodni, kdo hází první leg."
        }
    }

    private var canAdvance: Bool { isLastStep ? canPlay : (step == 0 || canContinue) }

    private var setupBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let onHome { onHome() } else { dismiss() }
                } label: {
                    Image(systemName: "house.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("Domů")

                Button { advance() } label: {
                    HStack(spacing: 8) {
                        Text(isLastStep ? "Hrát" : "Pokračovat")
                            .font(.headline)
                            .contentTransition(.opacity)
                        Image(systemName: isLastStep ? "play.fill" : "arrow.right")
                            .font(.subheadline.weight(.bold))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .foregroundStyle(canAdvance ? Color.black : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(canAdvance ? .regular.tint(Theme.brand).interactive() : .regular, in: Capsule())
                .disabled(!canAdvance)
                .animation(motion, value: canAdvance)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let fraction = CGFloat(step + 1) / CGFloat(stepCount)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(Theme.brand)
                        .frame(width: max(18, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Button { if index < step { setStep(index) } } label: {
                        Text(stepTitles[index])
                            .font(.caption.weight(index == step ? .bold : .medium))
                            .foregroundStyle(index == step ? Theme.accent : (index < step ? .primary : .secondary))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(index > step)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Krok \(step + 1) ze \(stepCount), \(stepTitles[min(step, stepTitles.count - 1)])")
        .accessibilityAdjustableAction { direction in
            if direction == .decrement, step > 0 { setStep(step - 1) }
        }
    }

    private var gameStep: some View {
        VStack(spacing: 12) {
            ForEach(GameMode.allCases) { mode in
                ChoiceCard(title: mode.shortTitle, detail: mode.detail, symbol: mode.symbol, selected: draft.config.mode == mode) {
                    withAnimation(motion) { draft.config.mode = mode }
                }
            }
            if let id = store.profile?.id.uuidString, let last = store.data.lastSetups?[id] {
                Button {
                    draft = last
                    scoreText = "\(last.config.startingScore)"
                    setStep(2)
                } label: {
                    Label("Použít poslední nastavení", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(16)
                }
                .foregroundStyle(Theme.action)
            }
        }
    }
    private enum Lineup: CaseIterable, Identifiable {
        case meBot, meFriend, botBot, friendFriend, solo
        var id: Self { self }
        var title: String {
            switch self {
            case .meBot: return "Ty vs Bot"
            case .meFriend: return "Ty vs Kamarád"
            case .botBot: return "Bot vs Bot"
            case .friendFriend: return "Kamarád vs Kamarád"
            case .solo: return "Sólo"
            }
        }
        var icon: String {
            switch self {
            case .meBot: return "cpu"
            case .meFriend: return "person.2.fill"
            case .botBot: return "cpu.fill"
            case .friendFriend: return "person.3.fill"
            case .solo: return "figure.archery"
            }
        }
    }

    private var currentLineup: Lineup? {
        let others = draft.seats.indices.filter { !isMe($0) }.map { draft.seats[$0] }
        switch (draft.includesMe, others.count) {
        case (true, 0): return .solo
        case (true, 1): return others[0].isBot ? .meBot : .meFriend
        case (false, 2):
            if others.allSatisfy(\.isBot) { return .botBot }
            if others.allSatisfy({ !$0.isBot }) { return .friendFriend }
            return nil
        default: return nil
        }
    }

    private func applyLineup(_ lineup: Lineup) {
        hideKeyboard()
        withAnimation(motion) {
            switch lineup {
            case .meBot: draft.seats = [SeatDraft(name: "Já"), SeatDraft(name: "Bot", isBot: true)]
            case .meFriend: draft.seats = [SeatDraft(name: "Já"), SeatDraft(name: "")]
            case .botBot: draft.seats = [SeatDraft(name: "Bot", isBot: true, level: 3), SeatDraft(name: "Bot", isBot: true, level: 6)]
            case .friendFriend: draft.seats = [SeatDraft(name: ""), SeatDraft(name: "")]
            case .solo: draft.seats = [SeatDraft(name: "Já")]
            }
            draft.withoutMe = (lineup == .botBot || lineup == .friendFriend) ? true : nil
            draft.starter = 0
        }
        if lineup == .meFriend || lineup == .friendFriend { focusedGuest = draft.seats.first { !$0.isBot && $0.name.isEmpty }?.id }
    }

    private func setPlaysMyself(_ on: Bool) {
        guard on != draft.includesMe else { return }
        hideKeyboard()
        withAnimation(motion) {
            if on {
                guard draft.seats.count < 4 else { return }
                draft.seats.insert(SeatDraft(name: "Já"), at: 0)
                draft.withoutMe = nil
            } else {
                if !draft.seats.isEmpty { draft.seats.removeFirst() }
                draft.withoutMe = true
            }
            draft.starter = 0
        }
    }

    private var rosterStep: some View {
        let others = draft.seats.indices.filter { !isMe($0) }
        return VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Rychlá sestava")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Lineup.allCases) { lineup in
                            let selected = currentLineup == lineup
                            Button { applyLineup(lineup) } label: {
                                Label(lineup.title, systemImage: lineup.icon)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 40)
                                    .foregroundStyle(selected ? Color.black : Color.primary)
                                    .background(selected ? Theme.brand : Color.primary.opacity(0.06), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .scrollClipDisabled()
                .sensoryFeedback(.selection, trigger: currentLineup)
            }

            meCard

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Eyebrow(text: draft.includesMe ? "Soupeři" : "Hráči")
                    Spacer()
                    Text("\(draft.seats.count) ze 4 míst")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                if others.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: draft.includesMe ? "figure.archery" : "person.crop.circle.badge.questionmark")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.includesMe ? "Sólo trénink" : "Zatím nikdo nehraje").font(.headline)
                            Text(draft.includesMe ? "Hraješ sám. Přidej soupeře níž." : "Přidej aspoň jednoho hráče nebo bota.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                }
                ForEach(others, id: \.self) { index in
                    Group {
                        if draft.seats[index].isBot { botCard(index) } else { friendCard(index) }
                    }
                    .transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity), removal: .opacity))
                }
            }

            if draft.seats.count < 4 {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Přidat hráče")
                    VStack(spacing: 0) {
                        addRow("Pozvat z přátel", detail: "Uložení přátelé, profily na telefonu a kontakty", icon: "person.2.fill") { showFriends = true }
                        Divider().padding(.leading, 66)
                        addRow("Host", detail: "Jen napíšeš jméno. Po hře se uloží mezi přátele", icon: "person.fill.badge.plus") { addGuest() }
                        Divider().padding(.leading, 66)
                        addRow("Bot", detail: "Počítačový soupeř s úrovní 1 až 10", icon: "cpu.fill") { addBot() }
                    }
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
                }
                .transition(.opacity)
            }

            Label(draft.includesMe ? "Všichni hrajete na tomhle telefonu a zapisujete se střídavě." : "Zápas běží na tomhle telefonu. Do tvých statistik se nepočítá.", systemImage: "iphone")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .sheet(isPresented: $showFriends) {
            FriendPickerSheet(
                taken: Set(draft.seats.compactMap(\.friendID) + [store.profile?.id].compactMap { $0 }),
                slots: 4 - draft.seats.count
            ) { picked in
                withAnimation(motion) {
                    for friend in picked where draft.seats.count < 4 {
                        draft.seats.append(SeatDraft(name: friend.name, friendID: friend.id))
                    }
                    draft.starter = 0
                }
            }
            .environmentObject(store)
        }
    }

    private var meCard: some View {
        let playing = draft.includesMe
        let blocked = !playing && draft.seats.count >= 4
        return HStack(spacing: 14) {
            Avatar(name: store.profile?.name ?? "Já", size: 52, photo: store.profile?.photoJPEG)
                .saturation(playing ? 1 : 0)
                .opacity(playing ? 1 : 0.5)
                .playerRing(playing ? seatColor(0) : nil)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(store.profile?.name ?? "Já").font(.title3.bold()).lineLimit(1)
                    Text("TY")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Theme.onAccent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.accentFill, in: Capsule())
                }
                Text(playing ? "Hraješ · statistiky se ukládají" : blocked ? "Místa jsou plná. Uvolni jedno." : "Nehraješ · jen spouštíš zápas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            Toggle("Hraju taky", isOn: Binding(get: { playing }, set: { setPlaysMyself($0) }))
                .labelsHidden()
                .tint(Theme.action)
                .disabled(blocked)
        }
        .padding(.leading, 14)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .playerCard(playing ? seatColor(0) : nil)
    }

    /// Barva místa v sestavě. Sólo hra barvy nepotřebuje.
    private func seatColor(_ index: Int) -> Color? {
        draft.seats.count > 1 ? Theme.playerColor(index) : nil
    }

    private func botPersona(_ index: Int) -> String {
        let seat = draft.seats[index]
        let persona = BotLevel.get(seat.level).persona
        let same = draft.seats[..<index].filter { $0.isBot && $0.level == seat.level }.count
        return same == 0 ? persona : "\(persona) \(same + 1)"
    }

    private func addRow(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(Theme.action)
                    .frame(width: 38, height: 38)
                    .background(Theme.action.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.action)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func isMe(_ index: Int) -> Bool { draft.includesMe && index == 0 }

    private func addGuest() {
        withAnimation(motion) {
            draft.seats.append(SeatDraft(name: ""))
            draft.starter = 0
        }
        focusedGuest = draft.seats.last?.id
    }

    private func addBot() {
        withAnimation(motion) {
            draft.seats.append(SeatDraft(name: "Bot", isBot: true))
            draft.starter = 0
        }
    }

    private func removeSeat(_ index: Int) {
        guard draft.seats.indices.contains(index), !isMe(index) else { return }
        withAnimation(motion) {
            _ = draft.seats.remove(at: index)
            draft.starter = 0
        }
    }

    private func removeButton(_ index: Int) -> some View {
        Button { removeSeat(index) } label: {
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(Color.primary.opacity(0.07), in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Odebrat \(seatName(index))")
    }

    private func friendCard(_ index: Int) -> some View {
        let seat = draft.seats[index]
        let linked = seat.friendID != nil
        let housemate = store.housemates.first { $0.id == seat.friendID }
        return HStack(spacing: 12) {
            Avatar(name: seat.name.isEmpty ? "?" : seat.name, size: 44, photo: housemate?.photoJPEG)
                .playerRing(seatColor(index))
            VStack(alignment: .leading, spacing: 3) {
                if linked {
                    Text(seat.name).font(.headline).lineLimit(1)
                } else {
                    TextField("Jméno kamaráda", text: $draft.seats[index].name)
                        .font(.headline)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($focusedGuest, equals: seat.id)
                        .submitLabel(.done)
                }
                Label(housemate != nil ? "Profil na tomto telefonu" : linked ? "Přítel" : "Host · uloží se mezi přátele", systemImage: housemate != nil ? "person.crop.circle.fill" : linked ? "heart.fill" : "person")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 4)
            removeButton(index)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 10)
        .playerCard(seatColor(index))
    }

    private func botCard(_ index: Int) -> some View {
        let level = draft.seats[index].level
        let info = BotLevel.get(level)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Avatar(name: info.persona, bot: true, size: 52, asset: info.photo)
                    .id(info.photo)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .playerRing(seatColor(index))
                VStack(alignment: .leading, spacing: 3) {
                    Text(botPersona(index)).font(.headline).contentTransition(.opacity)
                    Label("„\(info.nickname)“ · \(info.name)", systemImage: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 4)
                Text("\(level)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.action)
                    .contentTransition(.numericText(value: Double(level)))
                removeButton(index)
            }
            Slider(value: Binding(get: { Double(draft.seats[index].level) }, set: { value in
                withAnimation(motion) { draft.seats[index].level = Int(value) }
            }), in: 1...10, step: 1)
                .tint(seatColor(index) ?? Theme.action)
                .accessibilityLabel("Úroveň bota")
                .accessibilityValue("\(level), \(info.persona) \(info.nickname), \(info.name)")
            HStack { Text("ZAČÁTEČNÍK"); Spacer(); Text("LEGENDA") }
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 12)
        .playerCard(seatColor(index))
        .sensoryFeedback(.selection, trigger: level)
    }
    private var rulesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if draft.config.mode == .x01 {
                ruleSection(.start, "Start", icon: "flag.fill", value: "\(draft.config.startingScore) bodů") { scoreGroup }
                ruleSection(.finish, "Zavření a otevření", icon: "checkmark.seal.fill", value: finishSummary) { finishGroup }
            }
            if draft.config.mode == .cricket {
                ruleSection(.mode, "Cricket", icon: "line.3.horizontal.decrease.circle.fill", value: draft.config.settings.cricketNoScore ? "Bez bodů" : "S body") { cricketGroup }
            }
            if draft.config.mode == .countUp {
                ruleSection(.mode, "Délka", icon: "chart.bar.fill", value: "\(draft.config.settings.countUpRounds) kol") { countUpGroup }
            }
            if draft.config.mode == .aroundClock {
                ruleSection(.mode, "Zásah", icon: "clock.fill", value: draft.config.settings.clockStyle.title) { clockGroup }
            }
            if draft.config.mode == .x01 || draft.config.mode == .cricket {
                ruleSection(.length, "Délka zápasu", icon: "trophy.fill", value: draft.config.lengthLine) { lengthGroup }
            }
            if draft.config.mode == .x01 {
                ruleSection(.limit, "Limit šipek", icon: "timer", value: limitSummary) { limitGroup }
            }
            if draft.config.mode == .x01 && draft.seats.count > 1 {
                ruleSection(.handicap, "Handicap", icon: "scalemass.fill", value: handicapSummary) { handicapGroup }
            }
            ruleSection(.flow, "Během hry", icon: "slider.horizontal.3", value: flowSummary) { flowGroup }
        }
    }

    // MARK: Souhrn

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Hrají")
                VStack(spacing: 0) {
                    ForEach(draft.seats.indices, id: \.self) { index in
                        if index > 0 { Divider().padding(.leading, 64) }
                        summaryPlayer(index)
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: draft.config.mode.shortTitle)
                VStack(spacing: 0) {
                    let rows = summaryRows
                    ForEach(rows.indices, id: \.self) { index in
                        if index > 0 { Divider().padding(.leading, 64) }
                        summaryRow(rows[index])
                    }
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
            }
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Uložit jako předvolbu", isOn: $savePreset.animation(motion)).tint(Theme.action)
                if savePreset {
                    TextField("Název předvolby", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                        .transition(.opacity)
                }
            }
            .surface()
        }
    }

    private struct SummaryRow {
        var key: RuleKey
        var icon: String
        var title: String
        var value: String
    }

    private var summaryRows: [SummaryRow] {
        var rows: [SummaryRow] = []
        switch draft.config.mode {
        case .x01:
            rows.append(SummaryRow(key: .start, icon: "flag.fill", title: "Start", value: "\(draft.config.startingScore) bodů"))
            rows.append(SummaryRow(key: .finish, icon: "checkmark.seal.fill", title: "Zavření", value: draft.config.outRule.title))
            rows.append(SummaryRow(key: .finish, icon: "door.left.hand.open", title: "Otevření", value: draft.config.doubleIn ? "Double in" : "Hned"))
        case .cricket:
            rows.append(SummaryRow(key: .mode, icon: "line.3.horizontal.decrease.circle.fill", title: "Cricket", value: draft.config.settings.cricketNoScore ? "Bez bodů" : "S body"))
        case .countUp:
            rows.append(SummaryRow(key: .mode, icon: "chart.bar.fill", title: "Délka", value: "\(draft.config.settings.countUpRounds) kol"))
        case .aroundClock:
            rows.append(SummaryRow(key: .mode, icon: "clock.fill", title: "Zásah", value: draft.config.settings.clockStyle.title))
        }
        if draft.config.mode == .x01 || draft.config.mode == .cricket {
            rows.append(SummaryRow(key: .length, icon: "trophy.fill", title: "Délka zápasu", value: draft.config.lengthLine))
        }
        if draft.config.mode == .x01 {
            rows.append(SummaryRow(key: .limit, icon: "timer", title: "Limit šipek", value: limitSummary))
        }
        if draft.config.mode == .x01 && draft.seats.count > 1 {
            rows.append(SummaryRow(key: .handicap, icon: "scalemass.fill", title: "Handicap", value: seatsHaveHandicap ? handicapSummary : "Vypnuto"))
        }
        rows.append(SummaryRow(key: .flow, icon: "slider.horizontal.3", title: "Během hry", value: flowSummary))
        return rows
    }

    private func summaryRow(_ row: SummaryRow) -> some View {
        Button { jumpToRule(row.key) } label: {
            HStack(spacing: 14) {
                Image(systemName: row.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 36, height: 36)
                    .background(Theme.action.opacity(0.12), in: Circle())
                Text(row.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(row.value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Upravit")
    }

    private func summaryPlayer(_ index: Int) -> some View {
        let seat = draft.seats[index]
        let custom = draft.config.mode == .x01 && !(seat.handicap?.isEmpty ?? true)
        return Button { setStep(1) } label: {
            HStack(spacing: 14) {
                Avatar(
                    name: seatName(index),
                    bot: seat.isBot && !isMe(index),
                    size: 36,
                    photo: isMe(index) ? store.profile?.photoJPEG : store.housemates.first { $0.id == seat.friendID }?.photoJPEG,
                    asset: seat.isBot && !isMe(index) ? BotLevel.get(seat.level).photo : nil
                )
                .playerRing(seatColor(index))
                VStack(alignment: .leading, spacing: 2) {
                    Text(seatName(index)).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(isMe(index) ? "Ty" : seat.isBot ? "Bot · úroveň \(seat.level)" : seat.friendID != nil ? "Přítel" : "Host")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if draft.config.mode == .x01 {
                    Text(seatRuleLine(index))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(custom ? Theme.onAccent : Color.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(custom ? Theme.accentFill : Color.primary.opacity(0.06), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Upravit hráče")
    }

    private func jumpToRule(_ key: RuleKey) {
        openRule = key
        setStep(2)
    }

    private func ruleSection<Content: View>(_ key: RuleKey, _ title: String, icon: String, value: String, @ViewBuilder content: () -> Content) -> some View {
        let open = openRule == key
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                commitScoreFromField()
                hideKeyboard()
                withAnimation(sectionMotion) { openRule = open ? nil : key }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(open ? Theme.onAccent : Theme.action)
                        .frame(width: 38, height: 38)
                        .background(open ? Theme.accentFill : Theme.action.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline)
                        Text(value)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(value)
            .accessibilityHint(open ? "Sbalí nastavení" : "Rozbalí nastavení")
            .padding(16)
            content()
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .padding(.top, 2)
                .opacity(open ? 1 : 0)
                .blur(radius: open || reduceMotion ? 0 : 4)
                .offset(y: open ? 0 : -8)
                .frame(height: open ? nil : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
        }
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(open ? Theme.action.opacity(0.45) : Theme.stroke, lineWidth: open ? 1.5 : 1))
        .shadow(color: .black.opacity(open ? 0.08 : 0), radius: 14, y: 6)
        .id(key)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var finishSummary: String {
        draft.config.doubleIn ? "\(draft.config.outRule.title) · Double in" : draft.config.outRule.title
    }

    private var flowSummary: String {
        var parts: [String] = []
        if draft.config.mode == .x01 && !draftAnyDoubleIn { parts.append(draft.config.settings.entry == .total ? "Součet kola" : "Každá šipka") }
        if draft.config.mode == .x01 && draft.config.settings.checkoutHints { parts.append("nápověda") }
        if draft.config.settings.keepAwake { parts.append("displej svítí") }
        return parts.isEmpty ? "Výchozí" : parts.joined(separator: " · ")
    }

    private var scoreGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(draft.config.startingScore)")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(draft.config.startingScore)))
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Start \(draft.config.startingScore) bodů")
            RuleTiles(
                options: presetScores.map { (id: $0, title: "\($0)", detail: nil) } + [(id: -1, title: "Vlastní", detail: nil)],
                selection: usingExactScore ? -1 : draft.config.startingScore,
                columns: 3
            ) { id in
                withAnimation(motion) {
                    if id == -1 {
                        scoreExact = true
                    } else {
                        scoreExact = false
                        commitScore(id)
                    }
                }
            }
            if usingExactScore {
                TextField("Skóre", text: $scoreText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onChange(of: scoreText) { _, raw in
                        let digits = String(raw.filter(\.isNumber).prefix(4))
                        if digits != raw { scoreText = digits; return }
                        if let value = Int(digits), (GameConfig.minimumScore...GameConfig.maximumScore).contains(value) {
                            draft.config.startingScore = value
                        }
                    }
                Text("Od \(GameConfig.minimumScore) do \(GameConfig.maximumScore).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var finishGroup: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Poslední šipka").font(.subheadline.weight(.semibold))
                RuleTiles(
                    options: OutRule.allCases.map { (id: $0, title: $0.shortTitle, detail: outHint($0)) },
                    selection: draft.config.outRule,
                    columns: 3,
                    alignment: .leading
                ) { rule in
                    withAnimation(motion) { draft.config.outRule = rule }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("První body").font(.subheadline.weight(.semibold))
                RuleTiles(
                    options: [
                        (id: false, title: "Hned", detail: "Počítá se každý zásah"),
                        (id: true, title: "Double in", detail: "Body až od prvního doublu")
                    ],
                    selection: draft.config.doubleIn,
                    columns: 2,
                    alignment: .leading
                ) { value in
                    withAnimation(motion) { draft.config.doubleIn = value }
                }
            }
        }
    }

    private func outHint(_ rule: OutRule) -> String {
        switch rule {
        case .double: return "Double nebo bull"
        case .straight: return "Jakýkoli zásah"
        case .master: return "Double i triple"
        }
    }

    private var limitSummary: String {
        guard let limit = draft.config.settings.dartLimit else { return "Bez limitu" }
        return "\(limit) šipek · pak rozhoz"
    }

    private var usingCustomLimit: Bool {
        guard let limit = draft.config.settings.dartLimit else { return false }
        return limitCustom || !MatchOptions.dartLimitChoices.contains(limit)
    }

    private var limitGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            RuleTiles(
                options: [(id: 0, title: "Vypnuto", detail: nil)]
                    + MatchOptions.dartLimitChoices.map { (id: $0, title: "\($0)", detail: "\($0 / 3) kol") }
                    + [(id: -1, title: "Vlastní", detail: usingCustomLimit ? "\(draft.config.settings.dartLimit ?? 0) šipek" : "kola i šipky")],
                selection: usingCustomLimit ? -1 : draft.config.settings.dartLimit ?? 0,
                columns: 3
            ) { limit in
                withAnimation(motion) {
                    limitCustom = limit == -1
                    if limit == -1 {
                        if draft.config.settings.dartLimit == nil { options.wrappedValue.dartLimit = 45 }
                    } else {
                        options.wrappedValue.dartLimit = limit == 0 ? nil : limit
                    }
                }
            }
            if usingCustomLimit, let limit = draft.config.settings.dartLimit {
                Stepper(value: Binding(
                    get: { limit / 3 },
                    set: { rounds in options.wrappedValue.dartLimit = rounds * 3 }
                ), in: MatchOptions.dartLimitRounds) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(limit / 3) kol")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(limit)))
                        Text("\(limit) šipek na hráče").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityValue("\(limit / 3) kol, \(limit) šipek")
            }
            Text(draft.config.settings.dartLimit.map { "Když leg nikdo nezavře do \($0) šipek na hráče, rozhodne rozhoz na střed. Bližší šipka bere leg." }
                 ?? "Leg se hraje, dokud ho někdo nezavře.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cricketGroup: some View {
        RuleTiles(
            options: [
                (id: false, title: "S body", detail: "Zavři čísla a měj víc bodů"),
                (id: true, title: "Bez bodů", detail: "Vyhrává, kdo první zavře")
            ],
            selection: draft.config.settings.cricketNoScore,
            columns: 2,
            alignment: .leading
        ) { value in
            withAnimation(motion) { options.wrappedValue.cricketNoScore = value }
        }
    }

    private var countUpGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            RuleTiles(options: roundChoices.map { (id: $0, title: "\($0)", detail: nil) }, selection: draft.config.settings.countUpRounds, columns: 3) { rounds in
                withAnimation(motion) { options.wrappedValue.countUpRounds = rounds }
            }
            Text("\(draft.config.settings.countUpRounds * 3) šipek na hráče.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var clockGroup: some View {
        VStack(alignment: .leading, spacing: 12) {
            RuleTiles(options: ClockStyle.allCases.map { (id: $0, title: $0.title, detail: nil) }, selection: draft.config.settings.clockStyle, columns: 3) { style in
                withAnimation(motion) { options.wrappedValue.clockStyle = style }
            }
            Text("Postupně 1–20 a nakonec bull. U doublů a triplů se bull bere jen jako 50.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lengthGroup: some View {
        let bestOf = draft.config.format == .bestOf
        let stepSize = bestOf ? 2 : 1
        let legLimit = bestOf ? 15 : 11
        return VStack(alignment: .leading, spacing: 16) {
            RuleTiles(
                options: [
                    (id: MatchFormat.firstTo, title: "First to", detail: "Kdo první získá počet"),
                    (id: MatchFormat.bestOf, title: "Best of", detail: "Většina z počtu")
                ],
                selection: draft.config.format,
                columns: 2,
                alignment: .leading
            ) { format in
                withAnimation(motion) {
                    draft.config.apply(format: format, setsShown: draft.config.shownSets, legsShown: draft.config.shownLegs)
                }
            }
            CountStepper(
                title: "Sety",
                value: draft.config.shownSets,
                caption: draft.config.playsSets ? "Zápas se dělí na sety" : "Bez setů, hraje se na legy",
                canDecrease: draft.config.shownSets > 1,
                canIncrease: draft.config.shownSets + stepSize <= 11
            ) { delta in
                withAnimation(motion) {
                    draft.config.apply(format: draft.config.format, setsShown: draft.config.shownSets + delta * stepSize, legsShown: draft.config.shownLegs)
                }
            }
            CountStepper(
                title: draft.config.playsSets ? "Legy v setu" : "Legy",
                value: draft.config.shownLegs,
                caption: bestOf ? "Bere \(draft.config.legsToWin)" : "Na \(draft.config.legsToWin) výher",
                canDecrease: draft.config.shownLegs > 1,
                canIncrease: draft.config.shownLegs + stepSize <= legLimit
            ) { delta in
                withAnimation(motion) {
                    draft.config.apply(format: draft.config.format, setsShown: draft.config.shownSets, legsShown: draft.config.shownLegs + delta * stepSize)
                }
            }
            Text(draft.config.lengthDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
    }

    // MARK: Handicap

    private var seatsHaveHandicap: Bool { draft.seats.contains { !($0.handicap?.isEmpty ?? true) } }

    private var draftAnyDoubleIn: Bool {
        guard draft.config.mode == .x01 else { return false }
        return draft.seats.contains { $0.handicap?.doubleIn ?? draft.config.doubleIn }
    }

    private var handicapSummary: String {
        let count = draft.seats.filter { !($0.handicap?.isEmpty ?? true) }.count
        switch count {
        case 0: return "Vypnuto · všichni stejně"
        case 1: return "1 hráč má jiná pravidla"
        default: return "\(count) hráči mají jiná pravidla"
        }
    }

    private func seatRuleLine(_ index: Int) -> String {
        let handicap = draft.seats[index].handicap
        var parts = ["\(handicap?.startingScore ?? draft.config.startingScore)", (handicap?.outRule ?? draft.config.outRule).shortTitle]
        if handicap?.doubleIn ?? draft.config.doubleIn { parts.append("Double in") }
        return parts.joined(separator: " · ")
    }

    private func editHandicap(_ index: Int, _ change: (inout Handicap) -> Void) {
        guard draft.seats.indices.contains(index) else { return }
        var handicap = draft.seats[index].handicap ?? Handicap()
        change(&handicap)
        withAnimation(motion) { draft.seats[index].handicap = handicap.isEmpty ? nil : handicap }
    }

    private var handicapGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Každý hráč může mít jiný start, jiné zavření nebo otevření. Co nezměníš, platí jako ve hře.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(draft.seats.indices, id: \.self) { index in
                handicapCard(index)
            }
            Button {
                hideKeyboard()
                withAnimation(motion) {
                    for index in draft.seats.indices { draft.seats[index].handicap = nil }
                }
            } label: {
                Label("Všem stejná pravidla", systemImage: "equal.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(Theme.action)
            .disabled(!seatsHaveHandicap)
            .accessibilityHint("Zruší handicap všech hráčů")
        }
    }

    private func handicapCard(_ index: Int) -> some View {
        let handicap = draft.seats[index].handicap
        let start = handicap?.startingScore
        let startSelection = start.map { presetScores.contains($0) ? $0 : -2 } ?? -1
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(seatName(index)).font(.headline).lineLimit(1)
                Spacer()
                Text(seatRuleLine(index))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(handicap == nil ? Color.secondary : Theme.onAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(handicap == nil ? Color.primary.opacity(0.06) : Theme.accentFill, in: Capsule())
            }
            Text("Start").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            OptionSwitcher(
                options: [(id: -1, title: "Jako hra")] + presetScores.map { (id: $0, title: "\($0)") },
                selection: startSelection
            ) { id in
                editHandicap(index) { $0.startingScore = id == -1 ? nil : id }
            }
            ScoreEntryField(value: start, placeholder: draft.config.startingScore) { value in
                editHandicap(index) { $0.startingScore = value == draft.config.startingScore ? nil : value }
            }
            Text("Zavření").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            OptionSwitcher(
                options: [(id: OutRule?.none, title: "Jako hra")] + OutRule.allCases.map { (id: OutRule?.some($0), title: $0.shortTitle) },
                selection: handicap?.outRule
            ) { rule in
                editHandicap(index) { $0.outRule = rule == draft.config.outRule ? nil : rule }
            }
            Text("Otevření").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            OptionSwitcher(
                options: [(id: Bool?.none, title: "Jako hra"), (id: Bool?.some(false), title: "Hned"), (id: Bool?.some(true), title: "Double in")],
                selection: handicap?.doubleIn
            ) { value in
                editHandicap(index) { $0.doubleIn = value == draft.config.doubleIn ? nil : value }
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
    private var roundChoices: [Int] {
        var values = [5, 10, 15, 20, 30]
        let current = draft.config.settings.countUpRounds
        if !values.contains(current) { values.append(current); values.sort() }
        return values
    }

    private var openingStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            openingCard("Náhodně", detail: "Los určí, kdo hází první.", symbol: "dice", mode: .random)
            openingCard("Vybrat hráče", detail: "Sám zvolíš, kdo začíná.", symbol: "person.fill", mode: .pick)
            openingCard("Rozhoz na střed", detail: "Každý hodí na střed. Červený bere před zeleným. Stejný střed se hází znovu.", symbol: "smallcircle.filled.circle", mode: .bull)
            if opening == .pick {
                OptionSwitcher(
                    options: draft.seats.indices.map { ($0, seatName($0)) },
                    selection: pickedStarter ?? -1
                ) { index in
                    withAnimation(motion) { pickedStarter = index }
                }
            }
            if opening == .bull, let bullWinner {
                Label("Začíná \(seatName(bullWinner))", systemImage: "flag.checkered")
                    .font(.headline)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.brand.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Button("Hodit znovu") { showBullOff = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func openingCard(_ title: String, detail: String, symbol: String, mode: Opening) -> some View {
        ChoiceCard(title: title, detail: detail, symbol: symbol, selected: opening == mode) {
            withAnimation(motion) {
                opening = mode
                if mode == .random { pickedStarter = nil }
                if mode == .pick, pickedStarter == nil { pickedStarter = 0 }
                if mode == .bull { showBullOff = true }
            }
        }
    }

    private var flowGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            if draft.config.mode == .x01 && !draftAnyDoubleIn {
                Picker("Zápis skóre", selection: options.entry) {
                    ForEach(EntryStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Text(draft.config.settings.entry == .total ? "Napíšeš součet kola. Při zavření potvrdíš počet šipek." : "Každá šipka se zapíše hned a třetí předá tah.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label("Zápis po jednotlivých šipkách", systemImage: "scope")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if draft.seats.contains(where: \.isBot) {
                Picker("Tempo šipek bota", selection: options.botDelay) {
                    Text("Rychlé").tag(0.5)
                    Text("Plynulé").tag(1.5)
                    Text("Klidné").tag(3.0)
                }
                .pickerStyle(.segmented)
            }
            if draft.config.mode == .x01 { Toggle("Nápověda zavření", isOn: options.checkoutHints).tint(Theme.action) }
            Toggle("Nezhasínat displej", isOn: options.keepAwake).tint(Theme.action)
        }
    }

    private func commitScore(_ value: Int) {
        draft.config.startingScore = value
        scoreText = "\(value)"
    }

    private func advance() {
        commitScoreFromField()
        if !isLastStep { setStep(step + 1) }
        else if store.activeMatch != nil { replace = true }
        else { start() }
    }

    private func commitScoreFromField() {
        if let value = Int(scoreText), (GameConfig.minimumScore...GameConfig.maximumScore).contains(value) {
            draft.config.startingScore = value
        }
        scoreText = "\(draft.config.startingScore)"
    }

    private func setStep(_ value: Int) {
        commitScoreFromField()
        withAnimation(motion) { step = value }
    }
    private func seatName(_ i: Int) -> String {
        if isMe(i) { return store.profile?.name ?? "Já" }
        let seat = draft.seats[i]
        return seat.isBot ? botPersona(i) : seat.name
    }
    private func start() {
        guard makeMatch() else { return }
        launchIntro = true; live = true
    }

    private func makeMatch() -> Bool {
        guard let profile = store.profile, canContinue else { return false }
        for i in draft.seats.indices where !isMe(i) && !draft.seats[i].isBot && draft.seats[i].friendID == nil {
            draft.seats[i].friendID = store.addFriend(draft.seats[i].name)?.id
        }
        var players: [Player] = []
        for i in draft.seats.indices {
            let seat = draft.seats[i]
            if isMe(i) {
                players.append(Player(id: profile.id, name: profile.name))
            } else {
                let name = seat.isBot ? seatName(i) : String(seat.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
                players.append(Player(id: seat.isBot ? UUID() : seat.friendID ?? UUID(), name: name, botLevel: seat.isBot ? seat.level : nil))
            }
        }
        guard !players.isEmpty else { return false }
        store.notePlayed(with: draft.seats.compactMap(\.friendID))
        if [.aroundClock, .countUp].contains(draft.config.mode) {
            draft.config.legsToWin = 1
            draft.config.setsToWin = 1
        }
        draft.config.startingScore = min(GameConfig.maximumScore, max(GameConfig.minimumScore, draft.config.startingScore))
        draft.config.handicaps = draft.config.mode == .x01 && seatsHaveHandicap ? draft.seats.map { $0.handicap ?? Handicap() } : nil
        let first = openingPlayer(count: players.count)
        draft.starter = opening == .random ? -1 : first
        store.remember(draft)
        if savePreset { store.addPreset(name: presetName, setup: draft); savePreset = false }
        store.activeMatch = Match(config: draft.config, players: players, firstPlayer: first)
        store.feedback()
        return true
    }

    private func openingPlayer(count: Int) -> Int {
        guard count > 1 else { return 0 }
        switch opening {
        case .pick: return min(max(0, pickedStarter ?? 0), count - 1)
        case .bull: return min(max(0, bullWinner ?? 0), count - 1)
        case .random, nil: return Int.random(in: 0..<count)
        }
    }
}
struct ChoiceCard: View {
    var title: String; var detail: String; var symbol: String; var selected: Bool; var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: symbol).font(.title2).frame(width: 46, height: 52).foregroundStyle(Theme.action)
                VStack(alignment: .leading, spacing: 7) { Text(title).font(.title3.bold()); Text(detail).font(.caption).foregroundStyle(.secondary) }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.action : .secondary)
                    .contentTransition(.symbolEffect(.replace))
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

private extension View {
    /// Kroužek v barvě hráče kolem avataru.
    func playerRing(_ color: Color?) -> some View {
        padding(color == nil ? 0 : 3)
            .overlay {
                if let color { Circle().strokeBorder(color, lineWidth: 3) }
            }
    }

    /// Karta hráče s nádechem a rámečkem v jeho barvě.
    func playerCard(_ color: Color?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return background {
            ZStack(alignment: .leading) {
                Theme.card
                if let color { color.opacity(0.10) }
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(color?.opacity(0.55) ?? Theme.stroke, lineWidth: color == nil ? 1 : 1.5))
        .animation(.easeInOut(duration: 0.25), value: color)
    }
}

/// Mřížka velkých voleb s volitelným popiskem.
struct RuleTiles<ID: Hashable>: View {
    var options: [(id: ID, title: String, detail: String?)]
    var selection: ID
    var columns: Int
    var alignment: HorizontalAlignment = .center
    var onSelect: (ID) -> Void

    var body: some View {
        let tall = options.contains { $0.detail != nil }
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(options, id: \.id) { option in
                let selected = option.id == selection
                Button { onSelect(option.id) } label: {
                    VStack(alignment: alignment, spacing: 3) {
                        Text(option.title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if let detail = option.detail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(selected ? Color.black.opacity(0.7) : Color.secondary)
                                .multilineTextAlignment(alignment == .center ? .center : .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: tall ? 66 : 50, alignment: Alignment(horizontal: alignment, vertical: .center))
                    .foregroundStyle(selected ? Color.black : Color.primary)
                    .background(selected ? Theme.brand : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// Libovolné startovní skóre. Prázdné pole znamená stejně jako hra.
struct ScoreEntryField: View {
    var value: Int?
    var placeholder: Int
    var onCommit: (Int?) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    private var range: ClosedRange<Int> { GameConfig.minimumScore...GameConfig.maximumScore }
    private var invalid: Bool { Int(text).map { !range.contains($0) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vlastní číslo").font(.subheadline.weight(.semibold))
                    Text(invalid ? "Jen \(range.lowerBound) až \(range.upperBound)" : "Napiš jakýkoli start")
                        .font(.caption)
                        .foregroundStyle(invalid ? Color.red : Color.secondary)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 8)
                TextField("\(placeholder)", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .focused($focused)
                    .frame(width: 104, height: 46)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                    .overlay(Capsule().stroke(invalid ? Color.red : (focused ? Theme.action : Color.clear), lineWidth: 1.5))
                    .accessibilityLabel("Vlastní start")
            }
        }
        .onAppear { text = value.map(String.init) ?? "" }
        .onChange(of: value) { _, new in
            if !focused { text = new.map(String.init) ?? "" }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = value.map(String.init) ?? "" }
        }
        .onChange(of: text) { _, raw in
            let digits = String(raw.filter(\.isNumber).prefix(4))
            if digits != raw { text = digits; return }
            guard focused else { return }
            if digits.isEmpty { onCommit(nil) }
            else if let number = Int(digits), range.contains(number) { onCommit(number) }
        }
    }
}

/// Velké číslo s tlačítky minus a plus.
struct CountStepper: View {
    var title: String
    var value: Int
    var caption: String
    var canDecrease: Bool
    var canIncrease: Bool
    var onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(caption).font(.caption).foregroundStyle(.secondary).contentTransition(.opacity)
            }
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton("minus", enabled: canDecrease, label: "Méně") { onStep(-1) }
                Text("\(value)")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .frame(minWidth: 52)
                    .contentTransition(.numericText(value: Double(value)))
                stepButton("plus", enabled: canIncrease, label: "Více") { onStep(1) }
            }
            .padding(3)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrease { onStep(1) }
            case .decrement: if canDecrease { onStep(-1) }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.4))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// Stejný přepínač pro skóre, zavření, formát, sety i legy.
struct OptionSwitcher<ID: Hashable>: View {
    var options: [(id: ID, title: String)]
    var selection: ID
    var onSelect: (ID) -> Void

    var body: some View {
        let compact = options.count <= 3
        Group {
            if compact {
                HStack(spacing: 4) { chips }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) { chips }
                    }
                    .onAppear { proxy.scrollTo(selection, anchor: .center) }
                    .onChange(of: selection) { _, id in
                        withAnimation(.smooth(duration: 0.28)) { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .sensoryFeedback(.selection, trigger: selection)
    }

    @ViewBuilder private var chips: some View {
        ForEach(options, id: \.id) { option in
            let selected = option.id == selection
            Button { onSelect(option.id) } label: {
                Text(option.title)
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: options.count <= 3 ? .infinity : nil)
                    .frame(minHeight: 40)
                    .foregroundStyle(selected ? .black : .primary)
                    .background(selected ? Theme.brand : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .id(option.id)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

private struct BullShot: Identifiable {
    let id = UUID()
    let player: Int
    let dart: Dart
}

/// Body a přímky leží mimo `scaleEffect`, aby při přiblížení zůstaly stejně velké.
private struct BullPins: View, Animatable {
    struct Pin {
        var x: Double
        var y: Double
        var color: Color
        var closest: Bool
    }

    var zoom: CGFloat
    var pins: [Pin]

    var animatableData: CGFloat {
        get { zoom }
        set { zoom = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) * 0.43 * zoom
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for pin in pins {
                let end = CGPoint(x: center.x + pin.x * radius, y: center.y + pin.y * radius)
                var line = Path()
                line.move(to: center)
                line.addLine(to: end)
                context.stroke(line, with: .color(.black.opacity(0.55)), style: StrokeStyle(lineWidth: pin.closest ? 5 : 4, lineCap: .round))
                context.stroke(line, with: .color(pin.color), style: StrokeStyle(lineWidth: pin.closest ? 3 : 2, lineCap: .round))
                let dot = CGRect(x: end.x - 7, y: end.y - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: dot), with: .color(pin.color))
                context.stroke(Path(ellipseIn: dot), with: .color(.black.opacity(0.7)), lineWidth: 1.5)
            }
            if !pins.isEmpty {
                let hub = CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6)
                context.fill(Path(ellipseIn: hub), with: .color(.white))
            }
        }
    }
}

/// Rozhoz na střed. Červený střed je výš než zelený. Stejný výsledek se hází znovu v opačném pořadí.
/// Určí, kdo začíná, nebo rozhodne leg po vypršení limitu šipek.
struct BullOffView: View {
    enum Purpose { case opening, decider }
    var names: [String]
    var bots: [Int?]
    var purpose: Purpose = .opening
    var onFinish: (Int) -> Void
    var onCancel: () -> Void

    @State private var order: [Int]
    @State private var shots: [BullShot] = []
    @State private var winner: Int?
    @State private var note: String?
    /// Každé kolo hodů má vlastní číslo, aby bot hodil i tehdy, když začíná stejný hráč.
    @State private var round = 0
    /// Remíza je vidět chvíli na terči, než začne další kolo.
    @State private var tieShown = false
    /// 1, dokud nehodí všichni. Pak se plynule přiblíží na rozdíl hodů.
    @State private var shownZoom: CGFloat = 1

    init(names: [String], bots: [Int?], purpose: Purpose = .opening, onFinish: @escaping (Int) -> Void, onCancel: @escaping () -> Void) {
        self.names = names
        self.bots = bots
        self.purpose = purpose
        self.onFinish = onFinish
        self.onCancel = onCancel
        _order = State(initialValue: Array(names.indices))
    }

    private var pending: [Int] {
        let done = Set(shots.map(\.player))
        return order.filter { !done.contains($0) }
    }
    private var current: Int? { winner == nil && !tieShown ? pending.first : nil }

    private var headline: String {
        if let winner { return "Blíž je \(name(winner))" }
        if tieShown { return "Remíza" }
        if let current { return "Hází \(name(current))" }
        return "Rozhoz na střed"
    }

    private var subline: String {
        if let note { return note }
        if winner != nil { return "\(purpose == .decider ? "Leg bere" : "Začíná") \(name(winner ?? 0)). Terč je přiblížený na rozdíl hodů." }
        if shots.isEmpty {
            let tap = "Klepni tam, kam šipka dopadla. Přímka je v procentech poloměru."
            return purpose == .decider ? "Limit šipek vypršel a nikdo nezavřel. Leg rozhodne bližší šipka. \(tap)" : tap
        }
        return "Červený střed bere před zeleným."
    }

    /// Přiblížení až ve chvíli, kdy hodili všichni. Do té doby zůstává celý terč.
    private var targetZoom: CGFloat {
        guard pending.isEmpty, !shots.isEmpty else { return 1 }
        let farthest = shots.compactMap { shot -> Double? in
            guard let x = shot.dart.x, let y = shot.dart.y else { return nil }
            return hypot(x, y)
        }.max() ?? 1
        guard farthest > 0.02 else { return 1 }
        return CGFloat(min(6, max(1, 0.78 / farthest)))
    }

    private var rankedShots: [(player: Int, dart: Dart, rank: Int)] {
        shots.map { (player: $0.player, dart: $0.dart, rank: rank($0.dart)) }
            .sorted { $0.rank < $1.rank }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                header
                TouchDartboard(marks: [], interactive: humanTurn) { dart in
                    guard let current, humanTurn else { return }
                    record(dart, player: current)
                }
                .scaleEffect(shownZoom, anchor: .center)
                .overlay {
                    BullPins(
                        zoom: shownZoom,
                        pins: shots.compactMap { shot in
                            guard let x = shot.dart.x, let y = shot.dart.y, x.isFinite, y.isFinite else { return nil }
                            return BullPins.Pin(x: x, y: y, color: color(shot.player), closest: rankedShots.count > 1 && rank(shot.dart) == rankedShots.first?.rank)
                        }
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít", action: onCancel)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Znovu", action: reset)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button(purpose == .decider ? "Potvrdit" : "Hrát") { if let winner { onFinish(winner) } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.brand)
                        .foregroundStyle(.black)
                        .disabled(winner == nil)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onChange(of: targetZoom) { _, new in
            withAnimation(.smooth(duration: 1.05)) { shownZoom = new }
        }
        .task(id: "\(round)-\(current ?? -1)") {
            guard let current, bots.indices.contains(current), let level = bots[current], winner == nil else { return }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled, self.current == current, winner == nil else { return }
            record(botDart(level: level), player: current)
        }
        .task(id: tieShown ? round : -1) {
            guard tieShown else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, tieShown else { return }
            withAnimation(.smooth(duration: 0.45)) {
                order = Array(order.reversed())
                shots = []
                tieShown = false
                round += 1
                note = "Hází se znovu v opačném pořadí. Začíná \(name(order.first ?? 0))."
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(headline)
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(subline)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            if !rankedShots.isEmpty {
                HStack(spacing: 8) {
                    ForEach(rankedShots, id: \.player) { item in
                        let closest = item.rank == rankedShots.first?.rank
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Circle().fill(color(item.player)).frame(width: 10, height: 10)
                                Text(name(item.player))
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)
                            }
                            Text(measureText(item.dart))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.8))
                            if rankedShots.count > 1 {
                                Text(closest && rankedShots.allSatisfy { $0.rank == item.rank } ? "stejně" : (closest ? "blíž" : "dál"))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(closest ? Color(red: 0.30, green: 0.90, blue: 0.55) : .white.opacity(0.55))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(.white.opacity(closest ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
            }
        }
    }

    private func color(_ player: Int) -> Color { Theme.playerColor(player) }

    private func reset() {
        order = Array(names.indices)
        shots = []
        winner = nil
        note = nil
        tieShown = false
        round += 1
    }

    private var humanTurn: Bool {
        guard let current, bots.indices.contains(current) else { return false }
        return bots[current] == nil && winner == nil
    }

    private func name(_ player: Int) -> String {
        names.indices.contains(player) ? names[player] : "Hráč"
    }

    private func measureText(_ dart: Dart) -> String {
        if dart.segment == 25 { return dart.multiplier == 2 ? "červený střed" : "zelený střed" }
        guard let x = dart.x, let y = dart.y, hypot(x, y) <= 1 else { return "mimo terč" }
        return "\(rank(dart) - 100) % poloměru"
    }

    private func record(_ dart: Dart, player: Int) {
        guard winner == nil, current == player else { return }
        shots.append(BullShot(player: player, dart: dart))
        resolveIfComplete()
    }

    private func resolveIfComplete() {
        guard winner == nil, !tieShown, pending.isEmpty, !order.isEmpty else { return }
        let scored = order.compactMap { player -> (player: Int, rank: Int)? in
            guard let shot = shots.last(where: { $0.player == player }) else { return nil }
            return (player, rank(shot.dart))
        }
        guard let best = scored.map(\.rank).min() else { return }
        let leaders = order.filter { player in scored.first { $0.player == player }?.rank == best }
        if leaders.count == 1 {
            winner = leaders[0]
        } else {
            note = replayNote(best: best, count: leaders.count)
            order = leaders
            tieShown = true
        }
    }

    private func replayNote(best: Int, count: Int) -> String {
        let again = "Hází se znovu, opačné pořadí."
        if best == 0 { return count == 2 ? "Oba červený střed. \(again)" : "Stejný červený střed. \(again)" }
        if best == 1 { return count == 2 ? "Oba zelený střed. \(again)" : "Stejný zelený střed. \(again)" }
        return "Stejná vzdálenost. \(again)"
    }

    /// Nižší číslo vyhrává. Červený střed je výš než zelený, oba jsou výš než zbytek terče.
    private func rank(_ dart: Dart) -> Int {
        if dart.segment == 25 { return dart.multiplier == 2 ? 0 : 1 }
        guard let x = dart.x, let y = dart.y, x.isFinite, y.isFinite else { return 10_000 }
        let radius = hypot(x, y)
        if radius > 1 { return 9_000 }
        return 100 + Int((radius * 100).rounded())
    }

    private func botDart(level: Int) -> Dart {
        let spread = max(0.05, 0.75 - Double(min(10, max(1, level))) * 0.065)
        let radius = sqrt(Double.random(in: 0...1)) * spread
        let angle = Double.random(in: 0..<(2 * Double.pi))
        return BoardGeometry.hit(x: cos(angle) * radius, y: sin(angle) * radius)
    }
}
