import CloudKit
import Foundation

struct Card: Identifiable, Hashable {
    var id: String
    var name: String
    var emoji: String
    var production: Int

    init(id: String = UUID().uuidString, name: String, emoji: String = "", production: Int = 0) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.production = production
    }

    init?(record: CKRecord) {
        guard let name = record["name"] as? String,
              let emoji = record["emoji"] as? String,
              let production = record["production"] as? Int else {
            return nil
        }
        self.id = record.recordID.recordName
        self.name = name
        self.emoji = emoji
        self.production = production
    }

    func toCKRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: "Card", recordID: CKRecord.ID(recordName: id))
        record["name"] = name as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        record["production"] = production as CKRecordValue
        return record
    }
}
