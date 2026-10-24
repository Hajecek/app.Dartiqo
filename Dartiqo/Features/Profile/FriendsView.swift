import SwiftUI
import Combine

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
        case 0: return "Hledání, žádosti a seznam"
        case 1: return "1 žádost čeká na tebe"
        case 2...4: return "\(incoming) žádosti čekají na tebe"
        default: return "\(incoming) žádostí čeká na tebe"
        }
    }
}

/// Hledání hráčů. Žádosti a přijatí kamarádi jsou na vlastních stránkách.
struct FriendsView: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = DartiqoAccount.shared
    @StateObject private var directory = FriendDirectory()
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if account.api == nil {
                    EmptyCard(
                        title: "Přihlas se k Dartiqo",
                        subtitle: "Kamarádi, žádosti i hledání jsou na účtu.",
                        symbol: "person.crop.circle.badge.plus"
                    )
                } else {
                    hub
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .navigationTitle("Kamarádi")
        .navigationSubtitle("Hledání hráčů")
        .navigationBarTitleDisplayMode(.inline)
        .task { await directory.reload(store: store, account: account) }
        .refreshable { await directory.reload(store: store, account: account) }
        .onChange(of: directory.query) { _, _ in
            directory.scheduleSearch(account: account)
        }
    }

    @ViewBuilder
    private var hub: some View {
        banners
        if !directory.book.incoming.isEmpty {
            inboxLink(prominent: true)
        }
        searchGroup
        if directory.ready {
            searchResults
        } else {
            rosterLink
            if directory.book.incoming.isEmpty {
                inboxLink(prominent: false)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        if directory.note != nil || directory.error != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let note = directory.note {
                    FriendBanner(text: note, symbol: "checkmark.circle.fill", tint: Theme.positive)
                }
                if let error = directory.error {
                    FriendBanner(text: error, symbol: "exclamationmark.triangle.fill", tint: .red)
                }
            }
        }
    }

    private var searchGroup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Jméno, username nebo e-mail", text: $directory.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .focused($focused)
                    .submitLabel(.search)
                    .accessibilityLabel("Hledat hráče")
                if !directory.query.isEmpty {
                    Button {
                        directory.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Smazat hledání")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(focused ? Theme.accent : Theme.stroke, lineWidth: focused ? 1.5 : 0.5)
            )

            if !directory.ready {
                Text("Nového hráče přidáš žádostí. Kamarádem se stane, až ji přijme.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Výsledky")
            if directory.searching && directory.hits.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Hledám hráče…").foregroundStyle(.secondary)
                }
                .friendCard()
            } else if directory.hits.isEmpty {
                Text("Nikdo takový v Dartiqo není.")
                    .foregroundStyle(.secondary)
                    .friendCard()
            } else {
                ForEach(directory.hits) { person in
                    searchRow(person)
                }
            }
        }
    }

    private func searchRow(_ person: DirectoryPerson) -> some View {
        let state = person.relation ?? "none"
        let locked = state == "accepted" || state == "outgoing"
        return FriendPersonRow(
            name: FriendCopy.display(person),
            detail: FriendCopy.detail(for: person),
            photo: directory.photo(for: person, store: store),
            detailColor: state == "accepted" ? Theme.positive : .secondary
        ) {
            if locked {
                Text(state == "accepted" ? "Kamarádi" : "Odesláno")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            } else {
                FriendActionButton(
                    title: state == "incoming" ? "Přijmout" : "Žádost",
                    busy: directory.busyID == person.id,
                    enabled: directory.busyID == nil
                ) {
                    Task { await directory.send(person, store: store, account: account) }
                }
            }
        }
        .friendCard()
    }

    private func inboxLink(prominent: Bool) -> some View {
        NavigationLink {
            FriendInboxView(directory: directory)
        } label: {
            if prominent {
                prominentInbox
            } else {
                quietInbox
            }
        }
        .buttonStyle(.plain)
    }

    private var prominentInbox: some View {
        let count = directory.book.incoming.count
        return HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.clock")
                .font(.title2.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Theme.brandBlack.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Přijmout kamaráda")
                    .font(.title3.bold())
                Text(FriendCopy.incoming(count))
                    .font(.subheadline.weight(.medium))
                    .opacity(0.7)
            }
            Spacer(minLength: 8)
            Text("\(count)")
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.brand)
                .frame(minWidth: 36, minHeight: 36)
                .background(Theme.brandBlack, in: Capsule())
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .accessibilityHidden(true)
        }
        .foregroundStyle(Theme.brandBlack)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Přijmout kamaráda. \(FriendCopy.incoming(count))")
        .accessibilityHint("Otevře přišlé žádosti")
        .friendCard(prominent: true)
    }

    private var quietInbox: some View {
        let outgoing = directory.book.outgoing.count
        return HStack(spacing: 14) {
            Image(systemName: "tray.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.action)
                .frame(width: 48, height: 48)
                .background(Theme.action.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Žádosti")
                    .font(.headline)
                Text(outgoing == 0 ? "Přišlé a odeslané" : FriendCopy.outgoing(outgoing))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if outgoing > 0 {
                Text("\(outgoing)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.brandBlack)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.brand, in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Otevře přišlé a odeslané žádosti")
        .friendCard()
    }

    private var rosterLink: some View {
        NavigationLink {
            FriendRosterView(directory: directory)
        } label: {
            HStack(spacing: 14) {
                avatarStack
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tvoji kamarádi")
                        .font(.headline)
                    Text(rosterSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Tvoji kamarádi. \(rosterSubtitle)")
            .accessibilityHint("Otevře seznam přijatých kamarádů")
            .friendCard()
        }
        .buttonStyle(.plain)
    }

    private var rosterSubtitle: String {
        let count = directory.book.friends.count
        if directory.loading && count == 0 { return "Načítám…" }
        if count == 0 { return "Zatím tu nikdo není" }
        return FriendCopy.friends(count)
    }

    @ViewBuilder
    private var avatarStack: some View {
        let friends = directory.book.friends
        if directory.loading && friends.isEmpty {
            ProgressView()
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
        } else if friends.isEmpty {
            Image(systemName: "person.2.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.action)
                .frame(width: 48, height: 48)
                .background(Theme.action.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
        } else {
            HStack(spacing: -12) {
                ForEach(Array(friends.prefix(3))) { link in
                    Avatar(
                        name: FriendCopy.display(link.user),
                        size: 40,
                        photo: directory.photo(for: link.user, store: store)
                    )
                    .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                }
                if friends.count > 3 {
                    Text("+\(friends.count - 3)")
                        .font(.caption2.weight(.bold))
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 40, height: 40)
                        .background(Theme.background, in: Circle())
                        .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
                }
            }
            .frame(minHeight: 48, alignment: .leading)
            .accessibilityHidden(true)
        }
    }
}

/// Přišlé žádosti k přijetí a odeslané, které ještě čekají.
private struct FriendInboxView: View {
    @ObservedObject var directory: FriendDirectory
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = DartiqoAccount.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                notices
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Čekají na tebe")
                    if directory.loading && directory.book.incoming.isEmpty && directory.book.outgoing.isEmpty {
                        loadingRow
                    } else if directory.book.incoming.isEmpty {
                        Text("Žádná nová žádost. Až ti někdo napíše, objeví se tady a můžeš ji přijmout.")
                            .foregroundStyle(.secondary)
                            .friendCard()
                    } else {
                        ForEach(directory.book.incoming) { link in
                            incomingCard(link)
                        }
                        Text("Přijetím se z vás stanou kamarádi. Stejnou žádost jde potvrdit i na webu.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Čekáš na ně")
                    if directory.book.outgoing.isEmpty {
                        Text(directory.book.incoming.isEmpty ? "Nic jsi neposlal." : "Žádná čekající odeslaná žádost.")
                            .foregroundStyle(.secondary)
                            .friendCard()
                    } else {
                        ForEach(directory.book.outgoing) { link in
                            outgoingCard(link)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("Žádosti")
        .navigationSubtitle("Přišlé a odeslané")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await directory.reload(store: store, account: account) }
    }

    @ViewBuilder
    private var notices: some View {
        if directory.note != nil || directory.error != nil {
            VStack(alignment: .leading, spacing: 10) {
                if let note = directory.note {
                    FriendBanner(text: note, symbol: "checkmark.circle.fill", tint: Theme.positive)
                }
                if let error = directory.error {
                    FriendBanner(text: error, symbol: "exclamationmark.triangle.fill", tint: .red)
                }
            }
        }
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Načítám…").foregroundStyle(.secondary)
        }
        .friendCard()
    }

    private func incomingCard(_ link: FriendLink) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            FriendPersonRow(
                name: FriendCopy.display(link.user),
                detail: "Chce být kamarád",
                photo: directory.photo(for: link.user, store: store)
            ) { EmptyView() }
            if directory.busyID == link.id {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 10) {
                    wideButton("Odmítnout", prominent: false) {
                        Task { await directory.decline(link, store: store, account: account) }
                    }
                    wideButton("Přijmout", prominent: true) {
                        Task { await directory.accept(link, store: store, account: account) }
                    }
                }
                .disabled(directory.busyID != nil)
            }
        }
        .opacity(directory.busyID != nil && directory.busyID != link.id ? 0.45 : 1)
        .friendCard()
    }

    private func outgoingCard(_ link: FriendLink) -> some View {
        FriendPersonRow(
            name: FriendCopy.display(link.user),
            detail: "Čeká na přijetí",
            photo: directory.photo(for: link.user, store: store)
        ) {
            FriendActionButton(
                title: "Zrušit",
                prominent: false,
                busy: directory.busyID == link.id,
                enabled: directory.busyID == nil
            ) {
                Task { await directory.cancel(link, store: store, account: account) }
            }
        }
        .opacity(directory.busyID != nil && directory.busyID != link.id ? 0.45 : 1)
        .friendCard()
    }

    private func wideButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(prominent ? Theme.onAccent : .primary)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(prominent ? Theme.accentFill : Theme.background)
                }
        }
        .buttonStyle(.plain)
    }
}

/// Seznam přijatých kamarádů a jejich vzájemná bilance.
private struct FriendRosterView: View {
    @ObservedObject var directory: FriendDirectory
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = DartiqoAccount.shared
    @State private var pendingRemove: FriendLink?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if directory.note != nil || directory.error != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        if let note = directory.note {
                            FriendBanner(text: note, symbol: "checkmark.circle.fill", tint: Theme.positive)
                        }
                        if let error = directory.error {
                            FriendBanner(text: error, symbol: "exclamationmark.triangle.fill", tint: .red)
                        }
                    }
                }
                if directory.loading && directory.book.friends.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Načítám…").foregroundStyle(.secondary)
                    }
                    .friendCard()
                } else if directory.book.friends.isEmpty {
                    EmptyCard(
                        title: "Zatím tu nikdo není",
                        subtitle: "Pošli žádost z hledání. Kamarádem se stane, až ji přijme.",
                        symbol: "person.2"
                    )
                } else {
                    ForEach(directory.book.friends) { link in
                        friendCard(link)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .screen()
        .navigationTitle("Tvoji kamarádi")
        .navigationSubtitle(subtitle)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await directory.reload(store: store, account: account) }
        .confirmationDialog(
            "Odebrat kamaráda?",
            isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } }),
            titleVisibility: .visible,
            presenting: pendingRemove
        ) { link in
            Button("Odebrat", role: .destructive) {
                pendingRemove = nil
                Task { await directory.remove(link, store: store, account: account) }
            }
            Button("Zrušit", role: .cancel) {}
        } message: { link in
            Text("\(FriendCopy.display(link.user)) zmizí z kamarádů. Žádost pak půjde poslat znovu.")
        }
    }

    private var subtitle: String {
        let count = directory.book.friends.count
        if directory.loading && count == 0 { return "Načítám" }
        if count == 0 { return "Zatím nikdo" }
        return FriendCopy.friends(count)
    }

    private func friendCard(_ link: FriendLink) -> some View {
        HStack(spacing: 8) {
            NavigationLink {
                FriendRecordView(link: link, photo: directory.photo(for: link.user, store: store))
            } label: {
                HStack(spacing: 12) {
                    Avatar(
                        name: FriendCopy.display(link.user),
                        size: 48,
                        photo: directory.photo(for: link.user, store: store)
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(FriendCopy.display(link.user))
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(FriendCopy.friendLine(link))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if let summary = link.summary, summary.mutual.played > 0 {
                        Text("\(summary.mutual.wins) : \(summary.mutual.losses)")
                            .font(.title3.weight(.heavy))
                            .monospacedDigit()
                            .foregroundStyle(scoreTint(summary.mutual.wins, summary.mutual.losses))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("Odebrat", role: .destructive) { pendingRemove = link }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Akce pro \(FriendCopy.display(link.user))")
        }
        .friendCard()
    }

    private func scoreTint(_ wins: Int, _ losses: Int) -> Color {
        if wins > losses { return Theme.positive }
        if losses > wins { return .red }
        return .secondary
    }
}

@MainActor
private final class FriendDirectory: ObservableObject {
    @Published var book = FriendBook.empty
    @Published var loading = true
    @Published var error: String?
    @Published var note: String?
    @Published var query = ""
    @Published var hits: [DirectoryPerson] = []
    @Published var searching = false
    @Published var portraits: [Int: Data] = [:]
    @Published var busyID: Int?

    private var searchGeneration = 0
    private var reloadGeneration = 0

    var ready: Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
    }

    func reload(store: AppStore, account: DartiqoAccount) async {
        reloadGeneration += 1
        let generation = reloadGeneration
        guard account.api != nil else {
            loading = false
            error = "Pro kamarády se přihlas k Dartiqo."
            return
        }
        let fresh = await store.refreshAccountFriends()
        guard generation == reloadGeneration else { return }
        if let fresh {
            book = fresh
            error = nil
        } else {
            error = "Seznam se nepovedlo načíst."
        }
        loading = false
        let people = book.incoming.map(\.user) + book.outgoing.map(\.user) + book.friends.map(\.user) + hits
        await loadPortraits(people, account: account)
    }

    func scheduleSearch(account: DartiqoAccount) {
        searchGeneration += 1
        let generation = searchGeneration
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        hits = []
        guard needle.count >= 2 else {
            searching = false
            if error == "Hledání se nepovedlo. Zkus to znovu." { error = nil }
            return
        }
        searching = true
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard generation == searchGeneration else { return }
            await runSearch(needle, generation: generation, account: account)
        }
    }

    func photo(for user: DirectoryPerson, store: AppStore) -> Data? {
        if let data = portraits[user.id] { return data }
        if let friend = store.friends.first(where: { $0.accountID == user.id }) {
            return store.photo(for: friend.id)
        }
        return nil
    }

    func send(_ person: DirectoryPerson, store: AppStore, account: DartiqoAccount) async {
        let state = person.relation ?? "none"
        guard state != "accepted", state != "outgoing", let api = account.api else { return }
        busyID = person.id
        defer { busyID = nil }
        do {
            let result = try await api.requestFriend(userId: person.id)
            let accepted = result.relation == "accepted" || result.link.status == "accepted"
            note = accepted
                ? "\(FriendCopy.display(person)) je teď kamarád."
                : "Žádost pro \(FriendCopy.display(person)) je odeslaná. Kamarádem bude, až ji přijme."
            if accepted { store.tapHaptic() }
            error = nil
            await reload(store: store, account: account)
            let relation = accepted ? "accepted" : "outgoing"
            hits = hits.map { item in
                guard item.id == person.id else { return item }
                var copy = item
                copy.relation = relation
                return copy
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func accept(_ link: FriendLink, store: AppStore, account: DartiqoAccount) async {
        guard account.api != nil else { return }
        await mutate(id: link.id, store: store, account: account, acceptedNote: "\(FriendCopy.display(link.user)) je kamarád.") {
            guard let api = account.api else { return }
            _ = try await api.acceptFriend(link.id)
        }
    }

    func decline(_ link: FriendLink, store: AppStore, account: DartiqoAccount) async {
        guard account.api != nil else { return }
        await mutate(id: link.id, store: store, account: account, acceptedNote: nil) {
            guard let api = account.api else { return }
            try await api.declineFriend(link.id)
        }
    }

    func cancel(_ link: FriendLink, store: AppStore, account: DartiqoAccount) async {
        guard account.api != nil else { return }
        await mutate(id: link.id, store: store, account: account, acceptedNote: nil) {
            guard let api = account.api else { return }
            try await api.cancelFriend(link.id)
        }
    }

    func remove(_ link: FriendLink, store: AppStore, account: DartiqoAccount) async {
        guard account.api != nil else { return }
        await mutate(id: link.id, store: store, account: account, acceptedNote: nil) {
            guard let api = account.api else { return }
            try await api.removeFriend(link.id)
        }
    }

    private func mutate(
        id: Int,
        store: AppStore,
        account: DartiqoAccount,
        acceptedNote: String?,
        work: () async throws -> Void
    ) async {
        busyID = id
        defer { busyID = nil }
        do {
            try await work()
            note = acceptedNote
            if acceptedNote != nil { store.tapHaptic() }
            error = nil
            await reload(store: store, account: account)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runSearch(_ needle: String, generation: Int, account: DartiqoAccount) async {
        guard let api = account.api else {
            searching = false
            return
        }
        do {
            let people = try await api.searchPeople(query: needle)
            guard generation == searchGeneration else { return }
            hits = people
            searching = false
            error = nil
            await loadPortraits(people, account: account)
        } catch {
            guard generation == searchGeneration else { return }
            searching = false
            self.error = "Hledání se nepovedlo. Zkus to znovu."
        }
    }

    private func loadPortraits(_ people: [DirectoryPerson], account: DartiqoAccount) async {
        for person in people {
            guard portraits[person.id] == nil, person.photo != nil else { continue }
            if let data = await account.api?.downloadImage(person.photo) {
                var next = portraits
                next[person.id] = data
                portraits = next
            }
        }
    }
}

private enum FriendCopy {
    static func display(_ user: DirectoryPerson) -> String {
        user.fullName.isEmpty ? user.username : user.fullName
    }

    static func detail(for person: DirectoryPerson) -> String {
        let handle = "@\(person.username)"
        switch person.relation ?? "none" {
        case "accepted": return "\(handle) · už je kamarád"
        case "outgoing": return "\(handle) · žádost odeslána"
        case "incoming": return "\(handle) · čeká na tvoje přijetí"
        case "declined": return "\(handle) · můžeš poslat znovu"
        default: return handle
        }
    }

    static func friendLine(_ link: FriendLink) -> String {
        let handle = "@\(link.user.username)"
        guard let summary = link.summary else { return handle }
        if let average = summary.career.average {
            return "\(handle) · průměr \(oneDecimal(average))"
        }
        if summary.mutual.played == 0, summary.career.played > 0 {
            return "\(handle) · \(plural(summary.career.played, one: "zápas", few: "zápasy", many: "zápasů"))"
        }
        return handle
    }

    static func friends(_ count: Int) -> String {
        plural(count, one: "kamarád", few: "kamarádi", many: "kamarádů")
    }

    static func incoming(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if count == 1 { return "1 žádost čeká na tebe" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) {
            return "\(count) žádosti čekají na tebe"
        }
        return "\(count) žádostí čeká na tebe"
    }

    static func outgoing(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if count == 1 { return "1 odeslaná žádost čeká" }
        if (2...4).contains(mod10), !(12...14).contains(mod100) {
            return "\(count) odeslané žádosti čekají"
        }
        return "\(count) odeslaných žádostí čeká"
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        let word: String
        if count == 1 {
            word = one
        } else if (2...4).contains(mod10), !(12...14).contains(mod100) {
            word = few
        } else {
            word = many
        }
        return "\(count) \(word)"
    }
}

private struct FriendPersonRow<Trailing: View>: View {
    var name: String
    var detail: String
    var photo: Data?
    var detailColor: Color = .secondary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: name, size: 48, photo: photo)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
    }
}

private struct FriendActionButton: View {
    var title: String
    var prominent = true
    var busy: Bool
    var enabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if busy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(prominent ? Theme.onAccent : Theme.accent)
                } else {
                    Text(title)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Theme.onAccent : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minWidth: 76)
            .background {
                Capsule().fill(prominent ? Theme.accentFill : Color.clear)
            }
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(Theme.stroke, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!enabled || busy)
        .opacity(enabled || busy ? 1 : 0.45)
    }
}

private struct FriendBanner: View {
    var text: String
    var symbol: String
    var tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .friendCard()
    }
}

private struct FriendCardModifier: ViewModifier {
    var prominent = false

    private var radius: CGFloat { prominent ? 28 : 22 }

    func body(content: Content) -> some View {
        content
            .padding(prominent ? 18 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(prominent ? Theme.brand : Theme.card)
                    .overlay(alignment: .topTrailing) {
                        if prominent {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 96, weight: .bold))
                                .foregroundStyle(Theme.brandBlack.opacity(0.06))
                                .offset(x: 20, y: -18)
                                .accessibilityHidden(true)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Theme.stroke, lineWidth: 0.5)
                }
            }
            .contentShape(Rectangle())
    }
}

private extension View {
    func friendCard(prominent: Bool = false) -> some View {
        modifier(FriendCardModifier(prominent: prominent))
    }
}

/// Statistiky kamaráda a zápasy, které jste spolu odehráli.
struct FriendRecordView: View {
    let link: FriendLink
    var photo: Data?

    @ObservedObject private var account = DartiqoAccount.shared
    @State private var record: FriendRecord?
    @State private var loading = true
    @State private var error: String?
    @State private var portrait: Data?

    private var name: String {
        link.user.fullName.isEmpty ? link.user.username : link.user.fullName
    }

    private var theirFirst: String {
        link.user.first.isEmpty ? link.user.username : link.user.first
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Avatar(name: name, size: 56, photo: portrait ?? photo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name).font(.headline)
                        Text("@\(link.user.username)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error {
                Section { Text(error).foregroundStyle(.red) }
            } else if loading && record == nil {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Načítám zápasy…").foregroundStyle(.secondary)
                    }
                }
            }

            if let record {
                Section {
                    stat("Průměr", record.career.average.map { String(format: "%.1f", $0) } ?? "–")
                    stat("Zápasy", "\(record.career.played)")
                    stat("Výhry", "\(record.career.wins)")
                    stat("Úspěšnost", record.career.winRate.map { "\($0) %" } ?? "–")
                } header: {
                    Text("Jeho hra")
                } footer: {
                    Text("Ze zápasů, které nahrál na svůj účet.")
                }

                Section {
                    if record.mutual.played == 0 {
                        Text(record.standing).foregroundStyle(.secondary)
                    } else {
                        Text("\(record.mutual.wins) : \(record.mutual.losses)")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(record.standing).foregroundStyle(.secondary)
                        stat("Tvůj průměr", record.myAverage.map { String(format: "%.1f", $0) } ?? "–")
                        stat("Průměr \(theirFirst)", record.theirAverage.map { String(format: "%.1f", $0) } ?? "–")
                    }
                } header: {
                    Text("Vzájemně")
                }

                Section {
                    if record.games.isEmpty {
                        Text("Zatím tu žádný není.").foregroundStyle(.secondary)
                    } else {
                        ForEach(record.games) { game in
                            HStack(spacing: 12) {
                                Text(mark(game.result))
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(tint(game.result))
                                    .frame(width: 28, height: 28)
                                    .background(tint(game.result).opacity(0.15), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(game.title).font(.body.weight(.semibold)).lineLimit(1)
                                    Text(gameCaption(game))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(game.score)
                                        .font(.body.weight(.semibold))
                                        .monospacedDigit()
                                    Text(game.label)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Vzájemné zápasy")
                } footer: {
                    if !record.games.isEmpty {
                        Text("Výsledek je z tvého pohledu. Když zápas nahrál jen on, je tu bez odkazu na celý průběh.")
                    }
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func gameCaption(_ game: FriendRecord.Game) -> String {
        var line = "\(game.mode) · \(game.when)"
        if game.myAverage != nil || game.theirAverage != nil {
            let mine = game.myAverage.map { String(format: "%.1f", $0) } ?? "–"
            let theirs = game.theirAverage.map { String(format: "%.1f", $0) } ?? "–"
            line += " · \(mine) / \(theirs)"
        }
        return line
    }

    private func mark(_ result: String) -> String {
        switch result {
        case "win": return "V"
        case "loss": return "P"
        default: return "R"
        }
    }

    private func tint(_ result: String) -> Color {
        switch result {
        case "win": return Theme.positive
        case "loss": return .red
        default: return .secondary
        }
    }

    private func load() async {
        portrait = photo
        if portrait == nil, let data = await account.api?.downloadImage(link.user.photo) {
            portrait = data
        }
        guard let api = account.api else {
            loading = false
            error = "Pro statistiky se přihlas k Dartiqo."
            return
        }
        do {
            record = try await api.friendRecord(link.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
