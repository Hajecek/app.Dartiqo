import SwiftUI

/// Před rozhodujícím legem: kdo hází první.
struct DecidingLegStarterView: View {
    enum Choice: String, Identifiable {
        case matchOpener, bull, random, pick
        var id: String { rawValue }
    }

    var names: [String]
    var bots: [Int?]
    var picks: [StarterPick]
    var openingStarter: Int
    var onFinish: (Int) -> Void

    @State private var choice: Choice = .matchOpener
    @State private var picked: Int?
    @State private var showBull = false
    @State private var showPick = false
    @State private var showToss = false

    private var openerName: String {
        names.indices.contains(openingStarter) ? names[openingStarter] : "hráč"
    }

    private var readyPlayer: Int? {
        switch choice {
        case .matchOpener: return openingStarter
        case .pick: return picked
        case .bull, .random: return nil
        }
    }

    private var continueTitle: String {
        if let readyPlayer, names.indices.contains(readyPlayer) {
            return "Začíná \(names[readyPlayer])"
        }
        switch choice {
        case .bull: return "Rozhoz na střed"
        case .random: return "Losovat"
        case .pick: return "Vybrat hráče"
        case .matchOpener: return "Pokračovat"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.top, 28)
                    .padding(.bottom, 20)
                ScrollView {
                    VStack(spacing: 12) {
                        card(
                            .matchOpener,
                            title: "Jako na začátku",
                            detail: "Začíná \(openerName) — kdo házel první v zápase.",
                            symbol: "flag.checkered"
                        )
                        card(
                            .bull,
                            title: "Rozhoz na střed",
                            detail: "Každý hodí na střed. Bližší šipka začíná.",
                            symbol: "smallcircle.filled.circle"
                        )
                        card(
                            .random,
                            title: "Náhodně",
                            detail: "Los mincí určí, kdo hází první.",
                            symbol: "dice"
                        )
                        card(
                            .pick,
                            title: "Vybrat hráče",
                            detail: pickedName.map { "Zvoleno: \($0)" } ?? "Sám zvolíš, kdo začíná.",
                            symbol: "person.fill"
                        )
                    }
                    .padding(.bottom, 16)
                }
                confirm
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Rozhodující leg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled()
        .fullScreenCover(isPresented: $showBull) {
            BullOffView(
                names: names,
                bots: bots,
                purpose: .opening,
                onFinish: { winner in
                    showBull = false
                    onFinish(winner)
                },
                onCancel: { showBull = false }
            )
        }
        .fullScreenCover(isPresented: $showPick) {
            StarterPickerView(players: picks, initial: picked ?? openingStarter) { winner in
                picked = winner
                choice = .pick
                showPick = false
                onFinish(winner)
            } onCancel: {
                showPick = false
            }
        }
        .fullScreenCover(isPresented: $showToss) {
            CoinTossView(players: coinPlayers) { winner in
                showToss = false
                onFinish(winner)
            } onCancel: {
                showToss = false
            }
        }
    }

    private var pickedName: String? {
        guard let picked, names.indices.contains(picked) else { return nil }
        return names[picked]
    }

    private var coinPlayers: [CoinTossPlayer] {
        picks.map {
            CoinTossPlayer(id: $0.id, name: $0.name, photo: $0.photo, asset: $0.asset, bot: $0.bot, tint: $0.tint)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Rozhodující leg")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Kdo hází první? Předvolené je jako na začátku zápasu.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirm: some View {
        Button(action: continueTapped) {
            Label(continueTitle, systemImage: choice == .matchOpener || readyPlayer != nil ? "flag.checkered" : "arrow.right")
                .font(.headline)
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Theme.brand).interactive(), in: Capsule())
    }

    private func card(_ mode: Choice, title: String, detail: String, symbol: String) -> some View {
        let selected = choice == mode
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        // Značková žlutá je vidět ve světlém i tmavém režimu — ne `Theme.action` (ve světlém je černá).
        let accent = Theme.brand
        return Button {
            withAnimation(.smooth(duration: 0.22)) {
                choice = mode
                if mode == .pick { showPick = true }
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 46, height: 52)
                    .foregroundStyle(selected ? accent : Theme.action)
                VStack(alignment: .leading, spacing: 7) {
                    Text(title).font(.title3.bold())
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? accent : .secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? accent.opacity(0.22) : Theme.card, in: shape)
            .overlay(shape.strokeBorder(selected ? accent : Theme.stroke, lineWidth: selected ? 2 : 1))
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func continueTapped() {
        switch choice {
        case .matchOpener:
            onFinish(openingStarter)
        case .pick:
            if let picked {
                onFinish(picked)
            } else {
                showPick = true
            }
        case .bull:
            showBull = true
        case .random:
            showToss = true
        }
    }

}
