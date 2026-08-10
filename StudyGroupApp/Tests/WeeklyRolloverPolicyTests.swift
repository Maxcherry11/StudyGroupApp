import Foundation

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw TestFailure(description: message) }
}

private func input(streak: Int,
                   quotes: Int,
                   quotesGoal: Int,
                   sales: Int,
                   salesGoal: Int,
                   storedWeek: String = "2026-W32",
                   currentWeek: String = "2026-W33",
                   finalizedWeek: String? = nil) -> WeeklyRolloverPolicy.Input {
    WeeklyRolloverPolicy.Input(storedWeekId: storedWeek,
                               currentWeekId: currentWeek,
                               lastFinalizedWeekId: finalizedWeek,
                               previousStreak: streak,
                               quotes: quotes,
                               quotesGoal: quotesGoal,
                               salesWTD: sales,
                               salesWTDGoal: salesGoal)
}

private struct SimulatedCloudRecord {
    var revision: Int
    var weekId: String
    var finalizedWeekId: String?
    var streak: Int
    var quotes: Int
    var sales: Int
}

private func saveIfUnchanged(_ proposed: SimulatedCloudRecord,
                             readRevision: Int,
                             cloud: inout SimulatedCloudRecord) -> Bool {
    guard cloud.revision == readRevision else { return false }
    cloud = proposed
    cloud.revision += 1
    return true
}

@main
struct WeeklyRolloverPolicyTestRunner {
    static func main() throws {
        let dj = WeeklyRolloverPolicy.evaluate(
            input(streak: 4, quotes: 10, quotesGoal: 10, sales: 2, salesGoal: 2)
        )
        try expect(dj.didWin && dj.newStreak == 5, "D.J. should reach streak 5 (diamond)")

        let deanna = WeeklyRolloverPolicy.evaluate(
            input(streak: 1, quotes: 2, quotesGoal: 10, sales: 2, salesGoal: 2)
        )
        try expect(deanna.didWin && deanna.newStreak == 2, "Deanna should reach streak 2")

        let ron = WeeklyRolloverPolicy.evaluate(
            input(streak: 3, quotes: 4, quotesGoal: 10, sales: 1, salesGoal: 2)
        )
        try expect(!ron.didWin && ron.newStreak == 0, "Ron should reset to zero")

        let dimitri = WeeklyRolloverPolicy.evaluate(
            input(streak: 1, quotes: 0, quotesGoal: 10, sales: 0, salesGoal: 2)
        )
        try expect(!dimitri.didWin && dimitri.newStreak == 0, "Dimitri should reset to zero")

        let secondDevice = WeeklyRolloverPolicy.evaluate(
            input(streak: dj.newStreak,
                  quotes: 0,
                  quotesGoal: 10,
                  sales: 0,
                  salesGoal: 2,
                  storedWeek: "2026-W33",
                  currentWeek: "2026-W33",
                  finalizedWeek: dj.finalizedWeekId)
        )
        try expect(!secondDevice.shouldFinalize, "A second device must not finalize the week again")
        try expect(secondDevice.newStreak == 5, "A second device must preserve the diamond streak")

        let duplicateOldWeek = WeeklyRolloverPolicy.evaluate(
            input(streak: 5,
                  quotes: 10,
                  quotesGoal: 10,
                  sales: 2,
                  salesGoal: 2,
                  finalizedWeek: "2026-W32")
        )
        try expect(!duplicateOldWeek.shouldFinalize, "An already-finalized week must be idempotent")
        try expect(duplicateOldWeek.newStreak == 5, "Duplicate processing must not add another trophy")

        // Two devices read revision 0 at the same time. Device A saves first.
        // Device B's stale save is rejected, then its retry sees the finalized cloud state.
        var cloud = SimulatedCloudRecord(revision: 0,
                                         weekId: "2026-W32",
                                         finalizedWeekId: nil,
                                         streak: 4,
                                         quotes: 10,
                                         sales: 2)
        let deviceARead = cloud
        let deviceBRead = cloud
        let deviceAResult = WeeklyRolloverPolicy.evaluate(
            input(streak: deviceARead.streak,
                  quotes: deviceARead.quotes,
                  quotesGoal: 10,
                  sales: deviceARead.sales,
                  salesGoal: 2,
                  storedWeek: deviceARead.weekId,
                  finalizedWeek: deviceARead.finalizedWeekId)
        )
        var deviceAWrite = deviceARead
        deviceAWrite.weekId = "2026-W33"
        deviceAWrite.finalizedWeekId = deviceAResult.finalizedWeekId
        deviceAWrite.streak = deviceAResult.newStreak
        deviceAWrite.quotes = 0
        deviceAWrite.sales = 0
        try expect(saveIfUnchanged(deviceAWrite, readRevision: deviceARead.revision, cloud: &cloud),
                   "Device A should save the first finalization")

        try expect(!saveIfUnchanged(deviceBRead, readRevision: deviceBRead.revision, cloud: &cloud),
                   "Device B's stale save should be rejected")
        let deviceBRetry = WeeklyRolloverPolicy.evaluate(
            input(streak: cloud.streak,
                  quotes: cloud.quotes,
                  quotesGoal: 10,
                  sales: cloud.sales,
                  salesGoal: 2,
                  storedWeek: cloud.weekId,
                  finalizedWeek: cloud.finalizedWeekId)
        )
        try expect(!deviceBRetry.shouldFinalize && deviceBRetry.newStreak == 5,
                   "Device B's retry should preserve Device A's single award")

        print("✅ D.J. reaches diamond (streak 5)")
        print("✅ Deanna reaches two trophies (streak 2)")
        print("✅ Ron resets to zero")
        print("✅ Dimitri resets to zero")
        print("✅ Simultaneous devices: stale save rejected and retry does not award twice")
        print("✅ Already-finalized week remains unchanged")
    }
}
