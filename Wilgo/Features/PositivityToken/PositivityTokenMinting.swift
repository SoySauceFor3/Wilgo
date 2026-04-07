import Foundation
import SwiftData

enum PositivityTokenMinting {
    /// User may mint only within this interval after a check-in.
    private static let windowAfterCheckIn: TimeInterval = 60 * 60

    /// True when this check-in can sponsor a new positivity token at `now`.
    /// NOTE: The positivity-token ↔ check-in relationship has been removed (Commit 1).
    /// This function will be replaced with capacity-based logic in Commit 2.
    static func isCheckInSponsorable(checkIn: CheckIn, now: Date = Time.now()) -> Bool {
        let elapsed = now.timeIntervalSince(checkIn.createdAt)
        return elapsed >= 0 && elapsed <= windowAfterCheckIn
    }

    /// Oldest check-in that still has no linked token and is inside the mint window (FIFO).
    /// NOTE: Will be replaced with capacity-based logic in Commit 2.
    static func eligibleCheckIn(
        checkIns: [CheckIn],
        now: Date = Time.now()
    ) -> CheckIn? {
        checkIns.sorted(by: { $0.createdAt < $1.createdAt }).first {
            isCheckInSponsorable(checkIn: $0, now: now)
        }
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
