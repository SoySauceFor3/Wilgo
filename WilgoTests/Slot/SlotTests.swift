import Foundation
import Testing

@testable import Wilgo

// MARK: - Helpers

/// A time-of-day reference date. Only hour and minute are meaningful — the same
/// semantics HabitSlot uses for its start/end fields.
private func timeOfDay(hour: Int, minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = 2000
    comps.month = 1
    comps.day = 1
    comps.hour = hour
    comps.minute = minute
    comps.second = 0
    return Calendar.current.date(from: comps)!
}

@Suite("Slot tests")
struct SlotTests {

    @Suite("Slot — contains")
    struct SlotContainsTests {

        // MARK: contains(timeOfDay:)

        @Test("contains — same-day window includes boundaries and interior")
        @MainActor func contains_sameDay_includesBoundariesAndInterior() throws {
            let slot = HabitSlot(
                start: timeOfDay(hour: 9, minute: 0),
                end: timeOfDay(hour: 11, minute: 0)
            )

            #expect(slot.contains(timeOfDay: timeOfDay(hour: 9, minute: 0)))
            #expect(slot.contains(timeOfDay: timeOfDay(hour: 10, minute: 0)))
            #expect(slot.contains(timeOfDay: timeOfDay(hour: 11, minute: 0)))
        }

        @Test("contains — same-day window excludes outside times")
        @MainActor func contains_sameDay_excludesOutside() throws {
            let slot = HabitSlot(
                start: timeOfDay(hour: 9, minute: 0),
                end: timeOfDay(hour: 11, minute: 0)
            )

            #expect(!slot.contains(timeOfDay: timeOfDay(hour: 8, minute: 59)))
            #expect(!slot.contains(timeOfDay: timeOfDay(hour: 11, minute: 1)))
        }

        @Test("contains — cross-midnight window includes boundaries and interior")
        @MainActor func contains_crossMidnight_includesBoundariesAndInterior() throws {
            let slot = HabitSlot(
                start: timeOfDay(hour: 23, minute: 0),
                end: timeOfDay(hour: 1, minute: 0)
            )

            #expect(slot.contains(timeOfDay: timeOfDay(hour: 23, minute: 0)))
            #expect(slot.contains(timeOfDay: timeOfDay(hour: 0, minute: 0)))
            #expect(slot.contains(timeOfDay: timeOfDay(hour: 1, minute: 0)))
        }

        @Test("contains — cross-midnight window excludes outside times")
        @MainActor func contains_crossMidnight_excludesOutside() throws {
            let slot = HabitSlot(
                start: timeOfDay(hour: 23, minute: 0),
                end: timeOfDay(hour: 1, minute: 0)
            )

            #expect(!slot.contains(timeOfDay: timeOfDay(hour: 22, minute: 59)))
            #expect(!slot.contains(timeOfDay: timeOfDay(hour: 1, minute: 1)))
        }
    }

    @Suite("Slot — remainingFraction")
    struct SlotRemainingFractionTests {
        @Test("remainingFraction — same-day window fractions")
        @MainActor func remainingFraction_sameDay() throws {
            let slot = HabitSlot(
                start: timeOfDay(hour: 10, minute: 0),
                end: timeOfDay(hour: 11, minute: 0)
            )

            // Full window remaining at start.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 10, minute: 0)) == 1.0)
            // Half window remaining at halfway point.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 10, minute: 30)) == 0.5)
            // No time remaining at end.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 11, minute: 0)) == 0.0)
        }

        @Test("remainingFraction — cross-midnight window fractions")
        @MainActor func remainingFraction_crossMidnight() throws {
            let slot = HabitSlot(
                start: timeOfDay(hour: 23, minute: 0),
                end: timeOfDay(hour: 1, minute: 0)
            )

            // Window length is 2 hours (120 minutes): 23:00–01:00.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 23, minute: 0)) == 1.0)
            // One hour (60 minutes) remaining at midnight.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 0, minute: 0)) == 0.5)
            // No time remaining at end.
            #expect(slot.remainingFraction(at: timeOfDay(hour: 1, minute: 0)) == 0.0)
        }
    }
}
