import SwiftUI
import UIKit
import PhotosUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
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
                HStack { TextField("Přezdívka", text: $name).textContentType(.nickname); Button("Uložit") { store.rename(name); store.feedback() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            } header: { Text("Hráčský profil") } footer: { Text("Místní profil na tomto zařízení. Bez online účtu a synchronizace.") }
            Section("Přizpůsobení") {
                Picker("Vzhled", selection: $store.data.appearance) { Text("Tmavý").tag("dark"); Text("Světlý").tag("light"); Text("Podle systému").tag("system") }
                Toggle("Haptická odezva", isOn: $store.data.haptics).tint(Theme.mint)
                Toggle("Hlasové hlášení skóre", isOn: $store.data.voice).tint(Theme.mint)
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
                LabeledContent("Verze", value: "1.2.0")
                LabeledContent("Provoz", value: "Offline")
            }
            Section {
                Button("Přepnout hráčský profil") { store.signOut() }
                Button("Smazat tento profil a jeho hry", role: .destructive) { deletion = true }
            }
        }.navigationTitle("Nastavení").onAppear { name = store.profile?.name ?? "" }
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
            Section("Zápis") { Text("U X01 můžeš zapisovat součet kola. Při zavření potvrdíš počet šipek i správné pravidlo out. Tlačítko BUST zapíše přehoz s vybraným počtem šipek. Způsob zápisu změníš v nabídce zápasu. U součtů historie neuvádí domyšlené segmenty.\n\nPro přesný zápis vyber Single, Double nebo Triple a číslo, nebo klepni na pole terče. Skóre se ihned změní. Pro 25 a bull použij samostatná tlačítka. VEDLE je šipka bez bodů. Třetí šipka, přehoz nebo zavření automaticky ukončí návštěvu."); Text("Zpět vrátí poslední lidskou šipku a odstraní i případnou odpověď bota. Odchod přes křížek může rozehraný zápas uložit. Uložení konečného výsledku přidá zápas do historie a přidělí XP.") }
            Section("X01") { Text("Odečítej ze 101, 301, 501, 701 nebo 1001 přesně na nulu. Double out vyžaduje poslední šipku double nebo bull 50. Master out umožňuje i triple. Straight out libovolný zásah. Přehoz vrací skóre na začátek návštěvy. U double/master out je i zůstatek 1 přehoz. Double in započítává body až od prvního doublu.") }
            Section("Cricket") { Text("Hraje se na 15 až 20 a bull. Single je jeden zásah, double dva, triple tři. Tři zásahy zavřou číslo. Nadbytečné zásahy přidají body, pokud alespoň jeden soupeř číslo ještě nezavřel. Pro výhru musíš zavřít všechna čísla a nemít méně bodů než kterýkoli soupeř. Ve variantě bez bodů vyhrává první, kdo vše zavře.") }
            Section("Kolem hodin") { Text("Tref postupně 1, 2, …, 20. Volba pouze double / triple přijímá na číslech jen zvolený násobek, na konci vyžaduje bull 50. U libovolných zásahů stačí i outer bull 25. Násobek nepřeskakuje čísla. Správný zásah okamžitě posune další cíl, i uprostřed návštěvy.") }
            Section("Count Up") { Text("Zvolený počet kol (5 až 30) pro každého hráče, vždy tři šipky. Sčítají se všechny body. Nejvyšší skóre vítězí, shoda znamená remízu.") }
            Section("Boti a statistiky") { Text("Bot míří na skutečné segmenty a chybuje do singlů, sousedních polí nebo mimo terč. Úroveň zvyšuje přesnost; nejde o garantovaný průměr. Průměr X01 v této aplikaci používá skutečně zapsaný počet šipek, včetně šipek před otevřením a při přehozu.") }
            Section("Kalibrace terče") {
                Text("Nastavení → Autoscore → Kalibrace terče.")
                Text("Namiř kameru tak, aby byl celý terč ve snímku. Kruh zezelená, jakmile pozná okraj. Čísla na terči sama určí segmenty a otočení.")
                Text("V zápasu zvol způsob zápisu Kamera. Ukáže se živý obraz a nová šipka se zapíše, jakmile zůstane v terči. Šipku mimo terč doplň tlačítkem Mimo. Telefon po kalibraci nepřemisťuj.")
            }
        }.navigationTitle("Jak hrát").navigationBarTitleDisplayMode(.inline)
    }
}
