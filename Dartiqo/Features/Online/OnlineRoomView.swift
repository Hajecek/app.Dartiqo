import SwiftUI
import UIKit
import Combine

struct OnlineRoomView: View {
    @ObservedObject var session: OnlineSession
    @EnvironmentObject private var store: AppStore
    var matchID: String
    var onLeave: () -> Void
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
                    OnlineLiveMatch(session: session, match: match, onLeave: onLeave)
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
        .screen()
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
                    if await session.abandon() { onLeave() }
                }
            }
            Button("Zůstat", role: .cancel) {}
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
            VStack(alignment: .leading, spacing: 16) {
                overview(match)
                if let code = match.code {
                    codeCard(match, code: code)
                }
                if let notice = session.notice, !notice.isEmpty {
                    Text(notice).font(.subheadline).foregroundStyle(.red)
                }
                invites(match)
            }
            .padding(22)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    /// Horní přehled: kdo proti komu hraje, kdo je připravený a na jaká pravidla.
    private func overview(_ match: OnlineMatch) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Label(visibilityText(match), systemImage: match.isPublic ? "globe" : "lock.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 8)
                if match.isHost {
                    Button(action: onEdit) {
                        Label("Upravit", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .accessibilityHint("Změní pravidla nebo viditelnost lobby")
                }
            }

            HStack(alignment: .top, spacing: 0) {
                seat(match, slot: 0)
                Text("VS")
                    .font(AppFont.title(20))
                    .foregroundStyle(.secondary)
                    .frame(width: 44)
                    .padding(.top, 30)
                    .accessibilityHidden(true)
                seat(match, slot: 1)
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    ruleChip(title: "Start", value: "\(match.rules.startingScore)")
                    ruleChip(title: "Zavření", value: match.rules.outLabel)
                    if !match.rules.playsSets {
                        ruleChip(title: "Délka", value: match.rules.lengthLabel)
                    }
                }
                if match.rules.playsSets {
                    ruleChip(title: "Délka", value: match.rules.lengthLabel)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func visibilityText(_ match: OnlineMatch) -> String {
        if match.isPublic { return "Veřejné lobby" }
        return "Uzavřené lobby"
    }

    private func ruleChip(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func codeCard(_ match: OnlineMatch, code: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Kód lobby")
                    Text(copied ? "Zkopírováno do schránky" : "Klepnutím zkopíruješ")
                        .font(.caption)
                        .foregroundStyle(copied ? Theme.positive : .secondary)
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
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(copied ? Theme.positive.opacity(0.6) : .clear, lineWidth: 1.5)
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
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.smooth) { copied = false }
        }
    }

    private func shareText(_ match: OnlineMatch, code: String) -> String {
        "Zahraj si se mnou šipky v Dartiqo. \(match.rules.summary). Kód lobby: \(code)"
    }

    @ViewBuilder
    private func seat(_ match: OnlineMatch, slot: Int) -> some View {
        if let player = match.players.first(where: { $0.slot == slot }) {
            VStack(spacing: 6) {
                Avatar(name: player.name, size: 84, photo: photo(of: player))
                    .padding(4)
                    .overlay(
                        Circle().stroke(player.ready ? Theme.positive : Color.primary.opacity(0.12), lineWidth: 3)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if player.ready {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Theme.positive)
                                .background(Circle().fill(Theme.card).padding(-2))
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.smooth(duration: 0.3), value: player.ready)
                    .padding(.bottom, 4)
                Text(player.you ? "Ty" : player.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(player.slot == 0 ? "Hostitel" : "Soupeř")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.secondary)
                Text(player.ready ? "Připraven" : "Čeká")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(player.ready ? Theme.positive : .secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 6) {
                Image(systemName: "person.badge.plus")
                    .font(.title)
                    .foregroundStyle(.secondary)
                    .frame(width: 84, height: 84)
                    .padding(4)
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                    )
                    .padding(.bottom, 4)
                Text("Volné místo").font(.headline)
                Text("Čeká se na soupeře")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Pozvat kamaráda").font(.headline)
            Text("Pozvánka ho posadí rovnou do lobby.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.friends.isEmpty {
                Text("Zatím nemáš kamarády. Přidáš je v profilu a pak je sem pozveš.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(invitees(in: match)) { friend in
                    HStack {
                        Avatar(name: friendName(friend.user), size: 36, photo: session.photo(friend.user.photo))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friendName(friend.user)).lineLimit(1)
                            Text("@\(friend.user.username)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let publicId = friend.user.publicId, pending(publicId) {
                            Text("Pozváno").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        } else {
                            Button("Pozvat") { Task { await session.invite(friend.user.id) } }
                                .buttonStyle(.bordered)
                                .disabled(session.busy || match.players.count >= 2)
                        }
                    }
                }
            }
        }
        .surface()
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
            VStack(spacing: 18) {
                Text(forfeited ? "🏳️" : "👋")
                    .font(.system(size: 72))
                    .accessibilityHidden(true)
                Text(forfeited ? "Soupeř vzdal zápas" : "Lobby už není")
                    .font(AppFont.title(28))
                    .multilineTextAlignment(.center)
                Text(forfeited
                     ? "\(name) odešel z online zápasu. Zápas skončil vzdáním."
                     : "Hostitel lobby zrušil, nebo už vypršelo.")
                    .font(.body)
                    .foregroundStyle(.secondary)
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

/// Online zápas na stejné tabuli jako lokální hra.
private struct OnlineLiveMatch: View {
    @ObservedObject var session: OnlineSession
    @EnvironmentObject private var store: AppStore
    var match: OnlineMatch
    var onLeave: () -> Void
    @State private var link: OnlineMatchLink?

    var body: some View {
        Group {
            if let link, link.game != nil {
                MatchView(online: link, onOnlineExit: onLeave)
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

