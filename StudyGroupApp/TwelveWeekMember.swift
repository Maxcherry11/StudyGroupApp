import Foundation
import CloudKit

/// A team member's progress for the 12 Week Year feature.
///
/// Stores the member name and their collection of `GoalProgress` entries.
/// Provides a computed `progress` value representing the average percent
/// complete for all associated goals.
struct TwelveWeekMember: Identifiable, Codable {
    /// Stable identifier for binding and list use.
    var id = UUID()

    /// Display name for the team member.
    var name: String

    /// Collection of progress objects for each goal.
    var goals: [GoalProgress]

    /// Average completion across all goals as a value between 0 and 1.
    var progress: Double {
        guard !goals.isEmpty else { return 0 }
        return goals.map { $0.percent }.reduce(0, +) / Double(goals.count)
    }

    /// CloudKit record type for TwelveWeekMember
    static let recordType = "TwelveWeekMember"

    init(name: String, goals: [GoalProgress]) {
        self.name = name
        self.goals = goals
    }

    /// Initialize from a CloudKit record.
    init?(record: CKRecord) {
        guard
            let name = record["name"] as? String,
            let goalsData = record["goals"] as? Data,
            let decodedGoals = try? JSONDecoder().decode([GoalProgress].self, from: goalsData)
        else {
            return nil
        }

        self.name = name
        self.goals = decodedGoals
    }

    /// CloudKit record representation of this model.
    var record: CKRecord { toRecord() }

    /// Returns a ``CKRecord`` for this instance, optionally updating an existing
    /// record.
    func toRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: "twy-\(name)")
        )
        record["name"] = name as CKRecordValue
        if let data = try? JSONEncoder().encode(goals) {
            record["goals"] = data as CKRecordValue
        }
        return record
    }
}

extension TwelveWeekMember: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        for goal in goals {
            hasher.combine(goal.title)
            hasher.combine(goal.percent)
        }
    }

    static func == (lhs: TwelveWeekMember, rhs: TwelveWeekMember) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.goals == rhs.goals
    }
}
