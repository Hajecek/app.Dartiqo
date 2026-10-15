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
                                linkedProfileID: hit.id
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
                    Text("Vytvoř lokální profil, nebo najdi jiný profil na tomto telefonu podle username či e-mailu.")
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
                ContactPicker { names in
                    for name in names {
                        if let friend = store.addFriend(name) {
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

/// Hledání profilů v Dartiqo na tomto zařízení podle username nebo e-mailu.
struct FriendFindView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    var taken: Set<UUID>
    var onPick: (DartiqoPersonHit) -> Void

    @State private var query = ""
    @FocusState private var focused: Bool

    private var hits: [DartiqoPersonHit] {
        store.findDartiqoPeople(query: query)
    }

    var body: some View {
        List {
            Section {
                TextField("Username nebo e-mail", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .focused($focused)
                    .submitLabel(.search)
            } footer: {
                Text("Hledá mezi ostatními profily na tomto telefonu. Username a e-mail si každý nastaví v Nastavení.")
            }

            Section("Výsledky") {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                    Text("Zadej aspoň 2 znaky.")
                        .foregroundStyle(.secondary)
                } else if hits.isEmpty {
                    Text("Nikdo neodpovídá. Zkontroluj username nebo e-mail, případně vytvoř lokální profil.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hits) { hit in
                        let busy = taken.contains(hit.id)
                        Button {
                            guard !busy else { return }
                            onPick(hit)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Avatar(name: hit.name, size: 44, photo: hit.photoJPEG)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    if let username = hit.username, !username.isEmpty {
                                        Text("@\(username)").font(.caption).foregroundStyle(Theme.action)
                                    }
                                    if let email = hit.email, !email.isEmpty {
                                        Text(email).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(busy ? "Už hraje" : "Přidat")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(busy ? Color.secondary : Theme.action)
                            }
                        }
                        .disabled(busy)
                    }
                }
            }
        }
        .navigationTitle("Najít v Dartiqo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }
}

private extension Friend {
    var asPicked: PickedFriend { PickedFriend(id: id, name: name) }
}

/// Systémový výběr kontaktů. Aplikace nepotřebuje přístup ke všem kontaktům.
struct ContactPicker: UIViewControllerRepresentable {
    var onPick: ([String]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey]
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([String]) -> Void
        init(onPick: @escaping ([String]) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let names = contacts.compactMap { contact -> String? in
                let nick = contact.nickname.trimmingCharacters(in: .whitespaces)
                if !nick.isEmpty { return nick }
                let full = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                return full.isEmpty ? nil : full
            }
            onPick(names)
        }
    }
}

#if DEBUG
#Preview {
    FriendPickerSheet(taken: [], slots: 2, onPick: { _ in })
        .dartiqoPreview(PreviewSupport.store(activeMatch: false))
}
#endif
