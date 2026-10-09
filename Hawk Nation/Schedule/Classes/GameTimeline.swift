//
//  GameTimeline.swift
//  Hawk Nation
//
//  Created by Stephen Rector on 10/8/26.
//  Copyright © 2026 Stephen Rector. All rights reserved.
//

import Foundation

/// One moment in a game's timeline: a score, or in soccer a card.
///
/// Read from whichever list the sport's summary carries (R-2):
/// - football: top-level `scoringPlays`, each with the running score;
/// - soccer: top-level `keyEvents`, filtered to goals and cards; the running
///   score is counted from the goals, by the scoring side's `team.id`;
/// - basketball, baseball and hockey: top-level `plays`, filtered to
///   `scoringPlay`, each with the running score.
struct TimelineEvent: Hashable, Sendable, Identifiable {
    enum Kind: String, Hashable, Sendable {
        case score
        case yellowCard
        case redCard
    }

    /// The feed's play id.
    var id: String
    var period: Int
    /// The feed's name for the period (`"1st Quarter"`, `"2nd"`,
    /// `"Bottom 1st Inning"`), or empty when it gives none (football,
    /// soccer); the sheet then names the period from the league.
    var periodLabel: String
    /// The clock as the feed writes it (`"8:25"`, `"45'+1'"`); empty for
    /// baseball, which has none.
    var clock: String
    /// The ESPN id of the team the event belongs to; empty when the feed
    /// names none.
    var teamID: String
    /// `"home"` or `"away"`, looked up from `teamID` in the header; empty
    /// when the header does not list the team.
    var homeAway: String
    var kind: Kind
    var text: String
    /// The athletes the feed names, scorer first, without repeats.
    var athleteIDs: [String]
    /// The score after the event; `nil` for a card.
    var homeScore: Int?
    var awayScore: Int?
    /// The points the event added (`7` for a touchdown and kick, `1` for a
    /// goal); `nil` for a card.
    var points: Int?
}

/// The home team's chance of winning after one play, from the summary's
/// top-level `winprobability` list.
///
/// Plotted by position in that list. It is not parallel to `plays` in every
/// sport (MLB lists 81 probabilities against 595 plays), and football has no
/// `plays` at all, so `playID` is kept only as a stable identity.
struct WinProbabilityPoint: Hashable, Sendable, Identifiable {
    var index: Int
    /// From 0 to 1.
    var homeWinPercentage: Double
    var playID: String

    var id: Int { index }
}

/// One player on a team's injury report.
struct InjuryEntry: Hashable, Sendable, Identifiable {
    var athleteID: String
    var name: String
    /// The position's abbreviation (`"WR"`, `"RP"`), or empty.
    var position: String
    /// As the feed writes it: `"Out"`, `"Questionable"`, `"Day-To-Day"`,
    /// `"60-Day-IL"`.
    var status: String
    /// The body part or reason, `details.type` (`"Knee"`, `"Personal"`). The
    /// entry's own `type` is the status's code, not the injury.
    var injury: String
    /// `details.detail` (`"Surgery"`), empty when the feed says none or
    /// `"Not Specified"`.
    var detail: String
    /// `details.side` (`"Left"`), empty when the feed says none or
    /// `"Not Specified"`.
    var side: String
    /// `details.returnDate` as the feed writes it (`"2026-10-15"`), or empty.
    var returnDate: String

    var id: String { athleteID.isEmpty ? name : athleteID }
}

/// One team's injury report.
struct TeamInjuries: Hashable, Sendable, Identifiable {
    var teamID: String
    var name: String
    var abbreviation: String
    /// `"home"` or `"away"` from the header, or empty.
    var homeAway: String
    var injuries: [InjuryEntry]

    var id: String { teamID.isEmpty ? name : teamID }
}

/// A game's "story" (R-2): how it was scored, how the home side's chances
/// moved, and who was missing. Read from the summary the sheet already
/// polls; odds (`pickcenter`) are deliberately left out.
///
/// Teams are matched by `team.id` and athletes by their id, never by a
/// position shared between two lists (roadmap §5.3).
struct GameStory: Hashable, Sendable {
    /// A side in the header, keyed by team id.
    struct Side: Hashable, Sendable {
        var homeAway: String
        var abbreviation: String
    }

    var timeline: [TimelineEvent]
    var winProbability: [WinProbabilityPoint]
    /// Home first, then away; a team the header does not list follows.
    var injuries: [TeamInjuries]
    /// The header's competitors by team id.
    var sides: [String: Side]

    static let empty = GameStory(timeline: [], winProbability: [], injuries: [], sides: [:])

    var isEmpty: Bool {
        timeline.isEmpty && winProbability.isEmpty && injuries.allSatisfy(\.injuries.isEmpty)
    }

    /// The abbreviation of the team with ESPN id `teamID`, or empty.
    func abbreviation(teamID: String) -> String {
        sides[teamID]?.abbreviation ?? ""
    }

    /// The home team's abbreviation, or empty.
    var homeAbbreviation: String {
        sides.values.first { $0.homeAway == "home" }?.abbreviation ?? ""
    }
}

extension GameStory {
    /// Reads a summary document's story. Any part the document lacks is
    /// empty: a pre-game summary has injuries but no timeline, and its
    /// `winprobability` is an empty list.
    init(summary json: JSON) {
        var sides: [String: Side] = [:]
        for (_, competitor) in json["header", "competitions", 0, "competitors"] {
            let id = competitor["team", "id"].stringValue
            guard !id.isEmpty else { continue }
            sides[id] = Side(
                homeAway: competitor["homeAway"].stringValue,
                abbreviation: competitor["team", "abbreviation"].stringValue
            )
        }

        self.sides = sides
        self.timeline = Self.timeline(from: json, sides: sides)
        self.winProbability = Self.winProbability(from: json["winprobability"])
        self.injuries = Self.injuries(from: json["injuries"], sides: sides)
    }

    // MARK: Timeline

    private static func timeline(from json: JSON, sides: [String: Side]) -> [TimelineEvent] {
        if !json["scoringPlays"].arrayValue.isEmpty {
            return json["scoringPlays"].arrayValue
                .compactMap { scoringEvent($0, sides: sides) }
                .withPoints()
        }
        if !json["keyEvents"].arrayValue.isEmpty {
            return keyEvents(json["keyEvents"], sides: sides)
        }
        return json["plays"].arrayValue
            .filter { $0["scoringPlay"].boolValue }
            .compactMap { scoringEvent($0, sides: sides) }
            .withPoints()
    }

    /// A `scoringPlays` or `plays` entry, which carries the running score.
    private static func scoringEvent(_ play: JSON, sides: [String: Side]) -> TimelineEvent? {
        let teamID = play["team", "id"].stringValue
        let period = play["period"]
        var periodLabel = period["displayValue"].stringValue
        // Baseball names the half: "Top" / "Bottom".
        let half = period["type"].stringValue
        if !half.isEmpty, !periodLabel.isEmpty {
            periodLabel = "\(half) \(periodLabel)"
        }
        let text = trimmed(play["text"].stringValue)
        guard !text.isEmpty else { return nil }

        return TimelineEvent(
            id: play["id"].stringValue,
            period: period["number"].intValue,
            periodLabel: periodLabel,
            clock: play["clock", "displayValue"].stringValue,
            teamID: teamID,
            homeAway: sides[teamID]?.homeAway ?? "",
            kind: .score,
            text: text,
            athleteIDs: athleteIDs(play["participants"]),
            homeScore: play["homeScore"].int,
            awayScore: play["awayScore"].int
        )
    }

    /// A soccer summary's goals and cards, with the running score counted
    /// from the goals by the scoring side's `team.id`.
    private static func keyEvents(_ events: JSON, sides: [String: Side]) -> [TimelineEvent] {
        var home = 0
        var away = 0
        return events.arrayValue.compactMap { event -> TimelineEvent? in
            let type = event["type", "type"].stringValue
            let kind: TimelineEvent.Kind
            if event["scoringPlay"].boolValue {
                kind = .score
            } else if type.contains("red-card") {
                // Includes a second yellow ("yellow-red-card"): a sending off.
                kind = .redCard
            } else if type.contains("yellow-card") {
                kind = .yellowCard
            } else {
                return nil
            }
            // Shoot-out kicks don't move the match score.
            if event["shootout"].boolValue { return nil }

            let teamID = event["team", "id"].stringValue
            let side = sides[teamID]?.homeAway ?? ""
            let participants = athleteIDs(event["participants"])

            var text = trimmed(event["text"].stringValue)
            if text.isEmpty { text = trimmed(event["shortText"].stringValue) }
            if text.isEmpty {
                let name = event["participants", 0, "athlete", "displayName"].stringValue
                text = [name, event["type", "text"].stringValue]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
            }

            var points: Int?
            if kind == .score {
                switch side {
                case "home": home += 1
                case "away": away += 1
                default: break
                }
                points = 1
            }

            return TimelineEvent(
                id: event["id"].stringValue,
                period: event["period", "number"].intValue,
                periodLabel: "",
                clock: event["clock", "displayValue"].stringValue,
                teamID: teamID,
                homeAway: side,
                kind: kind,
                text: text,
                athleteIDs: participants,
                homeScore: kind == .score ? home : nil,
                awayScore: kind == .score ? away : nil,
                points: points
            )
        }
    }

    private static func athleteIDs(_ participants: JSON) -> [String] {
        var seen = Set<String>()
        return participants.arrayValue.compactMap { participant -> String? in
            let id = participant["athlete", "id"].stringValue
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return id
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Win probability

    private static func winProbability(from list: JSON) -> [WinProbabilityPoint] {
        var points: [WinProbabilityPoint] = []
        for entry in list.arrayValue {
            guard let pct = entry["homeWinPercentage"].double else { continue }
            points.append(WinProbabilityPoint(
                index: points.count,
                homeWinPercentage: min(max(pct, 0), 1),
                playID: entry["playId"].stringValue
            ))
        }
        return points
    }

    // MARK: Injuries

    private static func injuries(from list: JSON, sides: [String: Side]) -> [TeamInjuries] {
        let teams: [TeamInjuries] = list.arrayValue.map { entry -> TeamInjuries in
            let team = entry["team"]
            let teamID = team["id"].stringValue
            return TeamInjuries(
                teamID: teamID,
                name: team["displayName"].stringValue,
                abbreviation: team["abbreviation"].stringValue,
                homeAway: sides[teamID]?.homeAway ?? "",
                injuries: entry["injuries"].arrayValue.compactMap { injury -> InjuryEntry? in
                    let athlete = injury["athlete"]
                    let name = athlete["displayName"].stringValue
                    guard !name.isEmpty else { return nil }
                    let details = injury["details"]
                    return InjuryEntry(
                        athleteID: athlete["id"].stringValue,
                        name: name,
                        position: athlete["position", "abbreviation"].stringValue,
                        status: injury["status"].stringValue,
                        injury: specified(details["type"].stringValue),
                        detail: specified(details["detail"].stringValue),
                        side: specified(details["side"].stringValue),
                        returnDate: details["returnDate"].stringValue
                    )
                }
            )
        }
        func rank(_ team: TeamInjuries) -> Int {
            switch team.homeAway {
            case "home": 0
            case "away": 1
            default: 2
            }
        }
        // Stable: teams of the same rank keep the feed's order.
        return teams.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// The feed's value, or empty for its "Not Specified".
    private static func specified(_ value: String) -> String {
        value == "Not Specified" ? "" : value
    }
}

private extension Array where Element == TimelineEvent {
    /// Each score's points: its total less the total before it.
    func withPoints() -> [TimelineEvent] {
        var previous = 0
        return map { event in
            var event = event
            if let home = event.homeScore, let away = event.awayScore {
                event.points = home + away - previous
                previous = home + away
            }
            return event
        }
    }
}
