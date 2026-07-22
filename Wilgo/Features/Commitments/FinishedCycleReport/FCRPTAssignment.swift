import Foundation

/// Assigns free Positivity Tokens to PT-requiring cycles in the FCR.
///
/// Each eligible cycle (a failed cycle whose outcome requires a PT) needs exactly
/// one PT to close. Free tokens (those not yet consumed by any cycle) are assigned
/// oldest-first across eligible cycles that don't already have one. Cycles with an
/// existing assignment keep it.
enum FCRPTAssignment {
    /// - Parameters:
    ///   - eligibleCycleIDs: ids of cycles that currently require a PT.
    ///   - freeTokens: tokens available for assignment (not consumed elsewhere).
    ///   - alreadyAssigned: cycle id → token already assigned this session.
    /// - Returns: cycle id → assigned token, including prior assignments.
    static func autoAssign(
        eligibleCycleIDs: [String],
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

        for cycleID in eligibleCycleIDs where result[cycleID] == nil {
            guard !available.isEmpty else { break }
            result[cycleID] = available.removeFirst()
        }
        return result
    }
}
