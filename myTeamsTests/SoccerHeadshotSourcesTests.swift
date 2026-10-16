//
//  SoccerHeadshotSourcesTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/16/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
import UIKit

@testable import myTeams

/// A clock a test moves by hand.
private final class SoccerTestClock: @unchecked Sendable {
    var now: Date

    init(_ now: Date) {
        self.now = now
    }
}

/// 2026-10-16 12:00 UTC.
private let october16 = Date(timeIntervalSince1970: 1_792_152_000)

private func club(
    _ league: LeagueID,
    _ espnID: String,
    _ displayName: String,
    short shortName: String,
    abbreviation: String,
    location: String? = nil
) -> TeamRef {
    TeamRef(
        league: league, espnID: espnID,
        displayName: displayName, shortName: shortName, abbreviation: abbreviation, location: location ?? displayName,
        colorHex: "", alternateColorHex: "",
        logoURL: nil, logoDarkURL: nil, logoAsset: nil
    )
}

/// As `teams.json` has them.
private let sporting = club(.mls, "186", "Sporting Kansas City", short: "Sporting", abbreviation: "SKC")
private let seattle = club(.mls, "9726", "Seattle Sounders FC", short: "Seattle", abbreviation: "SEA")
private let arsenal = club(.premierLeague, "359", "Arsenal", short: "Arsenal", abbreviation: "ARS", location: "London")
private let arsenalWomen = club(.wsl, "20185", "Arsenal", short: "Arsenal", abbreviation: "ARS")
private let chelsea = club(.premierLeague, "363", "Chelsea", short: "Chelsea", abbreviation: "CHE")
private let bayern = club(.bundesliga, "132", "Bayern Munich", short: "Bayern", abbreviation: "MUN")
private let realMadridUCL = club(.championsLeague, "86", "Real Madrid", short: "Real Madrid", abbreviation: "RMA")

private func player(_ name: String, _ number: String, at team: TeamRef = sporting, id: String? = nil) -> SoccerHeadshotQuery {
    SoccerHeadshotQuery(espnID: id ?? name, name: name, number: number, team: team)
}

private func json(_ text: String) -> JSON {
    JSON(data: Data(text.utf8))
}

/// A 200 carrying `body`.
private func reply(_ body: String) -> RecordingTransport.Reply {
    RecordingTransport.Reply(body: Data(body.utf8))
}

// MARK: - Samples

/// FotMob's `search/suggest?term=Sporting Kansas City`, as probed on
/// 2026-10-16, trimmed: string ids, a reserve side, a match and a player.
private let sportingSuggest = """
[{"title":{"key":"all","value":"All"},"suggestions":[
  {"type":"team","id":"6604","name":"Sporting Kansas City","leagueId":130,"leagueName":"Major League Soccer"},
  {"type":"team","id":"722268","name":"Sporting Kansas City II","leagueId":10282,"leagueName":"MLS Next Pro"},
  {"type":"match","id":"5071435","leagueName":"Major League Soccer"},
  {"type":"player","id":"1284944","name":"André Luiz","teamName":"Sporting Kansas City"}]},
 {"title":{"key":"teams","value":"Teams"},"suggestions":[
  {"type":"team","id":"6604","name":"Sporting Kansas City","leagueId":130,"leagueName":"Major League Soccer"},
  {"type":"team","id":"722268","name":"Sporting Kansas City II","leagueId":10282,"leagueName":"MLS Next Pro"}]}]
"""

/// `search/suggest?term=Arsenal`.
private let arsenalSuggest = """
[{"title":{"key":"teams"},"suggestions":[
  {"type":"team","id":"9825","name":"Arsenal","leagueId":47,"leagueName":"Premier League"},
  {"type":"team","id":"258657","name":"Arsenal (W)","leagueId":9227,"leagueName":"WSL"},
  {"type":"team","id":"950214","name":"Arsenal U21","leagueId":9084,"leagueName":"Premier League 2"}]}]
"""

/// `search/suggest?term=Chelsea`: another club of the same name, in a
/// league of the same name.
private let chelseaSuggest = """
[{"title":{"key":"teams"},"suggestions":[
  {"type":"team","id":"8455","name":"Chelsea","leagueId":47,"leagueName":"Premier League"},
  {"type":"team","id":"258661","name":"Chelsea (W)","leagueId":9227,"leagueName":"WSL"},
  {"type":"team","id":"159949","name":"Berekum Chelsea","leagueId":522,"leagueName":"Premier League"}]}]
"""

/// `teams?id=6604`, trimmed to its squad.
private let sportingSquad = """
{"details":{"id":6604,"type":"team","name":"Sporting Kansas City","shortName":"Sporting KC","gender":"male"},
 "squad":{"squad":[
  {"title":"coach","members":[{"id":30705,"name":"Raphael Wicky","shirtNumber":null,"role":{"key":"coach","fallback":"Coach"}}]},
  {"title":"keepers","members":[{"id":1083233,"name":"John Pulskamp","shirtNumber":1,"ccode":"USA","positionIdsDesc":"GK"}]},
  {"title":"defenders","members":[
    {"id":1734140,"name":"Diego Borges","shirtNumber":57,"ccode":"BRA"},
    {"id":1440010,"name":"Jayden Reid","shirtNumber":99,"ccode":"USA"}]},
  {"title":"midfielders","members":[{"id":861720,"name":"Magomed-Shapi Suleymanov","shirtNumber":93,"ccode":"RUS"}]},
  {"title":"attackers","members":[
    {"id":1187420,"name":"Capita","shirtNumber":7,"ccode":"ANG"},
    {"id":1284944,"name":"André Luiz","shirtNumber":11,"ccode":"BRA","cname":"Brazil","positionIdsDesc":"RW,RM"},
    {"id":1726789,"name":"Seymour Reid","shirtNumber":29,"ccode":"JAM"}]}],
  "isNationalTeam":false}}
"""

/// TheSportsDB's `searchplayers.php?p=Dejan Joveljic` on 2026-10-16: his
/// row still names his old club.
private let joveljicSearch = """
{"player":[{"idPlayer":"34175553","idTeam":"134149","strPlayer":"Dejan Joveljić","strTeam":"Seattle Sounders",
 "strSport":"Soccer","strThumb":"https://r2.thesportsdb.com/images/media/player/thumb/9or0qp1661711095.jpg",
 "strCutout":"https://r2.thesportsdb.com/images/media/player/cutout/toe2fu1766426636.png",
 "strNationality":"Bosnia and Herzegovina","strStatus":"Active","strGender":"Male","strPosition":"Forward"}]}
"""

/// `searchplayers.php?p=Zorhan Bassong`.
private let bassongSearch = """
{"player":[{"idPlayer":"34195773","idTeam":"134143","strPlayer":"Zorhan Bassong","strTeam":"Sporting Kansas City",
 "strSport":"Soccer","strThumb":"https://r2.thesportsdb.com/images/media/player/thumb/vt57jl1641299057.jpg",
 "strCutout":"https://r2.thesportsdb.com/images/media/player/cutout/98irv81766426447.png",
 "strNationality":"Canada","strStatus":"Active","strGender":"Male","strPosition":"Defender"}]}
"""

/// `searchplayers.php?p=Andre_Luiz`: only a retired namesake.
private let andreLuizSearch = """
{"player":[{"idPlayer":"34266846","idTeam":"135181","strPlayer":"André Luiz","strTeam":"_Retired-Soccer",
 "strSport":"Soccer","strThumb":null,"strCutout":null,"strNationality":"Brazil","strStatus":"Retired","strGender":"Male"}]}
"""

/// `searchplayers.php?p=Capita`: a fuzzy hit on another name.
private let capitaSearch = """
{"player":[{"idPlayer":"34277799","idTeam":"135181","strPlayer":"Miguel Capitas","strTeam":"_Retired-Soccer",
 "strSport":"Soccer","strThumb":null,"strCutout":null,"strGender":"Male"}]}
"""

// MARK: - Matching

@Suite("Soccer headshots: name and club matching")
struct SoccerHeadshotMatchingTests {
    @Test("Names fold accents and case; clubs drop FC, SC, CF and Club")
    func normalization() {
        #expect(HeadshotNameMatching.words("Dejan Joveljić") == ["dejan", "joveljic"])
        #expect(HeadshotNameMatching.words("ANDRÉ LUIZ") == ["andre", "luiz"])
        #expect(HeadshotNameMatching.teamWords("Seattle Sounders FC") == ["seattle", "sounders"])
        #expect(HeadshotNameMatching.teamWords("Club América") == ["america"])
        #expect(HeadshotNameMatching.teamWords("CF Montréal") == ["montreal"])
    }

    @Test("Clubs match by containment either way, and by initials")
    func clubs() {
        #expect(HeadshotNameMatching.teamNamesMatch("Sporting Kansas City", "Sporting KC"))
        #expect(HeadshotNameMatching.teamNamesMatch("Sporting KC", "Sporting Kansas City"))
        #expect(HeadshotNameMatching.teamNamesMatch("LAFC", "Los Angeles FC"))
        #expect(HeadshotNameMatching.teamNamesMatch("Seattle Sounders FC", "Seattle Sounders"))
        #expect(HeadshotNameMatching.teamNamesMatch("Arsenal", "Arsenal (W)"))
        #expect(!HeadshotNameMatching.teamNamesMatch("LA Galaxy", "Los Angeles FC"))
        #expect(!HeadshotNameMatching.teamNamesMatch("Sporting Kansas City", "_Retired-Soccer"))
        #expect(!HeadshotNameMatching.teamNamesMatch("Sporting Kansas City", "Seattle Sounders"))
        #expect(!HeadshotNameMatching.teamNamesMatch("FC", "SC"))
    }

    @Test("ESPN's club matches by full name, a two-word short name, or its abbreviation; never a lone short name")
    func espnClubs() {
        #expect(HeadshotNameMatching.teamMatches(sporting, "Sporting KC"))
        #expect(HeadshotNameMatching.teamMatches(sporting, "Sporting Kansas City"))
        // "Sporting" alone is half of Iberia.
        #expect(!HeadshotNameMatching.teamMatches(sporting, "Sporting CP"))
        #expect(!HeadshotNameMatching.teamMatches(sporting, "Sporting Gijón"))
        let initialsOnly = club(.mls, "1", "S.K.C.", short: "", abbreviation: "SKC")
        #expect(HeadshotNameMatching.teamMatches(initialsOnly, "Sporting Kansas City"))
        let twoWordShort = club(.mls, "2", "Sporting Club of Kansas", short: "Sporting KC", abbreviation: "")
        #expect(HeadshotNameMatching.teamMatches(twoWordShort, "Sporting Kansas City"))
    }

    @Test("Sex: a women's league takes only female rows; a men's never does")
    func gender() {
        #expect(HeadshotNameMatching.isWomens(.wsl))
        #expect(HeadshotNameMatching.isWomens(.nwsl))
        #expect(HeadshotNameMatching.isWomens(.premiereLigue))
        #expect(!HeadshotNameMatching.isWomens(.mls))
        #expect(HeadshotNameMatching.genderFits("Female", womens: true))
        #expect(!HeadshotNameMatching.genderFits("Male", womens: true))
        #expect(HeadshotNameMatching.genderFits("Male", womens: false))
        #expect(!HeadshotNameMatching.genderFits("female", womens: false))
        #expect(HeadshotNameMatching.genderFits("", womens: true))
    }

    private struct Row: Equatable {
        var name: String
        var number: Int?
    }

    private func pick(_ name: String, _ number: Int?, _ rows: [Row]) -> Row? {
        HeadshotNameMatching.pick(
            name: name, number: number, among: rows,
            nameOf: { $0.name }, numberOf: { $0.number }
        )
    }

    @Test("Players: the same words, accents aside; single names; surname and number")
    func players() {
        let squad = [
            Row(name: "Dejan Joveljić", number: 9),
            Row(name: "Capita", number: 7),
            Row(name: "Magomed-Shapi Suleymanov", number: 93),
            Row(name: "Jayden Reid", number: 99),
            Row(name: "Seymour Reid", number: 29),
        ]
        #expect(pick("Dejan Joveljic", 9, squad)?.number == 9)
        #expect(pick("dejan joveljic", nil, squad)?.number == 9)
        #expect(pick("Capita", 7, squad)?.number == 7)
        #expect(pick("Capita", nil, squad)?.number == 7)
        // ESPN's short form, settled by the number.
        #expect(pick("Shapi Suleymanov", 93, squad)?.name == "Magomed-Shapi Suleymanov")
        // Without the number it is not guessed.
        #expect(pick("Shapi Suleymanov", nil, squad) == nil)
        // A shared surname is never enough on a different number.
        #expect(pick("Jayden Reid", 99, squad)?.name == "Jayden Reid")
        #expect(pick("Jamal Reid", 29, squad)?.name == "Seymour Reid")
        #expect(pick("Jamal Reid", 5, squad) == nil)
        #expect(pick("", 9, squad) == nil)
    }

    @Test("Two players of one name: the shirt number settles it, or nobody is matched")
    func ambiguity() {
        let squad = [
            Row(name: "Diego Borges", number: 57),
            Row(name: "Diego Borges", number: 4),
        ]
        #expect(pick("Diego Borges", 4, squad)?.number == 4)
        #expect(pick("Diego Borges", nil, squad) == nil)
        #expect(pick("Diego Borges", 10, squad) == nil)
        // Two loose candidates wearing the number: neither.
        let twins = [Row(name: "Ian James", number: 2), Row(name: "Ian James Jr", number: 2)]
        #expect(pick("James", 2, twins) == nil)
    }

    @Test("A query reads the shirt number, and keys by club and player")
    func query() {
        let andre = SoccerHeadshotQuery(espnID: "290777", name: "André Luiz", number: " 11 ", team: sporting)
        #expect(andre.number == 11)
        #expect(andre.isSoccer)
        #expect(andre.key == "soccer/usa.1:186#290777")
        #expect(SoccerHeadshotQuery(espnID: "1", name: "X", number: "", team: sporting).number == nil)
    }
}

// MARK: - FotMob parsing

@Suite("Soccer headshots: FotMob")
struct FotMobParsingTests {
    @Test("Suggestions give each club once, ids as numbers, players and matches skipped")
    func suggestions() {
        let teams = FotMob.parseTeams(json(sportingSuggest))
        #expect(teams.map(\.id) == [6604, 722268])
        #expect(teams.first?.name == "Sporting Kansas City")
        #expect(teams.first?.leagueID == 130)
        #expect(teams.first?.leagueName == "Major League Soccer")
        #expect(FotMob.parseTeams(json("[]")).isEmpty)
        #expect(FotMob.parseTeams(json("<html>oops</html>")).isEmpty)
        #expect(FotMob.parseTeams(json(#"{"error":"nope"}"#)).isEmpty)
    }

    @Test("Reserve, youth and women's sides are told apart")
    func sides() {
        #expect(FotMob.isReserveSide("Sporting Kansas City II"))
        #expect(FotMob.isReserveSide("Arsenal U21"))
        #expect(FotMob.isReserveSide("Barcelona B"))
        #expect(!FotMob.isReserveSide("Sporting Kansas City"))
        #expect(!FotMob.isReserveSide("Bayern München"))
        #expect(FotMob.isWomensSide("Arsenal (W)"))
        #expect(!FotMob.isWomensSide("Arsenal"))
    }

    @Test("The club is picked by name within ESPN's league, never a reserve or women's side")
    func pickTeam() {
        let sportingTeams = FotMob.parseTeams(json(sportingSuggest))
        #expect(FotMob.pickTeam(for: sporting, among: sportingTeams)?.id == 6604)

        let arsenalTeams = FotMob.parseTeams(json(arsenalSuggest))
        #expect(FotMob.pickTeam(for: arsenal, among: arsenalTeams)?.id == 9825)
        #expect(FotMob.pickTeam(for: arsenalWomen, among: arsenalTeams)?.id == 258657)

        // Berekum Chelsea plays in another "Premier League": the id tells them apart.
        let chelseaTeams = FotMob.parseTeams(json(chelseaSuggest))
        #expect(FotMob.pickTeam(for: chelsea, among: chelseaTeams)?.id == 8455)

        // FotMob says München: the league's only club in the answer.
        let bayernTeams = [FotMobTeam(id: 9823, name: "Bayern München", leagueName: "Bundesliga", leagueID: 54)]
        #expect(FotMob.pickTeam(for: bayern, among: bayernTeams)?.id == 9823)

        // The wrong league's club, however named, is not ESPN's.
        let elsewhere = [FotMobTeam(id: 1, name: "Sporting Kansas City", leagueName: "USL Championship", leagueID: 8972)]
        #expect(FotMob.pickTeam(for: sporting, among: elsewhere) == nil)
    }

    @Test("Without a league to check, the name alone: the same words first; two alike, neither")
    func pickTeamByName() {
        let madrid = [
            FotMobTeam(id: 8633, name: "Real Madrid", leagueName: "LaLiga", leagueID: 87),
            FotMobTeam(id: 8367, name: "Real Madrid Castilla", leagueName: "Primera Federacion", leagueID: 8968),
            FotMobTeam(id: 1077486, name: "Real Madrid (W)", leagueName: "Liga F", leagueID: 9907),
        ]
        #expect(FotMob.pickTeam(for: realMadridUCL, among: madrid)?.id == 8633)
        let twins = [
            FotMobTeam(id: 1, name: "Real Madrid", leagueName: nil, leagueID: nil),
            FotMobTeam(id: 2, name: "Real Madrid", leagueName: nil, leagueID: nil),
        ]
        #expect(FotMob.pickTeam(for: realMadridUCL, among: twins) == nil)
    }

    @Test("A squad gives every player but the coach, numbers where given, and the side's sex")
    func squad() {
        let squad = FotMob.parseSquad(json(sportingSquad))
        #expect(squad.gender == "male")
        #expect(squad.members.count == 7)
        #expect(!squad.members.contains { $0.name == "Raphael Wicky" })
        let andre = squad.members.first { $0.id == 1284944 }
        #expect(andre?.name == "André Luiz")
        #expect(andre?.shirtNumber == 11)
        #expect(FotMob.parseSquad(json("null")).members.isEmpty)
        #expect(FotMob.parseSquad(json(#"{"squad":{"squad":null}}"#)).members.isEmpty)
    }

    @Test("ESPN's roster finds its squad members by name and number")
    func members() {
        let squad = FotMob.parseSquad(json(sportingSquad)).members
        #expect(FotMob.member(for: player("André Luiz", "11"), in: squad)?.id == 1284944)
        #expect(FotMob.member(for: player("Andre Luiz", ""), in: squad)?.id == 1284944)
        #expect(FotMob.member(for: player("Capita", "7"), in: squad)?.id == 1187420)
        #expect(FotMob.member(for: player("Shapi Suleymanov", "93"), in: squad)?.id == 861720)
        #expect(FotMob.member(for: player("Alexander Cunningham", "42"), in: squad) == nil)
    }

    @Test("URLs: suggest, squad and photo")
    func urls() {
        #expect(FotMob.suggestURL(term: "Sporting Kansas City")?.absoluteString
            == "https://www.fotmob.com/api/data/search/suggest?term=Sporting%20Kansas%20City&lang=en")
        #expect(FotMob.suggestURL(term: "CF Montréal")?.absoluteString
            == "https://www.fotmob.com/api/data/search/suggest?term=CF%20Montr%C3%A9al&lang=en")
        #expect(FotMob.suggestURL(term: "  ") == nil)
        #expect(FotMob.teamURL(id: 6604)?.absoluteString == "https://www.fotmob.com/api/data/teams?id=6604&ccode3=USA")
        #expect(FotMob.photoURL(playerID: 1284944)?.absoluteString
            == "https://images.fotmob.com/image_resources/playerimages/1284944.png")
        #expect(FotMob.photoURL(playerID: 0) == nil)
        #expect(FotMob.leagueIDs[.mls] == 130)
        #expect(FotMob.leagueNames[.mls] == "Major League Soccer")
        #expect(FotMob.leagueIDs[.championsLeague] == nil)
    }
}

// MARK: - TheSportsDB parsing

@Suite("Soccer headshots: TheSportsDB")
struct TheSportsDBParsingTests {
    @Test("A search answer gives each row; `null` gives none; an error page is no answer")
    func parsing() throws {
        let rows = TheSportsDB.parsePlayers(json(joveljicSearch))
        let row = try #require(rows.first)
        #expect(rows.count == 1)
        #expect(row.id == "34175553")
        #expect(row.name == "Dejan Joveljić")
        #expect(row.team == "Seattle Sounders")
        #expect(row.sport == "Soccer")
        #expect(row.number == nil)
        #expect(row.imageURL?.absoluteString == "https://r2.thesportsdb.com/images/media/player/cutout/toe2fu1766426636.png")

        #expect(TheSportsDB.isPlayerAnswer(json(joveljicSearch)))
        #expect(TheSportsDB.isPlayerAnswer(json(#"{"player":null}"#)))
        #expect(TheSportsDB.parsePlayers(json(#"{"player":null}"#)).isEmpty)
        #expect(!TheSportsDB.isPlayerAnswer(json("The service is unavailable.")))
        #expect(!TheSportsDB.isPlayerAnswer(json(#"{"Message":"Too many requests"}"#)))
        #expect(!TheSportsDB.isPlayerAnswer(json(#"{"player":"nope"}"#)))
    }

    @Test("The cutout, then the thumbnail, then the render — HTTPS only")
    func imagePreference() {
        func row(cutout: String?, thumb: String?, render: String?) -> TheSportsDBPlayer {
            TheSportsDBPlayer(
                id: "1", name: "A", team: "B", sport: "Soccer", gender: "",
                number: nil, cutout: cutout, thumb: thumb, render: render
            )
        }
        #expect(row(cutout: "https://r2.thesportsdb.com/c.png", thumb: "https://r2.thesportsdb.com/t.jpg", render: nil)
            .imageURL?.lastPathComponent == "c.png")
        #expect(row(cutout: nil, thumb: "https://r2.thesportsdb.com/t.jpg", render: "https://r2.thesportsdb.com/r.png")
            .imageURL?.lastPathComponent == "t.jpg")
        #expect(row(cutout: "http://r2.thesportsdb.com/c.png", thumb: nil, render: "https://r2.thesportsdb.com/r.png")
            .imageURL?.lastPathComponent == "r.png")
        #expect(row(cutout: "http://r2.thesportsdb.com/c.png", thumb: "", render: nil).imageURL == nil)
    }

    @Test("A row counts only at ESPN's club, in soccer, of the roster's sex, and by name")
    func matching() throws {
        // Joveljić's row still says Seattle: not Sporting's player.
        let joveljic = TheSportsDB.parsePlayers(json(joveljicSearch))
        #expect(TheSportsDB.match(player("Dejan Joveljic", "9"), in: joveljic) == nil)
        #expect(TheSportsDB.match(player("Dejan Joveljic", "9", at: seattle), in: joveljic)?.id == "34175553")

        let bassong = TheSportsDB.photo(for: player("Zorhan Bassong", "22"), in: TheSportsDB.parsePlayers(json(bassongSearch)))
        #expect(bassong?.playerID == "34195773")
        #expect(bassong?.imageURL.absoluteString == "https://r2.thesportsdb.com/images/media/player/cutout/98irv81766426447.png")

        // A retired namesake, and a fuzzy hit on another name.
        #expect(TheSportsDB.photo(for: player("André Luiz", "11"), in: TheSportsDB.parsePlayers(json(andreLuizSearch))) == nil)
        #expect(TheSportsDB.match(player("Capita", "7"), in: TheSportsDB.parsePlayers(json(capitaSearch))) == nil)

        // Another sport's namesake, or a women's row for a men's roster.
        var other = try #require(TheSportsDB.parsePlayers(json(bassongSearch)).first)
        other.sport = "Basketball"
        #expect(TheSportsDB.match(player("Zorhan Bassong", "22"), in: [other]) == nil)
        other.sport = "Soccer"
        other.gender = "Female"
        #expect(TheSportsDB.match(player("Zorhan Bassong", "22"), in: [other]) == nil)
    }

    @Test("The search URL percent-encodes the name")
    func urls() {
        #expect(TheSportsDB.searchURL(name: "Dejan Joveljic")?.absoluteString
            == "https://www.thesportsdb.com/api/v1/json/3/searchplayers.php?p=Dejan%20Joveljic")
        #expect(TheSportsDB.searchURL(name: "André Luiz")?.absoluteString
            == "https://www.thesportsdb.com/api/v1/json/3/searchplayers.php?p=Andr%C3%A9%20Luiz")
        #expect(TheSportsDB.searchURL(name: "A & B")?.absoluteString
            == "https://www.thesportsdb.com/api/v1/json/3/searchplayers.php?p=A%20%26%20B")
        #expect(TheSportsDB.searchURL(name: " ") == nil)
        #expect(TheSportsDB.isImageHost("r2.thesportsdb.com"))
        #expect(!TheSportsDB.isImageHost("thesportsdb.com.evil.example"))
    }

    @Test("The image loader fetches only FotMob's and TheSportsDB's hosts, over HTTPS")
    func imageHosts() throws {
        func allows(_ string: String) throws -> Bool {
            SoccerPhotoImageLoader.allows(try #require(URL(string: string)))
        }
        #expect(try allows("https://images.fotmob.com/image_resources/playerimages/1284944.png"))
        #expect(try allows("https://r2.thesportsdb.com/images/media/player/cutout/a.png"))
        #expect(try !allows("http://images.fotmob.com/image_resources/playerimages/1.png"))
        #expect(try !allows("https://www.fotmob.com/api/data/teams?id=1"))
        #expect(try !allows("https://notthesportsdb.com/a.png"))
    }
}

// MARK: - Tiers

@Suite("Soccer headshots: tier order")
struct HeadshotTierTests {
    private let mls = HeadshotTiers.order(for: .mls)

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/\(name).png")
    }

    @Test("Soccer: FotMob, API-Football, TheSportsDB, Commons; other sports Commons alone")
    func order() {
        #expect(mls == [.fotMob, .apiFootball, .theSportsDB, .commons])
        #expect(HeadshotTiers.order(for: .premierLeague) == mls)
        #expect(HeadshotTiers.order(for: .nba) == [.commons])
        #expect(HeadshotTiers.order(for: nil) == [.commons])
    }

    @Test("The first photo wins; sources off or without one are passed over")
    func firstPhoto() {
        let states: [HeadshotSource: HeadshotTierState] = [
            .fotMob: .off, .apiFootball: .noPhoto, .theSportsDB: .photo(url("sportsdb")), .commons: .photo(url("commons")),
        ]
        #expect(HeadshotTiers.choose(order: mls, states: states, graceElapsed: false) == .photo(.theSportsDB, url("sportsdb")))
        var withFotMob = states
        withFotMob[.fotMob] = .photo(url("fotmob"))
        #expect(HeadshotTiers.choose(order: mls, states: withFotMob, graceElapsed: false) == .photo(.fotMob, url("fotmob")))
        #expect(HeadshotTiers.choose(order: mls, states: [:], graceElapsed: false) == .placeholder)
        let none: [HeadshotSource: HeadshotTierState] = [.fotMob: .noPhoto, .apiFootball: .noPhoto, .theSportsDB: .off, .commons: .noPhoto]
        #expect(HeadshotTiers.choose(order: mls, states: none, graceElapsed: true) == .placeholder)
    }

    @Test("A source not yet answering holds the rest back only for the grace")
    func grace() {
        let states: [HeadshotSource: HeadshotTierState] = [
            .fotMob: .off, .apiFootball: .noPhoto, .theSportsDB: .pending, .commons: .photo(url("commons")),
        ]
        #expect(HeadshotTiers.choose(order: mls, states: states, graceElapsed: false) == .waiting(.theSportsDB))
        #expect(HeadshotTiers.choose(order: mls, states: states, graceElapsed: true) == .photo(.commons, url("commons")))
        // Its photo, when it comes, outranks the later tier's.
        var answered = states
        answered[.theSportsDB] = .photo(url("sportsdb"))
        #expect(HeadshotTiers.choose(order: mls, states: answered, graceElapsed: true) == .photo(.theSportsDB, url("sportsdb")))
        #expect(HeadshotTiers.grace == .seconds(2))
    }

    @Test("Sources are asked in turn, never past a photo; within the grace, not past one pending")
    func asking() {
        let pending: [HeadshotSource: HeadshotTierState] = [
            .fotMob: .pending, .apiFootball: .noPhoto, .theSportsDB: .pending, .commons: .pending,
        ]
        #expect(HeadshotTiers.sourcesToAsk(order: mls, states: pending, graceElapsed: false) == [.fotMob])
        #expect(HeadshotTiers.sourcesToAsk(order: mls, states: pending, graceElapsed: true) == mls)

        let fotMobOff: [HeadshotSource: HeadshotTierState] = [
            .fotMob: .off, .apiFootball: .noPhoto, .theSportsDB: .pending, .commons: .pending,
        ]
        #expect(HeadshotTiers.sourcesToAsk(order: mls, states: fotMobOff, graceElapsed: false) == [.apiFootball, .theSportsDB])

        let found: [HeadshotSource: HeadshotTierState] = [
            .fotMob: .photo(url("fotmob")), .apiFootball: .noPhoto, .theSportsDB: .pending, .commons: .pending,
        ]
        #expect(HeadshotTiers.sourcesToAsk(order: mls, states: found, graceElapsed: true) == [.fotMob])

        let nba = HeadshotTiers.order(for: .nba)
        #expect(HeadshotTiers.sourcesToAsk(order: nba, states: [.commons: .pending], graceElapsed: false) == [.commons])
        #expect(HeadshotTiers.sourcesToAsk(order: nba, states: [.commons: .off], graceElapsed: true).isEmpty)
    }

    @Test("Settings: TheSportsDB on and FotMob off until the reader says otherwise")
    func settings() throws {
        let suite = "HeadshotTierTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(SoccerPhotoSettings.theSportsDBKey == "settings.thesportsdb.enabled")
        #expect(SoccerPhotoSettings.fotMobKey == "settings.fotmob.enabled")
        #expect(SoccerPhotoSettings.theSportsDBEnabled(defaults))
        #expect(!SoccerPhotoSettings.fotMobEnabled(defaults))
        defaults.set(false, forKey: SoccerPhotoSettings.theSportsDBKey)
        defaults.set(true, forKey: SoccerPhotoSettings.fotMobKey)
        #expect(!SoccerPhotoSettings.theSportsDBEnabled(defaults))
        #expect(SoccerPhotoSettings.fotMobEnabled(defaults))
    }
}

// MARK: - Stores

@Suite("Soccer headshots: stores", .serialized)
@MainActor
struct SoccerHeadshotStoreTests {
    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "SoccerHeadshotStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func sportsDB(
        _ transport: RecordingTransport,
        directory: URL,
        now: @escaping () -> Date = { october16 },
        isOn: @escaping @MainActor () -> Bool = { true }
    ) -> TheSportsDBHeadshotStore {
        TheSportsDBHeadshotStore(
            client: HTTPClient(transport: transport),
            directory: directory,
            spacing: .milliseconds(1),
            now: now,
            enabled: true,
            isOn: isOn
        )
    }

    private func fotMob(
        _ transport: RecordingTransport,
        directory: URL,
        isOn: @escaping @MainActor () -> Bool = { true }
    ) -> FotMobHeadshotStore {
        FotMobHeadshotStore(
            client: HTTPClient(transport: transport),
            directory: directory,
            spacing: .milliseconds(1),
            now: { october16 },
            enabled: true,
            isOn: isOn
        )
    }

    @Test("TheSportsDB off: no state, not one request")
    func sportsDBOff() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingTransport(always: reply(bassongSearch))
        let store = sportsDB(transport, directory: directory, isOn: { false })
        let bassong = player("Zorhan Bassong", "22", id: "286194")
        #expect(store.state(for: bassong) == .off)
        store.request(bassong)
        await store.settle()
        #expect(transport.requestCount == 0)
    }

    @Test("TheSportsDB: one search per player, cached on disk for the next launch")
    func sportsDBCaches() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingTransport(always: reply(bassongSearch))
        let store = sportsDB(transport, directory: directory)
        let bassong = player("Zorhan Bassong", "22", id: "286194")
        #expect(store.state(for: bassong) == .pending)
        store.request(bassong)
        store.request(bassong)
        await store.settle()
        #expect(transport.urls.map(\.absoluteString)
            == ["https://www.thesportsdb.com/api/v1/json/3/searchplayers.php?p=Zorhan%20Bassong"])
        let photo = try #require(URL(string: "https://r2.thesportsdb.com/images/media/player/cutout/98irv81766426447.png"))
        #expect(store.state(for: bassong) == .photo(photo))
        store.request(bassong)
        await store.settle()
        #expect(transport.requestCount == 1)

        let relaunched = sportsDB(transport, directory: directory)
        #expect(relaunched.state(for: bassong) == .photo(photo))
        relaunched.request(bassong)
        await relaunched.settle()
        #expect(transport.requestCount == 1)
    }

    @Test("TheSportsDB: no match is cached, and asked again once three days old")
    func sportsDBNoMatch() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let clock = SoccerTestClock(october16)
        let transport = RecordingTransport(always: reply(andreLuizSearch))
        let store = sportsDB(transport, directory: directory, now: { clock.now })
        let andre = player("André Luiz", "11", id: "290777")
        store.request(andre)
        await store.settle()
        #expect(store.state(for: andre) == .noPhoto)
        store.request(andre)
        await store.settle()
        #expect(transport.requestCount == 1)

        clock.now = october16.addingTimeInterval(TheSportsDB.noMatchInterval + 1)
        #expect(store.state(for: andre) == .pending)
        store.request(andre)
        await store.settle()
        #expect(transport.requestCount == 2)
    }

    @Test("TheSportsDB down: an error page caches nothing and the player falls through")
    func sportsDBDown() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingTransport(always: RecordingTransport.Reply(status: 503, body: Data("The service is unavailable.".utf8)))
        let store = sportsDB(transport, directory: directory)
        let bassong = player("Zorhan Bassong", "22", id: "286194")
        store.request(bassong)
        await store.settle()
        #expect(transport.requestCount == 1)
        #expect(store.state(for: bassong) == .noPhoto)
        #expect(store.records.isEmpty)
        // Not asked again straight away.
        store.request(bassong)
        await store.settle()
        #expect(transport.requestCount == 1)
    }

    @Test("TheSportsDB: a player withdrawn before their turn is never asked about")
    func sportsDBWithdraw() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingTransport(always: reply(#"{"player":null}"#))
        let store = sportsDB(transport, directory: directory)
        let first = player("Zorhan Bassong", "22", id: "286194")
        let second = player("Calvin Harris", "14", id: "293695")
        store.request(first)
        store.request(second)
        store.withdraw(second)
        await store.settle()
        #expect(transport.urls.map { $0.absoluteString.contains("Bassong") } == [true])
        #expect(store.state(for: second) == .pending)
    }

    @Test("FotMob: one search and one squad serve the whole roster, and survive a relaunch")
    func fotMobSquad() async throws {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingTransport { url, _ in
            url.path().hasSuffix("/search/suggest") ? reply(sportingSuggest) : reply(sportingSquad)
        }
        let store = fotMob(transport, directory: directory)
        let andre = player("André Luiz", "11", id: "290777")
        let capita = player("Capita", "7", id: "283361")
        let cunningham = player("Alexander Cunningham", "42", id: "300001")
        #expect(store.state(for: andre) == .pending)
        store.request(andre)
        store.request(capita)
        await store.settle()
        #expect(transport.urls.map(\.absoluteString) == [
            "https://www.fotmob.com/api/data/search/suggest?term=Sporting%20Kansas%20City&lang=en",
            "https://www.fotmob.com/api/data/teams?id=6604&ccode3=USA",
        ])
        let andrePhoto = try #require(FotMob.photoURL(playerID: 1284944))
        #expect(store.state(for: andre) == .photo(andrePhoto))
        let capitaPhoto = try #require(FotMob.photoURL(playerID: 1187420))
        #expect(store.state(for: capita) == .photo(capitaPhoto))
        #expect(store.state(for: cunningham) == .noPhoto)
        store.request(cunningham)
        await store.settle()
        #expect(transport.requestCount == 2)

        let relaunched = fotMob(transport, directory: directory)
        #expect(relaunched.state(for: andre) == .photo(andrePhoto))
        relaunched.request(andre)
        await relaunched.settle()
        #expect(transport.requestCount == 2)
    }

    @Test("FotMob off: no state, not one request")
    func fotMobOff() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingTransport(always: reply(sportingSuggest))
        let store = fotMob(transport, directory: directory, isOn: { false })
        let andre = player("André Luiz", "11", id: "290777")
        #expect(store.state(for: andre) == .off)
        store.request(andre)
        await store.settle()
        #expect(transport.requestCount == 0)
    }

    @Test("FotMob without the club: cached as not found, every player falls through")
    func fotMobNoClub() async {
        let directory = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = RecordingTransport(always: reply(#"[{"title":{"key":"all"},"suggestions":[]}]"#))
        let store = fotMob(transport, directory: directory)
        let andre = player("André Luiz", "11", id: "290777")
        store.request(andre)
        await store.settle()
        // The full name, then the short name; no squad to ask for.
        #expect(transport.requestCount == 2)
        #expect(store.state(for: andre) == .noPhoto)
    }

    @Test("A photo FotMob has not got (403) is not asked for twice")
    func missingPhoto() async throws {
        let transport = RecordingTransport(always: .status(403))
        let loader = SoccerPhotoImageLoader(transport: transport, enabled: true)
        let url = try #require(FotMob.photoURL(playerID: 1734140))
        #expect(await loader.image(for: url) == nil)
        #expect(await loader.image(for: url) == nil)
        #expect(transport.requestCount == 1)
    }
}
