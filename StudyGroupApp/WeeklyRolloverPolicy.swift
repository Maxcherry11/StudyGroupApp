import Foundation

struct WeeklyRolloverPolicy {
    struct Input {
        let storedWeekId: String?
        let currentWeekId: String
        let lastFinalizedWeekId: String?
        let previousStreak: Int
        let quotes: Int
        let quotesGoal: Int
        let salesWTD: Int
        let salesWTDGoal: Int
    }

    struct Result: Equatable {
        let shouldFinalize: Bool
        let didWin: Bool
        let newStreak: Int
        let finalizedWeekId: String?
    }

    static func evaluate(_ input: Input) -> Result {
        guard let priorWeekId = input.storedWeekId,
              priorWeekId != input.currentWeekId,
              input.lastFinalizedWeekId != priorWeekId else {
            return Result(shouldFinalize: false,
                          didWin: false,
                          newStreak: input.previousStreak,
                          finalizedWeekId: input.lastFinalizedWeekId)
        }

        let quotesHit = input.quotesGoal > 0 && input.quotes >= input.quotesGoal
        let salesHit = input.salesWTDGoal > 0 && input.salesWTD >= input.salesWTDGoal
        let didWin = quotesHit || salesHit

        return Result(shouldFinalize: true,
                      didWin: didWin,
                      newStreak: didWin ? input.previousStreak + 1 : 0,
                      finalizedWeekId: priorWeekId)
    }
}
