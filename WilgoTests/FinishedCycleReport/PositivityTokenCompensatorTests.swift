import Foundation
import Testing

@testable import Wilgo

private func date(year: Int, month: Int, day: Int) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = 0
    comps.minute = 0
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

@Suite("PositivityTokenCompensator")
struct PositivityTokenCompensatorTests {
    @Test("compensates one token per missed check-in")
    func compensatesPerMissedCheckIn() {
        let cycleEnd = date(year: 2026, month: 3, day: 10)
        let needs = [
            PositivityCycleNeed(
                cycleID: "cycle-1",
                commitmentID: "c1",
                cycleEndPsychDay: cycleEnd,
                missingCheckIns: 2
            )
        ]
        let t1 = PositivityToken(reason: "t1", createdAt: date(year: 2026, month: 2, day: 1))
        let t2 = PositivityToken(reason: "t2", createdAt: date(year: 2026, month: 2, day: 2))
        let t3 = PositivityToken(reason: "t3", createdAt: date(year: 2026, month: 2, day: 3))

        let aided = PositivityTokenCompensator.apply(
            cycleNeeds: needs,
            tokens: [t1, t2, t3],
            monthlyCap: 10
        )

        #expect(aided["cycle-1"] == 2)
        if case .active = t3.status {
            // expected
        } else {
            Issue.record("t3 should remain active")
        }
        #expect(t1.status == .used)
        #expect(t1.dayOfStatus == date(year: 2026, month: 3, day: 9))
        #expect(t2.status == .used)
        #expect(t2.dayOfStatus == date(year: 2026, month: 3, day: 9))
    }

    @Test("allocates FCFS by cycle end psych day")
    func allocatesFcfs() {
        let needs = [
            PositivityCycleNeed(
                cycleID: "older-cycle",
                commitmentID: "a",
                cycleEndPsychDay: date(year: 2026, month: 3, day: 10),
                missingCheckIns: 1
            ),
            PositivityCycleNeed(
                cycleID: "newer-cycle",
                commitmentID: "b",
                cycleEndPsychDay: date(year: 2026, month: 3, day: 11),
                missingCheckIns: 1
            ),
        ]
        let token = PositivityToken(reason: "single", createdAt: date(year: 2026, month: 2, day: 1))

        let aided = PositivityTokenCompensator.apply(
            cycleNeeds: needs,
            tokens: [token],
            monthlyCap: 10
        )

        #expect(aided["older-cycle"] == 1)
        #expect(aided["newer-cycle"] == nil)
    }

    @Test("cycle end on month boundary counts toward previous month cap")
    func monthBoundaryUsesPreviousMonth() {
        let cycleEndExclusive = date(year: 2026, month: 3, day: 1)  // usage day becomes Feb 28
        let needs = [
            PositivityCycleNeed(
                cycleID: "boundary-cycle",
                commitmentID: "a",
                cycleEndPsychDay: cycleEndExclusive,
                missingCheckIns: 1
            )
        ]
        let alreadyUsed = PositivityToken(reason: "used", createdAt: date(year: 2026, month: 1, day: 1))
        alreadyUsed.status = .used
        alreadyUsed.dayOfStatus = date(year: 2026, month: 2, day: 5)
        let active = PositivityToken(reason: "active", createdAt: date(year: 2026, month: 2, day: 6))

        let aided = PositivityTokenCompensator.apply(
            cycleNeeds: needs,
            tokens: [alreadyUsed, active],
            monthlyCap: 1
        )

        #expect(aided["boundary-cycle"] == nil)
        if case .active = active.status {
            // expected
        } else {
            Issue.record("active token should remain active when cap is exhausted")
        }
    }
}
