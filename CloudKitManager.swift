import CloudKit
import Foundation

class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    /// The primary iCloud container for all app data.
    static let container = CKContainer(identifier: "iCloud.com.dj.Outcast")
    private let database = CloudKitManager.container.publicCloudDatabase
    private let recordType = "TeamMember"
    private let cardRecordType = "Card"
    private let cardOrderRecordType = "CardOrder"
    private let goalNameRecordType = "GoalNames"
    private static let userRecordType = "TeamMember"

    // MARK: - Migration
    private static let migrationKey = "TeamMemberFieldMigrationVersion"
    private static let migrationVersion = 1

    /// Cached members fetched from CloudKit. Updates to this array reflect
    /// immediately in any views observing the manager.
    @Published var teamMembers: [TeamMember] = []

    // MARK: - Record ID Helpers
    private func memberID(for name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "member-\(name)")
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
        operation.recordFetchedBlock = { record in
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
        print("\u{1F50D} Starting fetchTeam()")
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "TeamMember", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]

        var fetchedMembers: [TeamMember] = []

        let operation = CKQueryOperation(query: query)
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
                switch result {
                case .success:
                    let valid = fetchedMembers.filter {
                        !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                    }
                    self.teamMembers = valid
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

    func save(_ member: TeamMember, completion: @escaping (CKRecord.ID?) -> Void) {
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
                let modifyOperation = self.prepareModifyOperation(for: member, existingRecord: matchedRecord, completion: completion)
                self.database.add(modifyOperation)
            }
        }

        database.add(operation)
    }

    private func prepareModifyOperation(for member: TeamMember, existingRecord: CKRecord?, completion: @escaping (CKRecord.ID?) -> Void) -> CKModifyRecordsOperation {
        let record = member.toRecord(existing: existingRecord)
        let modifyOperation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        modifyOperation.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .failure(let error):
                    print("❌ Error saving: \(error.localizedDescription)")
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
        let id = memberID(for: member.name)
        database.delete(withRecordID: id) { _, error in
            if let error = error {
                print("❌ Error deleting: \(error.localizedDescription)")
            }
        }
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
        let predicate = NSPredicate(format: "name == %@", name)
        let query = CKQuery(recordType: recordType, predicate: predicate)

        let operation = CKQueryOperation(query: query)
        operation.resultsLimit = 1

        var matchedID: CKRecord.ID?

        operation.recordMatchedBlock = { recordID, result in
            switch result {
            case .success:
                matchedID = recordID
            case .failure(let error):
                print("❌ Failed to find record to delete: \(error.localizedDescription)")
            }
        }

        operation.queryResultBlock = { result in
            DispatchQueue.main.async {
                guard let recordID = matchedID else {
                    print("⚠️ No matching record ID found for name: \(name)")
                    completion(false)
                    return
                }

                self.database.delete(withRecordID: recordID) { _, error in
                    DispatchQueue.main.async {
                        if let error = error {
                            print("❌ Error deleting record by name: \(error.localizedDescription)")
                            completion(false)
                        } else {
                            print("🗑️ Deleted record with name: \(name)")
                            completion(true)
                        }
                    }
                }
            }
        }

        database.add(operation)
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
    /// their production stats.
    func updateEmoji(for name: String, emoji: String, completion: @escaping (Bool) -> Void = { _ in }) {
        let id = memberID(for: name)
        database.fetch(withRecordID: id) { record, error in
            guard let record = record, error == nil else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            record["emoji"] = emoji as CKRecordValue
            self.database.save(record) { _, error in
                DispatchQueue.main.async { completion(error == nil) }
            }
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
        print("🕒 \(Date()) — \u{1F50D} Starting fetchAllUserNames()")
        let query = CKQuery(recordType: userRecordType, predicate: NSPredicate(value: true))
        CloudKitManager.container.publicCloudDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: ["name"], resultsLimit: CKQueryOperation.maximumResults) { result in
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
        let record = CKRecord(recordType: userRecordType, recordID: CloudKitManager.shared.memberID(for: name))
        record["name"] = name as CKRecordValue
        CloudKitManager.container.publicCloudDatabase.save(record) { _, error in
            if let error = error {
                print("❌ Error saving user: \(error)")
            } else {
                print("✅ Successfully saved member: \(name)")
            }
            completion()
        }
    }

    /// Deletes the user with the given name from CloudKit.
    static func deleteUser(_ name: String) {
        let id = CloudKitManager.shared.memberID(for: name)
        CloudKitManager.container.publicCloudDatabase.delete(withRecordID: id) { _, _ in }
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

    /// Fetches all Win the Day cards from CloudKit.
    static func fetchCards(completion: @escaping ([Card]) -> Void) {
        let query = CKQuery(recordType: shared.cardRecordType, predicate: NSPredicate(value: true))
        CloudKitManager.container.publicCloudDatabase.fetch(withQuery: query, inZoneWith: nil, desiredKeys: nil, resultsLimit: CKQueryOperation.maximumResults) { result in
            switch result {
            case .success(let (matchResults, _)):
                let records = matchResults.compactMap { _, recordResult in
                    try? recordResult.get()
                }
                let cards = records.compactMap(Card.init)
                completion(cards)
            case .failure:
                completion([])
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
