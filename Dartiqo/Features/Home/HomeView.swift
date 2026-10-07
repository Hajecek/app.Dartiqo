import SwiftUI

/// Lobby ve stylu herní aplikace. Navigace a tab bar zůstávají systémové.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var live = false
    @State private var testNotice = false

    private let canvas = Color.black

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                profileRow
                if store.activeMatch != nil { resumeRow }
                actionGrid
                wideCards
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(canvas.ignoresSafeArea())
        .navigationTitle("Dartiqo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("Logo")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .clipShape(Circle())
                    .accessibilityLabel("Dartiqo")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    testNotice = true
                } label: {
                    Image(systemName: "bell")
                }
                .tint(Theme.brand)
                .accessibilityLabel("Test")
            }
        }
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Test", isPresented: $testNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Zkušební tlačítko vpravo v liště.")
        }
        .fullScreenCover(isPresented: $live) {
            NavigationStack { MatchView() }
                .environmentObject(store)
        }
    }

    private var profileRow: some View {
        NavigationLink {
            ProfileView()
        } label: {
            HStack(spacing: 14) {
                Avatar(name: store.profile?.name ?? "", size: 76, photo: store.profile?.photoJPEG)
                    .environment(\.colorScheme, .dark)
                    .overlay(Circle().stroke(Theme.brand, lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.profile?.name ?? "Hráč")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Text("Level \(store.level)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                    Label(averageText, systemImage: "bolt.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                }
                Spacer(minLength: 8)
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(store.profile?.name ?? "Hráč"), level \(store.level), průměr \(averageText)")
    }

    private var averageText: String {
        store.ownVisits.isEmpty ? "—" : String(format: "%.1f", store.average)
    }

    private var resumeRow: some View {
        Button { live = true } label: {
            Label(store.activeMatch?.finished == true ? "Zobrazit výsledek" : "Pokračovat ve hře", systemImage: "play.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .foregroundStyle(.black)
                .background(Theme.brand, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var actionGrid: some View {
        HStack(spacing: 12) {
            NavigationLink { SetupView(mode: .x01) } label: {
                LobbyCard(
                    title: "Hrát lokálně",
                    detail: "X01 s kamarády nebo boty",
                    symbol: "target",
                    colors: [Color(red: 1.0, green: 0.42, blue: 0.29), Color(red: 0.86, green: 0.20, blue: 0.20)],
                    height: 190
                )
            }
            NavigationLink { SetupView(mode: .countUp) } label: {
                LobbyCard(
                    title: "Trénovat",
                    detail: "Count Up, překonej svoje maximum",
                    symbol: "scope",
                    colors: [Color(red: 1.0, green: 0.72, blue: 0.20), Color(red: 0.95, green: 0.48, blue: 0.08)],
                    height: 190
                )
            }
        }
        .buttonStyle(.plain)
    }

    private var wideCards: some View {
        VStack(spacing: 12) {
            NavigationLink { SetupView(mode: .cricket) } label: {
                LobbyCard(
                    title: "Cricket",
                    detail: "Zavři 15–20 a bull dřív než soupeř",
                    symbol: "line.3.horizontal.decrease.circle.fill",
                    colors: [Color(red: 0.11, green: 0.42, blue: 0.30), Color(red: 0.05, green: 0.20, blue: 0.15)],
                    height: 136,
                    wide: true
                )
            }
            NavigationLink { SetupView(mode: .aroundClock) } label: {
                LobbyCard(
                    title: "Kolem hodin",
                    detail: "Postupně 1 až 20 a nakonec bull",
                    symbol: "clock.fill",
                    colors: [Color(red: 0.30, green: 0.27, blue: 0.70), Color(red: 0.14, green: 0.12, blue: 0.38)],
                    height: 136,
                    wide: true
                )
            }
            NavigationLink { HistoryView() } label: {
                LobbyCard(
                    title: "Tvoje hry",
                    detail: store.matches.isEmpty
                        ? "Po prvním zápase tu uvidíš historii"
                        : "\(store.matches.count) zápasů · \(store.wins) výher",
                    symbol: "chart.xyaxis.line",
                    colors: [Color(red: 0.36, green: 0.29, blue: 0.12), Color(red: 0.16, green: 0.13, blue: 0.07)],
                    height: 136,
                    wide: true
                )
            }
        }
        .buttonStyle(.plain)
    }
}

/// Barevná karta s velkým symbolem v pozadí, text v systémovém písmu.
private struct LobbyCard: View {
    let title: String
    let detail: String
    let symbol: String
    let colors: [Color]
    var height: CGFloat
    var wide = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.18), in: Circle())
                .accessibilityHidden(true)
            Spacer(minLength: 12)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .padding(.trailing, wide ? 96 : 0)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol)
                    .font(.system(size: wide ? 120 : 110, weight: .bold))
                    .foregroundStyle(.white.opacity(0.14))
                    .rotationEffect(.degrees(-12))
                    .offset(x: wide ? -8 : 28, y: wide ? 22 : 30)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: colors.first?.opacity(0.35) ?? .clear, radius: 12, y: 6)
        .overlay(alignment: .topTrailing) {
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(16)
                .accessibilityHidden(true)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

struct MatchRow: View {
    let match: Match
    var profileID: UUID?
    private var won: Bool { match.winner.map { match.players[$0].id == profileID } ?? false }
    private var result: String {
        match.winner.map { match.players[$0].id == profileID ? "Výhra" : "Prohra" } ?? "Remíza"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: match.config.mode.symbol)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(match.players.map(\.name).joined(separator: " vs "))
                    .font(.body)
                    .lineLimit(2)
                Text("\(match.config.mode.shortTitle) · \(match.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(result)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(won ? Theme.positive : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
