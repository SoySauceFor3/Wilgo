import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentSlotStatusWholeDayTests {
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

    // MARK: - 5am whole-day slot

    @Test("5am whole-day daily slot is .insideSlot at 1am")
    @MainActor func fiveAMWholeDaySlot_isInsideSlotAtOneAM() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 5), end: tod(hour: 5), recurrence: .everyDay)
        let commitment = Commitment(
            title: "Whole day",
            createdAt: date(year: 2026, month: 3, day: 1, hour: 9),
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let slotSt = commitment.slotStatus(now: date(year: 2026, month: 3, day: 5, hour: 1))

        #expect(slotSt.kind == .insideSlot)
        #expect(slotSt.remainingSlots.first?.start == date(year: 2026, month: 3, day: 4, hour: 5))
        #expect(slotSt.remainingSlots.first?.end == date(year: 2026, month: 3, day: 5, hour: 5))
    }

    @Test("target-disabled 5am whole-day daily slot is .insideSlot at 1am")
    @MainActor func targetDisabledFiveAMWholeDaySlot_isInsideSlotAtOneAM() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 5), end: tod(hour: 5), recurrence: .everyDay)
        let commitment = Commitment(
            title: "Whole day",
            createdAt: date(year: 2026, month: 3, day: 1, hour: 9),
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1, mode: .disabled)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let slotSt = commitment.slotStatus(now: date(year: 2026, month: 3, day: 5, hour: 1))

        #expect(slotSt.kind == .insideSlot)
        #expect(slotSt.remainingSlots.first?.start == date(year: 2026, month: 3, day: 4, hour: 5))
        #expect(slotSt.remainingSlots.first?.end == date(year: 2026, month: 3, day: 5, hour: 5))
    }

    // MARK: - cross-midnight slot

    @Test("23-to-2 cross-midnight daily slot is .insideSlot at 1am")
    @MainActor func crossMidnightSlot_isInsideSlotAtOneAM() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 23), end: tod(hour: 2), recurrence: .everyDay)
        let commitment = Commitment(
            title: "Night slot",
            createdAt: date(year: 2026, month: 3, day: 1, hour: 9),
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let slotSt = commitment.slotStatus(now: date(year: 2026, month: 3, day: 5, hour: 1))

        #expect(slotSt.kind == .insideSlot)
        #expect(slotSt.remainingSlots.first?.start == date(year: 2026, month: 3, day: 4, hour: 23))
        #expect(slotSt.remainingSlots.first?.end == date(year: 2026, month: 3, day: 5, hour: 2))
    }

    @Test("target-disabled 23-to-2 cross-midnight daily slot is .insideSlot at 1am")
    @MainActor func targetDisabledCrossMidnightSlot_isInsideSlotAtOneAM() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 23), end: tod(hour: 2), recurrence: .everyDay)
        let commitment = Commitment(
            title: "Night slot",
            createdAt: date(year: 2026, month: 3, day: 1, hour: 9),
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1, mode: .disabled)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let slotSt = commitment.slotStatus(now: date(year: 2026, month: 3, day: 5, hour: 1))

        #expect(slotSt.kind == .insideSlot)
        #expect(slotSt.remainingSlots.first?.start == date(year: 2026, month: 3, day: 4, hour: 23))
        #expect(slotSt.remainingSlots.first?.end == date(year: 2026, month: 3, day: 5, hour: 2))
    }
}
