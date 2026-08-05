//
//  JayhawkWidgetScheduleLoader.swift
//  myTeams
//
//  Created by Stephen Rector on 12/1/20.
//  Copyright © 2020 Stephen Rector. All rights reserved.
//

import Foundation
import SwiftUI
import SwiftyJSON
import Alamofire

/*struct GameLoader {
    static func fetch(completion: @escaping (Result<GameInfo, Error>) -> Void) {
        let ScheduleURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/2305/schedule")!
        
        var returnGame = GameInfo(backgroundLogo: "jayhawk", teamName: " ", gameDate: " ", gameTime: " ", gameChannel: " ", teamLogo: "", teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
        var tempGame = GameInfo(backgroundLogo: "jayhawk", teamName: " ", gameDate: " ", gameTime: " ", gameChannel: " ", teamLogo: "", teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
        
        let task = URLSession.shared.dataTask(with: ScheduleURL) { (data, response, error) in
            print("Yay")
            guard error == nil else {
                completion(.failure(error!))
                return
            }
            
            let tempGame = downloadScheduleData(queryURL: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/2305/schedule", teamName: "Kansas")
            //print(tempGame)
            completion(.success(tempGame))
        }
        task.resume()
    }

    
    func downloadScheduleData(queryURL: String, teamName: String) -> GameInfo {
        var returnGame = GameInfo(backgroundLogo: "jayhawk", teamName: " ", gameDate: " ", gameTime: " ", gameChannel: " ", teamLogo: "", teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
        var tempGame = GameInfo(backgroundLogo: "jayhawk", teamName: " ", gameDate: " ", gameTime: " ", gameChannel: " ", teamLogo: "", teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
        
        OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
            switch response.result {
            case .success(let value):
                let json = JSON(value)
                
                
                for (_, subJson):(String, JSON) in json["events"] {
                    var gameOpponent = ""
                    var gameTime = ""
                    var gameDate = ""
                    var gameDateAsDate = Date()
                    var gameOpponentLogo = ""
                    var gameChannel = ""
                    
                    for (_, competitionsJson):(String, JSON) in subJson["competitions"] {
                        var date = subJson["date"].stringValue
                        date = date.replacingOccurrences(of: "T", with: " ")
                        date = date.replacingOccurrences(of: "Z", with: "")
                        
                        let dateFormatterGet = DateFormatter()
                        dateFormatterGet.dateFormat = "yyyy-MM-dd HH:mm"
                        
                        let dateFormatterPrint = DateFormatter()
                        let timeFormatterPrint = DateFormatter()
                        dateFormatterPrint.dateFormat = "MMM dd, yyyy"
                        timeFormatterPrint.dateFormat = "h:mm a"
                        
                        if var tempDate = dateFormatterGet.date(from: date) {
                            tempDate.addTimeInterval(TimeInterval(-6.0 * 3600.0))
                            gameDateAsDate = tempDate
                            gameDate = dateFormatterPrint.string(from: tempDate)
                            gameTime = timeFormatterPrint.string(from: tempDate)
                        } else {
                            print("There was an error decoding the string")
                        }
                        
                        gameChannel = competitionsJson["broadcasts",0,"media","shortName"].stringValue
                        
                        
                        if (gameChannel == "") {
                            gameChannel = "TBD"
                        }
                        
                        for (_, competitorsJson):(String, JSON) in competitionsJson["competitors"] {
                            
                            
                            if ((competitorsJson["team"]["nickname"]).stringValue == teamName) { //us
                                
                            } else { //Opponent
                                gameOpponent = competitorsJson["team"]["nickname"].stringValue
                                
                                for (_, logosJson):(String, JSON) in competitorsJson["team"]["logos"] {
                                    let link = logosJson["href"].stringValue
                                    
                                    if (!link.contains("dark")) {
                                        gameOpponentLogo = logosJson["href"].stringValue
                                    }
                                }
                            }
                        }
                    }
                    
                    let tempGame = GameInfo(backgroundLogo: "jayhawk", teamName: gameOpponent, gameDate: gameDate, gameTime: gameTime, gameChannel: gameChannel, teamLogo: gameOpponentLogo, teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
                    
                    if(gameDateAsDate > Date()) {
                        returnGame = tempGame
                    }
                }
            case .failure(let error):
                print(error)
                
            }
        }
        }
    }
}
 */

func downloadScheduleData(queryURL: String, teamName: String, completion: @escaping (GameInfo) -> Void) {
    var returnGame = GameInfo(backgroundLogo: "jayhawk", teamName: " ", gameDate: " ", gameTime: " ", gameChannel: " ", teamLogo: "", teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
    var tempGame = GameInfo(backgroundLogo: "jayhawk", teamName: " ", gameDate: " ", gameTime: " ", gameChannel: " ", teamLogo: "", teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
    
    OperationQueue().addOperation { AF.request(queryURL).responseJSON { response in
        switch response.result {
        case .success(let value):
            let json = JSON(value)
            
            
            for (_, subJson):(String, JSON) in json["events"] {
                var gameOpponent = ""
                var gameTime = ""
                var gameDate = ""
                var gameDateAsDate = Date()
                var gameOpponentLogo = ""
                var gameChannel = ""
                
                for (_, competitionsJson):(String, JSON) in subJson["competitions"] {
                    var date = subJson["date"].stringValue
                    date = date.replacingOccurrences(of: "T", with: " ")
                    date = date.replacingOccurrences(of: "Z", with: "")
                    
                    let dateFormatterGet = DateFormatter()
                    dateFormatterGet.dateFormat = "yyyy-MM-dd HH:mm"
                    
                    let dateFormatterPrint = DateFormatter()
                    let timeFormatterPrint = DateFormatter()
                    dateFormatterPrint.dateFormat = "MMM dd, yyyy"
                    timeFormatterPrint.dateFormat = "h:mm a"
                    
                    if var tempDate = dateFormatterGet.date(from: date) {
                        tempDate.addTimeInterval(TimeInterval(-6.0 * 3600.0))
                        gameDateAsDate = tempDate
                        gameDate = dateFormatterPrint.string(from: tempDate)
                        gameTime = timeFormatterPrint.string(from: tempDate)
                    } else {
                        print("There was an error decoding the string")
                    }
                    
                    gameChannel = competitionsJson["broadcasts",0,"media","shortName"].stringValue
                    
                    
                    if (gameChannel == "") {
                        gameChannel = "TBD"
                    }
                    
                    for (_, competitorsJson):(String, JSON) in competitionsJson["competitors"] {
                        
                        
                        if ((competitorsJson["team"]["nickname"]).stringValue == teamName) { //us
                            
                        } else { //Opponent
                            gameOpponent = competitorsJson["team"]["nickname"].stringValue
                            
                            for (_, logosJson):(String, JSON) in competitorsJson["team"]["logos"] {
                                let link = logosJson["href"].stringValue
                                
                                if (!link.contains("dark")) {
                                    gameOpponentLogo = logosJson["href"].stringValue
                                }
                            }
                        }
                    }
                }
                
                let tempGame = GameInfo(backgroundLogo: "jayhawk", teamName: gameOpponent, gameDate: gameDate, gameTime: gameTime, gameChannel: gameChannel, teamLogo: gameOpponentLogo, teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
                
                if(gameDateAsDate > Date()) {
                    returnGame = tempGame
                }
            }
        case .failure(let error):
            print(error)
            
        }
        OperationQueue.main.addOperation {
            completion(returnGame)
        }
    }
    }
}

class jayhawkSchedule {
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
        let notes: [Note]?
        let broadcasts: [Broadcast]?
        let status: Status?
        let tickets: [Ticket]?
    }

    // MARK: - Broadcast
    struct Broadcast: Codable {
        let type: BroadcastType?
        let market: Market?
        let media: Media?
        let lang: Lang?
        let region: Region?
    }

    enum Lang: String, Codable {
        case en = "en"
    }

    // MARK: - Market
    struct Market: Codable {
        let id: String?
        let type: MarketType?
    }

    enum MarketType: String, Codable {
        case national = "National"
    }

    // MARK: - Media
    struct Media: Codable {
        let shortName: String?
    }

    enum Region: String, Codable {
        case us = "us"
    }

    // MARK: - BroadcastType
    struct BroadcastType: Codable {
        let id: String?
        let shortName: ShortName?
    }

    enum ShortName: String, Codable {
        case radio = "Radio"
        case tv = "TV"
        case web = "Web"
    }

    // MARK: - Competitor
    struct Competitor: Codable {
        let id: String?
        let type: CompetitorType?
        let order: Int?
        let homeAway: HomeAway?
        let winner: Bool?
        let team: CompetitorTeam?
        let score: Score?
        let record: [Record]?
        let curatedRank: CuratedRank?
        let leaders: [CompetitorLeader]?
    }

    // MARK: - CuratedRank
    struct CuratedRank: Codable {
        let current: Int?
    }

    enum HomeAway: String, Codable {
        case away = "away"
        case home = "home"
    }

    // MARK: - CompetitorLeader
    struct CompetitorLeader: Codable {
        let name: LeaderName?
        let displayName: LeaderDisplayName?
        let abbreviation: LeaderAbbreviation?
        let leaders: [LeaderLeader]?
    }

    enum LeaderAbbreviation: String, Codable {
        case ast = "Ast"
        case pts = "Pts"
        case reb = "Reb"
    }

    enum LeaderDisplayName: String, Codable {
        case assists = "Assists"
        case points = "Points"
        case rebounds = "Rebounds"
    }

    // MARK: - LeaderLeader
    struct LeaderLeader: Codable {
        let displayValue: String?
        let value: Int?
        let athlete: Athlete?
    }

    // MARK: - Athlete
    struct Athlete: Codable {
        let id, lastName, displayName, shortName: String?
        let links: [AthleteLink]?
    }

    // MARK: - AthleteLink
    struct AthleteLink: Codable {
        let rel: [NoteType]?
        let href: String?
    }

    enum NoteType: String, Codable {
        case athlete = "athlete"
        case bio = "bio"
        case desktop = "desktop"
        case event = "event"
        case gamelog = "gamelog"
        case news = "news"
        case overview = "overview"
        case playercard = "playercard"
        case splits = "splits"
        case stats = "stats"
        case tickets = "tickets"
        case venue = "venue"
    }

    enum LeaderName: String, Codable {
        case assists = "assists"
        case points = "points"
        case rebounds = "rebounds"
    }

    // MARK: - Record
    struct Record: Codable {
        let id: String?
        let abbreviation: RecordAbbreviation?
        let displayName: RecordDisplayName?
        let shortDisplayName: ShortDisplayName?
        let recordDescription: RecordDescription?
        let type: RecordType?
        let displayValue: String?

        enum CodingKeys: String, CodingKey {
            case id, abbreviation, displayName, shortDisplayName
            case recordDescription = "description"
            case type, displayValue
        }
    }

    enum RecordAbbreviation: String, Codable {
        case game = "Game"
        case season = "Season"
        case vsConf = "VS CONF"
    }

    enum RecordDisplayName: String, Codable {
        case conf = "CONF"
        case recordYearToDate = "Record Year To Date"
        case teamSeasonRecord = "Team Season Record"
    }

    enum RecordDescription: String, Codable {
        case conferenceRecord = "Conference Record"
        case overallRecord = "Overall Record"
    }

    enum ShortDisplayName: String, Codable {
        case conf = "CONF"
        case season = "Season"
        case ytd = "YTD"
    }

    enum RecordType: String, Codable {
        case total = "total"
        case vsconf = "vsconf"
    }

    // MARK: - Score
    struct Score: Codable {
        let value: Int?
        let displayValue: String?
    }

    // MARK: - CompetitorTeam
    struct CompetitorTeam: Codable {
        let id, location, nickname, abbreviation: String?
        let displayName, shortDisplayName: String?
        let logos: [Logo]?
        let links: [TeamLink]?
    }

    // MARK: - TeamLink
    struct TeamLink: Codable {
        let rel: [CompetitorType]?
        let href: String?
        let text: PurpleText?
    }

    enum CompetitorType: String, Codable {
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
    }

    // MARK: - Note
    struct Note: Codable {
        let type: NoteType?
        let headline: String?
    }

    // MARK: - Status
    struct Status: Codable {
        let clock: Int?
        let displayClock: DisplayClock?
        let period: Int?
        let type: StatusType?
    }

    enum DisplayClock: String, Codable {
        case the000 = "0:00"
    }

    // MARK: - StatusType
    struct StatusType: Codable {
        let id: String?
        let name: TypeName?
        let state: State?
        let completed: Bool?
        let typeDescription: TypeDescription?
        let detail: String?
        let shortDetail: ShortDetail?

        enum CodingKeys: String, CodingKey {
            case id, name, state, completed
            case typeDescription = "description"
            case detail, shortDetail
        }
    }

    enum TypeName: String, Codable {
        case statusCanceled = "STATUS_CANCELED"
        case statusFinal = "STATUS_FINAL"
        case statusScheduled = "STATUS_SCHEDULED"
    }

    enum ShortDetail: String, Codable {
        case canceled = "Canceled"
        case shortDetailFinal = "Final"
        case tbd = "TBD"
        case the1217700PmEst = "12/17 - 7:00 PM EST"
        case the1222900PmEst = "12/22 - 9:00 PM EST"
    }

    enum State: String, Codable {
        case post = "post"
        case pre = "pre"
    }

    enum TypeDescription: String, Codable {
        case canceled = "Canceled"
        case descriptionFinal = "Final"
        case scheduled = "Scheduled"
    }

    // MARK: - Ticket
    struct Ticket: Codable {
        let id, summary, ticketDescription: String?
        let maxPrice, startingPrice, numberAvailable, totalPostings: Int?
        let links: [AthleteLink]?

        enum CodingKeys: String, CodingKey {
            case id, summary
            case ticketDescription = "description"
            case maxPrice, startingPrice, numberAvailable, totalPostings, links
        }
    }

    // MARK: - CompetitionType
    struct CompetitionType: Codable {
        let id: String?
        let text: TypeText?
        let abbreviation: TypeAbbreviation?
    }

    enum TypeAbbreviation: String, Codable {
        case nA = "N/A"
    }

    enum TypeText: String, Codable {
        case undefined = "Undefined"
    }

    // MARK: - Venue
    struct Venue: Codable {
        let fullName: String?
        let address: Address?
    }

    // MARK: - Address
    struct Address: Codable {
        let city, state: String?
    }

    // MARK: - EventLink
    struct EventLink: Codable {
        let language: Language?
        let rel: [LinkRel]?
        let href: String?
        let text, shortText: ShortTextEnum?
        let isExternal, isPremium: Bool?
    }

    enum Language: String, Codable {
        case enUS = "en-US"
    }

    enum LinkRel: String, Codable {
        case app = "app"
        case boxscore = "boxscore"
        case desktop = "desktop"
        case event = "event"
        case gamecast = "gamecast"
        case mobile = "mobile"
        case pbp = "pbp"
        case recap = "recap"
        case sportscenter = "sportscenter"
        case summary = "summary"
        case teamstats = "teamstats"
        case videos = "videos"
        case watchespn = "watchespn"
    }

    enum ShortTextEnum: String, Codable {
        case boxScore = "Box Score"
        case gamecast = "Gamecast"
        case playByPlay = "Play-by-Play"
        case recap = "Recap"
        case summary = "Summary"
        case teamStats = "Team Stats"
        case videos = "Videos"
        case watchESPN = "WatchESPN"
    }

    // MARK: - EventSeason
    struct EventSeason: Codable {
        let year: Int?
        let displayName: DisplayName?
    }

    enum DisplayName: String, Codable {
        case the202021 = "2020-21"
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
        let name: SeasonTypeName?
        let displayName: DisplayName?
        let half: Int?
    }

    // MARK: - ScheduleTeam
    struct ScheduleTeam: Codable {
        let id, abbreviation, location, name: String?
        let displayName: String?
        let clubhouse: String?
        let color: String?
        let logo: String?
        let recordSummary: String?
        let seasonSummary: DisplayName?
        let standingSummary: String?
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


    
    

    struct GameLoader {
        static func fetch(completion: @escaping (Result<GameInfo, Error>) -> Void) {
            let ScheduleURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/basketball/mens-college-basketball/teams/2305/schedule")!
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
            var tempGame = GameInfo(backgroundLogo: "jayhawk", teamName: " ", gameDate: " ", gameTime: " ", gameChannel: " ", teamLogo: "", teamColor: Color(UIColor(red: 0/255, green: 81/255, blue: 186/255, alpha: 1.00)))
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
                
                let gameDate = Calendar.current.date(byAdding: .hour, value: -6, to: (events?.first!.date!)!)!
                
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"
                let time = timeFormatter.string(from: gameDate)
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "E MMM d, y"
                let date = dateFormatter.string(from: gameDate)
                
                if(events?.first?.competitions?.first?.competitors?.first?.team?.nickname == "Kansas") {
                    tempGame.teamName = (events?.first?.competitions?.first?.competitors?.last?.team?.nickname) ?? " "
                    tempGame.teamLogo = (events?.first?.competitions?.first?.competitors?.last?.team?.logos?.first?.href) ?? " "
                } else {
                    tempGame.teamName = (events?.first?.competitions?.first?.competitors?.first?.team?.nickname) ?? " "
                    tempGame.teamLogo = (events?.first?.competitions?.first?.competitors?.first?.team?.logos?.first?.href) ?? " "
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


