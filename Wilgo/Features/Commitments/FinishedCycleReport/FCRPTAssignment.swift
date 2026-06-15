import Foundation

/// Assigns free Positivity Tokens to failed cycles in the FCR.
///
/// Each failed cycle needs exactly one PT to close. Free tokens (those not yet
/// consumed by any cycle) are assigned oldest-first across failed cycles that
/// don't already have one. Cycles with an existing assignment keep it.
enum FCRPTAssignment {
    /// - Parameters:
    ///   - failedCycleIDs: ids of cycles currently in the failed state.
    ///   - freeTokens: tokens available for assignment (not consumed elsewhere).
    ///   - alreadyAssigned: cycle id → token already assigned this session.
    /// - Returns: cycle id → assigned token, including prior assignments.
    static func autoAssign(
        failedCycleIDs: [String],
        freeTokens: [PositivityToken],
        alreadyAssigned: [String: PositivityToken] = [:]
    ) -> [String: PositivityToken] {
        var result = alreadyAssigned

        // Tokens already spoken for by existing assignments can't be reused.
        let usedTokenIDs = Set(alreadyAssigned.values.map(\.id))
        var available =
            freeTokens
            .filter { !usedTokenIDs.contains($0.id) }
            .sorted { $0.createdAt < $1.createdAt }

        for cycleID in failedCycleIDs where result[cycleID] == nil {
            guard !available.isEmpty else { break }
            result[cycleID] = available.removeFirst()
        }
        return result
    }
}
