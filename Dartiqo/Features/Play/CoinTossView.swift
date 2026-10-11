import SwiftUI

struct CoinTossPlayer: Identifiable, Equatable {
    var id: Int
    var name: String
    var photo: Data?
    var asset: String?
    var bot: Bool
    var tint: Color
}

/// Los mincí — líc jeden hráč, rub druhý. Točení přes Animatable, ať jsou vidět obě fotky.
struct CoinTossView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var players: [CoinTossPlayer]
    var onFinish: (Int) -> Void
    var onCancel: () -> Void

    @State private var faceA = 0
    @State private var faceB = 1
    @State private var degrees: Double = 0
    @State private var lift: CGFloat = 0
    @State private var spinToken = 0
    @State private var spinning = false
    @State private var settled = false
    @State private var winner: Int?
    @State private var appeared = false

    private var playerA: CoinTossPlayer? { players.indices.contains(faceA) ? players[faceA] : nil }
    private var playerB: CoinTossPlayer? { players.indices.contains(faceB) ? players[faceB] : nil }
    private var winnerPlayer: CoinTossPlayer? {
        guard let winner, players.indices.contains(winner) else { return nil }
        return players[winner]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer(minLength: 10)
                header
                Spacer(minLength: 28)
                coinStage
                Spacer(minLength: 24)
                resultLine
                Spacer(minLength: 14)
                actions
                    .padding(.bottom, 10)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    Theme.background
                    RadialGradient(
                        colors: [Theme.brand.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 20,
                        endRadius: 420
                    )
                }
                .ignoresSafeArea()
            }
            .navigationTitle("Los mincí")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít", action: onCancel)
                }
            }
        }
        .sensoryFeedback(.impact(flexibility: .solid, intensity: 1), trigger: settled)
        .onAppear {
            pinFaces()
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.4)) { appeared = true }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 280_000_000)
                guard spinToken == 0 else { return }
                toss()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(settled ? "Začíná" : "Los")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(settled ? (winnerPlayer?.name ?? "Hráč") : "Hod mincí")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.smooth(duration: 0.3), value: settled)
        }
    }

    private var coinStage: some View {
        ZStack {
            Ellipse()
                .fill(.black.opacity(0.32))
                .frame(width: 170, height: 32)
                .blur(radius: 8)
                .offset(y: 132)
                .scaleEffect(x: max(0.55, 1 - abs(lift) / 160), y: 1)
                .opacity(spinning ? 0.4 : 0.65)

            Coin3D(
                degrees: degrees,
                front: playerA,
                back: playerB
            )
            .frame(width: 220, height: 220)
            .offset(y: lift)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
            .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .frame(height: 290)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessLabel)
    }

    private var accessLabel: String {
        if settled, let winnerPlayer { return "Začíná \(winnerPlayer.name)" }
        if let a = playerA, let b = playerB {
            return "Mince. Líc \(a.name), rub \(b.name)."
        }
        return "Mince"
    }

    private var resultLine: some View {
        Text(settled ? "\(winnerPlayer?.name ?? "Hráč") hází první" : " ")
            .font(.title3.weight(.semibold))
            .frame(minHeight: 28)
            .opacity(settled ? 1 : 0)
            .animation(.smooth(duration: 0.3), value: settled)
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                Button { toss() } label: {
                    Label(settled ? "Opakovat los" : "Hodit znovu", systemImage: "arrow.trianglehead.2.clockwise")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
                .disabled(spinning)
                .opacity(spinning ? 0.55 : 1)

                Button {
                    guard let winner else { return }
                    onFinish(winner)
                } label: {
                    Label("Začít hru", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(settled ? Theme.onAccent : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(settled ? .regular.tint(Theme.brand).interactive() : .regular, in: Capsule())
                .disabled(!settled || spinning)
            }
        }
    }

    /// Od první chvíle: strana A = hráč 0, strana B = hráč 1 (u 2 hráčů).
    private func pinFaces() {
        guard players.count >= 2 else {
            faceA = 0
            faceB = 0
            return
        }
        if players.count == 2 {
            faceA = 0
            faceB = 1
        } else {
            var pool = Array(players.indices)
            pool.shuffle()
            faceA = pool[0]
            faceB = pool[1]
        }
    }

    private func toss() {
        guard players.count >= 2, !spinning else { return }

        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            degrees = ((degrees.truncatingRemainder(dividingBy: 360)) + 360).truncatingRemainder(dividingBy: 360)
        }

        spinToken += 1
        let token = spinToken
        settled = false
        spinning = true
        winner = nil

        let landFront = Bool.random()
        let picked = landFront ? faceA : faceB

        // Každých 180° = půlotáčka a výměna strany. Sudé → líc, liché → rub.
        var halves = Int.random(in: 17...23)
        if landFront && !halves.isMultiple(of: 2) { halves += 1 }
        if !landFront && halves.isMultiple(of: 2) { halves += 1 }

        let start = degrees
        let target = start + Double(halves) * 180
        let duration = reduceMotion ? 0.4 : 3.0

        if reduceMotion {
            degrees = target
            lift = 0
        } else {
            withAnimation(.easeOut(duration: 0.3)) { lift = -88 }
            withAnimation(.timingCurve(0.12, 0.78, 0.14, 1.0, duration: duration)) {
                degrees = target
            }
            withAnimation(.timingCurve(0.25, 0.9, 0.3, 1.0, duration: duration * 0.88).delay(0.12)) {
                lift = 0
            }
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000) + 50_000_000)
            guard token == spinToken else { return }
            var snap = Transaction(); snap.disablesAnimations = true
            withTransaction(snap) {
                let base = (target / 360).rounded(.down) * 360
                degrees = landFront ? base : base + 180
            }
            winner = picked
            spinning = false
            withAnimation(.smooth(duration: 0.35)) { settled = true }
        }
    }
}

// MARK: - 3D mince (Animatable = přepínání stran v každém snímku animace)

/// Klasický coin-flip vzor: obě strany v ZStack, jedna rotace, opacity podle úhlu přes Animatable.
private struct Coin3D: View, Animatable {
    var degrees: Double
    var front: CoinTossPlayer?
    var back: CoinTossPlayer?

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    /// Normalizovaný úhel 0…360.
    private var phase: Double {
        var p = degrees.truncatingRemainder(dividingBy: 360)
        if p < 0 { p += 360 }
        return p
    }

    /// Líc je k nám, když jsme v pásmu −90…+90 kolem 0/360.
    private var showFront: Bool {
        phase < 90 || phase >= 270
    }

    var body: some View {
        ZStack {
            // Rub — zrcadlově na X, ať po otočení text/fotka není převrácená
            coinFace(back)
                .scaleEffect(x: -1, y: 1)
                .opacity(showFront ? 0 : 1)

            // Líc
            coinFace(front)
                .opacity(showFront ? 1 : 0)
        }
        .rotation3DEffect(
            .degrees(degrees),
            axis: (x: 0.05, y: 1, z: 0),
            perspective: 0.55
        )
    }

    private func coinFace(_ player: CoinTossPlayer?) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.96, green: 0.84, blue: 0.38),
                            Color(red: 0.8, green: 0.6, blue: 0.16),
                            Color(red: 0.42, green: 0.3, blue: 0.08)
                        ],
                        center: UnitPoint(x: 0.32, y: 0.28),
                        startRadius: 4,
                        endRadius: 160
                    )
                )
                .overlay {
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.85), .black.opacity(0.45)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 12
                        )
                }
                .shadow(color: .black.opacity(0.4), radius: 16, y: 12)

            Circle()
                .strokeBorder((player?.tint ?? Theme.brand).opacity(0.95), lineWidth: 6)
                .padding(20)

            if let player {
                VStack(spacing: 8) {
                    Avatar(
                        name: player.name,
                        bot: player.bot,
                        size: 108,
                        photo: player.photo,
                        asset: player.asset
                    )
                    .overlay(Circle().strokeBorder(.white.opacity(0.5), lineWidth: 3))

                    Text(player.name)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black.opacity(0.88))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                }
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
    }
}
