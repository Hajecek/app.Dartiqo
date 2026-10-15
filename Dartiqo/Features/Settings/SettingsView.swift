import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var deletion = false
    @State private var exporting = false
    @State private var document: JSONDocument?
    @State private var exportError: String?
    @State private var photoItem: PhotosPickerItem?
    var body: some View {
        Form {
            Section {
                HStack(spacing: 18) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Avatar(name: store.profile?.name ?? "", size: 70, photo: store.profile?.photoJPEG)
                    }
                    .buttonStyle(.plain)
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
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Zvolit profilovou fotku", systemImage: "photo")
                }
                if store.profile?.photoJPEG != nil {
                    Button("Odebrat fotku", role: .destructive) { store.setPhoto(nil) }
                }
                HStack {
                    TextField("Přezdívka", text: $name).textContentType(.nickname)
                    Button("Uložit") { store.rename(name); store.feedback() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                TextField("E-mail", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                Button("Uložit kontakt") {
                    store.updateProfileContact(username: username, email: email)
                    store.feedback()
                }
            } header: {
                Text("Hráčský profil")
            } footer: {
                Text("Username a e-mail slouží k hledání mezi profily na tomto telefonu. Bez online účtu a synchronizace.")
            }
            Section {
                Picker("Vzhled", selection: $store.data.appearance) { Text("Tmavý").tag("dark"); Text("Světlý").tag("light"); Text("Podle systému").tag("system") }
                Toggle("Haptická odezva", isOn: $store.data.haptics).tint(Theme.mint)
                Toggle("Hlasové hlášení skóre", isOn: $store.data.voice).tint(Theme.mint)
                Toggle("Adaptivní bot", isOn: Binding(
                    get: { store.data.adaptiveAI != false },
                    set: { store.data.adaptiveAI = $0; store.save() }
                )).tint(Theme.mint)
            } header: {
                Text("Přizpůsobení")
            } footer: {
                Text("Hlášení čte dosažené skóre nahlas. Hlasový zápis (mikrofon v zápase) je zvlášť — řekneš šipku nebo součet kola. Adaptivní bot mezi zápasy srovná obtížnost s tvými posledními legy. Vypnutí ho nechá na ručně zvolené úrovni.")
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
                Toggle("Chránit profil odemknutím zařízení", isOn: Binding(get: { store.data.biometricLock }, set: { value in if value { Task { await store.authenticate(enabling: true) } } else { store.data.biometricLock = false; store.save() } })).tint(Theme.mint)
                if let error = store.authError { Text(error).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Soukromí") } footer: { Text("Použije Face ID, Touch ID nebo kód zařízení. Zámek chrání vstup do celé aplikace a aktivuje se po přechodu na pozadí.") }
            Section {
                Button { do { document = try store.export(); exporting = true } catch { exportError = error.localizedDescription } } label: { Label("Exportovat všechna data (JSON)", systemImage: "square.and.arrow.up") }
                Text("Export obsahuje všechny místní profily, historii a rozehrané zápasy. Obnovení dat probíhá ze zálohy zařízení; import JSON není součástí této verze.").font(.caption).foregroundStyle(.secondary)
            } header: { Text("Tvoje data") }
            Section {
                NavigationLink("Pravidla a ovládání") { RulesView() }
                NavigationLink("Za co dostávám XP") { XPInfoView() }
                LabeledContent("Verze", value: "1.2.0")
                LabeledContent("Provoz", value: "Offline")
            }
            Section {
                Button("Přepnout hráčský profil") { store.signOut() }
                Button("Smazat tento profil a jeho hry", role: .destructive) { deletion = true }
            }
        }.navigationTitle("Nastavení").onAppear {
            name = store.profile?.name ?? ""
            username = store.profile?.username ?? ""
            email = store.profile?.email ?? ""
        }
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
            .confirmationDialog("Smazat profil a všechny jeho zápasy?", isPresented: $deletion, titleVisibility: .visible) {
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
            Section("Cricket") { Text("Hraje se na 15 až 20 a bull. Single je jeden zásah, double dva, triple tři. Tři zásahy zavřou číslo. Nadbytečné zásahy přidají body, pokud alespoň jeden soupeř číslo ještě nezavřel. Pro výhru musíš zavřít všechna čísla a nemít méně bodů než kterýkoli soupeř. Ve variantě bez bodů vyhrává první, kdo vše zavře.") }
            Section("Kolem hodin") { Text("Tref postupně 1, 2, …, 20. Volba pouze double / triple přijímá na číslech jen zvolený násobek, na konci vyžaduje bull 50. U libovolných zásahů stačí i outer bull 25. Násobek nepřeskakuje čísla. Správný zásah okamžitě posune další cíl, i uprostřed návštěvy.") }
            Section("Count Up") { Text("Zvolený počet kol (5 až 30) pro každého hráče, vždy tři šipky. Sčítají se všechny body. Nejvyšší skóre vítězí, shoda znamená remízu.") }
            Section("Boti a statistiky") { Text("Každá šipka bota vznikne simulací zásahu na terči. Úrovně 1–20 mají dlouhodobý cíl průměru a úspěšnosti double, jednotlivá kola se liší. Styl mění skóre, zavírání a stabilitu. Adaptive AI mezi zápasy zvolí úroveň podle posledních legů a v nastavení jde vypnout. Průměr X01 používá skutečně zapsaný počet šipek, včetně šipek před otevřením a při přehozu.") }
            Section("Kalibrace terče") {
                Text("Nastavení → Autoscore → Kalibrace terče.")
                Text("Namiř kameru tak, aby byl celý terč ve snímku. Kruh zezelená, jakmile pozná okraj. Čísla na terči sama určí segmenty a otočení.")
                Text("V zápasu zvol způsob zápisu Kamera. Ukáže se živý obraz a nová šipka se zapíše, jakmile zůstane v terči. Šipku mimo terč doplň tlačítkem Mimo. Telefon po kalibraci nepřemisťuj.")
            }
            Section("XP") {
                Text("Body dávají dokončené zápasy a uložené tréninky.")
                NavigationLink("Za co dostávám XP") { XPInfoView() }
            }
        }.navigationTitle("Jak hrát").navigationBarTitleDisplayMode(.inline)
    }
}

/// Za co se dává XP — jen zdroje bodů, bez křivky levelů.
struct XPInfoView: View {
    var body: some View {
        List {
            Section("Zápas — výsledek") {
                Label("+40 XP za dohraný zápas", systemImage: "flag.checkered")
                Label("+50 XP výhra · +15 remíza · −25 prohra", systemImage: "trophy.fill")
                Text("Prohra bere XP schválně — ať je důvod vyhrát.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Průměr (X01)") {
                ForEach(MatchRewards.averageBands, id: \.label) { band in
                    Label("\(band.label) = +\(band.xp) XP", systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            Section("Zavírání % (X01)") {
                ForEach(MatchRewards.checkoutRateBands, id: \.label) { band in
                    Label("\(band.label) % = +\(band.xp) XP", systemImage: "percent")
                }
            }
            Section("Checkout skóre (X01)") {
                ForEach(MatchRewards.checkoutScoreBands, id: \.label) { band in
                    Label("\(band.label) = +\(band.xp) XP", systemImage: "flag.fill")
                }
            }
            Section("Nejlepší kolo (X01)") {
                ForEach(MatchRewards.bestVisitBands, id: \.label) { band in
                    Label("\(band.label) = +\(band.xp) XP", systemImage: "bolt.fill")
                }
                Label("+8 XP za vyhraný leg (max 24)", systemImage: "rectangle.split.3x1.fill")
            }
            Section("Zápas — ostatní režimy") {
                Label("Cricket / Count-Up: pásma bodů 20–49 / 50–99 / 100–149 / 150–199 / 200+", systemImage: "number")
                Label("Around the Clock: pásma postupu 5–9 / 10–14 / 15–19 / 20 / hotovo", systemImage: "clock.fill")
            }
            Section("Trénink") {
                Text("XP se započítá až po uložení dokončené hry, ve které padla aspoň jedna šipka. Restart, přerušení a prázdná hra nic nedají. Stejná hra se nezapočítá dvakrát.")
                Label("Základ 20 / 40 / 70 podle obtížnosti", systemImage: "slider.horizontal.3")
                Label("+30 za splnění", systemImage: "checkmark.circle.fill")
                Label("Až +20 podle přesnosti", systemImage: "scope")
                Label("+40 za nový rekord", systemImage: "medal.fill")
                Label("+15 při přesnosti aspoň 50 % nebo sérii 3 zásahů", systemImage: "flame.fill")
                Label("+50 u denní výzvy, +40 u týdenní", systemImage: "flag.fill")
            }
            Section("Ochrana před farmením") {
                Text("Čtvrté a další dokončení stejné tréninkové hry v jeden den dají jen 10 % základu, bez bonusů. U pokročilé obtížnosti to znamená 4 XP.")
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
            footer: "Každý řádek je pásmo od–do, nebo výsledek zápasu. Prohra bere XP.",
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
