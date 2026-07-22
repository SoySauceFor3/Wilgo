import Foundation
import SwiftData
import Testing
@testable import Wilgo

extension SlotOccurrenceSuite {
@Suite(.serialized)
final class SlotOccurrenceTests {
    // MARK: - Helpers
    @MainActor
    private func makeSlot(
        startHour: Int, endHour: Int,
        recurrence: SlotRecurrence = .everyDay,
        in ctx: ModelContext
    ) -> Slot {
        let anchor = testDate(year: 2026, month: 1, day: 1)
        let slot = Slot(
            start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour), recurrence: recurrence)
        let commitment = Commitment(
            title: "Test",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1)
        )
        ctx.insert(commitment)
        ctx.insert(slot)
        return slot
    }

    // MARK: - occurrence(on:) construction + recurrence guard (Q1)

    @Test("everyDay slot: occurrence(on:) is non-nil for any day")
    @MainActor func everyDay_occurrenceNonNil() throws {
        let container = try makeTestContainer()
        let slot = makeSlot(startHour: 9, endHour: 11, in: container.mainContext)

        let day = testDate(year: 2026, month: 3, day: 5)
        #expect(slot.occurrence(on: day) != nil)
    }

    @Test("specific-weekday slot: occurrence(on:) is nil on an excluded day (Q1 guard)")
    @MainActor func specificWeekday_occurrenceNilOnExcludedDay() throws {
        let container = try makeTestContainer()
        // 2026-03-05 is a Thursday (weekday 5). Schedule only Mondays (weekday 2).
        let monday = SlotRecurrence.specificWeekdays([2])
        let slot = makeSlot(startHour: 9, endHour: 11, recurrence: monday, in: container.mainContext)

        let thursday = testDate(year: 2026, month: 3, day: 5)
        #expect(Calendar.current.component(.weekday, from: thursday) == 5)
        #expect(slot.occurrence(on: thursday) == nil)

        let monday2 = testDate(year: 2026, month: 3, day: 9)  // a Monday
        #expect(Calendar.current.component(.weekday, from: monday2) == 2)
        #expect(slot.occurrence(on: monday2) != nil)
    }

    // MARK: - Computed start/end — normal window

    @Test("normal window: start/end resolve onto the given psychDay")
    @MainActor func normal_startEnd() throws {
        let container = try makeTestContainer()
        let slot = makeSlot(startHour: 9, endHour: 11, in: container.mainContext)

        let day = testDate(year: 2026, month: 3, day: 5)
        let occ = try #require(slot.occurrence(on: day))

        #expect(occ.start == testDate(year: 2026, month: 3, day: 5, hour: 9))
        #expect(occ.end == testDate(year: 2026, month: 3, day: 5, hour: 11))
    }

    // MARK: - Computed start/end — cross-midnight window

    @Test("cross-midnight window: end falls on the following calendar day")
    @MainActor func crossMidnight_endNextDay() throws {
        let container = try makeTestContainer()
        // 11pm–1am
        let slot = makeSlot(startHour: 23, endHour: 1, in: container.mainContext)

        let day = testDate(year: 2025, month: 12, day: 31)
        let occ = try #require(slot.occurrence(on: day))

        #expect(occ.start == testDate(year: 2025, month: 12, day: 31, hour: 23))
        #expect(occ.end == testDate(year: 2026, month: 1, day: 1, hour: 1))
    }

    // MARK: - remainingFraction

    @Test("remainingFraction: midpoint of a normal window is ~0.5")
    @MainActor func remainingFraction_midpoint() throws {
        let container = try makeTestContainer()
        let slot = makeSlot(startHour: 9, endHour: 11, in: container.mainContext)
        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))

        let mid = testDate(year: 2026, month: 3, day: 5, hour: 10)
        #expect(abs(occ.remainingFraction(at: mid) - 0.5) < 0.001)
    }

    @Test("remainingFraction: clamps to [0, 1] outside the window")
    @MainActor func remainingFraction_clamps() throws {
        let container = try makeTestContainer()
        let slot = makeSlot(startHour: 9, endHour: 11, in: container.mainContext)
        let occ = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))

        let before = testDate(year: 2026, month: 3, day: 5, hour: 8)
        let after = testDate(year: 2026, month: 3, day: 5, hour: 12)
        #expect(occ.remainingFraction(at: before) == 1)
        #expect(occ.remainingFraction(at: after) == 0)
    }

    @Test("remainingFraction: cross-midnight window handled via concrete datetimes")
    @MainActor func remainingFraction_crossMidnight() throws {
        let container = try makeTestContainer()
        // 11pm–1am, 2-hour window. At 12am (midnight), 1 hour remains → 0.5.
        let slot = makeSlot(startHour: 23, endHour: 1, in: container.mainContext)
        let occ = try #require(slot.occurrence(on: testDate(year: 2025, month: 12, day: 31)))

        let midnight = testDate(year: 2026, month: 1, day: 1, hour: 0)
        #expect(abs(occ.remainingFraction(at: midnight) - 0.5) < 0.001)
    }

    // MARK: - Equatable

    @Test("Equatable: same slot + same day are equal; different day not equal")
    @MainActor func equatable() throws {
        let container = try makeTestContainer()
        let slot = makeSlot(startHour: 9, endHour: 11, in: container.mainContext)

        let occA = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        let occB = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 5)))
        let occC = try #require(slot.occurrence(on: testDate(year: 2026, month: 3, day: 6)))

        #expect(occA == occB)
        #expect(occA != occC)
    }
}
}
