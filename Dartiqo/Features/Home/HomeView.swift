import SwiftUI

/// Lobby ve stylu herní aplikace. Navigace a tab bar zůstávají systémové.
struct HomeView: View {
    @EnvironmentObject private var store: AppStore
    @State private var live = false
    @State private var testNotice = false
    @State private var preview: LockedPreview?

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
        .onChange(of: store.homeGeneration) { _, _ in live = false }
        .sheet(item: $preview) { item in
            FeaturePreview(preview: item)
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
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.title3.weight(.semibold))
                            .accessibilityHidden(true)
                        Text(averageText)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(Theme.brand)
                    Text("průměr")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
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
        VStack(spacing: 12) {
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
                NavigationLink { TrainingHomeView() } label: {
                    LobbyCard(
                        title: "Trénovat",
                        detail: "80 her, výzvy a plán podle hodů",
                        symbol: "scope",
                        colors: [Color(red: 1.0, green: 0.72, blue: 0.20), Color(red: 0.95, green: 0.48, blue: 0.08)],
                        height: 190
                    )
                }
            }
            HStack(spacing: 12) {
                Button { preview = .online } label: {
                    LobbyCard(
                        title: "Hrát online",
                        detail: "Uzamčeno · zápas s hráčem na dálku",
                        symbol: "globe",
                        colors: [Color(red: 0.18, green: 0.48, blue: 0.98), Color(red: 0.08, green: 0.22, blue: 0.72)],
                        height: 190,
                        locked: true
                    )
                }
                .accessibilityHint("Otevře, co v online hře přibude")
                Button { preview = .tournaments } label: {
                    LobbyCard(
                        title: "Turnaje",
                        detail: "Uzamčeno · tabulka, pavouk a ceny",
                        symbol: "flag.2.crossed",
                        colors: [Color(red: 0.58, green: 0.28, blue: 0.96), Color(red: 0.34, green: 0.12, blue: 0.70)],
                        height: 190,
                        locked: true
                    )
                }
                .accessibilityHint("Otevře, co v turnajích přibude")
            }
        }
        .buttonStyle(.plain)
    }

    private var wideCards: some View {
        Button { preview = .career } label: {
            LobbyCard(
                title: "Kariéra",
                detail: "Uzamčeno · hodnosti, výzvy a odměny",
                symbol: "trophy.fill",
                colors: [Color(red: 0.28, green: 0.24, blue: 0.08), Color(red: 0.12, green: 0.10, blue: 0.05)],
                height: 136,
                wide: true,
                locked: true
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Otevře, co v kariéře přibude")
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
    var locked = false

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
            Group {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 28, height: 28)
                        .background(Theme.brand, in: Circle())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(16)
            .accessibilityHidden(true)
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
    }
}

/// Obsah náhledu uzamčeného režimu v lobby.
private struct LockedPreview: Identifiable {
    let id: String
    let title: String
    let headline: String
    let summary: String
    let items: [(symbol: String, title: String, detail: String)]

    static let online = LockedPreview(
        id: "online",
        title: "Hrát online",
        headline: "Online hra je zatím uzamčená",
        summary: "Online zápas spojí dva hráče na dálku ve stejném kole. Zatím si ho můžeš jen prohlédnout.",
        items: [
            ("person.2.fill", "Soupeři", "Najdeš hráče se stejnou úrovní a zahraješ si X01 na dálku."),
            ("link", "Pozvánka", "Pošleš odkaz kamarádovi a zápas začne bez hledání soupeře."),
            ("chart.bar.fill", "Žebříček", "Online průměr a pořadí mezi hráči Dartiqo."),
            ("bolt.fill", "Živý zápas", "Skóre se počítá u obou hráčů ve stejném kole.")
        ]
    )

    static let tournaments = LockedPreview(
        id: "tournaments",
        title: "Turnaje",
        headline: "Turnaje jsou zatím uzamčené",
        summary: "Turnaj sjednotí víc zápasů do tabulky nebo pavouka. Zatím si ho můžeš jen prohlédnout.",
        items: [
            ("person.3.fill", "Startovní listina", "Přihláška, kapacita a rozlosování hráčů."),
            ("arrow.triangle.branch", "Pavouk", "Vyřazovací zápasy až do finále."),
            ("list.number", "Tabulka", "Skupiny, body a vzájemné zápasy."),
            ("trophy.fill", "Ceny", "Pořadí, odznaky a odměny pro nejlepší.")
        ]
    )

    static let career = LockedPreview(
        id: "career",
        title: "Kariéra",
        headline: "Kariéra je zatím uzamčená",
        summary: "Kariéra spojí level, hodnost a milníky do jednoho postupu. Zatím si ji můžeš jen prohlédnout.",
        items: [
            ("crown.fill", "Hodnosti", "Postup od začátečníka po experta podle nasbíraných XP."),
            ("flag.fill", "Výzvy", "Denní a týdenní úkoly navázané na tvoje zápasy."),
            ("medal.fill", "Odznaky", "Milníky za 180, vysoká zavření a série výher."),
            ("calendar", "Sezóny", "Žebříček a odměny, které se s novou sezónou obnoví.")
        ]
    )
}

/// Náhled uzamčeného režimu. Okno jen říká, co přibude.
private struct FeaturePreview: View {
    @Environment(\.dismiss) private var dismiss
    let preview: LockedPreview

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(width: 52, height: 52)
                            .background(Theme.brand, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Připravujeme")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Theme.brand)
                            Text(preview.headline)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                        }
                    }

                    Text(preview.summary)
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ForEach(preview.items, id: \.title) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: item.symbol)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(Theme.brand)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.brand.opacity(0.14), in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text(item.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.72))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(20)
                .padding(.bottom, 8)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(preview.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Zavřít") { dismiss() }
                        .tint(Theme.brand)
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
    }
}
