import SwiftUI

private enum FriendFolder: Hashable {
    case friends, requests
}

/// Vstup na stránku kamarádů z profilu.
struct FriendsProfileEntry: View {
    @EnvironmentObject private var store: AppStore

    private var incoming: Int { store.incomingFriendRequests }

    var body: some View {
        NavigationLink {
            FriendsView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.action)
                    .frame(width: 44, height: 44)
                    .background(Theme.action.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Kamarádi")
                        .font(.headline)
                    Text(incomingLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if incoming > 0 {
                    Text("\(incoming)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.brandBlack)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.brand, in: Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(incoming > 0 ? "Kamarádi, \(incoming) žádostí" : "Kamarádi")
        .task { await store.refreshAccountFriends() }
    }

    private var incomingLabel: String {
        switch incoming {
        case 0: return "Hledání hráčů a žádosti"
        case 1: return "1 žádost čeká na tebe"
        case 2...4: return "\(incoming) žádosti čekají na tebe"
        default: return "\(incoming) žádostí čeká na tebe"
        }
    }
}

/// Samostatná stránka: hledání, příchozí žádosti a přijatí kamarádi.
struct FriendsView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = DartiqoAccount.shared
    @State private var book = FriendBook.empty
    @State private var loading = true
    @State private var error: String?
    @State private var note: String?
    @State private var query = ""
    @State private var hits: [DirectoryPerson] = []
    @State private var searching = false
    @State private var searchGeneration = 0
    @State private var portraits: [Int: Data] = [:]
    @State private var busyID: Int?
    @State private var pendingRemove: FriendLink?
    @State private var folder = FriendFolder.friends
    @State private var didPickFolder = false
    @FocusState private var focused: Bool

    private var ready: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    private var requestCount: Int { book.incoming.count + book.outgoing.count }

    var body: some View {
        List {
            Section {
                Picker("Složka", selection: $folder) {
                    Text("Kamarádi").tag(FriendFolder.friends)
                    Text(book.incoming.isEmpty ? "Žádosti" : "Žádosti (\(book.incoming.count))").tag(FriendFolder.requests)
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            if let note {
                Section { Text(note).foregroundStyle(.secondary) }
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }

            if folder == .friends {
                friendsFolder
            } else {
                requestsFolder
            }
        }
        .navigationTitle(folder == .friends ? "Kamarádi" : "Žádosti")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .confirmationDialog(
            "Odebrat kamaráda?",
            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemove
        ) { link in
            Button("Odebrat", role: .destructive) { Task { await remove(link) } }
            Button("Zrušit", role: .cancel) {}
        } message: { link in
            Text("\(display(link.user)) zmizí z kamarádů. Žádost pak půjde poslat znovu.")
        }
    }

    @ViewBuilder
    private var friendsFolder: some View {
        Section {
            TextField("Jméno, username nebo e-mail", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .focused($focused)
                .submitLabel(.search)
        } footer: {
            Text("Tady jsou jen přijatí kamarádi. Nového hráče přidáš žádostí, kterou musí potvrdit.")
        }

        if ready {
            Section("Hledání") {
                if searching && hits.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Hledám hráče…").foregroundStyle(.secondary)
                    }
                } else if hits.isEmpty {
                    Text("Nikdo takový v Dartiqo není.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(hits) { person in
                        row(user: person, detail: detail(for: person)) {
                            searchButton(person)
                        }
                    }
                }
            }
        }

        Section {
            if loading && book.friends.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Načítám…").foregroundStyle(.secondary)
                }
            } else if book.friends.isEmpty {
                Text("Zatím tu nikdo není.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(book.friends) { link in
                    row(user: link.user, detail: "@\(link.user.username)") { EmptyView() }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Odebrat", role: .destructive) { pendingRemove = link }
                        }
                }
            }
        } header: {
            Text("Přijatí")
        }
    }

    @ViewBuilder
    private var requestsFolder: some View {
        Section {
            if book.incoming.isEmpty {
                Text("Žádná nová žádost. Až ti někdo napíše, objeví se tady a můžeš ji přijmout.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(book.incoming) { link in
                    row(user: link.user, detail: "Chce být kamarád") {
                        HStack(spacing: 8) {
                            Button("Odmítnout") { Task { await decline(link) } }
                                .buttonStyle(.bordered)
                            Button("Přijmout") { Task { await accept(link) } }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.action)
                        }
                        .controlSize(.small)
                    }
                    .disabled(busyID != nil)
                }
            }
        } header: {
            Text("Přišlé")
        } footer: {
            Text("Přijetím se z vás stanou kamarádi. Stejnou žádost jde potvrdit i na webu.")
        }

        Section {
            if book.outgoing.isEmpty {
                Text(requestCount == 0 ? "Nic jsi neposlal." : "Žádná čekající odeslaná žádost.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(book.outgoing) { link in
                    row(user: link.user, detail: "Čeká na přijetí") {
                        Button("Zrušit") { Task { await cancel(link) } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .disabled(busyID != nil)
                }
            }
        } header: {
            Text("Odeslané")
        }
    }

    private func row<Trailing: View>(user: DirectoryPerson, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Avatar(name: display(user), size: 44, photo: photo(for: user))
            VStack(alignment: .leading, spacing: 2) {
                Text(display(user))
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.action)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }

    private func searchTitle(_ person: DirectoryPerson) -> String {
        switch person.relation ?? "none" {
        case "accepted": return "Kamarádi"
        case "outgoing": return "Odesláno"
        case "incoming": return "Přijmout"
        default: return busyID == person.id ? "Posílám…" : "Žádost"
        }
    }

    @ViewBuilder
    private func searchButton(_ person: DirectoryPerson) -> some View {
        let state = person.relation ?? "none"
        Button(searchTitle(person)) { Task { await send(person) } }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(state == "accepted" || state == "outgoing" || busyID != nil)
    }

    private func display(_ user: DirectoryPerson) -> String {
        user.fullName.isEmpty ? user.username : user.fullName
    }

    private func detail(for person: DirectoryPerson) -> String {
        let handle = "@\(person.username)"
        switch person.relation ?? "none" {
        case "accepted": return "\(handle) · už je kamarád"
        case "outgoing": return "\(handle) · žádost odeslána"
        case "incoming": return "\(handle) · čeká na tvoje přijetí"
        case "declined": return "\(handle) · můžeš poslat znovu"
        default: return handle
        }
    }

    private func photo(for user: DirectoryPerson) -> Data? {
        if let data = portraits[user.id] { return data }
        if let friend = store.friends.first(where: { $0.accountID == user.id }) {
            return store.photo(for: friend.id)
        }
        return nil
    }

    private func reload() async {
        guard account.api != nil else {
            loading = false
            error = "Pro kamarády se přihlas k Dartiqo."
            return
        }
        if let fresh = await store.refreshAccountFriends() {
            book = fresh
            error = nil
            if !didPickFolder {
                didPickFolder = true
                if !fresh.incoming.isEmpty { folder = .requests }
            }
        } else {
            error = "Seznam se nepovedlo načíst."
        }
        loading = false
        await loadPortraits(book.incoming.map(\.user) + book.outgoing.map(\.user) + book.friends.map(\.user) + hits)
    }

    private func scheduleSearch() {
        searchGeneration += 1
        let generation = searchGeneration
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hits = []
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
        guard let api = account.api else { return }
        do {
            let people = try await api.searchPeople(query: needle)
            guard generation == searchGeneration else { return }
            hits = people
            searching = false
            await loadPortraits(people)
        } catch {
            guard generation == searchGeneration else { return }
            searching = false
            self.error = "Hledání se nepovedlo. Zkus to znovu."
        }
    }

    private func loadPortraits(_ people: [DirectoryPerson]) async {
        for person in people {
            guard portraits[person.id] == nil, person.photo != nil else { continue }
            if let data = await account.api?.downloadImage(person.photo) {
                portraits[person.id] = data
            }
        }
    }

    private func send(_ person: DirectoryPerson) async {
        let state = person.relation ?? "none"
        guard state != "accepted", state != "outgoing", let api = account.api else { return }
        busyID = person.id
        defer { busyID = nil }
        do {
            let result = try await api.requestFriend(userId: person.id)
            let accepted = result.relation == "accepted" || result.link.status == "accepted"
            note = accepted ? "\(display(person)) je teď kamarád." : "Žádost pro \(display(person)) je odeslaná. Kamarádem bude, až ji přijme."
            if accepted { store.tapHaptic() }
            await reload()
            if let index = hits.firstIndex(where: { $0.id == person.id }) {
                hits[index].relation = accepted ? "accepted" : "outgoing"
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func accept(_ link: FriendLink) async {
        await act(link, accepted: true) {
            guard let api = account.api else { return }
            _ = try await api.acceptFriend(link.id)
        }
    }

    private func decline(_ link: FriendLink) async {
        await act(link, accepted: false) {
            guard let api = account.api else { return }
            try await api.declineFriend(link.id)
        }
    }

    private func cancel(_ link: FriendLink) async {
        await act(link, accepted: false) {
            guard let api = account.api else { return }
            try await api.cancelFriend(link.id)
        }
    }

    private func remove(_ link: FriendLink) async {
        pendingRemove = nil
        await act(link, accepted: false) {
            guard let api = account.api else { return }
            try await api.removeFriend(link.id)
        }
    }

    private func act(_ link: FriendLink, accepted: Bool, work: () async throws -> Void) async {
        busyID = link.id
        defer { busyID = nil }
        do {
            try await work()
            note = accepted ? "\(display(link.user)) je kamarád." : nil
            if accepted { store.tapHaptic() }
            error = nil
            await reload()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
