import SwiftUI

/// Výsledek modalu — druh ghosta a případně konkrétní zápas.
struct GhostSelection: Equatable {
    var kind: GhostKind
    var matchID: UUID?
}

/// Výběr ghosta podle kategorií, přesného zápasu a odemčeného Zrcadla stylu.
struct GhostPickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var startingScore: Int
    var outRule: OutRule
    var initialKind: GhostKind?
    var initialMatchID: UUID?
    var title: String = "Vyber ghosta"
    var confirmTitle: String = "Potvrdit"
    var onConfirm: (GhostSelection) -> Void

    @State private var selectedKind: GhostKind?
    @State private var selectedMatchID: UUID?
    @State private var appeared = false
    @State private var showInfo = false

    private var catalogOffers: [GhostOffer] {
        store.ghostOffers(startingScore: startingScore, outRule: outRule)
    }
    private var matchOffers: [GhostOffer] {
        store.ghostMatchCandidates(startingScore: startingScore, outRule: outRule)
    }
    private var selectedOffer: GhostOffer? {
        guard let selectedKind else { return nil }
        if selectedKind == .pickMatch {
            return matchOffers.first { $0.sourceID == selectedMatchID }
        }
        return catalogOffers.first { $0.kind == selectedKind && !$0.locked }
    }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.28) }
    private var canConfirm: Bool { selectedOffer != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    hero
                    if catalogOffers.isEmpty && matchOffers.isEmpty {
                        emptyCard
                    } else {
                        ForEach(GhostCategory.allCases.filter { $0 != .match }) { category in
                            let items = catalogOffers.filter { $0.kind.category == category }
                            if !items.isEmpty {
                                section(category.title, items: items)
                            }
                        }
                        if !matchOffers.isEmpty {
                            matchSection
                        }
                    }
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .accessibilityLabel("Co je Ghost hra")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { confirmBar }
            .sheet(isPresented: $showInfo) {
                GhostInfoSheet()
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            restoreSelection()
            withAnimation(motion) { appeared = true }
        }
        .sensoryFeedback(.selection, trigger: selectedKind)
        .animation(motion, value: selectedKind)
        .animation(motion, value: selectedMatchID)
    }

    private func restoreSelection() {
        if let initialKind {
            if initialKind == .pickMatch, let initialMatchID, matchOffers.contains(where: { $0.sourceID == initialMatchID }) {
                selectedKind = .pickMatch
                selectedMatchID = initialMatchID
                return
            }
            if catalogOffers.contains(where: { $0.kind == initialKind && !$0.locked }) {
                selectedKind = initialKind
                return
            }
        }
        if let first = catalogOffers.first(where: { !$0.locked }) {
            selectedKind = first.kind
        } else if let firstMatch = matchOffers.first {
            selectedKind = .pickMatch
            selectedMatchID = firstMatch.sourceID
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.action.opacity(0.14))
                    .frame(width: 132, height: 132)
                if let photo = store.profile?.photoJPEG {
                    Avatar(name: store.profile?.name ?? "Ghost", size: 120, photo: photo)
                        .opacity(0.92)
                        .overlay { Circle().strokeBorder(Theme.brand.opacity(0.55), lineWidth: 2) }
                } else {
                    Image(systemName: selectedKind?.symbol ?? "person.fill.viewfinder")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(Theme.action)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            .opacity(appeared || reduceMotion ? 1 : 0)
            .shadow(color: Theme.action.opacity(0.25), radius: 16, y: 6)

            VStack(spacing: 5) {
                Text(selectedKind?.title ?? "Ghost")
                    .font(.title2.bold())
                    .contentTransition(.opacity)
                if let offer = selectedOffer {
                    Text("Průměr \(offer.averageText)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.action)
                    if let note = offer.styleNote, !note.isEmpty {
                        Text(note)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text(selectedKind?.detail ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else if let locked = catalogOffers.first(where: { $0.kind == selectedKind && $0.locked }) {
                    Text(locked.unlockHint ?? "Zatím zamčeno")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Přehraje tvoje skutečné šipky z historie")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Zatím žádný ghost", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Theme.action)
            Text("Nejdřív dohraj jeden X01 se startem \(startingScore) a \(outRule.title). Po \(GhostMode.mirrorUnlockCount) zápasech se odemkne Zrcadlo stylu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func section(_ title: String, items: [GhostOffer]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ForEach(items) { offer in
                optionRow(offer)
            }
        }
    }

    private var matchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(GhostCategory.match.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text("Vyber přesný zápas — ghost přehraje jeho šipky.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(matchOffers) { offer in
                let isOn = selectedKind == .pickMatch && selectedMatchID == offer.sourceID
                Button {
                    withAnimation(motion) {
                        selectedKind = .pickMatch
                        selectedMatchID = offer.sourceID
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(isOn ? Color.black : Theme.action)
                            .frame(width: 44, height: 44)
                            .background((isOn ? Color.black : Theme.action).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(offer.styleNote ?? "Zápas")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(isOn ? Color.black : Color.primary)
                            Text("Průměr \(offer.averageText)")
                                .font(.caption)
                                .foregroundStyle(isOn ? Color.black.opacity(0.65) : Color.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isOn ? Color.black : Color.secondary)
                    }
                    .padding(14)
                    .background(isOn ? Theme.brand : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(isOn ? Color.clear : Theme.stroke, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }

    private func optionRow(_ offer: GhostOffer) -> some View {
        let isOn = selectedKind == offer.kind && offer.kind != .pickMatch
        return Button {
            guard !offer.locked else {
                withAnimation(motion) { selectedKind = offer.kind }
                return
            }
            withAnimation(motion) {
                selectedKind = offer.kind
                selectedMatchID = nil
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: offer.kind.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(offer.locked ? Color.secondary : (isOn ? Color.black : Theme.action))
                    .frame(width: 44, height: 44)
                    .background(
                        (offer.locked ? Color.secondary : (isOn ? Color.black : Theme.action)).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(offer.kind.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(offer.locked ? Color.secondary : (isOn ? Color.black : Color.primary))
                        if offer.locked {
                            Text("ZAMČENO")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                        }
                    }
                    Text(offer.locked
                         ? (offer.unlockHint ?? "Zatím nedostupné")
                         : (offer.styleNote.map { "\($0) · \(offer.kind.detail)" } ?? "\(offer.averageText) průměr · \(offer.kind.detail)"))
                        .font(.caption)
                        .foregroundStyle(isOn && !offer.locked ? Color.black.opacity(0.65) : Color.secondary)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                if !offer.locked {
                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Color.black : Color.secondary)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(isOn && !offer.locked ? Theme.brand : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isOn && !offer.locked ? Color.clear : Theme.stroke, lineWidth: 1)
            )
            .opacity(offer.locked ? 0.85 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityLabel("\(offer.kind.title)\(offer.locked ? ", zamčeno" : ", průměr \(offer.averageText)")")
    }

    private var confirmBar: some View {
        GlassEffectContainer(spacing: 10) {
            Button {
                guard let kind = selectedKind, let offer = selectedOffer else { return }
                onConfirm(GhostSelection(kind: kind, matchID: kind == .pickMatch ? offer.sourceID : nil))
                dismiss()
            } label: {
                Text(confirmTitle)
                    .font(.headline)
                    .foregroundStyle(canConfirm ? Theme.onAccent : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(canConfirm ? .regular.tint(Theme.brand).interactive() : .regular, in: Capsule())
            .disabled(!canConfirm)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }
}

/// Vysvětlení Ghost režimu — otevře se z info tlačítka vedle Zavřít.
struct GhostInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    block(
                        title: "Co je Ghost",
                        text: "Ghost přehraje tvoje skutečné šipky z historie proti tobě. Nejde o bota s náhodou — u většiny variant jde o záznam konkrétního zápasu, který jsi už odehrál."
                    )
                    block(
                        title: "Dnes, včera a forma",
                        text: "Dnešní / včerejší já bere poslední X01 z daného dne. Poslední zápas je nejnovější. Nejlepší týden a měsíc hledají nejvyšší průměr v tom období — vždy se stejným startem a pravidlem out."
                    )
                    block(
                        title: "Rekordy",
                        text: "Nejlepší zápas je tvoje maximum průměru. Překonej PB hraje stejný ghost a v zápase sleduješ, jestli svůj průměr překonáš."
                    )
                    block(
                        title: "Přesný zápas",
                        text: "Vybereš konkrétní zápas ze seznamu. Ghost hodí přesně ty šipky, které v něm padly — návštěva po návštěvě."
                    )
                    block(
                        title: "Zrcadlo stylu",
                        text: "Po \(GhostMode.mirrorUnlockCount) X01 se stejným startem se odemkne chytrý ghost. Učí se z každého dalšího zápasu: průměr průměrů (EMA), oblíbené doubly, úspěšnost zavírání a typické sehrávky. Čím víc hraješ, tím vyšší je „učení %“ a tím jistěji hraje podle tvého stylu — ne podle jednoho záznamu."
                    )
                    block(
                        title: "Pravidla",
                        text: "Ghost funguje jen v X01. Nabídky vždy odpovídají zvolenému startu (např. 501) a zavření (double / straight / master). Bez historie se stejným nastavením ghost nejde spustit."
                    )
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Ghost hra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Hraješ proti sobě", systemImage: "person.fill.viewfinder")
                .font(.title3.bold())
                .foregroundStyle(Theme.action)
            Text("Vybereš, které „já z minulosti“ má stát na druhé straně terče.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    private func block(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview {
    GhostPickerSheet(startingScore: 501, outRule: .double, initialKind: .best, onConfirm: { _ in })
        .dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
