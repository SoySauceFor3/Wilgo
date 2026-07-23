import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Tests the single reminders gate (`Commitment.isActiveForReminders`: reminders-enabled +
/// goal-met∕continue rule) and that placement (`stageBuckets` over the filtered characteristics)
/// honors it — so Stage, the Live Activity, and the widget all agree.
extension SchedulingSuite {
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
        remindersEnabled: Bool = true,
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
            isRemindersEnabled: remindersEnabled,
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

    /// Mirrors the production boundary: filter on the gate, then characterize, then place.
    @MainActor
    private func placed(_ commitments: [Commitment], now: Date) -> [CommitmentCharacteristics] {
        let characteristics = commitments
            .filter { $0.isActiveForReminders(now: now) }
            .map { StageCharacterization.characteristics(of: $0, now: now) }
        let buckets = StageCharacterization.stageBuckets(characteristics: characteristics, now: now, n: 3)
        return buckets.current + buckets.upcoming + buckets.catchUp
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

    @Test("reminders disabled → inactive even when goal is unmet")
    @MainActor func remindersDisabled_inactive() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "A", targetCount: 2, continueAfterGoalMet: false, checkInCount: 0,
            remindersEnabled: false, in: container.mainContext)
        #expect(!c.isActiveForReminders(now: Date()))
    }

    // MARK: - placement honors the rule (the bug fix)

    @Test("placement excludes a goal-met commitment whose slot is still open")
    @MainActor func placement_excludesGoalMet() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // A: target 1, checked in once → goal met, continue off. Slot is whole-day (still open).
        let a = makeCommitment(
            title: "A", targetCount: 1, continueAfterGoalMet: false, checkInCount: 1, in: ctx)
        // B: target 2, no check-ins → not met, still current.
        let b = makeCommitment(
            title: "B", targetCount: 2, continueAfterGoalMet: false, checkInCount: 0, in: ctx)

        #expect(placed([a, b], now: Date()).map(\.commitment.title) == ["B"])
    }

    @Test("placement keeps a goal-met commitment when continueRemindersAfterGoalMet is on")
    @MainActor func placement_keepsGoalMetWhenContinue() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let a = makeCommitment(
            title: "A", targetCount: 1, continueAfterGoalMet: true, checkInCount: 1, in: ctx)

        #expect(placed([a], now: Date()).map(\.commitment.title) == ["A"])
    }
    /// Goal-met commitment with a slot that starts later today (so without the gate it would land in
    /// Upcoming). The gate must still exclude it from every bucket.
    @Test("placement excludes a goal-met commitment with a later-today slot")
    @MainActor func placement_excludesGoalMetUpcoming() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // now = 06:00, slot starts 14:00 → later today → would be Upcoming.
        let slot = Slot(start: timeOfDay(hour: 14), end: timeOfDay(hour: 15))
        ctx.insert(slot)
        let now = Calendar.current.startOfDay(for: Date()).addingTimeInterval(6 * 3600)
        let anchor = Calendar.current.startOfDay(for: now)
        let c = Commitment(
            title: "A",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: true,
            continueRemindersAfterGoalMet: false
        )
        ctx.insert(c)
        let checkIn = CheckIn(commitment: c, createdAt: now)
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)

        #expect(placed([c], now: now).isEmpty)
    }
}
}
