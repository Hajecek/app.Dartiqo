import SwiftUI
import PhotosUI
import Contacts
import ContactsUI

struct PickedFriend: Identifiable, Equatable {
    var id: UUID
    var name: String
}

/// Uložení kamarádi — výběr do sestavy, vytvoření a hledání v Dartiqo.
struct FriendPickerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var taken: Set<UUID>
    var slots: Int
    var onPick: ([PickedFriend]) -> Void

    @State private var selected: [PickedFriend] = []
    @State private var showContacts = false
    @State private var editingFriendID: UUID?
    @State private var pendingDelete: Friend?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FriendCreateView { friend in
                            toggle(friend.asPicked, forceOn: true)
                        }
                    } label: {
                        Label("Vytvořit kamaráda", systemImage: "person.badge.plus")
                    }
                    NavigationLink {
                        FriendFindView(taken: taken.union(Set(selected.map(\.id)))) { hit in
                            if let friend = store.createFriend(
                                name: hit.name,
                                username: hit.username,
                                email: hit.email,
                                photo: hit.photoJPEG.flatMap(UIImage.init(data:)),
                                linkedProfileID: hit.accountID == nil ? hit.id : nil,
                                accountID: hit.accountID
                            ) {
                                toggle(PickedFriend(id: friend.id, name: friend.name), forceOn: true)
                            }
                        }
                    } label: {
                        Label("Najít v Dartiqo", systemImage: "magnifyingglass")
                    }
                    Button { showContacts = true } label: {
                        Label("Importovat z kontaktů", systemImage: "person.crop.circle.badge.plus")
                    }
                } footer: {
                    Text("Vytvoř lokální profil, najdi registrovaného hráče podle jména, username nebo e-mailu, nebo ho importuj z kontaktů.")
                }

                if !store.housemates.isEmpty {
                    Section("Profily na tomto telefonu") {
                        ForEach(store.housemates) { profile in
                            personRow(
                                id: profile.id,
                                name: profile.name,
                                username: profile.username,
                                photo: profile.photoJPEG,
                                subtitle: "Profil v aplikaci"
                            )
                        }
                    }
                }

                Section("Uložení kamarádi") {
                    if store.friends.isEmpty {
                        Text("Zatím žádní. Vytvoř profil nebo je najdi v Dartiqo.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.friends) { friend in
                        personRow(
                            id: friend.id,
                            name: friend.name,
                            username: friend.username,
                            photo: store.photo(for: friend.id),
                            subtitle: friend.lastPlayed.map {
                                "Naposledy \($0.formatted(.relative(presentation: .named)))"
                            } ?? "Ještě jste spolu nehráli"
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = friend
                            } label: {
                                Label("Smazat", systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingFriendID = friend.id
                            } label: {
                                Label("Upravit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Kamarádi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Přidat" : "Přidat (\(selected.count))") {
                        confirm(selected)
                    }
                    .fontWeight(.semibold)
                    .disabled(selected.isEmpty)
                }
            }
            .navigationDestination(item: $editingFriendID) { id in
                FriendEditView(friendID: id) { updated in
                    if let index = selected.firstIndex(where: { $0.id == updated.id }) {
                        selected[index].name = updated.name
                    }
                }
            }
            .sheet(isPresented: $showContacts) {
                ContactPicker { imported in
                    for contact in imported {
                        if let friend = store.createFriend(name: contact.name, photo: contact.photo) {
                            toggle(friend.asPicked, forceOn: true)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .sensoryFeedback(.selection, trigger: selected)
            .confirmationDialog(
                "Smazat kamaráda?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { friend in
                Button("Smazat", role: .destructive) {
                    selected.removeAll { $0.id == friend.id }
                    store.deleteFriend(friend.id)
                }
                Button("Zrušit", role: .cancel) {}
            } message: { friend in
                Text("\(friend.name) zmizí ze seznamu. Odehrané zápasy zůstanou v historii.")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var full: Bool { selected.count >= slots }

    private func personRow(id: UUID, name: String, username: String?, photo: Data?, subtitle: String) -> some View {
        let picked = PickedFriend(id: id, name: name)
        let inRoster = taken.contains(id)
        let isOn = selected.contains { $0.id == id }
        let series = h2h(for: id, name: name)
        return Button { toggle(picked) } label: {
            HStack(spacing: 12) {
                Avatar(name: name, size: 48, photo: photo)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    if let username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.action)
                    }
                    Text(inRoster ? "Už hraje" : subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(series.recordLine)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(h2hTint(series))
                    Text(series.played == 0 ? "bez zápasů" : "\(series.played)×")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: isOn || inRoster ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isOn ? Theme.action : Color.secondary.opacity(inRoster ? 0.5 : 1))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(inRoster || (full && !isOn))
        .accessibilityLabel("\(name), bilance \(series.recordLine)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func h2h(for personID: UUID, name: String) -> HeadToHead {
        let key = RivalKey(kind: .person(personID))
        guard let me = store.profile?.id else {
            return .empty(key: key, name: name)
        }
        return HeadToHead.series(from: store.matches, me: me, key: key)
            ?? .empty(key: key, name: name)
    }

    private func h2hTint(_ series: HeadToHead) -> Color {
        if series.played == 0 { return .secondary }
        if series.myWins > series.theirWins { return Theme.positive }
        if series.myWins < series.theirWins { return Color.red.opacity(0.85) }
        return .orange
    }

    private func toggle(_ friend: PickedFriend, forceOn: Bool = false) {
        guard !taken.contains(friend.id) else { return }
        if let index = selected.firstIndex(where: { $0.id == friend.id }) {
            if !forceOn { selected.remove(at: index) }
        } else if !full {
            selected.append(friend)
            if slots == 1 {
                confirm(selected)
            }
        }
    }

    private func confirm(_ picked: [PickedFriend]) {
        guard !picked.isEmpty else { return }
        onPick(picked)
        dismiss()
    }
}

/// Samostatná stránka pro vytvoření lokálního profilu kamaráda.
struct FriendCreateView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var onCreated: (Friend) -> Void

    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @FocusState private var focus: Field?

    private enum Field { case name, username, email }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            if let photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                            } else {
                                Avatar(name: name.isEmpty ? "?" : name, size: 96, photo: nil)
                            }
                            Image(systemName: "camera.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(Theme.action, in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Jméno", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .name)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focus, equals: .username)
                TextField("E-mail", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .focused($focus, equals: .email)
            } header: {
                Text("Profil kamaráda")
            } footer: {
                Text("Username a e-mail pomáhají při hledání. Vše zůstává jen na tomto telefonu.")
            }
        }
        .navigationTitle("Nový kamarád")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Uložit") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onAppear { focus = .name }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                photo = image
            }
        }
    }

    private func save() {
        guard let friend = store.createFriend(
            name: name,
            username: username.isEmpty ? nil : username,
            email: email.isEmpty ? nil : email,
            photo: photo
        ) else { return }
        store.feedback()
        onCreated(friend)
        dismiss()
    }
}

/// Úprava uloženého lokálního profilu kamaráda.
struct FriendEditView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var friendID: UUID
    var onSaved: (Friend) -> Void

    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var photoChanged = false
    @State private var loaded = false
    @FocusState private var focus: Field?

    private enum Field { case name, username, email }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        ZStack(alignment: .bottomTrailing) {
                            if let photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 96, height: 96)
                                    .clipShape(Circle())
                            } else {
                                Avatar(name: name.isEmpty ? "?" : name, size: 96, photo: nil)
                            }
                            Image(systemName: "camera.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(7)
                                .background(Theme.action, in: Circle())
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Jméno", text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .name)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .focused($focus, equals: .username)
                TextField("E-mail", text: $email)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .focused($focus, equals: .email)
            } header: {
                Text("Profil kamaráda")
            } footer: {
                Text("Změny zůstanou jen na tomto telefonu.")
            }
        }
        .navigationTitle("Upravit kamaráda")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Uložit") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                photo = image
                photoChanged = true
            }
        }
    }

    private func load() {
        guard !loaded, let friend = store.friends.first(where: { $0.id == friendID }) else { return }
        loaded = true
        name = friend.name
        username = friend.username ?? ""
        email = friend.email ?? ""
        if let data = friend.photoJPEG ?? store.photo(for: friend.id) {
            photo = UIImage(data: data)
        }
    }

    private func save() {
        guard let friend = store.updateFriend(
            friendID,
            name: name,
            username: username.isEmpty ? nil : username,
            email: email.isEmpty ? nil : email,
            photo: photoChanged ? photo : nil
        ) else { return }
        store.feedback()
        onSaved(friend)
        dismiss()
    }
}

/// Hledání registrovaných hráčů a profilů na tomto telefonu.
struct FriendFindView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = DartiqoAccount.shared
    @Environment(\.dismiss) private var dismiss
    var taken: Set<UUID>
    var onPick: (DartiqoPersonHit) -> Void

    @State private var query = ""
    @State private var remote: [DirectoryPerson] = []
    @State private var searching = false
    @State private var searchError: String?
    @State private var addingID: Int?
    @State private var searchGeneration = 0
    @State private var portraits: [Int: Data] = [:]
    @State private var portraitPaths: [Int: String] = [:]
    @FocusState private var focused: Bool

    private var localHits: [DartiqoPersonHit] {
        store.findDartiqoPeople(query: query)
    }

    private var ready: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    var body: some View {
        List {
            Section {
                TextField("Jméno, username nebo e-mail", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .focused($focused)
                    .submitLabel(.search)
            } footer: {
                Text("Hledá registrované hráče podle jména, username, nebo přesné e-mailové adresy. Přidáním se uloží mezi kamarády.")
            }

            if ready && !localHits.isEmpty {
                Section("Na tomto telefonu") {
                    ForEach(localHits) { hit in
                        let busy = taken.contains(hit.id)
                        Button {
                            guard !busy else { return }
                            onPick(hit)
                            dismiss()
                        } label: {
                            personLabel(
                                name: hit.name,
                                username: hit.username,
                                photo: hit.photoJPEG,
                                detail: hit.email,
                                action: busy ? "Už hraje" : "Přidat",
                                enabled: !busy
                            )
                        }
                        .disabled(busy)
                    }
                }
            }

            Section("Účty Dartiqo") {
                if !ready {
                    Text("Zadej aspoň 2 znaky.")
                        .foregroundStyle(.secondary)
                } else if searching && remote.isEmpty && searchError == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Hledám hráče…")
                            .foregroundStyle(.secondary)
                    }
                } else if let searchError, remote.isEmpty {
                    Text(searchError)
                        .foregroundStyle(.secondary)
                } else if remote.isEmpty {
                    Text(localHits.isEmpty
                         ? "Žádný účet tomu neodpovídá. Zkontroluj jméno, nebo vytvoř lokální profil."
                         : "V účtech Dartiqo nikdo další.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(remote) { person in
                        let saved = savedFriend(person)
                        let busy = saved.map { taken.contains($0.id) } ?? false
                        Button {
                            guard !busy, addingID == nil else { return }
                            Task { await add(person) }
                        } label: {
                            personLabel(
                                name: person.fullName.isEmpty ? person.username : person.fullName,
                                username: person.username,
                                photo: portrait(for: person) ?? saved?.photoJPEG,
                                detail: nil,
                                action: addingID == person.id ? "Ukládám…" : (busy ? "Už hraje" : (saved == nil ? "Přidat" : "Vybrat")),
                                enabled: !busy && addingID == nil
                            )
                        }
                        .disabled(busy || addingID != nil)
                    }
                }
            }
        }
        .navigationTitle("Najít v Dartiqo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onChange(of: query) { _, _ in scheduleSearch() }
    }

    private func personLabel(name: String, username: String?, photo: Data?, detail: String?, action: String, enabled: Bool) -> some View {
        HStack(spacing: 12) {
            Avatar(name: name, size: 44, photo: photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                if let username, !username.isEmpty {
                    Text("@\(username)").font(.caption).foregroundStyle(Theme.action)
                }
                if let detail, !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? Theme.action : Color.secondary)
        }
    }

    private func savedFriend(_ person: DirectoryPerson) -> Friend? {
        store.friends.first {
            $0.accountID == person.id || $0.username?.caseInsensitiveCompare(person.username) == .orderedSame
        }
    }

    private func scheduleSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        remote = []
        searchError = nil
        guard needle.count >= 2 else {
            searching = false
            return
        }
        searching = true
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard generation == searchGeneration else { return }
            await runSearch(needle, generation: generation)
        }
    }

    private func runSearch(_ needle: String, generation: Int) async {
        guard let api = account.api else {
            searching = false
            searchError = "Pro hledání účtů se přihlas k Dartiqo."
            return
        }
        do {
            let people = try await api.searchPeople(query: needle)
            guard generation == searchGeneration else { return }
            remote = people
            searching = false
            await loadPortraits(people)
        } catch {
            guard generation == searchGeneration else { return }
            searching = false
            searchError = "Hledání se nepovedlo. Zkus to znovu."
        }
    }

    private func portrait(for person: DirectoryPerson) -> Data? {
        guard portraitPaths[person.id] == person.photo else { return nil }
        return portraits[person.id]
    }

    private func loadPortraits(_ people: [DirectoryPerson]) async {
        let server = account.serverURL
        let jobs = people.compactMap { person -> (Int, String)? in
            guard let path = person.photo, portraitPaths[person.id] != path else { return nil }
            return (person.id, path)
        }
        guard !jobs.isEmpty else { return }
        let generation = searchGeneration
        await withTaskGroup(of: (Int, String, Data)?.self) { group in
            for (id, path) in jobs {
                group.addTask {
                    guard let data = await fetchedAvatar(path: path, server: server) else { return nil }
                    return (id, path, data)
                }
            }
            for await item in group {
                guard generation == searchGeneration, let (id, path, data) = item else { continue }
                portraits[id] = data
                portraitPaths[id] = path
            }
        }
    }

    private func add(_ person: DirectoryPerson) async {
        addingID = person.id
        defer { addingID = nil }
        var photo = portrait(for: person)
        if photo == nil {
            photo = await account.api?.downloadImage(person.photo)
        }
        let name = person.fullName.isEmpty ? person.username : person.fullName
        onPick(DartiqoPersonHit(
            id: savedFriend(person)?.id ?? UUID(),
            name: name,
            username: person.username,
            photoJPEG: photo,
            accountID: person.id
        ))
        dismiss()
    }
}

private extension Friend {
    var asPicked: PickedFriend { PickedFriend(id: id, name: name) }
}

/// Stáhne portrét mimo hlavní izolaci, ať se fotky ve výsledcích načtou najednou.
private nonisolated func fetchedAvatar(path: String, server: String) async -> Data? {
    let absolute: URL?
    if path.hasPrefix("http://") || path.hasPrefix("https://") {
        absolute = URL(string: path)
    } else {
        let root = server.hasSuffix("/") ? server : server + "/"
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        absolute = URL(string: relative, relativeTo: URL(string: root))?.absoluteURL
    }
    guard let absolute else { return nil }
    var request = URLRequest(url: absolute)
    request.timeoutInterval = 12
    guard let (data, response) = try? await URLSession.shared.data(for: request),
          (response as? HTTPURLResponse)?.statusCode == 200,
          !data.isEmpty else { return nil }
    return data
}

private struct ImportedContact {
    var name: String
    var photo: UIImage?
}

/// Systémový výběr kontaktů. Jméno přijde z výběru; fotka se dočte jen u vybraných lidí.
struct ContactPicker: UIViewControllerRepresentable {
    fileprivate var onPick: ([ImportedContact]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactNicknameKey,
            CNContactImageDataKey,
            CNContactThumbnailImageDataKey,
            CNContactImageDataAvailableKey
        ]
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        fileprivate let onPick: ([ImportedContact]) -> Void
        fileprivate init(onPick: @escaping ([ImportedContact]) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let drafts = contacts.compactMap { Self.draft(from: $0) }
            Task { @MainActor in
                let imported = await Self.resolvePhotos(drafts)
                self.onPick(imported)
            }
        }

        private struct Draft {
            var name: String
            var identifier: String
            var inlinePhoto: Data?
            var imageAvailable: Bool
        }

        private static func draft(from contact: CNContact) -> Draft? {
            let nick = contact.nickname.trimmingCharacters(in: .whitespaces)
            let name = nick.isEmpty
                ? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                : nick
            guard !name.isEmpty else { return nil }
            let inline = inlinePhoto(from: contact)
            let available = inline != nil || !contact.isKeyAvailable(CNContactImageDataAvailableKey) || contact.imageDataAvailable
            return Draft(name: name, identifier: contact.identifier, inlinePhoto: inline, imageAvailable: available)
        }

        private static func inlinePhoto(from contact: CNContact) -> Data? {
            if contact.isKeyAvailable(CNContactImageDataKey), let data = contact.imageData { return data }
            if contact.isKeyAvailable(CNContactThumbnailImageDataKey), let data = contact.thumbnailImageData { return data }
            return nil
        }

        private static func resolvePhotos(_ drafts: [Draft]) async -> [ImportedContact] {
            let store = CNContactStore()
            let needsPhotos = drafts.contains { $0.inlinePhoto == nil && $0.imageAvailable }
            let mayFetch: Bool
            if needsPhotos {
                mayFetch = await canReadPhotos(store)
            } else {
                mayFetch = false
            }
            let keys = [CNContactImageDataKey, CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
            return drafts.map { draft in
                var bytes = draft.inlinePhoto
                if bytes == nil, mayFetch, draft.imageAvailable,
                   let full = try? store.unifiedContact(withIdentifier: draft.identifier, keysToFetch: keys) {
                    bytes = full.imageData ?? full.thumbnailImageData
                }
                return ImportedContact(name: draft.name, photo: bytes.flatMap(UIImage.init(data:)))
            }
        }

        /// Výběr jména oprávnění nepotřebuje. Fotku systému vrátí až po souhlasu ke kontaktům.
        private static func canReadPhotos(_ store: CNContactStore) async -> Bool {
            switch CNContactStore.authorizationStatus(for: .contacts) {
            case .authorized, .limited:
                return true
            case .notDetermined:
                return (try? await store.requestAccess(for: .contacts)) ?? false
            default:
                return false
            }
        }
    }
}

#if DEBUG
#Preview {
    FriendPickerSheet(taken: [], slots: 2, onPick: { _ in })
        .dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
