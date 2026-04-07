import Foundation
import SwiftData

enum PositivityTokenMinting {
    /// Remaining mint slots: max(0, totalCheckIns - totalPTCreated).
    static func mintCapacity(tokenCount: Int, checkInCount: Int) -> Int {
        max(0, checkInCount - tokenCount)
    }

    /// True when the user may mint at least one more PT.
    static func canMint(tokenCount: Int, checkInCount: Int) -> Bool {
        mintCapacity(tokenCount: tokenCount, checkInCount: checkInCount) > 0
    }

    /// Total number of PositivityToken records in the store.
    static func fetchTotalTokenCount(context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<PositivityToken>())
    }

    /// Total number of CheckIn records in the store.
    static func fetchTotalCheckInCount(context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<CheckIn>())
    }
}
