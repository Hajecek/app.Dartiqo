import Foundation
import Testing
@testable import Dartiqo

struct OnlineMatchDecodeTests {
    @Test func serverShape() throws {
        let json = """
        {"ok":true,"lobbyInvites":[{"name":"Test host","username":"host","publicId":"abc","status":"pending"}],
        "match":{"id":"0123456789abcdef01234567","code":"K7NP2Q","kind":"classic","visibility":"private","ratingChange":null,"status":"lobby","seq":2,"yourSlot":0,"activeSlot":0,"yourTurn":false,"member":true,"hasPassword":true,"winner":null,"startedAt":null,
        "rules":{"startingScore":501,"outRule":"double","legsToWin":1,"setsToWin":1,"format":"firstTo","doubleIn":false},
        "players":[{"slot":0,"id":"abc","name":"Test host","username":"host","photo":"/uploads/avatars/a.jpg?v=2","ready":false,"you":true,"remaining":501,"legs":0,"sets":0,"rating":1000}],
        "state":{"mode":"x01","title":"Test host","leg":1,"set":1,"legsToWin":1,"active":0,"winner":null,"currentDarts":[],"players":[{"name":"Test host","score":"501"}],"visits":[]}}}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(OnlineSnapshot.self, from: json)
        #expect(snapshot.match?.code == "K7NP2Q")
        #expect(snapshot.match?.rules.summary == "501 · Double out · First to 1 leg")
        #expect(snapshot.match?.isPublic == false)
        #expect(snapshot.match?.players.first?.photo == "/uploads/avatars/a.jpg?v=2")
        #expect(snapshot.lobbyInvites.first?.status == "pending")
        #expect(snapshot.match?.state.currentDarts.isEmpty == true)
    }

    @Test func setsBoard() throws {
        let json = """
        {"ok":true,"match":{"id":"0123456789abcdef01234567","code":null,"visibility":"public","status":"finished","seq":40,"yourSlot":1,"activeSlot":1,"yourTurn":false,"member":true,"hasPassword":false,"winner":1,
        "rules":{"startingScore":501,"outRule":"straight","legsToWin":2,"setsToWin":3,"format":"bestOf","doubleIn":false},
        "players":[{"slot":0,"id":"aaa","name":"Host","username":"host","ready":true,"you":false,"remaining":40,"legs":0,"sets":1},{"slot":1,"id":"bbb","name":"Guest","username":"guest","ready":true,"you":true,"remaining":0,"legs":2,"sets":3}],
        "state":{"leg":7,"set":4,"winner":1,"currentDarts":[],"played":300,"running":false}}}
        """.data(using: .utf8)!
        let match = try JSONDecoder().decode(OnlineSnapshot.self, from: json).match
        #expect(match?.isPublic == true)
        #expect(match?.rules.playsSets == true)
        #expect(match?.rules.lengthLabel == "Best of 5 setů · Best of 3 legy v setu")
        #expect(match?.you?.sets == 3)
    }

    @Test func lobbyList() throws {
        let json = """
        {"ok":true,"rating":{"rating":1000,"played":0,"wins":0},
        "lobbies":[{"id":"0123456789abcdef01234567","kind":"classic","rules":{"startingScore":301,"outRule":"double","legsToWin":3,"setsToWin":1,"format":"firstTo","doubleIn":false},
        "host":{"name":"Petr Novák","username":"petr","publicId":"abcabcabcabcabcabcabcabc","rating":1000},"seated":1,"open":true,"createdAt":"2026-10-25T00:00:00+00:00"}]}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(OnlineSnapshot.self, from: json)
        #expect(snapshot.lobbies.first?.host.name == "Petr Novák")
        #expect(snapshot.lobbies.first?.open == true)
        #expect(snapshot.lobbies.first?.rules.summary == "301 · Double out · First to 3 legy")
    }

    @Test func dartLabels() {
        #expect(Dart(onlineLabel: "T20") == Dart(20, 3))
        #expect(Dart(onlineLabel: "D16") == Dart(16, 2))
        #expect(Dart(onlineLabel: "S1") == Dart(1))
        #expect(Dart(onlineLabel: "BULL") == Dart(25, 2))
        #expect(Dart(onlineLabel: "25") == Dart(25))
        #expect(Dart(onlineLabel: "MISS") == Dart.miss)
        #expect(Dart(onlineLabel: "T25") == nil)
        #expect(Dart(onlineLabel: "X5") == nil)
    }

    @MainActor @Test func replaysServerDarts() throws {
        let json = """
        {"ok":true,"match":{"id":"0123456789abcdef01234567","code":null,"visibility":"private","status":"live","seq":9,"yourSlot":0,"activeSlot":0,"yourTurn":true,"member":true,"hasPassword":false,"winner":null,
        "rules":{"startingScore":101,"outRule":"double","legsToWin":1,"setsToWin":2,"format":"firstTo","doubleIn":false},
        "players":[{"slot":0,"id":"aaaaaaaaaaaaaaaaaaaaaaaa","name":"Host","username":"host","ready":true,"you":true,"remaining":41,"legs":0,"sets":1},{"slot":1,"id":"bbbbbbbbbbbbbbbbbbbbbbbb","name":"Guest","username":"guest","ready":true,"you":false,"remaining":41,"legs":0,"sets":0}],
        "state":{"leg":2,"set":2,"winner":null,"currentDarts":["T20"],
        "visits":[{"player":0,"leg":1,"darts":["T20","S1","D20"],"score":101,"bust":false,"checkout":true},{"player":1,"leg":2,"darts":["S20","S20","S20"],"score":60,"bust":false,"checkout":false}]}}}
        """.data(using: .utf8)!
        let match = try #require(try JSONDecoder().decode(OnlineSnapshot.self, from: json).match)
        let me = UUID()
        let link = OnlineMatchLink(session: OnlineSession(), match: match, profileID: me)
        let game = try #require(link.game)
        #expect(game.players[0].id == me)
        #expect(game.leg == 2)
        #expect(game.states[0].sets == 1)
        #expect(game.states[0].legs == 0)
        #expect(game.states[1].remaining == 41)
        #expect(game.active == 0)
        #expect(game.currentDarts == [Dart(20, 3)])
        #expect(game.liveProjection.states[0].remaining == 41)
        #expect(link.yourTurn)
        #expect(link.isRemote(1))
    }

    @Test func lobbySettingsBody() {
        var config = GameConfig(startingScore: 301, outRule: .master, legsToWin: 3, setsToWin: 2, format: .bestOf)
        config.options = MatchOptions()
        let body = OnlineLobbySettings(config: config, isPublic: false, password: " tajne ", keepPassword: false).body
        #expect(body["kind"] as? String == "classic")
        #expect(body["visibility"] as? String == "private")
        #expect(body["setsToWin"] as? Int == 2)
        #expect(body["format"] as? String == "bestOf")
        #expect(body["outRule"] as? String == "master")
        #expect(body["password"] as? String == "tajne")
    }
}
