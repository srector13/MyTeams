//
//  RoyalsWidgetScheduleLoader.swift
//  myTeamWidgetExtension
//
//  Created by Stephen Rector on 12/4/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI

class royalsSchedule {
    // MARK: - Schedule
    struct Schedule: Codable {
        let timestamp: String?
        let status: String?
        let season: RequestedSeasonClass?
        let team: ScheduleTeam?
        let events: [Event]?
        let requestedSeason: RequestedSeasonClass?
    }

    // MARK: - Event
    struct Event: Codable {
        let id, name, shortName: String?
        let date: Date?
        let season: EventSeason?
        let seasonType: SeasonType?
        let week: Week?
        let timeValid: Bool?
        let competitions: [Competition]?
        let links: [EventLink]?
    }

    // MARK: - Competition
    struct Competition: Codable {
        let id: String?
        let date: Date?
        let attendance: Int?
        let type: CompetitionType?
        let timeValid, neutralSite, boxscoreAvailable, ticketsAvailable: Bool?
        let venue: Venue?
        let competitors: [Competitor]?
        let notes: [JSONAny]?
        let broadcasts: [Broadcast]?
        let tickets: [Ticket]?
        let status: Status?
    }

    // MARK: - Broadcast
    struct Broadcast: Codable {
        let type: BroadcastType?
        let market: Market?
        let media: Media?
        let lang, region: String?
    }

    // MARK: - Market
    struct Market: Codable {
        let id, type: String?
    }

    // MARK: - Media
    struct Media: Codable {
        let shortName: String?
    }

    // MARK: - BroadcastType
    struct BroadcastType: Codable {
        let id, shortName: String?
    }

    // MARK: - Competitor
    struct Competitor: Codable {
        let id: String?
        let type: TypeElement?
        let order: Int?
        let homeAway: HomeAway?
        let team: CompetitorTeam?
    }

    enum HomeAway: String, Codable {
        case away = "away"
        case home = "home"
    }

    // MARK: - CompetitorTeam
    struct CompetitorTeam: Codable {
        let id, location, abbreviation, displayName: String?
        let shortDisplayName: String?
        let logos: [Logo]?
        let links: [TeamLink]?
    }

    // MARK: - TeamLink
    struct TeamLink: Codable {
        let rel: [TypeElement]?
        let href: String?
        let text: PurpleText?
    }

    enum TypeElement: String, Codable {
        case clubhouse = "clubhouse"
        case desktop = "desktop"
        case team = "team"
    }

    enum PurpleText: String, Codable {
        case clubhouse = "Clubhouse"
    }

    // MARK: - Logo
    struct Logo: Codable {
        let href: String?
        let width, height: Int?
        let alt: String?
        let rel: [LogoRel]?
    }

    enum LogoRel: String, Codable {
        case dark = "dark"
        case full = "full"
        case relDefault = "default"
        case scoreboard = "scoreboard"
    }

    // MARK: - Status
    struct Status: Codable {
        let clock: Int?
        let displayClock: DisplayClock?
        let period: Int?
        let type: StatusType?
        let halfInning: Int?
        let periodPrefix: PeriodPrefix?
    }

    enum DisplayClock: String, Codable {
        case the000 = "0:00"
    }

    enum PeriodPrefix: String, Codable {
        case top = "Top"
    }

    // MARK: - StatusType
    struct StatusType: Codable {
        let id: String?
        let name: TypeName?
        let state: State?
        let completed: Bool?
        let typeDescription: Description?
        let detail: String?
        let shortDetail: ShortDetail?

        enum CodingKeys: String, CodingKey {
            case id, name, state, completed
            case typeDescription = "description"
            case detail, shortDetail
        }
    }

    enum TypeName: String, Codable {
        case statusScheduled = "STATUS_SCHEDULED"
    }

    enum ShortDetail: String, Codable {
        case tbd = "TBD"
        case the427635PmEdt = "4/27 - 6:35 PM EDT"
        case the428635PmEdt = "4/28 - 6:35 PM EDT"
        case the45400PmEdt = "4/5 - 4:00 PM EDT"
    }

    enum State: String, Codable {
        case pre = "pre"
    }

    enum Description: String, Codable {
        case scheduled = "Scheduled"
    }

    // MARK: - Ticket
    struct Ticket: Codable {
        let id, summary, ticketDescription: String?
        let maxPrice, startingPrice, numberAvailable, totalPostings: Int?
        let links: [TicketLink]?

        enum CodingKeys: String, CodingKey {
            case id, summary
            case ticketDescription = "description"
            case maxPrice, startingPrice, numberAvailable, totalPostings, links
        }
    }

    // MARK: - TicketLink
    struct TicketLink: Codable {
        let rel: [PurpleRel]?
        let href: String?
    }

    enum PurpleRel: String, Codable {
        case desktop = "desktop"
        case event = "event"
        case tickets = "tickets"
        case venue = "venue"
    }

    // MARK: - CompetitionType
    struct CompetitionType: Codable {
        let id: String?
        let text: TypeText?
        let abbreviation: TypeAbbreviation?
    }

    enum TypeAbbreviation: String, Codable {
        case std = "STD"
    }

    enum TypeText: String, Codable {
        case standard = "Standard"
    }

    // MARK: - Venue
    struct Venue: Codable {
        let fullName: String?
        let address: Address?
    }

    // MARK: - Address
    struct Address: Codable {
        let city, state, zipCode: String?
    }

    // MARK: - EventLink
    struct EventLink: Codable {
        let language: Language?
        let rel: [FluffyRel]?
        let href: String?
        let text, shortText: ShortTextEnum?
        let isExternal, isPremium: Bool?
    }

    enum Language: String, Codable {
        case enUS = "en-US"
    }

    enum FluffyRel: String, Codable {
        case app = "app"
        case desktop = "desktop"
        case event = "event"
        case now = "now"
        case sportscenter = "sportscenter"
        case summary = "summary"
        case videos = "videos"
        case watchespn = "watchespn"
    }

    enum ShortTextEnum: String, Codable {
        case gamecast = "Gamecast"
        case now = "Now"
        case summary = "Summary"
        case videos = "Videos"
        case watchESPN = "WatchESPN"
    }

    // MARK: - EventSeason
    struct EventSeason: Codable {
        let year: Int?
        let displayName: String?
    }

    // MARK: - SeasonType
    struct SeasonType: Codable {
        let id: String?
        let type: Int?
        let name: SeasonTypeName?
        let abbreviation: SeasonTypeAbbreviation?
    }

    enum SeasonTypeAbbreviation: String, Codable {
        case reg = "reg"
    }

    enum SeasonTypeName: String, Codable {
        case regularSeason = "Regular Season"
    }

    // MARK: - Week
    struct Week: Codable {
        let number: Int?
        let text: String?
    }

    // MARK: - RequestedSeasonClass
    struct RequestedSeasonClass: Codable {
        let year, type: Int?
        let name, displayName: String?
        let half: Int?
    }

    // MARK: - ScheduleTeam
    struct ScheduleTeam: Codable {
        let id, abbreviation, location, name: String?
        let displayName: String?
        let clubhouse: String?
        let color: String?
        let logo: String?
        let seasonSummary, standingSummary: String?
        let groups: Groups?
    }

    // MARK: - Groups
    struct Groups: Codable {
        let id: String?
        let parent: Parent?
        let isConference: Bool?
    }

    // MARK: - Parent
    struct Parent: Codable {
        let id: String?
    }

    // MARK: - Encode/decode helpers

    class JSONNull: Codable, Hashable {

        public static func == (lhs: JSONNull, rhs: JSONNull) -> Bool {
            return true
        }

        public var hashValue: Int {
            return 0
        }

        public func hash(into hasher: inout Hasher) {
            // No-op
        }

        public init() {}

        public required init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if !container.decodeNil() {
                throw DecodingError.typeMismatch(JSONNull.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for JSONNull"))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encodeNil()
        }
    }

    class JSONCodingKey: CodingKey {
        let key: String

        required init?(intValue: Int) {
            return nil
        }

        required init?(stringValue: String) {
            key = stringValue
        }

        var intValue: Int? {
            return nil
        }

        var stringValue: String {
            return key
        }
    }

    class JSONAny: Codable {

        let value: Any

        static func decodingError(forCodingPath codingPath: [CodingKey]) -> DecodingError {
            let context = DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode JSONAny")
            return DecodingError.typeMismatch(JSONAny.self, context)
        }

        static func encodingError(forValue value: Any, codingPath: [CodingKey]) -> EncodingError {
            let context = EncodingError.Context(codingPath: codingPath, debugDescription: "Cannot encode JSONAny")
            return EncodingError.invalidValue(value, context)
        }

        static func decode(from container: SingleValueDecodingContainer) throws -> Any {
            if let value = try? container.decode(Bool.self) {
                return value
            }
            if let value = try? container.decode(Int64.self) {
                return value
            }
            if let value = try? container.decode(Double.self) {
                return value
            }
            if let value = try? container.decode(String.self) {
                return value
            }
            if container.decodeNil() {
                return JSONNull()
            }
            throw decodingError(forCodingPath: container.codingPath)
        }

        static func decode(from container: inout UnkeyedDecodingContainer) throws -> Any {
            if let value = try? container.decode(Bool.self) {
                return value
            }
            if let value = try? container.decode(Int64.self) {
                return value
            }
            if let value = try? container.decode(Double.self) {
                return value
            }
            if let value = try? container.decode(String.self) {
                return value
            }
            if let value = try? container.decodeNil() {
                if value {
                    return JSONNull()
                }
            }
            if var container = try? container.nestedUnkeyedContainer() {
                return try decodeArray(from: &container)
            }
            if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self) {
                return try decodeDictionary(from: &container)
            }
            throw decodingError(forCodingPath: container.codingPath)
        }

        static func decode(from container: inout KeyedDecodingContainer<JSONCodingKey>, forKey key: JSONCodingKey) throws -> Any {
            if let value = try? container.decode(Bool.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(Int64.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(Double.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(String.self, forKey: key) {
                return value
            }
            if let value = try? container.decodeNil(forKey: key) {
                if value {
                    return JSONNull()
                }
            }
            if var container = try? container.nestedUnkeyedContainer(forKey: key) {
                return try decodeArray(from: &container)
            }
            if var container = try? container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key) {
                return try decodeDictionary(from: &container)
            }
            throw decodingError(forCodingPath: container.codingPath)
        }

        static func decodeArray(from container: inout UnkeyedDecodingContainer) throws -> [Any] {
            var arr: [Any] = []
            while !container.isAtEnd {
                let value = try decode(from: &container)
                arr.append(value)
            }
            return arr
        }

        static func decodeDictionary(from container: inout KeyedDecodingContainer<JSONCodingKey>) throws -> [String: Any] {
            var dict = [String: Any]()
            for key in container.allKeys {
                let value = try decode(from: &container, forKey: key)
                dict[key.stringValue] = value
            }
            return dict
        }

        static func encode(to container: inout UnkeyedEncodingContainer, array: [Any]) throws {
            for value in array {
                if let value = value as? Bool {
                    try container.encode(value)
                } else if let value = value as? Int64 {
                    try container.encode(value)
                } else if let value = value as? Double {
                    try container.encode(value)
                } else if let value = value as? String {
                    try container.encode(value)
                } else if value is JSONNull {
                    try container.encodeNil()
                } else if let value = value as? [Any] {
                    var container = container.nestedUnkeyedContainer()
                    try encode(to: &container, array: value)
                } else if let value = value as? [String: Any] {
                    var container = container.nestedContainer(keyedBy: JSONCodingKey.self)
                    try encode(to: &container, dictionary: value)
                } else {
                    throw encodingError(forValue: value, codingPath: container.codingPath)
                }
            }
        }

        static func encode(to container: inout KeyedEncodingContainer<JSONCodingKey>, dictionary: [String: Any]) throws {
            for (key, value) in dictionary {
                let key = JSONCodingKey(stringValue: key)!
                if let value = value as? Bool {
                    try container.encode(value, forKey: key)
                } else if let value = value as? Int64 {
                    try container.encode(value, forKey: key)
                } else if let value = value as? Double {
                    try container.encode(value, forKey: key)
                } else if let value = value as? String {
                    try container.encode(value, forKey: key)
                } else if value is JSONNull {
                    try container.encodeNil(forKey: key)
                } else if let value = value as? [Any] {
                    var container = container.nestedUnkeyedContainer(forKey: key)
                    try encode(to: &container, array: value)
                } else if let value = value as? [String: Any] {
                    var container = container.nestedContainer(keyedBy: JSONCodingKey.self, forKey: key)
                    try encode(to: &container, dictionary: value)
                } else {
                    throw encodingError(forValue: value, codingPath: container.codingPath)
                }
            }
        }

        static func encode(to container: inout SingleValueEncodingContainer, value: Any) throws {
            if let value = value as? Bool {
                try container.encode(value)
            } else if let value = value as? Int64 {
                try container.encode(value)
            } else if let value = value as? Double {
                try container.encode(value)
            } else if let value = value as? String {
                try container.encode(value)
            } else if value is JSONNull {
                try container.encodeNil()
            } else {
                throw encodingError(forValue: value, codingPath: container.codingPath)
            }
        }

        public required init(from decoder: Decoder) throws {
            if var arrayContainer = try? decoder.unkeyedContainer() {
                self.value = try JSONAny.decodeArray(from: &arrayContainer)
            } else if var container = try? decoder.container(keyedBy: JSONCodingKey.self) {
                self.value = try JSONAny.decodeDictionary(from: &container)
            } else {
                let container = try decoder.singleValueContainer()
                self.value = try JSONAny.decode(from: container)
            }
        }

        public func encode(to encoder: Encoder) throws {
            if let arr = self.value as? [Any] {
                var container = encoder.unkeyedContainer()
                try JSONAny.encode(to: &container, array: arr)
            } else if let dict = self.value as? [String: Any] {
                var container = encoder.container(keyedBy: JSONCodingKey.self)
                try JSONAny.encode(to: &container, dictionary: dict)
            } else {
                var container = encoder.singleValueContainer()
                try JSONAny.encode(to: &container, value: self.value)
            }
        }
    }

    struct GameLoader {
        static func fetch(completion: @escaping (Result<GameInfo, Error>) -> Void) {
            let ScheduleURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/baseball/mlb/teams/7/schedule")!
            let task = URLSession.shared.dataTask(with: ScheduleURL) { (data, response, error) in
                print("Yay")
                guard error == nil else {
                    completion(.failure(error!))
                    return
                }
                let tempGame = getGameInfo(fromData: data!)
                //print(tempGame)
                completion(.success(tempGame))
            }
            task.resume()
        }
    
    static func getGameInfo(fromData data: Data) -> GameInfo {
        var tempGame = GameInfo(backgroundLogo: "royals", teamName: "IT", gameDate: "DID", gameTime: "NOT", gameChannel: "WORK", teamLogo: "", teamColor: Color(UIColor(red: 0/255, green: 70/255, blue: 135/255, alpha: 1.00)))
        let jsonDecoder = JSONDecoder()
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        formatter.locale = Locale.current
        jsonDecoder.dateDecodingStrategy = .formatted(formatter)
        do {
            let schedule = try jsonDecoder.decode(Schedule.self, from: data)
            var events = schedule.events
            events = events!.filter({Calendar.current.date(byAdding: .hour, value: -6, to: $0.date!)! >= Date()})
            events = events!.sorted(by: {$0.date!.compare($1.date!) == .orderedAscending })
            //events = events.sorted(by: { $0.date < $1.date })
            
            let gameDate = Calendar.current.date(byAdding: .hour, value: -6, to: (events?.first!.date!)!)!
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let time = timeFormatter.string(from: gameDate)
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "E MMM d, y"
            let date = dateFormatter.string(from: gameDate)
            
            if(events?.first?.competitions?.first?.competitors?.first?.team?.shortDisplayName == "Royals") {
                tempGame.teamName = (events?.first?.competitions?.first?.competitors?.last?.team?.shortDisplayName)!
                tempGame.teamLogo = (events?.first?.competitions?.first?.competitors?.last?.team?.logos?.first?.href)!
            } else {
                tempGame.teamName = (events?.first?.competitions?.first?.competitors?.first?.team?.shortDisplayName)!
                tempGame.teamLogo = (events?.first?.competitions?.first?.competitors?.first?.team?.logos?.first?.href)!
            }
            
            tempGame.gameDate = date
            tempGame.gameTime = time
            tempGame.gameChannel = events?.first!.competitions?.first?.broadcasts?.first?.media?.shortName ?? "TBD"
        } catch {
            print(error)
        }
        
        return tempGame
    }
    }
}
