import Foundation
import SwiftData

enum PositivityTokenMinting {
    /// User may mint only within this interval after a check-in.
    static let windowAfterCheckIn: TimeInterval = 60 * 60

    /// Oldest check-in that still has no linked token and is inside the mint window (FIFO).
    /// “No token” is `checkIn.positivityToken == nil` on the relationship inverse.
    static func eligibleCheckIn(
        checkIns: [CheckIn],
        now: Date = .now
    ) -> CheckIn? {
        for checkIn in checkIns.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard checkIn.isSponsorableForPositivityToken(now: now) else { continue }
            return checkIn
        }
        return nil
    }

    /// Seconds remaining in the mint window after `checkIn`, or `nil` if the window has closed.
    static func secondsRemainingInMintWindow(for checkIn: CheckIn, now: Date = .now)
        -> TimeInterval?
    {
        let remaining = windowAfterCheckIn - now.timeIntervalSince(checkIn.createdAt)
        return remaining > 0 ? remaining : nil
    }

    /// Only check-ins at or after this time can still be inside the mint window (used to avoid loading full history).
    static func recentCheckInsLowerBound(now: Date = .now) -> Date {
        now.addingTimeInterval(-windowAfterCheckIn)
    }

    /// Bounded fetch for eligibility checks (main context; call on the main actor).
    static func fetchRecentCheckInsForMint(context: ModelContext, now: Date = .now) throws
        -> [CheckIn]
    {
        let lowerBound = recentCheckInsLowerBound(now: now)
        var descriptor = FetchDescriptor<CheckIn>(
            predicate: #Predicate<CheckIn> { checkIn in
                checkIn.createdAt >= lowerBound
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        descriptor.fetchLimit = 500
        return try context.fetch(descriptor)
    }
}
