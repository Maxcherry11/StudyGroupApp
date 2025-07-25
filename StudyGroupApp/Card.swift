import CloudKit
import Foundation

/// Represents a single Win the Day card. The type conforms to `Codable`
/// so it can be persisted with `JSONEncoder`/`JSONDecoder`.
struct Card: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var emoji: String
    var production: Int
    /// Determines display order when loading from CloudKit
    var orderIndex: Int

    init(id: String = UUID().uuidString, name: String, emoji: String = "", production: Int = 0, orderIndex: Int = 0) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.production = production
        self.orderIndex = orderIndex
    }

    init?(record: CKRecord) {
        guard let name = record["name"] as? String,
              let emoji = record["emoji"] as? String,
              let production = record["production"] as? Int else {
            return nil
        }
        let orderIndex = record["orderIndex"] as? Int ?? 0
        self.id = record.recordID.recordName
        self.name = name
        self.emoji = emoji
        self.production = production
        self.orderIndex = orderIndex
    }

    func toCKRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: "Card", recordID: CKRecord.ID(recordName: id))
        record["name"] = name as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        record["production"] = production as CKRecordValue
        record["orderIndex"] = orderIndex as CKRecordValue
        return record
    }
}
