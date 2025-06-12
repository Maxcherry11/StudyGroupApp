import Foundation
import CloudKit

struct GoalNames: Codable {
    /// CloudKit record identifier. This value isn't persisted locally so we
    /// don't attempt to encode/decode it with `Codable`.
    var id: CKRecord.ID = CKRecord.ID(recordName: "GoalNames")
    var quotes: String
    var salesWTD: String
    var salesMTD: String

    private enum CodingKeys: String, CodingKey {
        case quotes, salesWTD, salesMTD
    }

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

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quotes = try container.decode(String.self, forKey: .quotes)
        salesWTD = try container.decode(String.self, forKey: .salesWTD)
        salesMTD = try container.decode(String.self, forKey: .salesMTD)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(quotes, forKey: .quotes)
        try container.encode(salesWTD, forKey: .salesWTD)
        try container.encode(salesMTD, forKey: .salesMTD)
    }
}
