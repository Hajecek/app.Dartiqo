import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject private var account = DartiqoAccount.shared
    @State private var name = ""
    @State private var deletion = false
    @State private var confirmLogout = false
    @State private var exporting = false
    @State private var document: JSONDocument?
    @State private var exportError: String?
    @State private var photoItem: PhotosPickerItem?

    private var lockGraceSelection: Int {
        let value = store.data.lockGraceSeconds ?? Int(InactivityLock.defaultGrace)
        return [0, 30, 60, 300].contains(value) ? value : Int(InactivityLock.defaultGrace)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            Avatar(name: store.profile?.name ?? "", size: 70, photo: store.profile?.photoJPEG)
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.onAccent)
                                .frame(width: 26, height: 26)
                                .background(Theme.accentFill, in: Circle())
                                .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Změnit profilovou fotku")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(store.profile?.name ?? "Hráč").font(.title2.bold())
                        if let handle = store.profile?.username, !handle.isEmpty {
                            Text("@\(handle)").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.action)
                        }
                        Text("Level \(store.level) · \(store.xp) XP").font(.subheadline).foregroundStyle(.secondary)
                        Text(store.ownVisits.isEmpty ? "Průměr —" : String(format: "Průměr %.1f", store.average))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
                if store.profile?.photoJPEG != nil {
                    Button("Odebrat fotku", role: .destructive) { store.setPhoto(nil) }
                }
                HStack {
                    TextField("Přezdívka", text: $name).textContentType(.nickname)
                    Button("Uložit") { store.rename(name); store.feedback() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Hráčský profil")
            } footer: {
                Text("Přezdívka se ukazuje v zápasech. Username a e-mail patří k účtu na webu.")
            }
            Section {
                NavigationLink {
                    AccountView()
                } label: {
                    HStack {
                        Label("Dartiqo účet", systemImage: "person.badge.key")
                        Spacer()
                        Text(account.user.map { "@\($0.username)" } ?? (account.isGuest ? "Bez účtu" : ""))
                            .font(.caption)
                            .foregroundStyle(account.user != nil ? Theme.mint : .secondary)
                    }
                }
            } header: {
                Text("Online")
            } footer: {
                Text("Po přihlášení se rozehraný zápas živě ukáže na webu Dartiqo.")
            }
            Section {
                Picker("Vzhled", selection: $store.data.appearance) { Text("Tmavý").tag("dark"); Text("Světlý").tag("light"); Text("Podle systému").tag("system") }
                Toggle("Haptická odezva", isOn: $store.data.haptics).tint(Theme.mint)
                Toggle("Hlasové hlášení skóre", isOn: $store.data.voice).tint(Theme.mint)
                ForEach(Commentator.allCases) { item in
                    CommentatorOptionRow(item: item)
                }
                NavigationLink {
                    CommentaryLibraryView()
                } label: {
                    CommentaryStudioLink()
                }
                Toggle("Adaptivní bot", isOn: Binding(
                    get: { store.data.adaptiveAI != false },
                    set: { store.data.adaptiveAI = $0; store.save() }
                )).tint(Theme.mint)
            } header: {
                Text("Přizpůsobení")
            } footer: {
                Text("Hlášení čte dosažené skóre nahlas. Vlastní komentátor pustí tvoje nahrávky, chybějící situace dočte výchozí hlas. Hlasový zápis (mikrofon v zápase) je zvlášť — řekneš šipku nebo součet kola. Adaptivní bot mezi zápasy srovná obtížnost s tvými posledními legy. Vypnutí ho nechá na ručně zvolené úrovni.")
            }
            Section {
                NavigationLink {
                    BoardCalibrationView(initial: store.boardCalibration)
                } label: {
                    HStack {
                        Label("Kalibrace terče", systemImage: "camera.viewfinder")
                        Spacer()
                        Text(store.boardMapper != nil ? "Hotovo" : "Nenastaveno")
                            .font(.caption)
                            .foregroundStyle(store.boardMapper != nil ? Theme.mint : .secondary)
                    }
                }
                if store.boardCalibration?.isCameraMapped == true {
                    HStack {
                        Label("Naučeno z oprav", systemImage: "brain")
                        Spacer()
                        Text("\(store.learnedCorrections)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if store.learnedCorrections > 0 {
                        Button("Zapomenout opravy") { store.forgetLearning() }
                    }
                }
                if store.boardCalibration != nil {
                    Button("Vymazat kalibraci", role: .destructive) { store.clearBoardCalibration() }
                }
            } header: { Text("Autoscore") } footer: { Text("Kamera najde terč podle barev segmentů a uloží mapu. V zápase zvol zápis Kamera. Když hod opravíš klepnutím, mapa se z opravy doučí. Nová kalibrace začíná učení od nuly.") }
            Section {
                Toggle("Ověřit mě při návratu do aplikace", isOn: Binding(get: { store.data.biometricLock }, set: { value in if value { Task { await store.authenticate(enabling: true) } } else { store.disableBiometricLock() } })).tint(Theme.mint)
                if store.data.biometricLock {
                    Picker("Po době na pozadí", selection: Binding(get: { lockGraceSelection }, set: { store.setLockGrace($0) })) {
                        Text("Hned").tag(0)
                        Text("30 sekund").tag(30)
                        Text("1 minuta").tag(60)
                        Text("5 minut").tag(300)
                    }
                }
                if let error = store.authError { Text(error).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Soukromí") } footer: { Text("Po zvolené době na pozadí se objeví zámek. Odemkne ho Face ID, Touch ID nebo kód zařízení. Krátké přepnutí hru nepřeruší.") }
            Section {
                Button { do { document = try store.export(); exporting = true } catch { exportError = error.localizedDescription } } label: { Label("Exportovat všechna data (JSON)", systemImage: "square.and.arrow.up") }
                Text("Export obsahuje všechny místní profily, historii a rozehrané zápasy. Obnovení dat probíhá ze zálohy zařízení; import JSON není součástí této verze.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Tvoje data") }
            Section {
                NavigationLink("Pravidla a ovládání") { RulesView() }
                NavigationLink("Za co dostávám XP") { XPInfoView() }
                LabeledContent("Verze", value: "1.2.0")
                LabeledContent("Provoz", value: account.user != nil ? "Online" : "Offline")
            }
            Section {
                if account.isGuest {
                    Button("Přihlásit se k účtu") { store.signOut(); account.leaveGuest() }
                } else {
                    Button("Odhlásit se", role: .destructive) { confirmLogout = true }
                }
                Button("Smazat hry tohoto účtu v telefonu", role: .destructive) { deletion = true }
            }
        }.navigationTitle("Nastavení").onAppear {
            name = store.profile?.name ?? ""
        }
            .logoutConfirmation(isPresented: $confirmLogout)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    store.setPhoto(image)
                }
            }
            .onChange(of: store.data.appearance) { _, _ in store.save() }
            .onChange(of: store.data.haptics) { _, _ in store.save() }
            .onChange(of: store.data.voice) { _, _ in store.save() }
            .confirmationDialog("Smazat všechny hry a statistiky tohoto účtu v telefonu?", isPresented: $deletion, titleVisibility: .visible) {
                Button("Smazat natrvalo", role: .destructive) { store.deleteProfile() }
                Button("Zrušit", role: .cancel) {}
            }
            .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Dartiqo-export") { result in if case .failure(let error) = result { exportError = error.localizedDescription } }
            .alert("Export dat", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) { Button("OK") {} } message: { Text(exportError ?? "") }
    }
}
struct RulesView: View {
    var body: some View {
        List {
            Section("Zápis") {
                Text("U X01 můžeš zapisovat součet kola. Při zavření potvrdíš počet šipek i správné pravidlo out. Tlačítko BUST zapíše přehoz s vybraným počtem šipek. Způsob zápisu změníš v nabídce zápasu. U součtů historie neuvádí domyšlené segmenty.\n\nPro přesný zápis vyber Single, Double nebo Triple a číslo, nebo klepni na pole terče. Skóre se ihned změní. Pro 25 a bull použij samostatná tlačítka. VEDLE je šipka bez bodů. Třetí šipka, přehoz nebo zavření automaticky ukončí návštěvu.")
                Text("Zpět vrátí poslední lidskou šipku a odstraní i případnou odpověď bota. Odchod přes křížek může rozehraný zápas uložit. Uložení konečného výsledku přidá zápas do historie a přidělí XP.")
            }
            Section("Hlasový zápis") {
                Text("V zápase zvol způsob zápisu Hlas — poslech běží sám. Mezi hodama udělej krátkou pauzu, šipka nebo součet se zapíše automaticky. Funguje jen na fyzickém iPhonu (ne v simulátoru), ideálně s internetem.")
                Text("Šipky: „trojitá dvacet“, „dvojitá šestnáct“, „T20“, „bull“, „mimo“. Více šipek: „dvacet a dvacet a pět“ nebo „t20 t20 t20“.")
                Text("Součet: „sto osmdesát“, „sto čtyřicet“, „dvacet šest“, „180“. „Přehoz“ nebo „bust“ nabídne zápis přehozu.")
            }
            Section("X01") { Text("Odečítej ze 101, 301, 501, 701 nebo 1001 přesně na nulu. Double out vyžaduje poslední šipku double nebo bull 50. Master out umožňuje i triple. Straight out libovolný zásah. Přehoz vrací skóre na začátek návštěvy. U double/master out je i zůstatek 1 přehoz. Double in započítává body až od prvního doublu.") }
            Section("Cricket") { Text("Čísla se volí při založení hry. Výchozí jsou 15 až 20 a bull. Ve hře se ukážou jen ta. Single je jeden zásah, double dva, triple tři. Tři zásahy zavřou číslo. Nadbytečné zásahy přidají body, pokud alespoň jeden soupeř číslo ještě nezavřel. Pro výhru musíš zavřít všechna zvolená čísla a nemít méně bodů než kterýkoli soupeř. Ve variantě bez bodů vyhrává první, kdo vše zavře.") }
            Section("Kolem hodin") { Text("Tref postupně 1, 2, …, 20. Volba pouze double / triple přijímá na číslech jen zvolený násobek, na konci vyžaduje bull 50. U libovolných zásahů stačí i outer bull 25. Násobek nepřeskakuje čísla. Správný zásah okamžitě posune další cíl, i uprostřed návštěvy.") }
            Section("Count Up") { Text("Zvolený počet kol (5 až 30) pro každého hráče, vždy tři šipky. Sčítají se všechny body. Nejvyšší skóre vítězí, shoda znamená remízu.") }
            Section("Boti a statistiky") { Text("Každá šipka bota vznikne simulací zásahu na terči. Úrovně 1–20 mají dlouhodobý cíl průměru a úspěšnosti double, jednotlivá kola se liší. Styl u těchto úrovní mění skóre, zavírání a stabilitu. Vlastní bot má nastavený průměr, úspěšnost double až do 100 %, stabilitu, nervy a taktiku. Styl u něj mění míření a stavbu zavření. Adaptive AI mezi zápasy zvolí úroveň podle posledních legů a v nastavení jde vypnout. Průměr X01 používá skutečně zapsaný počet šipek, včetně šipek před otevřením a při přehozu.") }
            Section("Kalibrace terče") {
                Text("Nastavení → Autoscore → Kalibrace terče.")
                Text("Namiř kameru tak, aby byl celý terč ve snímku. Kruh zezelená, jakmile pozná okraj. Čísla na terči sama určí segmenty a otočení.")
                Text("V zápasu zvol způsob zápisu Kamera. Ukáže se živý obraz a nová šipka se zapíše, jakmile zůstane v terči. Šipku mimo terč doplň tlačítkem Mimo. Telefon po kalibraci nepřemisťuj.")
            }
            Section("XP") {
                Text("Body dávají uložené tréninky a dokončené zápasy proti botovi nebo ověřenému online soupeři. Lokální zápas na jednom zařízení XP nepřiděluje.")
                NavigationLink("Za co dostávám XP") { XPInfoView() }
            }
        }.navigationTitle("Jak hrát").navigationBarTitleDisplayMode(.inline)
    }
}

/// Za co se dává XP — jen zdroje bodů, bez křivky levelů.
struct XPInfoView: View {
    private var xp: MatchXPConfig { .standard }

    var body: some View {
        List {
            Section("Zápas — základ") {
                Label("+\(xp.playedXP) XP za odehraný zápas", systemImage: "flag.checkered")
                Label("+\(xp.completedXP) XP za dokončený zápas", systemImage: "checkmark.circle.fill")
                Label("+\(xp.winXP) XP výhra · +\(xp.drawXP) remíza · \(xp.lossXP) prohra", systemImage: "trophy.fill")
                Text("XP se připíše až po dokončení. Nedokončený a zrušený zápas nedá nic. Výsledková odměna je jen jedna a prohra se odečítá od ostatních XP.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Průměr na 3 šipky") {
                ForEach(xp.averageBands, id: \.label) { band in
                    Label("\(band.label) = +\(band.xp) XP", systemImage: "chart.line.uptrend.xyaxis")
                }
                Text("Jen v X01, od \(xp.fullAwardLegs) dokončených legů a aspoň \(xp.minimumAverageDarts) šipek.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Úspěšnost zavírání") {
                Label("0 % = 0 XP", systemImage: "percent")
                ForEach(xp.checkoutBands, id: \.label) { band in
                    Label("\(band.label) = +\(band.xp) XP", systemImage: "percent")
                }
                Text("Úspěšná zavření dělená pokusy o double. Bonus chce aspoň \(xp.fullAwardLegs) dokončené legy a \(xp.minimumCheckoutAttempts) pokusy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Speciální bonusy") {
                Label("+\(xp.oneEightyXP) XP za 180 · max \(xp.oneEightyCap)", systemImage: "flame.fill")
                Label("+\(xp.highCheckoutXP) XP za zavření \(xp.highCheckoutMinimum)+ · max \(xp.highCheckoutCap)", systemImage: "flag.fill")
                Text("Jen skutečně zapsané hody a jen od \(xp.fullAwardLegs) dokončených legů. Kratší zápas má jen odehrání, dokončení a výsledek.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Ochrana před farmením") {
                Text("První \(xp.repeatFullCount) dokončené zápasy proti stejnému soupeři za 24 hodin mají 100 % XP. Čtvrtý a pátý 50 %. Šestý a každý další 0 %.")
                Text("Proti botovi se počítá \(Int((xp.botCoefficient * 100).rounded())) % XP, nejvýš \(xp.botDailyCap) zápasů denně, a jen když bot taky hodil.")
                Text("Lokální zápas, sólo a ghost XP nepřidělují. Plné XP jsou pro ověřený online zápas proti skutečnému hráči. Trénink má vlastní XP, ne zápasové.")
                Text("Podezřelý průběh, třeba rozbitý zápis nebo opakované výhry bez hodu soupeře, XP pozastaví. Samotný vysoký průměr nebo rychlá výhra podvod neznamená.")
                Text("Každý zápas má jedno id a XP se k němu zapíšou jen jednou, včetně důvodu a rozpisu. Obnovení obrazovky je nepřidá znovu.")
            }
            Section("Trénink") {
                Text("XP se započítá až po uložení dokončené hry, ve které padla aspoň jedna šipka. Restart, přerušení a prázdná hra nic nedají. Stejná hra se nezapočítá dvakrát.")
                Label("Základ 20 / 40 / 70 podle obtížnosti", systemImage: "slider.horizontal.3")
                Label("+30 za splnění", systemImage: "checkmark.circle.fill")
                Label("Až +20 podle přesnosti", systemImage: "scope")
                Label("+40 za nový rekord", systemImage: "medal.fill")
                Label("+15 při přesnosti aspoň 50 % nebo sérii 3 zásahů", systemImage: "flame.fill")
                Label("+50 u denní výzvy, +40 u týdenní", systemImage: "flag.fill")
                Text("Čtvrté a další dokončení stejné tréninkové hry v jeden den dají jen 10 % základu, bez bonusů. U pokročilé obtížnosti to znamená 4 XP.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Za co dostávám XP")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Rozklad XP za právě dohraný zápas.
struct MatchXPBreakdownSheet: View {
    var breakdown: MatchXPBreakdown

    var body: some View {
        XPBreakdownSheet(
            title: "XP za zápas",
            accessibilityTotal: "\(breakdown.total) XP za zápas",
            footer: breakdown.explanation,
            lines: breakdown.lines.map {
                XPBreakdownRow(id: $0.id, title: $0.title, detail: $0.detail, symbol: $0.symbol, amount: $0.amount)
            },
            total: breakdown.total
        )
    }
}

/// Rozklad XP za právě dohraný trénink.
struct TrainingXPBreakdownSheet: View {
    var breakdown: TrainingXPBreakdown

    var body: some View {
        XPBreakdownSheet(
            title: "XP za trénink",
            accessibilityTotal: "\(breakdown.total) XP za trénink",
            footer: "Každý řádek je jedna složka odměny za tuhle hru.",
            lines: breakdown.lines.map {
                XPBreakdownRow(id: $0.id, title: $0.title, detail: $0.detail, symbol: $0.symbol, amount: $0.amount)
            },
            total: breakdown.total
        )
    }
}

struct XPBreakdownRow: Identifiable {
    var id: String
    var title: String
    var detail: String
    var symbol: String
    var amount: Int
    var signedText: String { amount > 0 ? "+\(amount)" : "\(amount)" }
}

/// Společné modalní okno s rozkladem XP.
struct XPBreakdownSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var accessibilityTotal: String
    var footer: String?
    var lines: [XPBreakdownRow]
    var total: Int

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let tint = total >= 0 ? Theme.brand : Color.red
                    VStack(spacing: 14) {
                        Image(systemName: total >= 0 ? "bolt.fill" : "bolt.slash.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.black)
                            .frame(width: 52, height: 52)
                            .background(tint, in: Circle())
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(total > 0 ? "+\(total)" : "\(total)")
                                .font(.system(size: 56, weight: .heavy, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(tint)
                                .contentTransition(.numericText())
                            Text("XP")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(tint.opacity(0.72))
                                .padding(.bottom, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(accessibilityTotal)
                }
                if let footer {
                    Section {
                        Text(footer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Rozklad") {
                    ForEach(lines) { line in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: line.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(line.amount >= 0 ? Theme.brand : Color.red)
                                .frame(width: 28, height: 28)
                                .background((line.amount >= 0 ? Theme.brand : Color.red).opacity(0.15), in: Circle())
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(line.title)
                                    .font(.body.weight(.semibold))
                                Text(line.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            Text(line.signedText)
                                .font(.title3.weight(.bold).monospacedDigit())
                                .foregroundStyle(line.amount >= 0 ? Theme.brand : Color.red)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(line.title), \(line.signedText) XP. \(line.detail)")
                    }
                }
                Section {
                    HStack {
                        Text("Celkem")
                            .font(.headline)
                        Spacer()
                        Text("\(total > 0 ? "+" : "")\(total) XP")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(total >= 0 ? Theme.brand : Color.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hotovo") { dismiss() }
                        .tint(Theme.brand)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Okno s vysvětlením XP. Stejný obsah jako v nastavení.
struct XPInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            XPInfoView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Hotovo") { dismiss() }
                            .tint(Theme.brand)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
#Preview("Nastavení") {
    NavigationStack { SettingsView() }.dartiqoPreview()
}
#Preview("Pravidla") {
    NavigationStack { RulesView() }.dartiqoPreview()
}
#Preview("XP") {
    NavigationStack { XPInfoView() }.dartiqoPreview()
}
#endif
