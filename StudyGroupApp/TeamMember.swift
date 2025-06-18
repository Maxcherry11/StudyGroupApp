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
    @Published var sortIndex: Int

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
        sortIndex: Int
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
        self.sortIndex = sortIndex
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
            sortIndex: 0
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
        sortIndex: 0
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
        sortIndex: 1
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
        var sortIndex: Int
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
            sortIndex: sortIndex
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
            sortIndex: codable.sortIndex
        )
    }
}

import CloudKit

extension TeamMember {
    static let recordType = "TeamMember"

    convenience init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            !name.isEmpty,
            let quotesToday = record["quotesToday"] as? Int,
            let salesWTD = record["salesWTD"] as? Int,
            let salesMTD = record["salesMTD"] as? Int,
            let quotesGoal = record["quotesGoal"] as? Int,
            let salesWTDGoal = record["salesWTDGoal"] as? Int,
            let salesMTDGoal = record["salesMTDGoal"] as? Int,
            let emoji = record["emoji"] as? String
        else {
            return nil
        }

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
            sortIndex: 0
        )
    }

    func toRecord(existing: CKRecord? = nil) -> CKRecord {
        guard !name.isEmpty else {
            fatalError("❌ Cannot save TeamMember without a name.")
        }

        let record = existing ?? CKRecord(recordType: "TeamMember", recordID: CKRecord.ID(recordName: name))

        record["name"] = name as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        record["quotesGoal"] = quotesGoal as CKRecordValue
        record["quotesToday"] = quotesToday as CKRecordValue
        record["salesMTD"] = salesMTD as CKRecordValue
        record["salesMTDGoal"] = salesMTDGoal as CKRecordValue
        record["salesWTD"] = salesWTD as CKRecordValue
        record["salesWTDGoal"] = salesWTDGoal as CKRecordValue
        record["sortIndex"] = sortIndex as CKRecordValue

        return record
    }
}
