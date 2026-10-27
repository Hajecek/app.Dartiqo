import SwiftUI
import UIKit
import Combine

struct OnlineRoomView: View {
    @ObservedObject var session: OnlineSession
    @EnvironmentObject private var store: AppStore
    var matchID: String
    var onLeave: () -> Void
    /// Zrušení lobby nebo zápasu zavře online a vrátí na Domů.
    var onCancel: () -> Void
    var onEdit: () -> Void
    @State private var copied = false
    @State private var confirmLeave = false
    /// Jakmile zápas jednou běžel, opuštění ukáže vzdání, ne zrušené lobby.
    @State private var sawLive = false

    private var match: OnlineMatch? { session.match?.id == matchID ? session.match : nil }

    var body: some View {
        Group {
            if let match {
                switch match.status {
                case "live", "finished":
                    OnlineLiveMatch(session: session, match: match, onLeave: onLeave, onCancel: onCancel)
                case "abandoned":
                    closed(match, forfeited: sawLive)
                        .task {
                            if sawLive {
                                await DartiqoAccount.shared.refreshMatchCompletion(into: store)
                            }
                        }
                default:
                    lobby(match)
                }
            } else {
                ProgressView("Načítám lobby…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if lobbyChrome {
                Color.black.ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: match?.status) { _, status in
            if status == "live" || status == "finished" { sawLive = true }
        }
        .onAppear {
            if match?.isLive == true || match?.status == "finished" { sawLive = true }
        }
        .toolbar {
            if let match, match.status == "lobby" {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if match.isHost {
                            Button("Upravit lobby", systemImage: "slider.horizontal.3") { onEdit() }
                            Button("Smazat lobby", systemImage: "trash", role: .destructive) { confirmLeave = true }
                        } else {
                            Button("Odejít z lobby", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { confirmLeave = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Možnosti lobby")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let match, match.status == "lobby" {
                lobbyBar(match)
            }
        }
        .task(id: matchID) {
            await session.open(matchID)
            while !Task.isCancelled {
                let status = session.match?.status
                if status == "finished" || status == "abandoned" { return }
                try? await Task.sleep(for: .milliseconds(status == "live" ? 1200 : 2000))
                if Task.isCancelled { return }
                await session.pull(matchID)
            }
        }
        .confirmationDialog(leaveTitle, isPresented: $confirmLeave, titleVisibility: .visible) {
            Button(leaveAction, role: .destructive) {
                Task {
                    if await session.abandon() { onCancel() }
                }
            }
            Button("Zůstat", role: .cancel) {}
        }
    }

    /// Lobby, načítání a zrušená místnost sedí na černém plátně. Rozehraný zápas má vlastní tabuli.
    private var lobbyChrome: Bool {
        guard let match else { return true }
        switch match.status {
        case "live", "finished": return false
        default: return true
        }
    }

    private var title: String {
        guard let match else { return "Lobby" }
        if match.isLive { return "Zápas" }
        return match.isHost ? "Tvoje lobby" : "Lobby"
    }

    private var leaveTitle: String {
        guard let match else { return "Opustit?" }
        if match.isLive { return "Opustit zápas?" }
        return match.isHost ? "Smazat lobby?" : "Odejít z lobby?"
    }

    private var leaveAction: String {
        guard let match else { return "Opustit" }
        if match.isLive { return "Opustit zápas" }
        return match.isHost ? "Smazat lobby" : "Odejít"
    }

    // MARK: Lobby

    private func lobby(_ match: OnlineMatch) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                overview(match)
                if let code = match.code {
                    codeCard(match, code: code)
                }
                if let notice = session.notice, !notice.isEmpty {
                    noticeBanner(notice)
                }
                invites(match)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// Horní přehled: kdo proti komu hraje, kdo je připravený a na jaká pravidla.
    private func overview(_ match: OnlineMatch) -> some View {
        VStack(spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: match.playRules.gameMode.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        LinearGradient(colors: match.playRules.gameMode.tileColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Circle()
                    )
                    .accessibilityHidden(true)
                Text(visibilityText(match))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                if match.isHost {
                    Button(action: onEdit) {
                        Label("Upravit", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Změní pravidla nebo viditelnost lobby")
                }
            }

            HStack(alignment: .top, spacing: 0) {
                seat(match, slot: 0)
                Text("VS")
                    .font(AppFont.display(18))
                    .foregroundStyle(Theme.brand)
                    .frame(width: 44)
                    .padding(.top, 34)
                    .accessibilityHidden(true)
                seat(match, slot: 1)
            }

            ruleOverview(match.playRules)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .modifier(LobbyPanel())
    }

    private func visibilityText(_ match: OnlineMatch) -> String {
        let game = match.playRules.gameMode.shortTitle
        if match.isPublic { return "Veřejné lobby · \(game)" }
        return "Uzavřené lobby · \(game)"
    }

    @ViewBuilder
    private func ruleOverview(_ rules: OnlineRules) -> some View {
        let chips = rules.overviewChips
        if rules.gameMode == .x01, rules.playsSets, chips.count >= 3 {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ruleChip(title: chips[0].title, value: chips[0].value)
                    ruleChip(title: chips[1].title, value: chips[1].value)
                }
                ruleChip(title: chips[2].title, value: chips[2].value)
            }
        } else {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    ruleChip(title: chip.title, value: chip.value)
                }
            }
        }
    }

    private func ruleChip(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func codeCard(_ match: OnlineMatch, code: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("KÓD LOBBY")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(copied ? "Zkopírováno do schránky" : "Klepnutím zkopíruješ")
                        .font(.caption)
                        .foregroundStyle(copied ? Theme.positive : .white.opacity(0.62))
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 8)
                ShareLink(item: shareText(match, code: code)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Theme.brand).interactive(), in: Circle())
                .foregroundStyle(.black)
                .accessibilityLabel("Sdílet kód")
            }
            Button {
                UIPasteboard.general.string = code
                withAnimation(.smooth) { copied = true }
            } label: {
                HStack(spacing: 6) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(AppFont.display(28))
                            .monospaced()
                            .foregroundStyle(Theme.brand)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(copied ? Theme.positive.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1.5)
                            )
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: copied) { _, now in now }
            .accessibilityLabel("Kód lobby \(code.map(String.init).joined(separator: " "))")
            .accessibilityHint("Zkopíruje kód")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(LobbyPanel())
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.smooth) { copied = false }
        }
    }

    private func shareText(_ match: OnlineMatch, code: String) -> String {
        "Zahraj si se mnou šipky v Dartiqo. \(match.playRules.summary). Kód lobby: \(code)"
    }

    @ViewBuilder
    private func seat(_ match: OnlineMatch, slot: Int) -> some View {
        if let player = match.players.first(where: { $0.slot == slot }) {
            VStack(spacing: 6) {
                Avatar(name: player.name, size: 84, photo: photo(of: player))
                    .padding(4)
                    .overlay(
                        Circle().stroke(player.ready ? Theme.positive : Color.white.opacity(0.16), lineWidth: 3)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if player.ready {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Theme.positive)
                                .background(Circle().fill(Color.black).padding(-2))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: player.ready)
                    .padding(.bottom, 4)
                Text(player.you ? "Ty" : player.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(player.slot == 0 ? "Hostitel" : "Soupeř")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.5))
                Text(player.ready ? "Připraven" : "Čeká")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(player.ready ? Theme.positive : .white.opacity(0.62))
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.title)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 84, height: 84)
                    .padding(4)
                    .background(Theme.brand.opacity(0.08), in: Circle())
                    .overlay(
                        Circle().strokeBorder(Theme.brand.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    )
                    .padding(.bottom, 4)
                Text("Volné místo")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Čeká se na soupeře")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
    }

    private func photo(of player: OnlinePlayer) -> Data? {
        if player.you, let mine = store.profile?.photoJPEG { return mine }
        return session.photo(player.photo)
    }

    /// Připravenost a spuštění drží spodní lišta, stejně jako „Další“ v průvodci zápasem.
    private func lobbyBar(_ match: OnlineMatch) -> some View {
        let ready = match.you?.ready == true
        let canStart = match.players.count == 2 && match.players.allSatisfy(\.ready)
        return VStack(spacing: 8) {
            Text(lobbyStatus(match))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentTransition(.opacity)
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        Task { await session.setReady(!ready) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: ready ? "checkmark.circle.fill" : "hand.raised.fill")
                                .font(.subheadline.weight(.bold))
                                .contentTransition(.symbolEffect(.replace))
                            Text(ready ? "Připraven" : "Jsem připraven")
                                .font(.headline)
                                .contentTransition(.opacity)
                        }
                        .foregroundStyle(readyForeground(ready: ready, host: match.isHost))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(readyGlass(ready: ready, host: match.isHost), in: Capsule())
                    .disabled(session.busy)
                    .accessibilityValue(ready ? "Připraven" : "Nepřipraven")
                    .accessibilityHint(ready ? "Zruší připravenost" : "Dá soupeři vědět, že můžeš hrát")

                    if match.isHost {
                        Button {
                            Task { await session.start() }
                        } label: {
                            HStack(spacing: 8) {
                                Text("Spustit").font(.headline)
                                Image(systemName: "play.fill").font(.subheadline.weight(.bold))
                            }
                            .foregroundStyle(canStart ? Color.black : Color.secondary)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(canStart ? .regular.tint(Theme.brand).interactive() : .regular, in: Capsule())
                        .disabled(session.busy || !canStart)
                    }
                }
            }
            .animation(.smooth(duration: 0.3), value: ready)
            .animation(.smooth(duration: 0.3), value: canStart)
            .sensoryFeedback(.success, trigger: ready) { _, now in now }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func readyForeground(ready: Bool, host: Bool) -> Color {
        if ready { return Theme.positive }
        return host ? .primary : .black
    }

    private func readyGlass(ready: Bool, host: Bool) -> Glass {
        if ready { return .regular.tint(Theme.positive.opacity(0.25)).interactive() }
        return host ? .regular.interactive() : .regular.tint(Theme.brand).interactive()
    }

    private func invites(_ match: OnlineMatch) -> some View {
        let people = invitees(in: match)
        let full = match.players.count >= 2
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Pozvat kamaráda")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(full ? "Místo je obsazené. Až se uvolní, můžeš sem někoho poslat." : "Pozvánka ho posadí rovnou do lobby.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            if session.friends.isEmpty {
                Text("Zatím nemáš kamarády. Přidáš je v profilu a pak je sem pozveš.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .modifier(LobbyPanel())
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(people.enumerated()), id: \.element.id) { index, friend in
                        if index > 0 {
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(height: 1)
                                .padding(.leading, 64)
                        }
                        friendInviteRow(friend, full: full)
                    }
                }
                .modifier(LobbyPanel())
            }
        }
    }

    private func friendInviteRow(_ friend: FriendLink, full: Bool) -> some View {
        let invited = friend.user.publicId.map(pending) ?? false
        return HStack(spacing: 12) {
            Avatar(name: friendName(friend.user), size: 40, photo: session.photo(friend.user.photo))
            VStack(alignment: .leading, spacing: 2) {
                Text(friendName(friend.user))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("@\(friend.user.username)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if invited {
                Label("Pozváno", systemImage: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.positive)
                    .labelStyle(.titleAndIcon)
            } else {
                Button {
                    Task { await session.invite(friend.user.id) }
                } label: {
                    Text("Pozvat")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Theme.brand, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(session.busy || full)
                .opacity(session.busy || full ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func noticeBanner(_ text: String) -> some View {
        let sent = text == "Pozvánka je odeslaná."
        return Label(text, systemImage: sent ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(sent ? Theme.positive : Color.red)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background((sent ? Theme.positive : Color.red).opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func invitees(in match: OnlineMatch) -> [FriendLink] {
        let seated = Set(match.players.map(\.id))
        return session.friends.filter { friend in
            guard let publicId = friend.user.publicId else { return true }
            return !seated.contains(publicId)
        }
    }

    private func pending(_ publicId: String) -> Bool {
        session.lobbyInvites.contains { $0.publicId == publicId && $0.status == "pending" }
    }

    private func lobbyStatus(_ match: OnlineMatch) -> String {
        if match.players.count < 2 { return "Čeká se na soupeře. Pošli kód, nebo pozvi kamaráda." }
        let mine = match.you?.ready == true
        let theirs = match.players.first(where: { !$0.you })?.ready == true
        switch (mine, theirs) {
        case (true, true):
            return match.isHost ? "Oba jste připravení. Spusť zápas." : "Oba jste připravení. Hostitel spustí zápas."
        case (true, false):
            return "Čeká se, až bude připravený soupeř."
        case (false, true):
            return "Soupeř je připravený. Teď ty."
        case (false, false):
            return "Až budete oba připravení, hostitel zápas spustí."
        }
    }

    private func closed(_ match: OnlineMatch, forfeited: Bool) -> some View {
        let opponent = match.players.first(where: { !$0.you })
        let name = opponent?.name ?? "Soupeř"
        return VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(spacing: 16) {
                Image(systemName: forfeited ? "flag.fill" : "person.2.slash")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(forfeited ? .black : Theme.brand)
                    .frame(width: 84, height: 84)
                    .background(forfeited ? Theme.brand : Theme.brand.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                Text(forfeited ? "Soupeř vzdal zápas" : "Lobby už není")
                    .font(AppFont.title(28))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(forfeited
                     ? "\(name) odešel z online zápasu. Zápas skončil vzdáním."
                     : "Hostitel lobby zrušil, nebo už vypršelo.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 24)
            Button("Zpět do lobby") { onLeave() }
                .buttonStyle(PrimaryButton())
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(forfeited ? "Vzdání" : "Lobby")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func friendName(_ user: DirectoryPerson) -> String {
        let name = user.fullName
        return name.isEmpty ? user.username : name
    }
}

/// Tmavý panel lobby. Sedí na černém plátně stejně jako karty na Domů.
struct LobbyPanel: ViewModifier {
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        content
            .background(Color.white.opacity(0.06), in: shape)
            .overlay(shape.stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// Online zápas na stejné tabuli jako lokální hra.
private struct OnlineLiveMatch: View {
    @ObservedObject var session: OnlineSession
    @EnvironmentObject private var store: AppStore
    var match: OnlineMatch
    var onLeave: () -> Void
    var onCancel: () -> Void
    @State private var link: OnlineMatchLink?

    var body: some View {
        Group {
            if let link, link.game != nil {
                MatchView(online: link, onOnlineExit: onLeave, onOnlineCancel: onCancel)
            } else if link != nil {
                ContentUnavailableView(
                    "Zápas nejde zobrazit",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Stav ze serveru se nepodařilo přehrát. Zkus se vrátit do lobby a otevřít ho znovu.")
                )
            } else {
                ProgressView("Načítám zápas…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            guard link == nil else { return }
            link = OnlineMatchLink(session: session, match: match, profileID: store.profile?.id)
        }
    }
}

