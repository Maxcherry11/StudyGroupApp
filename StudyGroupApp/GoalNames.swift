import Foundation
import CloudKit

struct GoalNames: Codable {
    var id: CKRecord.ID = CKRecord.ID(recordName: "GoalNames")
    var quotes: String
    var salesWTD: String
    var salesMTD: String

    init(quotes: String = "Quotes WTD", salesWTD: String = "Sales WTD", salesMTD: String = "Sales MTD") {
        self.quotes = quotes
        self.salesWTD = salesWTD
        self.salesMTD = salesMTD
    }

    init?(record: CKRecord) {
        guard let quotes = record["quotesLabel"] as? String,
              let salesWTD = record["salesWTDLabel"] as? String,
              let salesMTD = record["salesMTDLabel"] as? String else {
            return nil
        }
        self.id = record.recordID
        self.quotes = quotes
        self.salesWTD = salesWTD
        self.salesMTD = salesMTD
    }

    func toRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: "GoalNames", recordID: id)
        record["quotesLabel"] = quotes as CKRecordValue
        record["salesWTDLabel"] = salesWTD as CKRecordValue
        record["salesMTDLabel"] = salesMTD as CKRecordValue
        return record
    }
}
