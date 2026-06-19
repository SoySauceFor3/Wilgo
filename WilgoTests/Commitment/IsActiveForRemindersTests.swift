import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Tests the single goal-met∕continue rule (`Commitment.isActiveForReminders`) and that the
/// `*WithBehind` helpers honor it — so Stage, the Live Activity, and the widget all agree.
@Suite(.serialized)
final class IsActiveForRemindersTests {
    // Whole-day slot (start == end == midnight) is always inside its window regardless of wall clock.
    private func makeWholeDaySlot() -> Slot {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = 0
        let midnight = Calendar.current.date(from: c)!
        return Slot(start: midnight, end: midnight)
    }

    @MainActor
    private func makeCommitment(
        title: String,
        targetCount: Int,
        continueAfterGoalMet: Bool,
        checkInCount: Int,
        in ctx: ModelContext
    ) -> Commitment {
        let slot = makeWholeDaySlot()
        ctx.insert(slot)
        let anchor = Calendar.current.startOfDay(for: Date())
        let c = Commitment(
            title: title,
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: targetCount),
            isRemindersEnabled: true,
            continueRemindersAfterGoalMet: continueAfterGoalMet
        )
        ctx.insert(c)
        for _ in 0..<checkInCount {
            let checkIn = CheckIn(commitment: c, createdAt: Date())
            ctx.insert(checkIn)
            c.checkIns.append(checkIn)
        }
        return c
    }

    // MARK: - isActiveForReminders

    @Test("goal not met → active")
    @MainActor func goalNotMet_active() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "A", targetCount: 2, continueAfterGoalMet: false, checkInCount: 0,
            in: container.mainContext)
        #expect(c.isActiveForReminders(now: Date()))
    }

    @Test("goal met + continue off → inactive")
    @MainActor func goalMet_continueOff_inactive() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "A", targetCount: 1, continueAfterGoalMet: false, checkInCount: 1,
            in: container.mainContext)
        #expect(!c.isActiveForReminders(now: Date()))
    }

    @Test("goal met + continue on → active")
    @MainActor func goalMet_continueOn_active() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "A", targetCount: 1, continueAfterGoalMet: true, checkInCount: 1,
            in: container.mainContext)
        #expect(c.isActiveForReminders(now: Date()))
    }

    // MARK: - currentWithBehind honors the rule (the bug fix)

    @Test("currentWithBehind excludes a goal-met commitment whose slot is still open")
    @MainActor func currentWithBehind_excludesGoalMet() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // A: target 1, checked in once → goal met, continue off. Slot is whole-day (still open).
        let a = makeCommitment(
            title: "A", targetCount: 1, continueAfterGoalMet: false, checkInCount: 1, in: ctx)
        // B: target 2, no check-ins → not met, still current.
        let b = makeCommitment(
            title: "B", targetCount: 2, continueAfterGoalMet: false, checkInCount: 0, in: ctx)

        let current = CommitmentAndSlot.currentWithBehind(commitments: [a, b], now: Date())
        #expect(current.map(\.commitment.title) == ["B"])
    }

    @Test("currentWithBehind keeps a goal-met commitment when continueRemindersAfterGoalMet is on")
    @MainActor func currentWithBehind_keepsGoalMetWhenContinue() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let a = makeCommitment(
            title: "A", targetCount: 1, continueAfterGoalMet: true, checkInCount: 1, in: ctx)

        let current = CommitmentAndSlot.currentWithBehind(commitments: [a], now: Date())
        #expect(current.map(\.commitment.title) == ["A"])
    }
}
