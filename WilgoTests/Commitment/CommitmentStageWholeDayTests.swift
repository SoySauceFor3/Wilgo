import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Commitment.stageStatus - whole-day carry-over", .serialized)
final class CommitmentStageWholeDayTests {

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, SlotSnooze.self, Tag.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

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

    @Test("5am whole-day daily slot is current at 1am after creation day")
    @MainActor func fiveAMWholeDaySlot_isCurrentAtOneAM() throws {
        let container = try makeContainer()
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

        let now = date(year: 2026, month: 3, day: 5, hour: 1)
        let status = commitment.stageStatus(now: now)

        #expect(status.category == .current)
        #expect(status.nextUpSlots.first?.start == date(year: 2026, month: 3, day: 4, hour: 5))
        #expect(status.nextUpSlots.first?.end == date(year: 2026, month: 3, day: 5, hour: 5))
    }

    @Test("target-disabled 5am whole-day daily slot is current at 1am")
    @MainActor func targetDisabledFiveAMWholeDaySlot_isCurrentAtOneAM() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 5), end: tod(hour: 5), recurrence: .everyDay)
        let commitment = Commitment(
            title: "Whole day",
            createdAt: date(year: 2026, month: 3, day: 1, hour: 9),
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1, isEnabled: false)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let now = date(year: 2026, month: 3, day: 5, hour: 1)
        let status = commitment.stageStatus(now: now)

        #expect(status.category == .current)
        #expect(status.nextUpSlots.first?.start == date(year: 2026, month: 3, day: 4, hour: 5))
        #expect(status.nextUpSlots.first?.end == date(year: 2026, month: 3, day: 5, hour: 5))
    }

    @Test("23-to-2 cross-midnight daily slot is current at 1am")
    @MainActor func crossMidnightSlot_isCurrentAtOneAM() throws {
        let container = try makeContainer()
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

        let now = date(year: 2026, month: 3, day: 5, hour: 1)
        let status = commitment.stageStatus(now: now)

        #expect(status.category == .current)
        #expect(status.nextUpSlots.first?.start == date(year: 2026, month: 3, day: 4, hour: 23))
        #expect(status.nextUpSlots.first?.end == date(year: 2026, month: 3, day: 5, hour: 2))
    }

    @Test("target-disabled 23-to-2 cross-midnight daily slot is current at 1am")
    @MainActor func targetDisabledCrossMidnightSlot_isCurrentAtOneAM() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 23), end: tod(hour: 2), recurrence: .everyDay)
        let commitment = Commitment(
            title: "Night slot",
            createdAt: date(year: 2026, month: 3, day: 1, hour: 9),
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1, isEnabled: false)
        )
        ctx.insert(commitment)
        ctx.insert(slot)

        let now = date(year: 2026, month: 3, day: 5, hour: 1)
        let status = commitment.stageStatus(now: now)

        #expect(status.category == .current)
        #expect(status.nextUpSlots.first?.start == date(year: 2026, month: 3, day: 4, hour: 23))
        #expect(status.nextUpSlots.first?.end == date(year: 2026, month: 3, day: 5, hour: 2))
    }
}
