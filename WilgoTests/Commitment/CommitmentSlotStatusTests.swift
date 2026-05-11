import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite("Commitment - Slot Status", .serialized)
final class CommitmentSlotStatusTests {

    // MARK: - Helpers

    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1; c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute; c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        return try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    @MainActor
    private func makeCommitment(
        slots slotDefs: [(start: Int, end: Int, maxCheckIns: Int?)],
        targetCount: Int = 3,
        targetMode: TargetMode = .on,
        cycleKind: CycleKind = .daily,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map {
            Slot(start: tod(hour: $0.start), end: tod(hour: $0.end), maxCheckIns: $0.maxCheckIns)
        }
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: cycleKind, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: targetCount, mode: targetMode)
        )
        ctx.insert(c)
        slots.forEach { ctx.insert($0) }
        return c
    }

    @MainActor
    private func addCheckIn(to c: Commitment, at date: Date, in ctx: ModelContext) {
        let checkIn = CheckIn(commitment: c, createdAt: date)
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
    }

    // MARK: - Tests

    @Test("now inside a slot's window → kind is .insideSlot; remaining includes the current slot")
    @MainActor func slotStatus_nowInsideSlot_kindIsInsideSlot_remainingIncludesCurrentSlot() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, nil)], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        let status = c.slotStatus(now: now)

        #expect(status.kind == .insideSlot)
        #expect(status.remainingSlots.count == 1)
        let first = try #require(status.remainingSlots.first)
        #expect(first.start <= now)
        #expect(first.end >= now)
    }

    @Test("now before today's first slot → kind is .beforeNextToday")
    @MainActor func slotStatus_nowBeforeFirstSlotToday_kindIsBeforeNextToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(14, 16, nil)], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        let status = c.slotStatus(now: now)

        #expect(status.kind == .beforeNextToday)
        #expect(status.remainingSlots.count == 1)
        let first = try #require(status.remainingSlots.first)
        #expect(first.start > now)
    }

    @Test("all of today's slots have passed (daily cycle) → kind is .noSlotToday")
    @MainActor func slotStatus_allSlotsTodayPassed_kindIsNoSlotToday() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Daily cycle so that the cycle window IS the psych day. Otherwise tomorrow's
        // occurrence would show up in `remainingSlots` and the kind classification
        // would still be `.noSlotToday`, but we want to assert the list is empty too.
        let c = makeCommitment(slots: [(9, 11, nil)], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 12)

        let status = c.slotStatus(now: now)

        #expect(status.kind == .noSlotToday)
        #expect(status.remainingSlots.isEmpty)
    }

    @Test("current slot is snoozed → today's occurrence excluded; future occurrences remain")
    @MainActor func slotStatus_currentSlotSnoozed_excludedFromRemaining() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Weekly cycle so the cycle window spans multiple days. The single slot
        // definition (9-11) recurs every day of the week, giving us today's
        // occurrence plus future-day occurrences of the same slot. This exercises
        // that snooze is scoped per-occurrence (per-psychDay) and not per slot
        // definition: today's occurrence must be filtered out while tomorrow's
        // occurrence of the same slot must remain.
        let c = makeCommitment(slots: [(9, 11, nil)], cycleKind: .weekly, in: ctx)
        let slot = try #require(c.slots.first)

        // 2026-03-05 is a Thursday and lines up with the weekly cycle start
        // (reference psych day is 2026-01-01, also a Thursday — exactly 9 weeks
        // earlier), so 2026-03-06 falls in the same cycle window.
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let psychDay = date(year: 2026, month: 3, day: 5)
        let snooze = SlotSnooze(slot: slot, psychDay: psychDay, snoozedAt: now)
        ctx.insert(snooze)

        let status = c.slotStatus(now: now)

        // Today's snoozed occurrence (the one whose window contains `now`) must
        // be filtered out.
        #expect(status.remainingSlots.contains(where: { $0.start <= now && $0.end >= now }) == false)
        // A future-day occurrence of the same slot definition must still appear:
        // the snooze is scoped to today's psychDay only, per `Slot.isSnoozed(at:)`
        // / `SlotSnooze.slotPsychDay` semantics.
        #expect(status.remainingSlots.contains(where: { $0.start > now }))
    }

    @Test("current slot saturated by in-window check-ins → excluded from remainingSlots")
    @MainActor func slotStatus_currentSlotSaturatedByCheckIns_excludedFromRemaining() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Cap 1: a single in-window check-in saturates the slot.
        let c = makeCommitment(slots: [(9, 11, 1)], in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.slotStatus(now: now)

        // The saturated active slot must not appear in remainingSlots.
        #expect(status.remainingSlots.contains(where: { $0.start <= now && $0.end >= now }) == false)
    }

    @Test(
        "target disabled and target enabled produce same remainingSlots and kind (mode-agnostic)"
    )
    @MainActor func slotStatus_targetDisabled_returnsCycleRemaining_sameAsEnabled() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Use a weekly cycle so the cycle window is genuinely wider than the
        // psych-day window today's `targetDisabledStatus` reads. If `slotStatus`
        // were not mode-agnostic, the disabled-mode list would be a strict subset.
        let enabled = makeCommitment(
            slots: [(9, 11, nil)],
            targetMode: .on,
            cycleKind: .weekly,
            in: ctx
        )
        let disabled = makeCommitment(
            slots: [(9, 11, nil)],
            targetMode: .disabled,
            cycleKind: .weekly,
            in: ctx
        )

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let enabledStatus = enabled.slotStatus(now: now)
        let disabledStatus = disabled.slotStatus(now: now)

        #expect(enabledStatus.kind == disabledStatus.kind)
        #expect(enabledStatus.remainingSlots.count == disabledStatus.remainingSlots.count)
        // Compare element-wise by start/end since the two commitments have
        // independent Slot instances with their own IDs.
        for (lhs, rhs) in zip(enabledStatus.remainingSlots, disabledStatus.remainingSlots) {
            #expect(lhs.start == rhs.start)
            #expect(lhs.end == rhs.end)
        }
    }

    @Test("forward projection: future `now` returns deterministic future-time slots/kind")
    @MainActor func slotStatus_forwardProjection_futureNow_returnsFutureSlots() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Single afternoon slot, daily.
        let c = makeCommitment(slots: [(14, 16, nil)], in: ctx)

        // "Now" of the test: morning. The slot is later today → .beforeNextToday.
        let testNow = date(year: 2026, month: 3, day: 5, hour: 10)
        let morning = c.slotStatus(now: testNow)
        #expect(morning.kind == .beforeNextToday)
        let morningFirst = try #require(morning.remainingSlots.first)
        #expect(morningFirst.start > testNow)

        // Project forward to mid-slot. Function must behave deterministically and
        // classify the (future) time as inside the slot.
        let projected = date(year: 2026, month: 3, day: 5, hour: 15)
        let inside = c.slotStatus(now: projected)
        #expect(inside.kind == .insideSlot)
        let insideFirst = try #require(inside.remainingSlots.first)
        #expect(insideFirst.start <= projected)
        #expect(insideFirst.end >= projected)
    }

    @Test("carry-over slot spanning midnight is included when now is in early-morning portion")
    @MainActor func slotStatus_carryOverSlot_includedWhenSpanningMidnight() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        // Cross-midnight slot 23:00 → 02:00, every day.
        let c = makeCommitment(slots: [(23, 2, nil)], in: ctx)

        // Early-morning of Mar 5: the slot that started 23:00 on Mar 4 is still open.
        let now = date(year: 2026, month: 3, day: 5, hour: 1)
        let status = c.slotStatus(now: now)

        #expect(status.kind == .insideSlot)
        // The first remaining slot must be the carry-over occurrence whose start
        // is on the previous calendar day (before today's psych-day boundary).
        let first = try #require(status.remainingSlots.first)
        let todayPsychDay = Calendar.current.startOfDay(for: now)
        #expect(first.start < todayPsychDay)
        #expect(first.end > now)
    }
}
