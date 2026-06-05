import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentSlotStatusTests {
    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = minute
        c.second = 0
        return Calendar.current.date(from: c)!
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

    // MARK: - kind classification

    @Test("now inside a slot's window → kind is .insideSlot; remaining includes the current slot")
    @MainActor func nowInsideSlot_kindIsInsideSlot() throws {
        let container = try makeTestContainer()
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
    @MainActor func nowBeforeFirstSlotToday_kindIsBeforeNextToday() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(14, 16, nil)], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        let status = c.slotStatus(now: now)

        #expect(status.kind == .beforeNextToday)
        #expect(status.remainingSlots.count == 1)
        let first = try #require(status.remainingSlots.first)
        #expect(first.start > now)
    }

    @Test("all of today's slots have passed (daily cycle) → kind is .noSlotToday, remainingSlots empty")
    @MainActor func allSlotsTodayPassed_kindIsNoSlotToday() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, nil)], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 12)

        let status = c.slotStatus(now: now)

        #expect(status.kind == .noSlotToday)
        #expect(status.remainingSlots.isEmpty)
    }

    // MARK: - mode-agnostic

    @Test("target disabled and target enabled produce same remainingSlots and kind")
    @MainActor func targetDisabled_returnsSameAsModeOn() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let enabled = makeCommitment(slots: [(9, 11, nil)], targetMode: .on, cycleKind: .weekly, in: ctx)
        let disabled = makeCommitment(slots: [(9, 11, nil)], targetMode: .disabled, cycleKind: .weekly, in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let enabledStatus = enabled.slotStatus(now: now)
        let disabledStatus = disabled.slotStatus(now: now)

        #expect(enabledStatus.kind == disabledStatus.kind)
        #expect(enabledStatus.remainingSlots.count == disabledStatus.remainingSlots.count)
        for (lhs, rhs) in zip(enabledStatus.remainingSlots, disabledStatus.remainingSlots) {
            #expect(lhs.start == rhs.start)
            #expect(lhs.end == rhs.end)
        }
    }

    // MARK: - snooze

    @Test("current slot snoozed → excluded from remainingSlots; future occurrences remain")
    @MainActor func currentSlotSnoozed_excludedFromRemaining() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, nil)], cycleKind: .weekly, in: ctx)
        let slot = try #require(c.slots.first)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let psychDay = date(year: 2026, month: 3, day: 5)
        ctx.insert(SlotSnooze(slot: slot, psychDay: psychDay, snoozedAt: now))

        let status = c.slotStatus(now: now)

        #expect(status.remainingSlots.contains(where: { $0.start <= now && $0.end >= now }) == false)
        #expect(status.remainingSlots.contains(where: { $0.start > now }))
    }

    // MARK: - saturation

    @Test("current slot saturated by in-window check-ins → excluded from remainingSlots")
    @MainActor func currentSlotSaturatedByCheckIns_excludedFromRemaining() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, 1)], in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let status = c.slotStatus(now: now)

        #expect(status.remainingSlots.contains(where: { $0.start <= now && $0.end >= now }) == false)
    }

    // MARK: - forward projection

    @Test("forward projection: future `now` returns deterministic future-time slots/kind")
    @MainActor func forwardProjection_futureNow_returnsFutureSlots() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(14, 16, nil)], in: ctx)

        let testNow = date(year: 2026, month: 3, day: 5, hour: 10)
        let morning = c.slotStatus(now: testNow)
        #expect(morning.kind == .beforeNextToday)

        let projected = date(year: 2026, month: 3, day: 5, hour: 15)
        let inside = c.slotStatus(now: projected)
        #expect(inside.kind == .insideSlot)
        let insideFirst = try #require(inside.remainingSlots.first)
        #expect(insideFirst.start <= projected)
        #expect(insideFirst.end >= projected)
    }

    // MARK: - carry-over / cross-midnight

    @Test("carry-over slot spanning midnight is included when now is in early-morning portion")
    @MainActor func carryOverSlot_includedWhenSpanningMidnight() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(23, 2, nil)], in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 1)
        let status = c.slotStatus(now: now)

        #expect(status.kind == .insideSlot)
        let first = try #require(status.remainingSlots.first)
        let todayPsychDay = Calendar.current.startOfDay(for: now)
        #expect(first.start < todayPsychDay)
        #expect(first.end > now)
    }
}
