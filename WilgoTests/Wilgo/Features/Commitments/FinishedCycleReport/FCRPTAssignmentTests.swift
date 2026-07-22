import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension FinishedCycleReportSuite {
@MainActor
struct FCRPTAssignmentTests {
    private func freeToken(_ reason: String, _ created: Date) -> PositivityToken {
        PositivityToken(reason: reason, createdAt: created)
    }

    private func day(_ d: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: TimeInterval(d) * 86400)
    }

    // MARK: - autoAssign

    @Test func noFreeTokens_assignsNothing() {
        let result = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: ["a", "b"],
            freeTokens: []
        )
        #expect(result.isEmpty)
    }

    @Test func noEligibleCycles_assignsNothing() {
        // e.g. all failed cycles are labelled Intended/Excused (no-PT outcomes),
        // so the eligible set is empty even though free tokens exist.
        let t1 = freeToken("t1", day(1))

        let result = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: [],
            freeTokens: [t1]
        )

        #expect(result.isEmpty)
    }

    @Test func assignsOldestTokenFirst() {
        let newer = freeToken("newer", day(10))
        let older = freeToken("older", day(1))

        let result = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: ["onlyCycle"],
            freeTokens: [newer, older]
        )

        #expect(result["onlyCycle"]?.reason == "older")
    }

    @Test func assignsOnlyToEligibleCycles() {
        // Free tokens available, but only one cycle is eligible (requires a PT);
        // the other is not in the eligible set and must get nothing.
        let t1 = freeToken("t1", day(1))
        let t2 = freeToken("t2", day(2))

        let result = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: ["eligible"],
            freeTokens: [t1, t2]
        )

        #expect(result.count == 1)
        #expect(result["eligible"]?.reason == "t1")
        #expect(result["ineligible"] == nil)
    }

    @Test func assignsOneTokenPerCycle() {
        let t1 = freeToken("t1", day(1))
        let t2 = freeToken("t2", day(2))
        let t3 = freeToken("t3", day(3))

        let result = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: ["c1", "c2"],
            freeTokens: [t1, t2, t3]
        )

        #expect(result.count == 2)
        // Oldest two assigned, one per cycle, no token reused
        let assignedReasons = Set(result.values.map(\.reason))
        #expect(assignedReasons == Set(["t1", "t2"]))
    }

    @Test func fewerTokensThanCycles_assignsWhatItCan() {
        let t1 = freeToken("t1", day(1))

        let result = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: ["c1", "c2", "c3"],
            freeTokens: [t1]
        )

        #expect(result.count == 1)
    }

    @Test func doesNotReassignAlreadyAssignedCycles() {
        let existing = freeToken("existing", day(1))
        let fresh = freeToken("fresh", day(2))

        let result = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: ["c1", "c2"],
            freeTokens: [fresh],
            alreadyAssigned: ["c1": existing]
        )

        // c1 keeps its existing token; c2 gets the fresh one
        #expect(result["c1"]?.reason == "existing")
        #expect(result["c2"]?.reason == "fresh")
    }

    @Test func tokenFreedFromOneCycleIsAssignableToAnother() {
        // Simulates a label change: cycle "a" was eligible and held the token,
        // then flipped to a no-PT outcome (dropped from alreadyAssigned by the
        // view's release loop). Re-running autoAssign with only "b" eligible must
        // hand that freed token to "b".
        let token = freeToken("shared", day(1))

        let result = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: ["b"],
            freeTokens: [token],
            alreadyAssigned: [:]
        )

        #expect(result["b"]?.reason == "shared")
        #expect(result["a"] == nil)
    }
}
}
