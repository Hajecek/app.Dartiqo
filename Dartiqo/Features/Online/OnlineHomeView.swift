import SwiftUI
import Combine

enum OnlineRoute: Hashable {
    case create
    case join
    case room(String)
    case edit(String)
}

/// Stav online lobby a zápasu. Skóre drží server, telefon ho jen zobrazuje a posílá šipku.
@MainActor
final class OnlineSession: ObservableObject {
    @Published var current: OnlineMatch?
    @Published var match: OnlineMatch?
    @Published var invites: [OnlineInvite] = []
    @Published var lobbyInvites: [OnlineLobbyInvite] = []
    @Published var lobbies: [OnlineLobby] = []
    @Published var friends: [FriendLink] = []
    @Published var notice: String?
    @Published var busy = false
    @Published var loaded = false
    /// Stažené profilové fotky podle cesty na serveru. Cesta nese revizi, takže nová fotka má nový klíč.
    @Published private(set) var photos: [String: Data] = [:]

    private var api: DartiqoAPI? { DartiqoAccount.shared.api }
    private var loadingPhotos: Set<String> = []

    func photo(_ path: String?) -> Data? {
        guard let data = path.flatMap({ photos[$0] }), !data.isEmpty else { return nil }
        return data
    }

    private func loadPhotos(_ paths: [String?]) {
        guard let api else { return }
        let missing = Set(paths.compactMap { $0 }).subtracting(photos.keys).subtracting(loadingPhotos)
        for path in missing {
            loadingPhotos.insert(path)
            Task {
                let data = await api.downloadImage(path)
                loadingPhotos.remove(path)
                // Prázdná data si pamatují nedostupnou fotku, ať ji polling nestahuje pořád dokola.
                photos[path] = data ?? Data()
            }
        }
    }
    /// Zneplatní rozjeté načtení seznamu, když mezitím vznikne nebo skončí zápas.
    private var hallToken = 0

    func loadHall() async {
        guard let api, !busy else { return }
        let token = hallToken
        do {
            async let current = api.currentOnline()
            async let invites = api.onlineInvites()
            async let hall = api.onlineLobbies(kind: nil)
            let match = try await current
            let incoming = try await invites
            let listed = try await hall
            guard token == hallToken else { return }
            self.current = match
            self.invites = incoming
            lobbies = listed.lobbies
            loadPhotos(listed.lobbies.map(\.host.photo) + (match?.players.map(\.photo) ?? []))
            loaded = true
        } catch {
            guard token == hallToken else { return }
            notice = error.localizedDescription
            loaded = true
        }
    }

    func returnToHall() {
        hallToken += 1
        current = nil
        match = nil
        notice = nil
    }

    func open(_ id: String) async {
        guard let api else { return }
        do {
            let snapshot = try await api.onlineMatch(id)
            if let next = snapshot.match { apply(next) }
            lobbyInvites = snapshot.lobbyInvites
            if match?.status == "lobby", friends.isEmpty {
                friends = (try? await api.friendBook())?.friends ?? []
                loadPhotos(friends.map(\.user.photo))
            }
        } catch {
            notice = error.localizedDescription
        }
    }

    func pull(_ id: String) async {
        guard !busy else { return }
        await fetch(id)
    }

    func create(_ settings: OnlineLobbySettings) async -> String? {
        await perform {
            let created = try await $0.createOnline(settings)
            apply(created)
            current = created
            return created.id
        }
    }

    func update(_ settings: OnlineLobbySettings) async -> Bool {
        guard let id = match?.id else { return false }
        let saved = await perform { api in
            let snapshot = try await api.updateOnline(id, settings: settings)
            if let next = snapshot.match {
                apply(next)
                current = next
            }
            lobbyInvites = snapshot.lobbyInvites
            return id
        }
        return saved != nil
    }

    func joinPublic(_ lobby: OnlineLobby) async -> String? {
        await perform {
            let joined = try await $0.joinPublicOnline(lobby.id)
            apply(joined)
            current = joined
            return joined.id
        }
    }

    func join(code: String) async -> String? {
        let normalized = code.uppercased().filter { !$0.isWhitespace }
        return await perform {
            let joined = try await $0.joinOnline(code: normalized)
            apply(joined)
            current = joined
            return joined.id
        }
    }

    func accept(_ inviteID: Int) async -> String? {
        await perform {
            let joined = try await $0.acceptOnlineInvite(inviteID)
            apply(joined)
            invites.removeAll { $0.id == inviteID }
            current = joined
            return joined.id
        }
    }

    func decline(_ inviteID: Int) async {
        guard let api else { return }
        do {
            try await api.declineOnlineInvite(inviteID)
            invites.removeAll { $0.id == inviteID }
        } catch {
            notice = error.localizedDescription
        }
    }

    func setReady(_ ready: Bool) async {
        guard let id = match?.id else { return }
        _ = await perform { api in
            apply(try await api.setOnlineReady(id, ready: ready))
            return id
        }
    }

    func start() async {
        guard let id = match?.id else { return }
        _ = await perform { api in
            apply(try await api.startOnline(id))
            return id
        }
    }

    func invite(_ userId: Int) async {
        guard let api, let id = match?.id, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await api.inviteOnline(id, userId: userId)
            notice = "Pozvánka je odeslaná."
            await fetch(id)
        } catch let failure as OnlineFailure {
            if let next = failure.match { apply(next) }
            notice = failure.message
        } catch {
            notice = error.localizedDescription
        }
    }

    func abandon() async -> Bool {
        guard let api, let match else { return true }
        hallToken += 1
        busy = true
        defer { busy = false }
        do {
            try await api.abandonOnline(match.id)
            if current?.id == match.id { current = nil }
            self.match = nil
            return true
        } catch {
            notice = error.localizedDescription
            return false
        }
    }

    private func fetch(_ id: String) async {
        guard let api, let snapshot = try? await api.onlineMatch(id), let next = snapshot.match else { return }
        apply(next)
        if current?.id == next.id { current = next }
        if next.status == "lobby" { lobbyInvites = snapshot.lobbyInvites }
    }

    private func perform(_ work: (DartiqoAPI) async throws -> String) async -> String? {
        guard let api else {
            notice = "Přihlas se k účtu Dartiqo."
            return nil
        }
        hallToken += 1
        busy = true
        defer { busy = false }
        do {
            let id = try await work(api)
            notice = nil
            return id
        } catch let failure as OnlineFailure {
            if let next = failure.match { apply(next) }
            notice = failure.message
            return failure.match?.member == true ? failure.match?.id : nil
        } catch {
            notice = error.localizedDescription
            return nil
        }
    }

    /// Odpověď na šipku z online zápasu. Starší stav než ten, co už telefon má, se zahodí.
    func adopt(_ next: OnlineMatch) {
        apply(next)
        if current?.id == next.id { current = next }
    }

    func refresh(_ id: String) async {
        await fetch(id)
    }

    private func apply(_ next: OnlineMatch) {
        if let match, match.id == next.id, next.seq < match.seq { return }
        match = next
        loadPhotos(next.players.map(\.photo))
    }
}

struct OnlineHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var account = DartiqoAccount.shared
    @StateObject private var session = OnlineSession()
    @State private var path: [OnlineRoute] = []
    @State private var setupNotice: String?
    @State private var pendingJoin: OnlineLobby?
    /// Rozehraný zápas se otevře sám jen jednou, ať jde z něj odejít zpátky do seznamu.
    @State private var autoOpened: String?

    private var mine: OnlineMatch? {
        guard let current = session.current, current.isOpen else { return nil }
        return current
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if account.user == nil {
                    signedOut
                } else {
                    hall
                }
            }
            .screen()
            .navigationTitle("Online")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Zavřít") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if account.user != nil { hallMenu }
            }
            .navigationDestination(for: OnlineRoute.self) { route in
                destination(route)
            }
        }
        .task(id: path.isEmpty) { await watchHall() }
        .confirmationDialog(
            "Tvoje lobby se zruší",
            isPresented: Binding(get: { pendingJoin != nil }, set: { if !$0 { pendingJoin = nil } }),
            titleVisibility: .visible,
            presenting: pendingJoin
        ) { lobby in
            Button("Připojit se k \(lobby.host.name)") { join(lobby) }
            Button("Zůstat", role: .cancel) {}
        } message: { _ in
            Text("Můžeš být jen v jednom lobby. Když se připojíš jinam, to svoje opustíš.")
        }
    }

    @ViewBuilder
    private func destination(_ route: OnlineRoute) -> some View {
        switch route {
        case .create:
            SetupView(
                mode: .x01,
                online: OnlineSetupMode(finish: finishSetup),
                onlineNotice: $setupNotice
            )
        case .join:
            OnlineJoinView(session: session) { id in path = [.room(id)] }
        case .room(let id):
            OnlineRoomView(
                session: session,
                matchID: id,
                onLeave: leaveRoom,
                onEdit: { path.append(.edit(id)) }
            )
        case .edit(let id):
            if let match = session.match, match.id == id {
                SetupView(
                    mode: .x01,
                    preset: preset(for: match),
                    online: OnlineSetupMode(
                        editing: true,
                        isPublic: match.isPublic,
                        finish: saveSettings
                    ),
                    onlineNotice: $setupNotice
                )
            }
        }
    }

    private func watchHall() async {
        guard account.user != nil, path.isEmpty else { return }
        while !Task.isCancelled {
            await session.loadHall()
            if let live = mine, live.isLive, autoOpened != live.id, path.isEmpty {
                autoOpened = live.id
                path = [.room(live.id)]
                return
            }
            try? await Task.sleep(for: .seconds(3))
            if !path.isEmpty { return }
        }
    }

    private func preset(for match: OnlineMatch) -> SetupDraft {
        var draft = SetupDraft(mode: .x01)
        draft.config = match.playRules.config
        return draft
    }

    private func finishSetup(_ draft: SetupDraft, settings: OnlineLobbySettings) async {
        setupNotice = nil
        guard let id = await session.create(settings) else {
            setupNotice = session.notice
            return
        }
        if let friendID = draft.seats.compactMap(\.friendID).first,
           let friend = store.friends.first(where: { $0.id == friendID }) {
            if let accountID = friend.accountID {
                await session.invite(accountID)
            } else {
                session.notice = "\(friend.name) nemá účet Dartiqo, pozvánka neodešla. V lobby pozvi kamaráda, který účet má."
            }
        }
        path = [.room(id)]
    }

    private func saveSettings(_ draft: SetupDraft, settings: OnlineLobbySettings) async {
        setupNotice = nil
        if await session.update(settings) {
            if case .edit = path.last { path.removeLast() }
        } else {
            setupNotice = session.notice
        }
    }

    private func leaveRoom() {
        session.returnToHall()
        path = []
    }

    private func tryJoin(_ lobby: OnlineLobby) {
        if let mine, mine.status == "lobby" {
            pendingJoin = lobby
        } else {
            join(lobby)
        }
    }

    private func join(_ lobby: OnlineLobby) {
        Task {
            if let id = await session.joinPublic(lobby) {
                path = [.room(id)]
            } else {
                await session.loadHall()
            }
        }
    }

    // MARK: Obrazovky

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Online zápas je na účtu").font(AppFont.title(28))
            Text("Přihlas se, ať můžeš založit lobby, připojit se k ostatním nebo přijmout pozvánku od kamaráda.")
                .foregroundStyle(.secondary)
            Button("Přihlásit se") {
                dismiss()
                account.leaveGuest()
            }
            .buttonStyle(PrimaryButton())
            Spacer()
        }
        .padding(22)
    }

    private var hall: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if let notice = session.notice, !notice.isEmpty {
                    Text(notice).font(.subheadline).foregroundStyle(.red)
                }
                if let mine {
                    myLobbyCard(mine)
                }
                if !session.invites.isEmpty {
                    invitesSection
                }
                lobbyList
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await session.loadHall() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Lobby").font(AppFont.title(32))
            Text("Připoj se k otevřenému zápasu, nebo založ vlastní.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Spodní menu jako u lokálního průvodce: založit vlastní zápas, nebo vstoupit kódem.
    private var hallMenu: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                NavigationLink(value: OnlineRoute.join) {
                    HStack(spacing: 8) {
                        Image(systemName: "number")
                            .font(.subheadline.weight(.bold))
                        Text("Připojit")
                            .font(.headline)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityHint("Vstup do lobby kódem")

                NavigationLink(value: OnlineRoute.create) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.bold))
                        Text("Vytvořit zápas")
                            .font(.headline)
                    }
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.brand).interactive(), in: Capsule())
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func myLobbyCard(_ match: OnlineMatch) -> some View {
        Button { path = [.room(match.id)] } label: {
            HStack(spacing: 14) {
                Image(systemName: match.isLive ? "target" : "person.2.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 44, height: 44)
                    .background(Theme.accentFill, in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(match.isLive ? "Rozehraný zápas" : (match.isHost ? "Tvoje lobby" : "Jsi v lobby"))
                        .font(.headline)
                    Text(lobbyLine(match))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.brand.opacity(0.7), lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func lobbyLine(_ match: OnlineMatch) -> String {
        var parts: [String] = []
        if let code = match.code, !match.isLive { parts.append("Kód \(code)") }
        parts.append(match.playRules.summary)
        if !match.isLive { parts.append("\(match.players.count)/2") }
        return parts.joined(separator: " · ")
    }

    private var invitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pozvánky").font(.headline)
            ForEach(session.invites) { invite in
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(invite.from) tě zve").font(.headline)
                    Text(invite.summary).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Přijmout") {
                            Task {
                                if let id = await session.accept(invite.id) { path = [.room(id)] }
                            }
                        }
                        .buttonStyle(PrimaryButton())
                        Button("Odmítnout") { Task { await session.decline(invite.id) } }
                            .buttonStyle(.bordered)
                    }
                }
                .surface()
            }
        }
    }

    private var lobbyList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Otevřená lobby").font(.headline)
                Spacer()
                Text("\(session.lobbies.filter(\.open).count) volných")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if !session.loaded {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if session.lobbies.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Teď nikdo nečeká")
                        .font(.headline)
                    Text("Založ vlastní veřejný zápas a ostatní se k tobě připojí.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                ForEach(session.lobbies) { lobby in
                    lobbyRow(lobby)
                }
            }
        }
    }

    private func lobbyRow(_ lobby: OnlineLobby) -> some View {
        HStack(spacing: 12) {
            Avatar(name: lobby.host.name, size: 46, photo: session.photo(lobby.host.photo))
            VStack(alignment: .leading, spacing: 4) {
                Text(lobby.host.name).font(.headline).lineLimit(1)
                Text(lobby.playRules.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                OnlineBadge(text: "\(lobby.seated)/2")
            }
            Spacer(minLength: 8)
            if lobby.open {
                Button("Připojit") { tryJoin(lobby) }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.brand)
                    .foregroundStyle(Theme.onAccent)
                    .disabled(session.busy)
            } else {
                Text("Plné")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct OnlineBadge: View {
    var text: String
    var strong = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(strong ? Theme.onAccent : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(strong ? Theme.accentFill : Color.primary.opacity(0.08), in: Capsule())
    }
}

private struct OnlineJoinView: View {
    @ObservedObject var session: OnlineSession
    var onOpen: (String) -> Void
    @State private var code = ""
    @FocusState private var focus: Bool

    /// Stejná abeceda jako generátor kódů na serveru, bez zaměnitelných 0, O, 1 a I.
    private static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    private static let length = 6

    private var complete: Bool { code.count == Self.length }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Vstup do lobby")
                        .font(AppFont.title(30))
                    Text("Zadej šest znaků, které ti poslal hostitel.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                codeField

                HStack {
                    PasteButton(payloadType: String.self) { values in
                        guard let first = values.first else { return }
                        Task { @MainActor in
                            code = Self.clean(first)
                        }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleAndIcon)
                    .controlSize(.small)
                    Spacer(minLength: 8)
                    if !code.isEmpty {
                        Button("Smazat", systemImage: "delete.left") {
                            code = ""
                            focus = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
                }

                if let notice = session.notice, !notice.isEmpty {
                    Label(notice, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                Label("Do veřejného lobby se připojíš i rovnou ze seznamu, bez kódu.", systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screen()
        .navigationTitle("Připojit")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { joinBar }
        .onAppear { focus = true }
        .onChange(of: code) { _, next in
            let cleaned = Self.clean(next)
            if cleaned != next { code = cleaned }
        }
    }

    /// Šest políček nad skrytým polem. Klepnutí kamkoli otevře klávesnici.
    private var codeField: some View {
        let characters = Array(code)
        return ZStack {
            TextField("", text: $code)
                .focused($focus)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .textContentType(.oneTimeCode)
                .submitLabel(.join)
                .onSubmit(join)
                .foregroundStyle(.clear)
                .tint(.clear)
                .frame(height: 1)
                .opacity(0.02)
                .accessibilityLabel("Kód lobby")
                .accessibilityValue(code.map(String.init).joined(separator: " "))

            HStack(spacing: 8) {
                ForEach(0..<Self.length, id: \.self) { index in
                    let active = focus && index == min(characters.count, Self.length - 1)
                    Text(index < characters.count ? String(characters[index]) : "")
                        .font(AppFont.display(30))
                        .monospaced()
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(tileStroke(active: active, filled: index < characters.count), lineWidth: active ? 2 : 1.5)
                        )
                        .contentTransition(.numericText())
                }
            }
            .animation(.snappy(duration: 0.2), value: code)
            .contentShape(Rectangle())
            .onTapGesture { focus = true }
            .accessibilityHidden(true)
        }
    }

    private func tileStroke(active: Bool, filled: Bool) -> Color {
        if complete { return Theme.positive.opacity(0.7) }
        if active { return Theme.brand }
        return filled ? Color.primary.opacity(0.25) : Color.primary.opacity(0.1)
    }

    private var joinBar: some View {
        GlassEffectContainer {
            Button(action: join) {
                HStack(spacing: 8) {
                    if session.busy {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.subheadline.weight(.bold))
                    }
                    Text(session.busy ? "Vstupuju…" : "Vstoupit")
                        .font(.headline)
                }
                .foregroundStyle(complete ? Color.black : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassEffect(complete ? .regular.tint(Theme.brand).interactive() : .regular, in: Capsule())
            .disabled(session.busy || !complete)
            .animation(.smooth(duration: 0.25), value: complete)
            .accessibilityHint(complete ? "Vstoupí do lobby" : "Nejdřív zadej celý kód")
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func join() {
        guard complete, !session.busy else { return }
        Task {
            if let id = await session.join(code: code) {
                onOpen(id)
            }
        }
    }

    private static func clean(_ raw: String) -> String {
        String(raw.uppercased().filter { alphabet.contains($0) }.prefix(length))
    }
}
