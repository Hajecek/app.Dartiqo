import SwiftUI

struct CoinTossPlayer: Identifiable, Equatable {
    var id: Int
    var name: String
    var photo: Data?
    var asset: String?
    var bot: Bool
    var tint: Color
}

/// Los mincí — líc jeden hráč, rub druhý. Točení přes Animatable, ať jsou vidět obě strany.
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

    private let coinSize: CGFloat = 228

    private var playerA: CoinTossPlayer? { players.indices.contains(faceA) ? players[faceA] : nil }
    private var playerB: CoinTossPlayer? { players.indices.contains(faceB) ? players[faceB] : nil }
    private var winnerPlayer: CoinTossPlayer? {
        guard let winner, players.indices.contains(winner) else { return nil }
        return players[winner]
    }

    private var stageTint: Color {
        settled ? (winnerPlayer?.tint ?? Theme.brand) : Theme.brand
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                    .padding(.top, 8)
                Spacer(minLength: 8)
                coinStage
                Spacer(minLength: 16)
                actions
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { backdrop }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("LOS MINCÍ")
                        .font(AppFont.caption(12, weight: .bold))
                        .tracking(2.4)
                        .foregroundStyle(.secondary)
                }
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

    private var backdrop: some View {
        ZStack {
            Theme.background
            RadialGradient(
                colors: [stageTint.opacity(settled ? 0.28 : 0.16), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 20,
                endRadius: 460
            )
        }
        .animation(.smooth(duration: 0.55), value: settled)
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(settled ? "ZAČÍNÁ" : "KDO HÁZÍ PRVNÍ")
                .font(AppFont.caption(12, weight: .bold))
                .tracking(2.2)
                .foregroundStyle(.secondary)
            Text(settled ? (winnerPlayer?.name ?? "Hráč") : "Hod mincí")
                .font(AppFont.display(40, weight: .black))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .contentTransition(.opacity)
            Text(settled ? "Hází první šipku" : "Každý hráč má svou stranu")
                .font(AppFont.body(16, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .animation(.smooth(duration: 0.35), value: settled)
        .frame(maxWidth: .infinity, minHeight: 96)
    }

    private var coinStage: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                .frame(width: coinSize + 56, height: coinSize + 56)
            Circle()
                .stroke(stageTint.opacity(settled ? 0.85 : 0.22), lineWidth: settled ? 2.5 : 1)
                .frame(width: coinSize + 16, height: coinSize + 16)
                .animation(.smooth(duration: 0.45), value: settled)
            Circle()
                .fill(stageTint.opacity(settled ? 0.34 : 0.1))
                .frame(width: coinSize * 0.92, height: coinSize * 0.92)
                .blur(radius: 36)
                .animation(.smooth(duration: 0.45), value: settled)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [.black.opacity(spinning ? 0.28 : 0.4), .clear],
                        center: .center,
                        startRadius: 8,
                        endRadius: 100
                    )
                )
                .frame(width: 168, height: 34)
                .blur(radius: 7)
                .offset(y: coinSize * 0.56)
                .scaleEffect(x: max(0.52, 1 - abs(lift) / 150))

            Coin3D(degrees: degrees, front: playerA, back: playerB)
                .frame(width: coinSize, height: coinSize)
                .offset(y: lift)
                .scaleEffect(appeared || reduceMotion ? 1 : 0.88)
                .opacity(appeared || reduceMotion ? 1 : 0)
        }
        .frame(height: 272)
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

        spinToken += 1
        let token = spinToken
        settled = false
        spinning = true
        winner = nil

        let landFront = Bool.random()
        let picked = landFront ? faceA : faceB

        // Nový los vždy ze stejného klidového úhlu. Stejný počet otáček i stejné 3 s.
        let start: Double = coinShowsFront(degrees) ? 0 : 180
        var halves = Int.random(in: 17...23)
        let endsFront = (start == 0) == halves.isMultiple(of: 2)
        if endsFront != landFront { halves += 1 }
        let target = start + Double(halves) * 180
        let duration = reduceMotion ? 0.4 : 3.0

        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            degrees = start
            lift = 0
        }

        Task { @MainActor in
            // Nejdřív nechat usadit reset. Jinak animace naváže na starý úhel a zrychlí.
            try? await Task.sleep(nanoseconds: 32_000_000)
            guard token == spinToken else { return }

            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.3)) { lift = -88 }
                withAnimation(.timingCurve(0.12, 0.78, 0.14, 1.0, duration: duration)) {
                    degrees = target
                }
                withAnimation(.timingCurve(0.25, 0.9, 0.3, 1.0, duration: duration * 0.88).delay(0.12)) {
                    lift = 0
                }
            } else {
                degrees = target
            }

            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000) + 50_000_000)
            guard token == spinToken else { return }
            var snap = Transaction()
            snap.disablesAnimations = true
            withTransaction(snap) {
                degrees = landFront ? 0 : 180
                lift = 0
            }
            winner = picked
            spinning = false
            withAnimation(.smooth(duration: 0.35)) { settled = true }
        }
    }
}

/// Líc je k nám v pásmu −90…+90 kolem 0/360.
private func coinShowsFront(_ degrees: Double) -> Bool {
    var phase = degrees.truncatingRemainder(dividingBy: 360)
    if phase < 0 { phase += 360 }
    return phase < 90 || phase >= 270
}

// MARK: - 3D mince

/// Obě strany v jednom ZStacku. Rub je zrcadlený, ať po otočení kolem osy Y není text převrácený.
private struct Coin3D: View, Animatable {
    var degrees: Double
    var front: CoinTossPlayer?
    var back: CoinTossPlayer?

    var animatableData: Double {
        get { degrees }
        set { degrees = newValue }
    }

    private var showFront: Bool {
        coinShowsFront(degrees)
    }

    var body: some View {
        ZStack {
            CoinMedal(player: back)
                .scaleEffect(x: -1, y: 1)
                .opacity(showFront ? 0 : 1)
            CoinMedal(player: front)
                .opacity(showFront ? 1 : 0)
        }
        .rotation3DEffect(
            .degrees(degrees),
            axis: (x: 0.05, y: 1, z: 0),
            perspective: 0.55
        )
    }
}

/// Zlatá mince jako dřív. Uvnitř je jen fotka, bez jména.
private struct CoinMedal: View {
    var player: CoinTossPlayer?

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            face(side)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func face(_ side: CGFloat) -> some View {
        let photo = side * 0.62
        return ZStack {
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
                        endRadius: side * 0.72
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

            Circle()
                .strokeBorder((player?.tint ?? Theme.brand).opacity(0.95), lineWidth: 6)
                .padding(side * 0.09)

            portrait(photo)
        }
        .frame(width: side, height: side)
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 16, y: 12)
    }

    private func portrait(_ size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.28))
            if let player {
                Avatar(
                    name: player.name,
                    bot: player.bot,
                    size: size - 8,
                    photo: player.photo,
                    asset: player.asset
                )
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 3))
        .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
    }
}

#if DEBUG
#Preview("Tmavý") {
    CoinTossView(
        players: [
            CoinTossPlayer(id: 0, name: "Ty", photo: nil, asset: nil, bot: false, tint: Theme.playerColor(0)),
            CoinTossPlayer(id: 1, name: "Bot 5", photo: nil, asset: BotLevel.get(5).photo, bot: true, tint: Theme.playerColor(1))
        ],
        onFinish: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Světlý") {
    CoinTossView(
        players: [
            CoinTossPlayer(id: 0, name: "Ty", photo: nil, asset: nil, bot: false, tint: Theme.playerColor(0)),
            CoinTossPlayer(id: 1, name: "Bot 5", photo: nil, asset: BotLevel.get(5).photo, bot: true, tint: Theme.playerColor(1))
        ],
        onFinish: { _ in },
        onCancel: {}
    )
    .preferredColorScheme(.light)
}
#endif
