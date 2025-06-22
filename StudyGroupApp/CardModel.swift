import CloudKit
import Foundation

struct CardModel: Identifiable {
    var userName: String
    var emoji: String
    var goal1: Int
    var goal2: Int
    var goal3: Int
    var sortIndex: Int
    var id: String { userName }

    init(userName: String,
         emoji: String = "🙂",
         goal1: Int = 0,
         goal2: Int = 0,
         goal3: Int = 0,
         sortIndex: Int = 0) {
        self.userName = userName
        self.emoji = emoji
        self.goal1 = goal1
        self.goal2 = goal2
        self.goal3 = goal3
        self.sortIndex = sortIndex
    }

    func toRecord() -> CKRecord {
        let record = CKRecord(recordType: "CardModel", recordID: CKRecord.ID(recordName: "card-\(userName)"))
        record["userName"] = userName as CKRecordValue
        record["emoji"] = emoji as CKRecordValue
        record["goal1"] = goal1 as CKRecordValue
        record["goal2"] = goal2 as CKRecordValue
        record["goal3"] = goal3 as CKRecordValue
        record["sortIndex"] = sortIndex as CKRecordValue
        return record
    }
}
