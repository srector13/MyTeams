//
//  TabBarTests.swift
//  myTeamsTests
//
//  Created by Stephen Rector on 10/4/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation
import Testing
import UIKit

@testable import myTeams

/// How many favorites the system tab bar shows before "More"
/// (`HomeTabs.barCount`). The bar holds teams only: adding teams is in
/// Settings (t_fa6748f4).
@Suite("Tab bar")
struct TabBarTests {
    @Test("Every team is in the bar while they all fit")
    func allInTheBarWhileTheyFit() {
        #expect(HomeTabs.barCount(teamCount: 0, barCapacity: HomeTabs.compactCapacity) == 0)
        #expect(HomeTabs.barCount(teamCount: 1, barCapacity: HomeTabs.compactCapacity) == 1)
        // No Teams tab taking a slot: five teams fill the bar.
        #expect(HomeTabs.barCount(teamCount: 5, barCapacity: HomeTabs.compactCapacity) == 5)
    }

    @Test("Past the bar's capacity the bar shows one fewer and More lists the rest")
    func restUnderMoreOnceTheyOverflow() {
        // Six favorites: four in the bar, then More with the other two.
        #expect(HomeTabs.barCount(teamCount: 6, barCapacity: HomeTabs.compactCapacity) == 4)
        #expect(HomeTabs.barCount(teamCount: 12, barCapacity: HomeTabs.compactCapacity) == 4)
    }

    @Test("With no limit on the bar every team is in it")
    func allInTheBarWithoutALimit() {
        #expect(HomeTabs.barCount(teamCount: 12, barCapacity: nil) == 12)
    }
}

/// Choosing a team from the bar's "More" list loads its page, as a tap on
/// its tab would (t_fa6748f4): both go through `HomeRouting.teamChosen`.
@Suite("Choosing a team")
struct TeamChosenTests {
    private let teams = [
        "football/nfl:12", "baseball/mlb:7", "soccer/usa.1:186",
        "basketball/mens-college-basketball:2305", "hockey/nhl:24", "football/nfl:13",
    ]

    /// A team the compact bar lists under "More".
    private var moreTeam: String {
        let barCount = HomeTabs.barCount(teamCount: teams.count, barCapacity: HomeTabs.compactCapacity)
        return teams[barCount]
    }

    @Test("A team picked from More is selected")
    func morePickSelectsTheTeam() {
        let start = HomeRouting.State(selection: teams[0], pendingLink: nil)
        let next = HomeRouting.teamChosen(start, team: moreTeam, teams: teams)
        #expect(next.selection == moreTeam)
    }

    @Test("A pick from More makes the same change as a tap on a bar tab")
    func morePickMatchesATabTap() {
        let start = HomeRouting.State(selection: teams[0], pendingLink: nil, showsSettings: false)
        let fromMore = HomeRouting.teamChosen(start, team: moreTeam, teams: teams)
        // What the tab view's selection would have been set to by a tap.
        var tapped = start
        tapped.selection = moreTeam
        #expect(fromMore == tapped)
        // And a bar tab goes the same way.
        let barTap = HomeRouting.teamChosen(start, team: teams[1], teams: teams)
        #expect(barTap.selection == teams[1])
        #expect(barTap.pendingLink == start.pendingLink)
        #expect(barTap.showsSettings == start.showsSettings)
    }

    @Test("Choosing the team already selected changes nothing")
    func choosingTheSelectedTeamIsANoOp() {
        let start = HomeRouting.State(selection: moreTeam, pendingLink: nil)
        #expect(HomeRouting.teamChosen(start, team: moreTeam, teams: teams) == start)
    }

    @Test("A team no longer followed isn't selected")
    func unknownTeamIsIgnored() {
        let start = HomeRouting.State(selection: teams[0], pendingLink: nil)
        #expect(HomeRouting.teamChosen(start, team: "football/nfl:99", teams: teams) == start)
    }

    @Test("Choosing a team leaves Settings and a pending link alone")
    func leavesTheRestAlone() {
        let start = HomeRouting.State(selection: teams[0], pendingLink: teams[2], showsSettings: true)
        let next = HomeRouting.teamChosen(start, team: moreTeam, teams: teams)
        #expect(next.selection == moreTeam)
        #expect(next.pendingLink == teams[2])
        #expect(next.showsSettings)
    }
}

/// Settings belongs to `Home`, not to a team's page, so it outlives the
/// page (A-5): `HomeRouting` moves the selection but never closes it.
@Suite("Settings sheet lifecycle")
struct SettingsSheetLifecycleTests {
    private let chiefs = "football/nfl:12"
    private let royals = "baseball/mlb:7"
    private let sporting = "soccer/usa.1:186"

    @Test("Removing the team on screen in Manage Teams leaves Settings open")
    func survivesRemovingTheCurrentTeam() {
        let open = HomeRouting.State(selection: chiefs, pendingLink: nil, showsSettings: true)
        // Settings → Manage Teams unfollows the Chiefs; the favorites resolve
        // without them and the selection moves to the next team.
        let next = HomeRouting.favoritesResolved(open, teams: [royals, sporting])
        #expect(next.selection == royals)
        #expect(next.showsSettings)
    }

    @Test("Removing every team leaves Settings open")
    func survivesRemovingEveryTeam() {
        let open = HomeRouting.State(selection: chiefs, pendingLink: nil, showsSettings: true)
        let next = HomeRouting.favoritesResolved(open, teams: [])
        #expect(next.selection == "")
        #expect(next.showsSettings)
    }

    @Test("A widget link arriving while Settings is open leaves it open")
    func survivesALink() {
        let open = HomeRouting.State(selection: chiefs, pendingLink: royals, showsSettings: true)
        let linked = HomeRouting.linkChanged(open, teams: [chiefs, royals], favoriteIDs: [chiefs, royals])
        #expect(linked.selection == royals)
        #expect(linked.showsSettings)
        // And one that resolves later, with the favorites.
        let pending = HomeRouting.State(selection: chiefs, pendingLink: sporting, showsSettings: true)
        let resolved = HomeRouting.favoritesResolved(pending, teams: [chiefs, sporting])
        #expect(resolved.selection == sporting)
        #expect(resolved.showsSettings)
    }

    @Test("Routing never opens Settings by itself")
    func closedStaysClosed() {
        let closed = HomeRouting.State(selection: chiefs, pendingLink: nil)
        #expect(!closed.showsSettings)
        #expect(!HomeRouting.favoritesResolved(closed, teams: [royals]).showsSettings)
    }
}

/// The tab crests' cache key (A-17) and the bar crest's contrast outline
/// (B-4, t_fa6748f4).
@Suite("Tab and bar crests")
@MainActor
struct CrestTests {
    @Test("A stored crest's key changes with its file's modification date")
    func sourceKeyFollowsTheFile() {
        let path = "/Logos/favorites/football.nfl_12.default.png"
        let before = Date(timeIntervalSinceReferenceDate: 1_000)
        let after = Date(timeIntervalSinceReferenceDate: 2_000)
        #expect(TabCrest.sourceKey(path: path, modified: before) == TabCrest.sourceKey(path: path, modified: before))
        #expect(TabCrest.sourceKey(path: path, modified: before) != TabCrest.sourceKey(path: path, modified: after))
        #expect(TabCrest.sourceKey(path: path, modified: before)
            != TabCrest.sourceKey(path: "/Logos/catalog/football.nfl_12.default.png", modified: before))
    }

    @Test("A crest close to the bar's colour gets an outline; one that stands out doesn't")
    func outlineOnLowContrast() throws {
        let red = try #require(TeamColors.relativeLuminance(hex: "E31837"))
        // A red crest on its own red bar.
        #expect(BarCrest.crestNeedsOutline(dominantLuminance: red, heroHex: "E31837"))
        // A white crest on a pale yellow bar.
        #expect(BarCrest.crestNeedsOutline(dominantLuminance: 1, heroHex: "FFF2A8"))
        // A navy crest on black.
        let navy = try #require(TeamColors.relativeLuminance(hex: "0B1F3A"))
        #expect(BarCrest.crestNeedsOutline(dominantLuminance: navy, heroHex: "000000"))
        // White on navy, black on gold: no outline.
        #expect(!BarCrest.crestNeedsOutline(dominantLuminance: 1, heroHex: "0B1F3A"))
        #expect(!BarCrest.crestNeedsOutline(dominantLuminance: 0, heroHex: "FFB612"))
    }

    @Test("The outline goes on below the minimum contrast and off above it")
    func outlineThreshold() {
        // On black (luminance 0) the contrast is (L + 0.05) / 0.05, so the
        // minimum falls at this luminance.
        let atMinimum = BarCrest.minimumContrast * 0.05 - 0.05
        #expect(!BarCrest.crestNeedsOutline(dominantLuminance: atMinimum + 0.01, heroHex: "000000"))
        #expect(BarCrest.crestNeedsOutline(dominantLuminance: atMinimum - 0.01, heroHex: "000000"))
        #expect(BarCrest.crestNeedsOutline(dominantLuminance: 0, heroHex: "000000"))
    }

    @Test("A bar colour that isn't hex never outlines")
    func outlineNeedsAHex() {
        #expect(!BarCrest.crestNeedsOutline(dominantLuminance: 0.5, heroHex: ""))
        #expect(!BarCrest.crestNeedsOutline(dominantLuminance: 0.5, heroHex: "red"))
    }

    @Test("A crest's dominant shade is its biggest opaque area, not the transparency around it")
    func dominantLuminance() throws {
        let size = CGSize(width: 48, height: 48)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        // Three quarters white, a quarter black, on a transparent corner.
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 48, height: 36))
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 36, width: 36, height: 12))
        }
        let luminance = try #require(BarCrest.dominantLuminance(of: image))
        #expect(luminance > 0.9)

        let clear = UIGraphicsImageRenderer(size: size, format: format).image { _ in }
        #expect(BarCrest.dominantLuminance(of: clear) == nil)
    }
}

/// What a team page's header says under the team's name
/// (`TeamHeaderSummary`).
@Suite("Team page header")
struct TeamHeaderSummaryTests {
    private let chiefs = TeamRef.chiefs

    private func game(pointer: Int, opponent: String = "Raiders", home: Bool = true, completed: Bool) -> Game {
        Game(
            team: "Chiefs", opponent: opponent, score: "", opponentScore: "",
            time: "", date: "", dateAsDate: .now, opponentLogo: "", channel: "",
            location: "", gameHome: home, gameID: "\(pointer)", pointer: pointer,
            gameWin: false, completed: completed, competitionName: "",
            cancelled: false, postponed: false, gameClock: "",
            gamePeriod: "", gameHalftime: false
        )
    }

    private func entry(_ teamID: String, rank: Int?) -> StandingsEntry {
        StandingsEntry(
            teamID: teamID, name: teamID, shortName: teamID, abbreviation: teamID,
            logoURL: nil, record: Record(wins: 0, losses: 0, format: .winLoss), rank: rank,
            gamesBehind: "", conferenceRecord: "", goalDifference: "", streak: "",
            note: "", noteColorHex: "", clincher: ""
        )
    }

    private func standings(_ kind: StandingsKind, rank: Int?) -> Standings {
        Standings(kind: kind, seasonDisplayName: "", groups: [
            StandingsGroup(id: "1", name: "AFC West", abbreviation: "AFCW", entries: [
                entry("13", rank: 1), entry("12", rank: rank),
            ]),
        ])
    }

    @Test("Nothing to say before the feeds load")
    func empty() {
        let summary = TeamHeaderSummary(
            team: chiefs, games: [], nextGame: 0,
            record: Record(wins: 0, losses: 0, format: .winLoss), standings: nil
        )
        #expect(summary == TeamHeaderSummary())
        #expect(summary.recordLine == nil)
    }

    @Test("The record and the table position share a line")
    func recordLine() {
        let summary = TeamHeaderSummary(
            team: chiefs, games: [game(pointer: 0, completed: true)], nextGame: 0,
            record: Record(wins: 10, losses: 6, format: .winLoss), standings: standings(.records, rank: 2)
        )
        #expect(summary.record == "10-6")
        #expect(summary.standing == "2nd in AFC West")
        #expect(summary.recordLine == "10-6 · 2nd in AFC West")
        #expect(TeamHeaderSummary(record: "4-1-0").recordLine == "4-1-0")
    }

    @Test("A poll gives a rank; an unranked team or one not in the table gives nothing")
    func standing() {
        #expect(TeamHeaderSummary.standing(of: "12", in: standings(.rankings, rank: 5)) == "No. 5 in AFC West")
        #expect(TeamHeaderSummary.standing(of: "12", in: standings(.pointsTable, rank: 13)) == "13th in AFC West")
        #expect(TeamHeaderSummary.standing(of: "12", in: standings(.records, rank: nil)) == nil)
        #expect(TeamHeaderSummary.standing(of: "12", in: standings(.records, rank: 0)) == nil)
        #expect(TeamHeaderSummary.standing(of: "99", in: standings(.records, rank: 2)) == nil)
    }

    @Test("The next game reads vs at home and at away, until the season is played out")
    func nextGame() throws {
        let home = try #require(TeamHeaderSummary.upcoming(games: [game(pointer: 0, completed: false)], nextGame: 0))
        #expect(home.hasPrefix("vs Raiders · "))
        let away = try #require(TeamHeaderSummary.upcoming(
            games: [game(pointer: 0, completed: true), game(pointer: 1, opponent: "Broncos", home: false, completed: false)],
            nextGame: 1
        ))
        #expect(away.hasPrefix("at Broncos · "))
        // `getNextGame` clamps to the last game once all are played.
        #expect(TeamHeaderSummary.upcoming(games: [game(pointer: 0, completed: true)], nextGame: 0) == nil)
        #expect(TeamHeaderSummary.upcoming(games: [], nextGame: 0) == nil)
    }
}
