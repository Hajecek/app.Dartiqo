import SwiftUI

#if DEBUG
@MainActor
enum PreviewSupport {
    nonisolated static var isXcodePreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    static func store(
        players: Int = 2,
        activeMatch: Bool = true,
        finished: Bool = false
    ) -> AppStore {
        let me = Profile(name: "Ty")
        let rival = Profile(name: "Pavel")
        var data = StoredData()
        data.profiles = [me, rival]
        data.selectedProfile = me.id
        data.appearance = "dark"
        data.friends = [
            Friend(id: rival.id, owner: me.id, name: rival.name, lastPlayed: .now)
        ]
        let store = AppStore(preview: data)
        guard activeMatch else { return store }

        let lineup: [Player]
        switch max(1, min(4, players)) {
        case 1:
            lineup = [Player(id: me.id, name: me.name)]
        case 3:
            lineup = [
                Player(id: me.id, name: me.name),
                Player(id: rival.id, name: rival.name),
                Player(name: "Bot 3", botLevel: 3)
            ]
        case 4:
            lineup = [
                Player(id: me.id, name: me.name),
                Player(id: rival.id, name: rival.name),
                Player(name: "Bot 4", botLevel: 4),
                Player(name: "Bot 7", botLevel: 7)
            ]
        default:
            lineup = [
                Player(id: me.id, name: me.name),
                Player(name: "Bot 5", botLevel: 5)
            ]
        }

        var match = Match(config: GameConfig(), players: lineup, firstPlayer: 0)
        if finished {
            match.finished = true
            match.winner = 0
            match.completedAt = .now
            match.states[0].legs = match.config.legsToWin
        }
        store.activeMatch = match

        // Historie / H2H v previewu potřebují aspoň jeden uložený zápas.
        var archived = match
        archived.finished = true
        archived.winner = archived.winner ?? 0
        archived.completedAt = archived.completedAt ?? .now
        store.data.matches = [archived]
        return store
    }

    static var sampleMatch: Match {
        store().activeMatch!
    }

    static var sampleHeadToHead: HeadToHead {
        let match = sampleMatch
        let key = RivalKey.of(opponent: match.players[1], in: match)
        return HeadToHead(
            key: key,
            opponentName: match.players[1].name,
            opponentBotLevel: match.players[1].botLevel,
            isGhost: false,
            matches: [match],
            myWins: 2,
            theirWins: 1,
            draws: 0
        )
    }

    static var sampleTraining: TrainingDefinition {
        TrainingCatalog.find("around-clock") ?? TrainingCatalog.all[0]
    }
}

extension AppStore {
    static var preview: AppStore { PreviewSupport.store() }
}

extension View {
    @MainActor
    func dartiqoPreview(_ store: AppStore? = nil) -> some View {
        environmentObject(store ?? .preview)
            .tint(Theme.action)
            .preferredColorScheme(.dark)
    }
}
#endif
