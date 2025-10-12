import Foundation
import CloudKit

/// Centralized manager that keeps weekly/monthly streaks, trophies,
/// and period resets in CloudKit so every device reads the same state.
final class CloudStreakManager {
    static let shared = CloudStreakManager()

    private let database: CKDatabase
    private let calendar: Calendar
    private let timeZone: TimeZone
    private let maxRetryCount = 6

    enum Period {
        case weekly
        case monthly
    }

    private init() {
        database = CloudKitManager.container.publicCloudDatabase
        timeZone = TimeZone(identifier: "America/Chicago") ?? .current
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2 // Monday
        self.calendar = calendar
    }

    // MARK: - Public API

    /// Ensures the member's CloudKit record is aligned with the current week/month.
    /// Resets streak counters and production numbers when the stored keys drift.
    func appBecameActive(for memberName: String, completion: @escaping (Result<CKRecord, Error>) -> Void) {
        let recordID = recordID(for: memberName)
        modifyRecord(with: recordID, mutate: { [weak self] record in
            guard let self else { return false }
            return self.applyResetsIfNeeded(on: record, now: Date())
        }, completion: completion)
    }

    /// Registers a completed goal. Ensures any pending resets occur before
    /// incrementing streak counters and awarding trophies.
    func markWin(for memberName: String, completion: @escaping (Result<CKRecord, Error>) -> Void) {
        let recordID = recordID(for: memberName)
        modifyRecord(with: recordID, mutate: { [weak self] record in
            guard let self else { return false }
            let now = Date()
            var didChange = applyResetsIfNeeded(on: record, now: now)

            let weekly = (record["streakCountWeek"] as? Int ?? 0) + 1
            let monthly = (record["streakCountMonth"] as? Int ?? 0) + 1
            record["streakCountWeek"] = weekly as CKRecordValue
            record["streakCountMonth"] = monthly as CKRecordValue
            record["totalWins"] = ((record["totalWins"] as? Int) ?? 0 + 1) as CKRecordValue
            record["lastCompletedAt"] = now as CKRecordValue

            record["trophies"] = updatedTrophies(
                existing: record["trophies"] as? [String] ?? [],
                weekly: weekly,
                monthly: monthly
            ) as CKRecordValue

            didChange = true
            return didChange
        }, completion: completion)
    }

    /// Forces a manual reset for a specific period. Useful for admin tools.
    func resetPeriodIfNeeded(for memberName: String, period: Period, completion: @escaping (Result<CKRecord, Error>) -> Void) {
        let recordID = recordID(for: memberName)
        modifyRecord(with: recordID, mutate: { [weak self] record in
            guard let self else { return false }
            switch period {
            case .weekly:
                return applyWeeklyReset(on: record, now: Date())
            case .monthly:
                return applyMonthlyReset(on: record, now: Date())
            }
        }, completion: completion)
    }

    // MARK: - Record Helpers

    private func recordID(for memberName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "member-\(memberName)")
    }

    private func modifyRecord(with recordID: CKRecord.ID,
                              attempts: Int = 0,
                              mutate: @escaping (CKRecord) -> Bool,
                              completion: @escaping (Result<CKRecord, Error>) -> Void) {
        database.fetch(withRecordID: recordID) { [weak self] record, error in
            guard let self else { return }
            if let record {
                let didMutate = mutate(record)
                guard didMutate else {
                    completion(.success(record))
                    return
                }
                self.save(record,
                          recordID: recordID,
                          attempts: attempts,
                          mutate: mutate,
                          completion: completion)
                return
            }

            if let error {
                completion(.failure(error))
            } else {
                completion(.failure(NSError(domain: "CloudStreakManager",
                                            code: -1,
                                            userInfo: [NSLocalizedDescriptionKey: "Missing record for \(recordID.recordName)"])))
            }
        }
    }

    private func save(_ record: CKRecord,
                      recordID: CKRecord.ID,
                      attempts: Int,
                      mutate: @escaping (CKRecord) -> Bool,
                      completion: @escaping (Result<CKRecord, Error>) -> Void) {
        let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        operation.savePolicy = .ifServerRecordUnchanged
        operation.modifyRecordsResultBlock = { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                completion(.success(record))
            case .failure(let error):
                if let ckError = error as? CKError, ckError.code == .serverRecordChanged, attempts < maxRetryCount {
                    let backoff = pow(2.0, Double(attempts)) * 0.1
                    DispatchQueue.global().asyncAfter(deadline: .now() + backoff) {
                        self.modifyRecord(with: recordID,
                                          attempts: attempts + 1,
                                          mutate: mutate,
                                          completion: completion)
                    }
                } else {
                    completion(.failure(error))
                }
            }
        }
        database.add(operation)
    }

    // MARK: - Reset Logic

    private func applyResetsIfNeeded(on record: CKRecord, now: Date) -> Bool {
        let weekly = applyWeeklyReset(on: record, now: now)
        let monthly = applyMonthlyReset(on: record, now: now)
        return weekly || monthly
    }

    private func applyWeeklyReset(on record: CKRecord, now: Date) -> Bool {
        let currentKey = currentWeekKey(for: now)
        let storedKey = record["weekKey"] as? String
        guard storedKey != currentKey else { return false }
        record["weekKey"] = currentKey as CKRecordValue
        record["streakCountWeek"] = 0 as CKRecordValue
        record["quotesToday"] = 0 as CKRecordValue
        record["salesWTD"] = 0 as CKRecordValue
        return true
    }

    private func applyMonthlyReset(on record: CKRecord, now: Date) -> Bool {
        let currentKey = currentMonthKey(for: now)
        let storedKey = record["monthKey"] as? String
        guard storedKey != currentKey else { return false }
        record["monthKey"] = currentKey as CKRecordValue
        record["streakCountMonth"] = 0 as CKRecordValue
        record["salesMTD"] = 0 as CKRecordValue
        return true
    }

    private func currentWeekKey(for date: Date) -> String {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? calendar.component(.year, from: date)
        let week = components.weekOfYear ?? 1
        return String(format: "%04d-W%02d", year, week)
    }

    private func currentMonthKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? calendar.component(.year, from: date)
        let month = components.month ?? 1
        return String(format: "%04d-M%02d", year, month)
    }

    // MARK: - Trophy Helpers

    private func updatedTrophies(existing: [String], weekly: Int, monthly: Int) -> [String] {
        var set = Set(existing)
        trophies(for: weekly, prefix: "w").forEach { set.insert($0) }
        trophies(for: monthly, prefix: "m").forEach { set.insert($0) }
        return Array(set).sorted()
    }

    private func trophies(for streak: Int, prefix: String) -> [String] {
        switch streak {
        case 1: return ["\(prefix)_first"]
        case 3: return ["\(prefix)_3"]
        case 7: return ["\(prefix)_7"]
        case 14: return ["\(prefix)_14"]
        case 30: return ["\(prefix)_30"]
        default: return []
        }
    }
}
