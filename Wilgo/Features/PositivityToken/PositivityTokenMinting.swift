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
            guard checkIn.positivityToken == nil else { continue }
            let elapsed = now.timeIntervalSince(checkIn.createdAt)
            guard elapsed >= 0, elapsed <= windowAfterCheckIn else { continue }
            return checkIn
        }
        return nil
    }
}
