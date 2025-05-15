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
}

import CloudKit

extension TeamMember {
    static let recordType = "TeamMember"

    convenience init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let quotesToday = record["quotesToday"] as? Int,
            let salesWTD = record["salesWTD"] as? Int,
            let salesMTD = record["salesMTD"] as? Int,
            let quotesGoal = record["quotesGoal"] as? Int,
            let salesWTDGoal = record["salesWTDGoal"] as? Int,
            let salesMTDGoal = record["salesMTDGoal"] as? Int,
            let emoji = record["emoji"] as? String,
            let sortIndex = record["sortIndex"] as? Int
        else {
            return nil
        }

        self.init(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
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

    func toRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record["name"] = name as CKRecordValue
        record["quotesToday"] = quotesToday as CKRecordValue
        record["salesWTD"] = salesWTD as CKRecordValue
        record["salesMTD"] = salesMTD as CKRecordValue
        record["quotesGoal"] = quotesGoal as CKRecordValue
        record["salesWTDGoal"] = salesWTDGoal as CKRecordValue
        record["salesMTDGoal"] = salesMTDGoal as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        record["sortIndex"] = sortIndex as CKRecordValue
        return record
    }
}
