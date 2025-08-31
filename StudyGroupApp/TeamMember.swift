//
//  TeamMember.swift
//  Outcast
//
//  Created by D.J. Jones on 5/11/25.
//

import Foundation

class TeamMember: Identifiable, ObservableObject {
    var id: UUID
    @Published var name: String
    @Published var quotesToday: Int
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
        score: Int = 0
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
            score: score
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
            score: codable.score
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
            score: score
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
        return record
    }
}
