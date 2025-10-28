//
//  TeamMember.swift
//  Outcast
//
//  Created by D.J. Jones on 5/11/25.
//

import Combine
import Foundation

class TeamMember: Identifiable, ObservableObject {
    var id: UUID
    @Published var name: String
    // NOTE: This represents Quotes Week (WTD) in Win the Day, retained as 'quotesToday' for persistence compatibility.
    @Published var quotesToday: Int
    
    // MARK: - Backwards-compatible alias: Quotes Week (WTD)
    // The app's business logic and UI treat this as Quotes Week.
    // Keep storage key 'quotesToday' for CloudKit/UserDefaults compatibility.
    var quotesWTD: Int {
        get { quotesToday }
        set { quotesToday = newValue }
    }
    
    @Published var salesWTD: Int
    @Published var salesMTD: Int
    @Published var quotesGoal: Int
    @Published var salesWTDGoal: Int
    @Published var salesMTDGoal: Int
    @Published var emoji: String
    @Published var emojiUserSet: Bool
    @Published var sortIndex: Int
    @Published var pending: Int
    @Published var projected: Double
    @Published var actual: Int
    @Published var score: Int
    @Published var weekKey: String?
    @Published var monthKey: String?
    @Published var streakCountWeek: Int
    @Published var streakCountMonth: Int
    @Published var trophies: [String]
    @Published var totalWins: Int
    @Published var lastCompletedAt: Date?
    @Published var trophyStreakCount: Int
    @Published var trophyLastFinalizedWeekId: String?

    init(
        id: UUID = UUID(),
        name: String,
        quotesToday: Int,
        salesWTD: Int,
        salesMTD: Int,
        quotesGoal: Int,
        salesWTDGoal: Int,
        salesMTDGoal: Int,
        emoji: String,
        emojiUserSet: Bool = false,
        sortIndex: Int,
        pending: Int = 0,
        projected: Double = 0.0,
        actual: Int = 0,
        score: Int = 0,
        weekKey: String? = nil,
        monthKey: String? = nil,
        streakCountWeek: Int = 0,
        streakCountMonth: Int = 0,
        trophies: [String] = [],
        totalWins: Int = 0,
        lastCompletedAt: Date? = nil,
        trophyStreakCount: Int = 0,
        trophyLastFinalizedWeekId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.quotesToday = quotesToday
        self.salesWTD = salesWTD
        self.salesMTD = salesMTD
        self.quotesGoal = quotesGoal
        self.salesWTDGoal = salesWTDGoal
        self.salesMTDGoal = salesMTDGoal
        self.emoji = emoji
        self.emojiUserSet = emojiUserSet
        self.sortIndex = sortIndex
        self.pending = pending
        self.projected = projected
        self.actual = actual
        self.score = score
        self.weekKey = weekKey
        self.monthKey = monthKey
        self.streakCountWeek = streakCountWeek
        self.streakCountMonth = streakCountMonth
        self.trophies = trophies
        self.totalWins = totalWins
        self.lastCompletedAt = lastCompletedAt
        self.trophyStreakCount = trophyStreakCount
        self.trophyLastFinalizedWeekId = trophyLastFinalizedWeekId
    }

    convenience init(name: String) {
        self.init(
            name: name,
            quotesToday: 0,
            salesWTD: 0,
            salesMTD: 0,
            quotesGoal: 1,
            salesWTDGoal: 1,
            salesMTDGoal: 1,
            emoji: "🙂",
            emojiUserSet: false,
            sortIndex: 0,
            pending: 0,
            projected: 0.0,
            actual: 0,
            score: 0
        )
    }

    static let dj: TeamMember = TeamMember(
        name: "D.J.",
        quotesToday: 0,
        salesWTD: 0,
        salesMTD: 0,
        quotesGoal: 1,
        salesWTDGoal: 1,
        salesMTDGoal: 1,
        emoji: "🧠",
        emojiUserSet: false,
        sortIndex: 0,
        pending: 0,
        projected: 0.0,
        actual: 0,
        score: 0
    )
    static let ron: TeamMember = TeamMember(
        name: "Ron",
        quotesToday: 0,
        salesWTD: 0,
        salesMTD: 0,
        quotesGoal: 2,
        salesWTDGoal: 2,
        salesMTDGoal: 2,
        emoji: "🏌️",
        emojiUserSet: false,
        sortIndex: 1,
        pending: 0,
        projected: 0.0,
        actual: 0,
        score: 0
    )
}

extension TeamMember {
    struct CodableModel: Codable {
        var id: UUID
        var name: String
        var quotesToday: Int
        var salesWTD: Int
        var salesMTD: Int
        var quotesGoal: Int
        var salesWTDGoal: Int
        var salesMTDGoal: Int
        var emoji: String
        var emojiUserSet: Bool
        var sortIndex: Int
        var pending: Int
        var projected: Double
        var actual: Int
        var score: Int
        var weekKey: String?
        var monthKey: String?
        var streakCountWeek: Int = 0
        var streakCountMonth: Int = 0
        var trophies: [String] = []
        var totalWins: Int = 0
        var lastCompletedAt: Date?
        var trophyStreakCount: Int = 0
        var trophyLastFinalizedWeekId: String?
    }

    var codable: CodableModel {
        CodableModel(
            id: id,
            name: name,
            quotesToday: quotesToday,
            salesWTD: salesWTD,
            salesMTD: salesMTD,
            quotesGoal: quotesGoal,
            salesWTDGoal: salesWTDGoal,
            salesMTDGoal: salesMTDGoal,
            emoji: emoji,
            emojiUserSet: emojiUserSet,
            sortIndex: sortIndex,
            pending: pending,
            projected: projected,
            actual: actual,
            score: score,
            weekKey: weekKey,
            monthKey: monthKey,
            streakCountWeek: streakCountWeek,
            streakCountMonth: streakCountMonth,
            trophies: trophies,
            totalWins: totalWins,
            lastCompletedAt: lastCompletedAt,
            trophyStreakCount: trophyStreakCount,
            trophyLastFinalizedWeekId: trophyLastFinalizedWeekId
        )
    }

    convenience init(codable: CodableModel) {
        self.init(
            id: codable.id,
            name: codable.name,
            quotesToday: codable.quotesToday,
            salesWTD: codable.salesWTD,
            salesMTD: codable.salesMTD,
            quotesGoal: codable.quotesGoal,
            salesWTDGoal: codable.salesWTDGoal,
            salesMTDGoal: codable.salesMTDGoal,
            emoji: codable.emoji,
            emojiUserSet: codable.emojiUserSet,
            sortIndex: codable.sortIndex,
            pending: codable.pending,
            projected: codable.projected,
            actual: codable.actual,
            score: codable.score,
            weekKey: codable.weekKey,
            monthKey: codable.monthKey,
            streakCountWeek: codable.streakCountWeek,
            streakCountMonth: codable.streakCountMonth,
            trophies: codable.trophies,
            totalWins: codable.totalWins,
            lastCompletedAt: codable.lastCompletedAt,
            trophyStreakCount: codable.trophyStreakCount,
            trophyLastFinalizedWeekId: codable.trophyLastFinalizedWeekId
        )
    }
}

import CloudKit

extension TeamMember {
    static let recordType = "TeamMember"

    convenience init?(record: CKRecord) {
        guard let name = record["name"] as? String, !name.isEmpty else {
            return nil
        }

        let quotesToday = record["quotesToday"] as? Int ?? 0
        let salesWTD = record["salesWTD"] as? Int ?? 0
        let salesMTD = record["salesMTD"] as? Int ?? 0
        let quotesGoal = record["quotesGoal"] as? Int ?? 0
        let salesWTDGoal = record["salesWTDGoal"] as? Int ?? 0
        let salesMTDGoal = record["salesMTDGoal"] as? Int ?? 0
        let emoji = record["emoji"] as? String ?? "🙂"
        let emojiUserSet = record["emojiUserSet"] as? Bool ?? false

        let pending = record["pending"] as? Int ?? 0
        let projected = record["projected"] as? Double ?? 0.0
        let actual = record["actual"] as? Int ?? 0
        let score = record["score"] as? Int ?? 0
        let weekKey = record["weekKey"] as? String
        let monthKey = record["monthKey"] as? String
        let streakCountWeek = record["streakCountWeek"] as? Int ?? 0
        let streakCountMonth = record["streakCountMonth"] as? Int ?? 0
        let trophies = record["trophies"] as? [String] ?? []
        let totalWins = record["totalWins"] as? Int ?? 0
        let lastCompletedAt = record["lastCompletedAt"] as? Date
        let trophyStreakCount = record["trophyStreakCount"] as? Int ?? 0
        let trophyLastFinalizedWeekId = record["trophyLastFinalizedWeekId"] as? String

        self.init(
            id: UUID(),
            name: name,
            quotesToday: quotesToday,
            salesWTD: salesWTD,
            salesMTD: salesMTD,
            quotesGoal: quotesGoal,
            salesWTDGoal: salesWTDGoal,
            salesMTDGoal: salesMTDGoal,
            emoji: emoji,
            emojiUserSet: emojiUserSet,
            sortIndex: 0,
            pending: pending,
            projected: projected,
            actual: actual,
            score: score,
            weekKey: weekKey,
            monthKey: monthKey,
            streakCountWeek: streakCountWeek,
            streakCountMonth: streakCountMonth,
            trophies: trophies,
            totalWins: totalWins,
            lastCompletedAt: lastCompletedAt,
            trophyStreakCount: trophyStreakCount,
            trophyLastFinalizedWeekId: trophyLastFinalizedWeekId
        )
    }

    func toRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: "TeamMember",
            recordID: CKRecord.ID(recordName: "member-\(self.name)")
        )
        record["name"] = self.name
        record["emoji"] = self.emoji
        record["emojiUserSet"] = self.emojiUserSet as CKRecordValue
        record["pending"] = self.pending as CKRecordValue
        record["projected"] = self.projected as CKRecordValue
        record["actual"] = self.actual as CKRecordValue
        record["quotesGoal"] = self.quotesGoal as CKRecordValue
        record["quotesToday"] = self.quotesToday as CKRecordValue
        record["salesMTD"] = self.salesMTD as CKRecordValue
        record["salesMTDGoal"] = self.salesMTDGoal as CKRecordValue
        record["salesWTD"] = self.salesWTD as CKRecordValue
        record["salesWTDGoal"] = self.salesWTDGoal as CKRecordValue
        record["score"] = self.score as CKRecordValue
        record["sortIndex"] = self.sortIndex as CKRecordValue
        if let weekKey = self.weekKey {
            record["weekKey"] = weekKey as CKRecordValue
        } else {
            record["weekKey"] = nil
        }
        if let monthKey = self.monthKey {
            record["monthKey"] = monthKey as CKRecordValue
        } else {
            record["monthKey"] = nil
        }
        record["streakCountWeek"] = self.streakCountWeek as CKRecordValue
        record["streakCountMonth"] = self.streakCountMonth as CKRecordValue
        record["trophies"] = self.trophies as CKRecordValue
        record["totalWins"] = self.totalWins as CKRecordValue
        if let lastCompletedAt = self.lastCompletedAt {
            record["lastCompletedAt"] = lastCompletedAt as CKRecordValue
        } else {
            record["lastCompletedAt"] = nil
        }
        record["trophyStreakCount"] = self.trophyStreakCount as CKRecordValue
        if let trophyLastFinalizedWeekId = self.trophyLastFinalizedWeekId {
            record["trophyLastFinalizedWeekId"] = trophyLastFinalizedWeekId as CKRecordValue
        } else {
            record["trophyLastFinalizedWeekId"] = nil
        }
        return record
    }
}
