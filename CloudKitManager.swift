import CloudKit
import Foundation

class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    /// The primary iCloud container for all app data.
    static let container: CKContainer = {
        let container = CKContainer(identifier: "iCloud.com.dj.Outcast")
        print("☁️ CloudKit container:", container.containerIdentifier ?? "nil")
        print("☁️ CloudKit database: public")
        return container
    }()
    private let database = CloudKitManager.container.publicCloudDatabase
    private let recordType = "TeamMember"
    private let cardRecordType = "Card"
    private let cardOrderRecordType = "CardOrder"
    private let goalNameRecordType = "GoalNames"
    private static let userRecordType = "TeamMember"
    private static let teamMemberSubscriptionID = "team-member-changes"
#if DEBUG
    private static let enableFetchCardsDiagnostics = true
#else
    private static let enableFetchCardsDiagnostics = false
#endif
    private static var didRunFetchCardsDiagnostics = false
    private static let fetchCardsDiagnosticsLock = DispatchQueue(label: "CloudKitManager.fetchCardsDiagnostics")

    // MARK: - Migration
    private static let migrationKey = "TeamMemberFieldMigrationVersion"
    private static let migrationVersion = 1

    // MARK: - Subscriptions
    func ensureTeamMemberSubscription() {
        let subscriptionID = Self.teamMemberSubscriptionID
        database.fetch(withSubscriptionID: subscriptionID) { subscription, error in
            if let subscription = subscription {
                print("✅ CloudKit subscription ready: \(subscription.subscriptionID)")
                return
            }
            if let error = error as? CKError, error.code != .unknownItem {
                print("❌ CloudKit subscription fetch failed: \(error.localizedDescription)")
                return
            }

            let predicate = NSPredicate(value: true)
            let subscription = CKQuerySubscription(
                recordType: self.recordType,
                predicate: predicate,
                subscriptionID: subscriptionID,
                options: [.firesOnRecordUpdate, .firesOnRecordCreation, .firesOnRecordDeletion]
            )
            let info = CKSubscription.NotificationInfo()
            info.shouldSendContentAvailable = true
            subscription.notificationInfo = info

            self.database.save(subscription) { _, error in
                if let error = error {
                    print("❌ CloudKit subscription save failed: \(error.localizedDescription)")
                } else {
                    print("✅ CloudKit subscription installed: \(subscriptionID)")
                }
            }
        }
    }

    func handleRemoteNotification(_ userInfo: [AnyHashable: Any], completion: @escaping (Bool) -> Void) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completion(false)
            return
        }
        guard notification.subscriptionID == Self.teamMemberSubscriptionID else {
            completion(false)
            return
        }
        print("📬 [CK PUSH] TeamMember change notification received")
        refreshTeamMembersFromPush(completion: completion)
    }

    private func refreshTeamMembersFromPush(completion: @escaping (Bool) -> Void) {
        guard !isFetchingTeam else {
            print("⚠️ [CK PUSH] fetchTeam already in progress; deferring notification")
            pendingTeamMemberPushNotification = true
            completion(false)
            return
        }
        print("🔄 [CK PUSH] Triggering TeamMember refetch")
        fetchTeam { _ in
            NotificationCenter.default.post(name: .cloudKitTeamMemberDidChange, object: nil)
            completion(true)
        }
    }

    /// Cached members fetched from CloudKit. Updates to this array reflect
    /// immediately in any views observing the manager.
    @Published var teamMembers: [TeamMember] = []
    private var isFetchingTeam = false
    private var pendingTeamMemberPushNotification = false
    private var isFetchingAllUserNames = false
    private var deletingNames: Set<String> = []
    private let deletingNamesLock = DispatchQueue(label: "CloudKitManager.deletingNames")

    // MARK: - Record ID Helpers
    private func memberID(for name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "member-\(name)")
    }

    private func teamMemberRecordID(for name: String) -> CKRecord.ID {
        memberID(for: name)
    }

    private func twyRecordID(for name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "twy-\(name)")
    }

    private func cardID(for name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "card-\(name)")
    }

    private func isValid(_ member: TeamMember) -> Bool {
        !member.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Migration: ensures all TeamMember records contain `actual`, `pending`,
    /// and `projected` fields. Missing values are set to `0`.
    func migrateTeamMemberFieldsIfNeeded() {
        let defaults = UserDefaults.standard
        let stored = defaults.integer(forKey: Self.migrationKey)
        guard stored < Self.migrationVersion else { return }

        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        var updated: [CKRecord] = []
        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                var needsUpdate = false
                if record["actual"] == nil {
                    record["actual"] = 0 as CKRecordValue
                    needsUpdate = true
                }
                if record["pending"] == nil {
                    record["pending"] = 0 as CKRecordValue
                    needsUpdate = true
                }
                if record["projected"] == nil {
                    record["projected"] = 0.0 as CKRecordValue
                    needsUpdate = true
                }
                if needsUpdate { updated.append(record) }
            case .failure(let error):
                print("❌ Migration record match failed: \(error.localizedDescription)")
            }
        }
        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                guard case .success = result else {
                    if case .failure(let error) = result {
                        print("❌ Migration query failed: \(error.localizedDescription)")
                    }
                    return
                }
                guard !updated.isEmpty else {
                    defaults.set(Self.migrationVersion, forKey: Self.migrationKey)
                    print("🛠️ Migration complete: no records needed updates")
                    return
                }
                let modify = CKModifyRecordsOperation(recordsToSave: updated, recordIDsToDelete: nil)
                modify.modifyRecordsResultBlock = { modifyResult in
                    DispatchQueue.main.async {
                        switch modifyResult {
                        case .success:
                            print("✅ Migration updated \(updated.count) TeamMember records")
                            defaults.set(Self.migrationVersion, forKey: Self.migrationKey)
                        case .failure(let error):
                            print("❌ Migration modify failed: \(error.localizedDescription)")
                        }
                    }
                }
                self.database.add(modify)
            }
        }
        database.add(operation)
    }

    func fetchTeam(completion: @escaping ([TeamMember]) -> Void) {
        if isFetchingTeam {
            print("⚠️ fetchTeam() already in progress; skipping duplicate request")
            return
        }
        isFetchingTeam = true
        print("\u{1F50D} Starting fetchTeam()")
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "TeamMember", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        var fetchedMembers: [TeamMember] = []

        let operation = CKQueryOperation(query: query)
        operation.desiredKeys = [
            "name",
            "quotesToday",
            "salesWTD",
            "salesMTD",
            "quotesGoal",
            "salesWTDGoal",
            "salesMTDGoal",
            "emoji",
            "emojiUserSet",
            "sortIndex",
            "actual",
            "pending",
            "projected",
            "weekKey",
            "monthKey",
            "streakCountWeek",
            "streakCountMonth",
            "trophies",
            "totalWins",
            "lastCompletedAt",
            "trophyStreakCount",
            "trophyLastFinalizedWeekId",
            "wonThisWeek",
            "wonThisWeekSetAt"
        ]
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let member = TeamMember(record: record) {
                    fetchedMembers.append(member)
                }
                print("✅ fetchTeam() matched record: \(recordID.recordName)")
            case .failure(let error):
                print("❌ fetchTeam() record match failed: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                defer { self.isFetchingTeam = false }
                switch result {
                case .success:
                    let valid = fetchedMembers.filter {
                        !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                    }
                    let names = valid.map { $0.name }.sorted()
                    let preview = names.prefix(8).joined(separator: ", ")
                    let suffix = names.count > 8 ? ", ..." : ""
                    print("📥 fetchTeam completion snapshotCount=\(valid.count) snapshotNames=[\(preview)\(suffix)]")
                    self.teamMembers = valid
                    if self.pendingTeamMemberPushNotification {
                        self.pendingTeamMemberPushNotification = false
                        NotificationCenter.default.post(name: .cloudKitTeamMemberDidChange, object: nil)
                    }
                    print("✅ fetchTeam(): loaded \(valid.count) TeamMember records")
                    completion(valid)
                case .failure(let error):
                    print("❌ fetchTeam() query failed: \(error.localizedDescription)")
                    completion([])
                }
            }
        }

        database.add(operation)
    }

    /// Convenience wrapper to fetch all team members and update ``teamMembers``.
    /// - Parameter completion: Called with the retrieved members.
    func fetchAllTeamMembers(completion: @escaping ([TeamMember]) -> Void = { _ in }) {
        fetchTeam(completion: completion)
    }

    /// Creates a new ``TeamMember`` record in CloudKit and updates ``teamMembers``.
    /// The new member's production goals are initialized to match the existing
    /// team, if any members are already present.
    func addTeamMember(name: String, emoji: String = "🙂", completion: @escaping (Bool) -> Void = { _ in }) {
        logCloudKitIdentityAndScope(
            context: "addTeamMember()",
            container: CloudKitManager.container,
            dbScope: .public
        )
        let createAndSave: (TeamMember?) -> Void = { template in
            let member = TeamMember(name: name)

            if let template = template {
                member.quotesGoal = template.quotesGoal
                member.salesWTDGoal = template.salesWTDGoal
                member.salesMTDGoal = template.salesMTDGoal
            }

            member.emoji = emoji
            self.save(member) { id in
                DispatchQueue.main.async {
                    if id != nil {
                        self.teamMembers.append(member)
                        completion(true)
                    } else {
                        completion(false)
                    }
                }
            }
        }

        if teamMembers.isEmpty {
            fetchTeam { fetched in
                let template = fetched.first { member in
                    member.quotesGoal != 0 || member.salesWTDGoal != 0 || member.salesMTDGoal != 0
                }
                createAndSave(template)
            }
        } else {
            let template = teamMembers.first { member in
                member.quotesGoal != 0 || member.salesWTDGoal != 0 || member.salesMTDGoal != 0
            }
            createAndSave(template)
        }
    }

    /// Deletes the provided ``TeamMember`` from CloudKit and local cache.
    func deleteTeamMember(_ member: TeamMember, completion: @escaping (Bool) -> Void = { _ in }) {
        delete(member)
        DispatchQueue.main.async {
            self.teamMembers.removeAll { $0.id == member.id }
            completion(true)
        }
    }

    func save(_ member: TeamMember,
              allowZeroWeeklyFields: Bool = false,
              allowZeroMonthlyFields: Bool = false,
              completion: @escaping (CKRecord.ID?) -> Void) {
        guard isValid(member) else {
            print("⚠️ Skipping save for invalid member: \(member.name)")
            completion(nil)
            return
        }
        let predicate = NSPredicate(format: "name == %@", member.name)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        let operation = CKQueryOperation(query: query)
        operation.desiredKeys = nil
        operation.resultsLimit = 1

        var matchedRecord: CKRecord?

        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                matchedRecord = record
            case .failure(let error):
                print("❌ Failed to match existing record: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                let modifyOperation = self.prepareModifyOperation(for: member,
                                                                 existingRecord: matchedRecord,
                                                                 allowZeroWeeklyFields: allowZeroWeeklyFields,
                                                                 allowZeroMonthlyFields: allowZeroMonthlyFields,
                                                                 completion: completion)
                self.database.add(modifyOperation)
            }
        }

        database.add(operation)
    }

    private func prepareModifyOperation(for member: TeamMember,
                                        existingRecord: CKRecord?,
                                        allowZeroWeeklyFields: Bool,
                                        allowZeroMonthlyFields: Bool,
                                        completion: @escaping (CKRecord.ID?) -> Void) -> CKModifyRecordsOperation {
        let record = member.toRecord(existing: existingRecord,
                                     allowZeroWeeklyFields: allowZeroWeeklyFields,
                                     allowZeroMonthlyFields: allowZeroMonthlyFields)
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        modifyOperation.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    print("❌ Error saving: \(error.localizedDescription)")
                    logCKError(error, context: "save(member)")
                    completion(nil)
                case .success:
                    print("✅ Successfully saved member: \(member.name)")
                    completion(record.recordID)
                }
            }
        }

        return modifyOperation
    }

    func delete(_ member: TeamMember) {
        deleteUserEverywhere(name: member.name) { _ in }
    }

    func fetchAll(completion: @escaping ([TeamMember]) -> Void) {
        print("\u{1F50D} Starting fetchAll()")
        fetchTeam { members in
            print("✅ fetchAll(): retrieved \(members.count) members")
            completion(members)
        }
    }

    func fetchFiltered(byUserName name: String, completion: @escaping ([TeamMember]) -> Void) {
        print("\u{1F50D} Starting fetchFiltered() for user: \(name)")
        let predicate = NSPredicate(format: "name == %@", name)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        var results: [TeamMember] = []

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                if let member = TeamMember(record: record) {
                    results.append(member)
                }
                print("✅ fetchFiltered() matched record: \(recordID.recordName)")
            case .failure(let error):
                print("❌ fetchFiltered() record match failed: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                let valid = results.filter { self.isValid($0) }
                switch result {
                case .success:
                    print("✅ fetchFiltered(): loaded \(valid.count) TeamMember records")
                case .failure(let error):
                    print("❌ fetchFiltered() query failed: \(error.localizedDescription)")
                }
                completion(valid)
            }
        }

        database.add(operation)
    }

    func deleteAll(completion: @escaping (Bool) -> Void) {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        var recordIDsToDelete: [CKRecord.ID] = []

        let operation = CKQueryOperation(query: query)
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success:
                recordIDsToDelete.append(recordID)
            case .failure(let error):
                print("❌ Error matching record for deletion: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            if recordIDsToDelete.isEmpty {
                DispatchQueue.main.async {
                    print("🧹 No records to delete.")
                    completion(true)
                }
                return
            }

            let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDsToDelete)
            deleteOperation.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    switch result {
                    case .failure(let error):
                        print("❌ Error deleting records: \(error.localizedDescription)")
                        completion(false)
                    case .success:
                        print("🗑️ Deleted \(recordIDsToDelete.count) records from CloudKit.")
                        completion(true)
                    }
                }
            }
            self.database.add(deleteOperation)
        }

        database.add(operation)
    }
    
    func deleteByName(_ name: String, completion: @escaping (Bool) -> Void) {
        deleteUserEverywhere(name: name, completion: completion)
    }

    func deleteUserEverywhere(name: String, completion: @escaping (Bool) -> Void = { _ in }) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("⚠️ deleteUserEverywhere() called with empty name; skipping")
            completion(false)
            return
        }
        let deleteKey = trimmed.lowercased()
        let alreadyDeleting = deletingNamesLock.sync { () -> Bool in
            if deletingNames.contains(deleteKey) { return true }
            deletingNames.insert(deleteKey)
            return false
        }
        if alreadyDeleting {
            print("⚠️ deleteUserEverywhere() already in progress for \(trimmed); skipping duplicate request")
            completion(false)
            return
        }
        print("🗑️ deleteUserEverywhere() starting for \(trimmed)")

        let recordIDsLock = DispatchQueue(label: "CloudKitManager.deleteUserEverywhere.recordIDs")
        var recordIDsToDelete = Set<CKRecord.ID>()
        recordIDsLock.sync {
            recordIDsToDelete.insert(teamMemberRecordID(for: trimmed))
            recordIDsToDelete.insert(twyRecordID(for: trimmed))
            recordIDsToDelete.insert(cardID(for: trimmed))
        }

        let namePredicate = NSPredicate(format: "name == %@", trimmed)
        let userNamePredicate = NSPredicate(format: "userName == %@", trimmed)
        let group = DispatchGroup()
        func finish(_ success: Bool) {
            deletingNamesLock.sync { () -> Void in
                deletingNames.remove(deleteKey)
            }
            completion(success)
        }

        func queryRecordIDs(recordType: String, predicate: NSPredicate, label: String) {
            group.enter()
            let query = CKQuery(recordType: recordType, predicate: predicate)
            database.fetch(withQuery: query,
                           inZoneWith: nil,
                           desiredKeys: nil,
                           resultsLimit: CKQueryOperation.maximumResults) { result in
                switch result {
                case .success(let (matchResults, _)):
                    var found: [CKRecord.ID] = []
                    for (recordID, recordResult) in matchResults {
                        switch recordResult {
                        case .success:
                            found.append(recordID)
                        case .failure(let error):
                            print("❌ deleteUserEverywhere() \(label) record failed: \(error.localizedDescription)")
                            logCKError(error, context: "deleteUserEverywhere() \(label)")
                        }
                    }
                    if !found.isEmpty {
                        recordIDsLock.sync {
                            for recordID in found { recordIDsToDelete.insert(recordID) }
                        }
                    }
                    print("🗑️ deleteUserEverywhere() \(label) found \(found.count) records")
                case .failure(let error):
                    print("❌ deleteUserEverywhere() \(label) query failed: \(error.localizedDescription)")
                    logCKError(error, context: "deleteUserEverywhere() \(label)")
                }
                group.leave()
            }
        }

        queryRecordIDs(recordType: recordType, predicate: namePredicate, label: "TeamMember(name)")
        queryRecordIDs(recordType: TwelveWeekMember.recordType, predicate: namePredicate, label: "TwelveWeekMember(name)")
        queryRecordIDs(recordType: cardRecordType, predicate: namePredicate, label: "Card(name)")
        queryRecordIDs(recordType: cardOrderRecordType, predicate: userNamePredicate, label: "CardOrder(userName)")
        queryRecordIDs(recordType: "CardModel", predicate: userNamePredicate, label: "CardModel(userName)")

        group.notify(queue: .main) {
            let recordIDs = recordIDsLock.sync { Array(recordIDsToDelete) }
            guard !recordIDs.isEmpty else {
                print("⚠️ deleteUserEverywhere() no records found for \(trimmed)")
                finish(false)
                return
            }

            let recordNames = recordIDs.map { $0.recordName }.sorted()
            print("🗑️ deleteUserEverywhere() deleting \(recordIDs.count) records for \(trimmed): \(recordNames)")
            let deleteOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            deleteOperation.isAtomic = false
            deleteOperation.modifyRecordsResultBlock = { result in
                DispatchQueue.main.async {
                    var didSucceed = false
                    defer { finish(didSucceed) }
                    switch result {
                    case .success:
                        didSucceed = true
                        print("🗑️ deleteUserEverywhere() deleted \(recordIDs.count) records for \(trimmed)")
                        NotificationCenter.default.post(
                            name: .cloudKitUserDeleted,
                            object: nil,
                            userInfo: ["name": trimmed]
                        )
                    case .failure(let error):
                        print("❌ deleteUserEverywhere() delete failed: \(error.localizedDescription)")
                        logCKError(error, context: "deleteUserEverywhere()")
                        if let ckError = error as? CKError,
                           let partials = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                            for (recordID, partialError) in partials {
                                logCKError(partialError, context: "deleteUserEverywhere() partial \(recordID.recordName)")
                            }
                        }
                    }
                }
            }
            self.database.add(deleteOperation)
        }
    }

    // Save the given score entry, updating the matching TeamMember's score fields.
    func saveScore(entry: LifeScoreboardViewModel.ScoreEntry, pending: Int, projected: Double) {
        let name = entry.name
        fetchFiltered(byUserName: name) { members in
            guard let member = members.first else {
                print("❌ No matching TeamMember found for \(name)")
                return
            }

            let updated = member
            updated.actual = entry.score
            updated.pending = pending
            updated.projected = projected

            self.save(updated) { _ in }
        }
    }


    func fetchScores(for names: [String], completion: @escaping ([String: (score: Int, pending: Int, projected: Double)]) -> Void) {
        print("\u{1F50D} Starting fetchScores() for names: \(names)")
        guard !names.isEmpty else {
            completion([:])
            return
        }
        let ids = names.map { memberID(for: $0) }
        var results: [String: (Int, Int, Double)] = [:]
        let operation = CKFetchRecordsOperation(recordIDs: ids)
        operation.perRecordResultBlock = { recordID, result in
            switch result {
            case .success(let record):
                let name = record["name"] as? String ?? recordID.recordName
                let score = record["actual"] as? Int ?? 0
                let pending = record["pending"] as? Int ?? 0
                let projected = record["projected"] as? Double ?? 0.0
                results[name] = (score, pending, projected)
                print("✅ fetchScores() matched record: \(recordID.recordName)")
            case .failure(let error):
                print("❌ fetchScores() record failed: \(error.localizedDescription)")
            }
        }
        operation.fetchRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    print("✅ fetchScores(): loaded \(results.count) records")
                case .failure(let error):
                    print("❌ fetchScores() query failed: \(error.localizedDescription)")
                }
                completion(results)
            }
        }

        database.add(operation)
    }

    /// Updates only the emoji value for the given member without overwriting
    /// their production stats. Falls back to query-by-name and creates the
    /// canonical record if needed.
    func updateEmoji(for name: String, emoji: String, completion: @escaping (Bool) -> Void = { _ in }) {
        let id = memberID(for: name)
        print("\u{1F4DD} updateEmoji() attempting fetch-by-ID: \(id.recordName) -> emoji=\(emoji)")
        database.fetch(withRecordID: id) { record, error in
            if let record = record, error == nil {
                record["emoji"] = emoji as CKRecordValue
                self.database.save(record) { _, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ updateEmoji() save failed (by-ID path): \(error.localizedDescription)")
                            completion(false)
                        } else {
                            print("✅ updateEmoji() saved (by-ID path) for \(name)")
                            completion(true)
                        }
                    }
                }
                return
            }

            // Fallback: query by name to find any existing record with a non-canonical ID
            let predicate = NSPredicate(format: "name == %@", name)
            let query = CKQuery(recordType: self.recordType, predicate: predicate)
            print("\u{1F50D} updateEmoji() falling back to query-by-name for: \(name)")
            let op = CKQueryOperation(query: query)
            op.resultsLimit = 1

            var matched: CKRecord?
            op.recordMatchedBlock = { _, result in
                if case .success(let rec) = result { matched = rec }
            }
            op.queryResultBlock = { _ in
                if let existing = matched {
                    existing["emoji"] = emoji as CKRecordValue
                    self.database.save(existing) { _, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("❌ updateEmoji() save failed (query path): \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("✅ updateEmoji() saved (query path) for \(name)")
                                completion(true)
                            }
                        }
                    }
                } else {
                    // Create canonical record with stable ID
                    print("ℹ️ updateEmoji() no existing record found for \(name); creating canonical record \(id.recordName)")
                    let newRecord = CKRecord(recordType: self.recordType, recordID: id)
                    newRecord["name"] = name as CKRecordValue
                    newRecord["emoji"] = emoji as CKRecordValue
                    self.database.save(newRecord) { _, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                print("❌ updateEmoji() failed to create canonical record: \(error.localizedDescription)")
                                completion(false)
                            } else {
                                print("✅ updateEmoji() created canonical record and saved emoji for \(name)")
                                completion(true)
                            }
                        }
                    }
                }
            }
            self.database.add(op)
        }
    }

    // MARK: - Card Order
    func fetchCardOrder(for user: String, completion: @escaping ([String]?) -> Void) {
        print("\u{1F50D} Starting fetchCardOrder() for user: \(user)")
        let predicate = NSPredicate(format: "userName == %@", user)
        let query = CKQuery(recordType: cardOrderRecordType, predicate: predicate)
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1

        var savedOrder: [String]?
        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success(let record):
                savedOrder = record["cardOrder"] as? [String]
                print("✅ fetchCardOrder() matched record: \(recordID.recordName)")
            case .failure(let error):
                print("❌ fetchCardOrder() record match failed: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    if savedOrder != nil {
                        print("✅ fetchCardOrder(): card order found for user: \(user)")
                    } else {
                        print("⚠️ fetchCardOrder(): no order found for user: \(user)")
                    }
                case .failure(let error):
                    print("❌ fetchCardOrder() query failed: \(error.localizedDescription)")
                }
                completion(savedOrder)
            }
        }

        database.add(operation)
    }

    func saveCardOrder(for user: String, order: [String]) {
        let predicate = NSPredicate(format: "userName == %@", user)
        let query = CKQuery(recordType: cardOrderRecordType, predicate: predicate)
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1

        var matchedRecord: CKRecord?
        operation.recordMatchedBlock = { _, result in
            if case .success(let record) = result {
                matchedRecord = record
            }
        }

        operation.queryResultBlock = { _ in
            let record = matchedRecord ?? CKRecord(recordType: self.cardOrderRecordType)
            record["userName"] = user as CKRecordValue
            record["cardOrder"] = order as CKRecordValue

            let modify = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            modify.modifyRecordsResultBlock = { _ in }
            self.database.add(modify)
        }

        database.add(operation)
    }

    // MARK: - User Sync

    /// Fetches user records filtered by the provided user name.
    static func fetchUsers(for userName: String, completion: @escaping ([String]) -> Void) {
        print("🕒 \(Date()) — \u{1F50D} Starting fetchUsers() for user: \(userName)")
        print("🕒 \(Date()) — \u{1F50D} \u{1F50D} fetchUsers() is searching for name: [\(userName)]")
        guard !userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("🕒 \(Date()) — ⚠️ fetchUsers() aborted: currentUser is empty or invalid.")
            completion([])
            return
        }
        // Use the custom "name" field rather than the system-level recordName
        let predicate = NSPredicate(format: "name == %@", userName)
        let query = CKQuery(recordType: userRecordType, predicate: predicate)

        CloudKitManager.container.publicCloudDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                let names = records.compactMap { $0["name"] as? String }
                print("🕒 \(Date()) — ✅ fetchUsers() loaded \(names.count) users")
                completion(names.sorted())
            case .failure(let error):
                let message = error.localizedDescription
                print("🕒 \(Date()) — ❌ fetchUsers() failed: \(message)")
                completion([])
            }
        }
    }

    /// Fetches all user names stored in CloudKit without filtering by name.
    static func fetchAllUserNames(completion: @escaping ([String]) -> Void) {
        let manager = CloudKitManager.shared
        if manager.isFetchingAllUserNames {
            print("⚠️ fetchAllUserNames() already in progress; skipping duplicate request")
            return
        }
        manager.isFetchingAllUserNames = true
        logCloudKitIdentityAndScope(
            context: "fetchAllUserNames()",
            container: CloudKitManager.container,
            dbScope: .public
        )
        print("🕒 \(Date()) — \u{1F50D} Starting fetchAllUserNames()")
        let query = CKQuery(recordType: userRecordType, predicate: NSPredicate(value: true))
        CloudKitManager.container.publicCloudDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: ["name"], resultsLimit: CKQueryOperation.maximumResults) { result in
            defer { manager.isFetchingAllUserNames = false }
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                let names = records.compactMap { $0["name"] as? String }
                print("🕒 \(Date()) — ✅ fetchAllUserNames() loaded \(names.count) users")
                completion(names.sorted())
            case .failure(let error):
                print("🕒 \(Date()) — ❌ fetchAllUserNames() failed: \(error.localizedDescription)")
                completion([])
            }
        }
    }

    /// Convenience wrapper that uses ``UserManager``'s current user.
    /// Calls ``fetchUsers(for:completion:)`` and simply prints the results.
    func fetchUsers() {
        let current = UserManager.shared.currentUser
        CloudKitManager.fetchUsers(for: current) { names in
            DispatchQueue.main.async {
                print("🕒 \(Date()) — 📥 Received users from CloudKit: \(names)")
            }
        }
    }

    /// Saves the provided user name to CloudKit.
    static func saveUser(_ name: String, completion: @escaping () -> Void) {
        logCloudKitIdentityAndScope(
            context: "saveUser()",
            container: CloudKitManager.container,
            dbScope: .public
        )
        let record = CKRecord(recordType: userRecordType, recordID: CloudKitManager.shared.memberID(for: name))
        record["name"] = name as CKRecordValue
        CloudKitManager.container.publicCloudDatabase.save(record) { _, error in
            if let error = error {
                print("❌ Error saving user: \(error)")
                logCKError(error, context: "saveUser()")
            } else {
                print("✅ Successfully saved member: \(name)")
            }
            completion()
        }
    }

    /// Deletes the user with the given name from CloudKit.
    static func deleteUser(_ name: String) {
        CloudKitManager.shared.deleteUserEverywhere(name: name) { _ in }
    }

    // MARK: - Twelve Week Year

    /// Saves a `TwelveWeekMember` record to CloudKit.
    static func saveTwelveWeekMember(_ member: TwelveWeekMember,
                                     completion: @escaping (Result<CKRecord.ID, Error>) -> Void = { _ in }) {
        print("\u{1F4BE} Starting saveTwelveWeekMember() for \(member.name)")
        let predicate = NSPredicate(format: "name == %@", member.name)
        let query = CKQuery(recordType: TwelveWeekMember.recordType, predicate: predicate)
        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1

        var matchedRecord: CKRecord?
        operation.recordMatchedBlock = { _, result in
            switch result {
            case .success(let record):
                matchedRecord = record
            case .failure(let error):
                print("❌ Failed to match TWY member: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    print("❌ saveTwelveWeekMember() query failed: \(error.localizedDescription)")
                }

                let record = member.toRecord(existing: matchedRecord)
                let modify = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
                print("\u{1F4DD} saveTwelveWeekMember(): adding modify operation for \(record.recordID.recordName)")
                modify.modifyRecordsResultBlock = { modifyResult in
                    DispatchQueue.main.async {
                        print("\u{1F4E6} saveTwelveWeekMember(): modify operation completed")
                        switch modifyResult {
                        case .failure(let error):
                            print("❌ Error saving TWY member \(record.recordID.recordName): \(error.localizedDescription)")
                            logCKError(error, context: "saveTwelveWeekMember()")
                            completion(.failure(error))
                        case .success:
                            print("✅ Successfully saved TWY member: \(member.name)")
                            completion(.success(record.recordID))
                        }
                    }
                }

                CloudKitManager.container.publicCloudDatabase.add(modify)
            }
        }

        CloudKitManager.container.publicCloudDatabase.add(operation)
    }

    /// Deletes the `TwelveWeekMember` with the given name from CloudKit.
    static func deleteTwelveWeekMember(named name: String) {
        let id = CKRecord.ID(recordName: "twy-\(name)")
        CloudKitManager.container.publicCloudDatabase.delete(withRecordID: id) { _, error in
            if let error = error {
                print("❌ Error deleting TWY member \(id.recordName): \(error.localizedDescription)")
            }
        }
    }

    /// Fetches `TwelveWeekMember` records from CloudKit.
    /// - Parameter names: Optional list of member names to filter by. Pass
    ///   `nil` or an empty array to fetch all records.
    static func fetchTwelveWeekMembers(matching names: [String]? = nil,
                                       completion: @escaping ([TwelveWeekMember]) -> Void) {
        print("\u{1F50D} Starting fetchTwelveWeekMembers()")

        let predicate: NSPredicate
        if let names = names, !names.isEmpty {
            predicate = NSPredicate(format: "name IN %@", names)
        } else {
            predicate = NSPredicate(value: true)
        }
        let query = CKQuery(recordType: TwelveWeekMember.recordType, predicate: predicate)

        CloudKitManager.container.publicCloudDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                var members: [TwelveWeekMember] = []
                for (recordID, recordResult) in matchResults {
                    switch recordResult {
                    case .success(let record):
                        if let member = TwelveWeekMember(record: record) {
                            members.append(member)
                            print("\u{1F4C4} fetchTwelveWeekMembers(): parsed member \(member.name)")
                        }
                        print("✅ fetchTwelveWeekMembers() matched record: \(recordID.recordName)")
                    case .failure(let error):
                        print("❌ fetchTwelveWeekMembers() record match failed: \(error.localizedDescription)")
                    }
                }
                DispatchQueue.main.async {
                    print("✅ fetchTwelveWeekMembers(): loaded \(members.count) records")
                    completion(members)
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    print("❌ fetchTwelveWeekMembers() query failed: \(error.localizedDescription)")
                    completion([])
                }
            }
        }
    }

    // MARK: - Card Sync

    private static func logCK(_ tag: String, _ msg: String) {
        print("☁️ [CK CARDS \(tag)] \(msg)")
    }

    /// Fetches all Win the Day cards from CloudKit.
    static func fetchCards(completion: @escaping ([Card]) -> Void) {
        fetchCards(requestedNames: [], completion: completion)
    }

    /// Fetches all Win the Day cards from CloudKit.
    static func fetchCards(requestedNames: [String], completion: @escaping ([Card]) -> Void) {
        // AUDIT-ONLY: do not change record type, predicates, or persistence behavior.
        let recordType = shared.cardRecordType
        let identifier = container.containerIdentifier ?? "(nil)"
        let fieldUsed = "name"
        guard !requestedNames.isEmpty else {
            logCK("QUERY", "containerIdentifier=\(identifier) dbScope=public recordType=\(recordType) fieldUsed=\(fieldUsed) predicate=<nil>")
            logCK("QUERY", "requestedNames=\(requestedNames)")
            logCK("RESULT", "⚠️ rawCount=0 mappedCount=0 droppedCount=0 predicate=<nil> fieldUsed=\(fieldUsed) (requestedNames empty)")
            completion([])
            return
        }
        let predicate = NSPredicate(format: "%K IN %@", fieldUsed, requestedNames)
        logCK("QUERY", "containerIdentifier=\(identifier) dbScope=public recordType=\(recordType) fieldUsed=\(fieldUsed) predicate=\(predicate.predicateFormat)")
        logCK("QUERY", "requestedNames=\(requestedNames)")

        func handleRecords(_ records: [CKRecord], predicate: NSPredicate) {
            logCK("RAW", "rawCount=\(records.count)")
            let rawRecordIDs = records.prefix(10).map { $0.recordID.recordName }
            logCK("RAW", "rawIDs=\(rawRecordIDs)")
            for (index, record) in records.prefix(3).enumerated() {
                let keys = record.allKeys().sorted()
                let nameVal = record["name"] as? String
                let userNameVal = record["userName"] as? String
                let keysSummary = Array(keys.prefix(12))
                logCK("RAW", "sample[\(index)] recordID=\(record.recordID.recordName) keys=\(keysSummary)")
                logCK("RAW", "sample[\(index)] name=\(nameVal ?? "<nil>") userName=\(userNameVal ?? "<nil>")")
            }

            var cards: [Card] = []
            var drops: [(id: String, reason: String, details: String)] = []
            let requestedSet = Set(requestedNames)
            func clean(_ value: String?) -> String? {
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            for record in records {
                if let card = Card(record: record) {
                    cards.append(card)
                } else {
                    let nameVal = clean(record["name"] as? String)
                    let userNameVal = clean(record["userName"] as? String)
                    let emojiVal = record["emoji"] as? String
                    let productionVal = record["production"] as? Int
                    let keys = record.allKeys().sorted()
                    let keysSummary = Array(keys.prefix(12))
                    let reason: String
                    if nameVal == nil && userNameVal == nil {
                        reason = "MISSING_USER_FIELD"
                    } else if !requestedSet.isEmpty {
                        let keyValue = userNameVal ?? nameVal
                        if let keyValue, !requestedSet.contains(keyValue) {
                            reason = "NAME_NOT_REQUESTED"
                        } else if emojiVal == nil || productionVal == nil {
                            reason = "DECODE_FAILURE"
                        } else {
                            reason = "UNKNOWN"
                        }
                    } else if emojiVal == nil || productionVal == nil {
                        reason = "DECODE_FAILURE"
                    } else {
                        reason = "UNKNOWN"
                    }
                    let details = "name=\(nameVal ?? "<nil>") userName=\(userNameVal ?? "<nil>") keys=\(keysSummary)"
                    drops.append((record.recordID.recordName, reason, details))
                }
            }
            logCK("MAP", "mappedCount=\(cards.count) droppedCount=\(drops.count)")
            if !drops.isEmpty {
                for drop in drops.prefix(10) {
                    logCK("DROP", "recordID=\(drop.id) reason=\(drop.reason) details=\(drop.details)")
                }
            }
            let rawCount = records.count
            let mappedCount = cards.count
            let droppedCount = drops.count
            let resultMessage: String
            if rawCount == 0 {
                resultMessage = "⚠️ rawCount=0 mappedCount=0 droppedCount=0 predicate=\(predicate.predicateFormat) fieldUsed=\(fieldUsed) (CloudKit returned no CKRecords)"
            } else if mappedCount == 0 {
                resultMessage = "⚠️ rawCount=\(rawCount) mappedCount=0 droppedCount=\(droppedCount) predicate=\(predicate.predicateFormat) fieldUsed=\(fieldUsed) (all records dropped during mapping)"
            } else {
                resultMessage = "✅ rawCount=\(rawCount) mappedCount=\(mappedCount) droppedCount=\(droppedCount) predicate=\(predicate.predicateFormat) fieldUsed=\(fieldUsed)"
            }
            logCK("RESULT", resultMessage)
            if mappedCount == 0 {
                runFetchCardsDiagnosticsIfNeeded(requestedNames: requestedNames)
            }
            completion(cards)
        }

        func fetchByRecordIDs() {
            let recordIDs = requestedNames.map { shared.cardID(for: $0) }
            let recordNames = recordIDs.prefix(10).map { $0.recordName }
            logCK("QUERY", "fallback=recordIDFetch recordIDs=\(recordNames)")
            let operation = CKFetchRecordsOperation(recordIDs: recordIDs)
            var fetched: [CKRecord] = []
            operation.perRecordResultBlock = { _, result in
                switch result {
                case .success(let record):
                    fetched.append(record)
                case .failure(let error):
                    logCK("RAW", "perRecord error=\(error.localizedDescription)")
                }
            }
            operation.fetchRecordsResultBlock = { result in
                switch result {
                case .success:
                    handleRecords(fetched, predicate: predicate)
                case .failure(let error):
                    let ns = error as NSError
                    logCK("RAW", "error=\(ns.domain)/\(ns.code) \(ns.localizedDescription)")
                    if let ckError = error as? CKError {
                        let keys = ckError.userInfo.keys.map { String(describing: $0) }.sorted()
                        logCK("RAW", "ckErrorCode=\(ckError.code.rawValue) userInfoKeys=\(keys)")
                    }
                    logCK("RESULT", "⚠️ rawCount=0 mappedCount=0 droppedCount=0 predicate=\(predicate.predicateFormat) fieldUsed=\(fieldUsed) (CloudKit error)")
                    completion([])
                }
            }
            container.publicCloudDatabase.add(operation)
        }

        let query = CKQuery(recordType: recordType, predicate: predicate)
        CloudKitManager.container.publicCloudDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                handleRecords(records, predicate: predicate)
            case .failure(let error):
                let ns = error as NSError
                logCK("RAW", "error=\(ns.domain)/\(ns.code) \(ns.localizedDescription)")
                if let ckError = error as? CKError {
                    let keys = ckError.userInfo.keys.map { String(describing: $0) }.sorted()
                    logCK("RAW", "ckErrorCode=\(ckError.code.rawValue) userInfoKeys=\(keys)")
                    if ckError.code == .invalidArguments {
                        let serverDescription = ckError.userInfo["CKErrorServerDescriptionKey"] as? String
                        let message = (serverDescription ?? ckError.localizedDescription).lowercased()
                        if message.contains("not marked queryable") {
                            fetchByRecordIDs()
                            return
                        }
                        logCK("RESULT", "⚠️ error=invalidArguments (non-queryable mismatch)")
                        completion([])
                        return
                    }
                }
                logCK("RESULT", "⚠️ rawCount=0 mappedCount=0 droppedCount=0 predicate=\(predicate.predicateFormat) fieldUsed=\(fieldUsed) (CloudKit error)")
                completion([])
            }
        }
    }

    private static func runFetchCardsDiagnosticsIfNeeded(requestedNames: [String]) {
        guard enableFetchCardsDiagnostics else { return }
        let shouldRun = fetchCardsDiagnosticsLock.sync { () -> Bool in
            if didRunFetchCardsDiagnostics { return false }
            didRunFetchCardsDiagnostics = true
            return true
        }
        guard shouldRun else { return }
        runFetchCardsDiagnostics(requestedNames: requestedNames)
    }

    private static func runFetchCardsDiagnostics(requestedNames: [String]) {
        let recordType = shared.cardRecordType
        let identifier = container.containerIdentifier ?? "(nil)"
        let predicate = NSPredicate(value: true)
        logCK("DIAG", "start containerIdentifier=\(identifier) dbScope=public recordType=\(recordType) predicate=\(predicate.predicateFormat)")

        let existenceQuery = CKQuery(recordType: recordType, predicate: predicate)
        container.publicCloudDatabase.fetch(withQuery: existenceQuery,
                                            inZoneWith: nil,
                                            desiredKeys: nil,
                                            resultsLimit: 10) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                logCK("DIAG", "existence count=\(records.count)")
                if records.isEmpty {
                    logCK("DIAG", "No records exist for recordType=\(recordType) in dbScope=public")
                    return
                }
                for record in records {
                    let keys = record.allKeys()
                    let zoneName = record.recordID.zoneID.zoneName
                    logCK("DIAG", "recordID=\(record.recordID.recordName) zone=\(zoneName) keys=\(keys)")
                }
                runFetchCardsFieldProbe(requestedNames: requestedNames, recordType: recordType)
            case .failure(let error):
                logCK("DIAG", "existence query failed: \(error.localizedDescription)")
                logCKError(error, context: "fetchCardsDiagnostics.existence")
            }
        }
    }

    private static func runFetchCardsFieldProbe(requestedNames: [String], recordType: String) {
        guard !requestedNames.isEmpty else {
            logCK("DIAG", "field probe skipped (requestedNames empty)")
            return
        }
        let fields = ["userName", "name"]
        for field in fields {
            let predicate = NSPredicate(format: "%K IN %@", field, requestedNames)
            let query = CKQuery(recordType: recordType, predicate: predicate)
            logCK("DIAG", "fieldProbe field=\(field) predicate=\(predicate.predicateFormat)")
            container.publicCloudDatabase.fetch(withQuery: query,
                                                inZoneWith: nil,
                                                desiredKeys: nil,
                                                resultsLimit: 50) { result in
                switch result {
                case .success(let (matchResults, _)):
                    let records = matchResults.compactMap { _, recordResult in
                        try? recordResult.get()
                    }
                    logCK("DIAG", "field=\(field) count=\(records.count)")
                    if let sample = records.first {
                        let value = sample[field] as? String ?? "(nil)"
                        logCK("DIAG", "field=\(field) sampleRecordID=\(sample.recordID.recordName) value=\(value)")
                    }
                case .failure(let error):
                    logCK("DIAG", "field=\(field) query failed: \(error.localizedDescription)")
                    logCKError(error, context: "fetchCardsDiagnostics.fieldProbe.\(field)")
                }
            }
        }
    }

    /// Saves a Win the Day card to CloudKit.
    static func saveCard(_ card: Card) {
        let record = card.toCKRecord()
        CloudKitManager.container.publicCloudDatabase.save(record) { _, _ in }
    }

    /// Saves a Win the Day ``CardModel`` using the user's name as the record ID.
    func save(card: CardModel) {
        let record = card.toRecord()
        database.save(record) { _, error in
            if let error = error {
                print("❌ Error saving card: \(error.localizedDescription)")
            } else {
                print("✅ Card saved for \(card.userName)")
            }
        }
    }

    // MARK: - Goal Name Sync

    func fetchGoalNames(completion: @escaping (GoalNames?) -> Void) {
        let id = CKRecord.ID(recordName: "GoalNames")
        database.fetch(withRecordID: id) { record, _ in
            DispatchQueue.main.async {
                if let record = record, let names = GoalNames(record: record) {
                    completion(names)
                } else {
                    completion(nil)
                }
            }
        }
    }

    func saveGoalNames(_ names: GoalNames) {
        let id = CKRecord.ID(recordName: "GoalNames")
        database.fetch(withRecordID: id) { existing, _ in
            let record = names.toRecord(existing: existing)
            self.database.save(record) { _, _ in }
        }
    }

}

private extension CKAccountStatus {
    var debugName: String {
        switch self {
        case .available:
            return "available"
        case .noAccount:
            return "noAccount"
        case .restricted:
            return "restricted"
        case .couldNotDetermine:
            return "couldNotDetermine"
        case .temporarilyUnavailable:
            return "temporarilyUnavailable"
        @unknown default:
            return "unknown"
        }
    }
}

private extension CKDatabase.Scope {
    var debugName: String {
        switch self {
        case .public:
            return "public"
        case .private:
            return "private"
        case .shared:
            return "shared"
        @unknown default:
            return "unknown"
        }
    }
}

func logCloudKitIdentityAndScope(context: String,
                                 container: CKContainer = .default(),
                                 dbScope: CKDatabase.Scope) {
    let identifier = container.containerIdentifier ?? "(nil)"
    print("☁️ [CK DEBUG] \(context) containerIdentifier=\(identifier) dbScope=\(dbScope.debugName)")

    container.accountStatus { status, error in
        if let error = error {
            print("☁️ [CK DEBUG] \(context) accountStatus error: \(error)")
        } else {
            print("☁️ [CK DEBUG] \(context) accountStatus=\(status.debugName)")
        }
    }

    container.fetchUserRecordID { recordID, error in
        if let error = error {
            print("☁️ [CK DEBUG] \(context) fetchUserRecordID FAILED: \(error)")
        } else {
            print("☁️ [CK DEBUG] \(context) fetchUserRecordID OK: \(recordID?.recordName ?? "(nil)")")
        }
    }
}

func logCKError(_ error: Error, context: String) {
    let ns = error as NSError
    print("❌ [CK ERROR] \(context) domain=\(ns.domain) code=\(ns.code) desc=\(ns.localizedDescription)")

    guard let ck = error as? CKError else { return }

    if let retry = ck.userInfo[CKErrorRetryAfterKey] as? NSNumber {
        print("❌ [CK ERROR] \(context) retryAfter=\(retry)")
    }
    if let message = ck.userInfo["CKErrorServerDescriptionKey"] as? String {
        print("❌ [CK ERROR] \(context) serverMessage=\(message)")
    }
    if let requestID = ck.userInfo["CKErrorRequestUUIDKey"] as? String {
        print("❌ [CK ERROR] \(context) requestUUID=\(requestID)")
    }
    if let clientRecord = ck.clientRecord {
        print("❌ [CK ERROR] \(context) clientRecord=\(clientRecord.recordType)/\(clientRecord.recordID.recordName)")
    }
    if let serverRecord = ck.serverRecord {
        print("❌ [CK ERROR] \(context) serverRecord=\(serverRecord.recordType)/\(serverRecord.recordID.recordName)")
    }
}

extension Notification.Name {
    static let cloudKitUserDeleted = Notification.Name("CloudKitUserDeleted")
    static let cloudKitTeamMemberDidChange = Notification.Name("CloudKitTeamMemberDidChange")
}
