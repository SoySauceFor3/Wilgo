import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Covers `Commitment.remainingUsableOccurrencesInCycle(now:)` — the in-cycle usable-occurrence
/// list the Stage characterization reads (`currentOccurrence` + remaining count). Focuses on the
/// edge cases that used to live in the deleted `slotStatus`/`SlotStatus` suites and aren't otherwise
/// covered by `CommitmentNearestSlotTests` (which looks *forward*): whole-day & cross-midnight
/// carry-over (an occurrence that started the *previous* day but is still open now), and the
/// out-of-window check-in not saturating an active slot.
@Suite(.serialized)
final class CommitmentRemainingUsableTests {
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
    private func addCheckIn(to c: Commitment, at date: Date, in ctx: ModelContext) {
        let checkIn = CheckIn(commitment: c, createdAt: date)
        ctx.insert(checkIn)
        c.checkIns.append(checkIn)
    }

    // MARK: - Whole-day carry-over

    @Test("whole-day daily slot: at 1am the open occurrence started the PREVIOUS day (carry-over)")
    @MainActor func wholeDayCarryOver() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // start == end == 5am → a whole-day slot whose window runs 5am → next-day 5am.
        let slot = Slot(start: tod(hour: 5), end: tod(hour: 5), recurrence: .everyDay)
        let c = Commitment(
            title: "Whole day",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1)
        )
        ctx.insert(c)
        ctx.insert(slot)

        // now = Mar 5, 1am → inside the occurrence that opened Mar 4 5am and closes Mar 5 5am.
        let remaining = c.remainingUsableOccurrencesInCycle(now: date(year: 2026, month: 3, day: 5, hour: 1))

        #expect(remaining.first?.start == date(year: 2026, month: 3, day: 4, hour: 5))
        #expect(remaining.first?.end == date(year: 2026, month: 3, day: 5, hour: 5))
    }

    @Test("23–2 cross-midnight daily slot: at 1am the open occurrence started the previous day")
    @MainActor func crossMidnightCarryOver() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 23), end: tod(hour: 2), recurrence: .everyDay)
        let c = Commitment(
            title: "Night",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 1)
        )
        ctx.insert(c)
        ctx.insert(slot)

        // now = Mar 5, 1am → inside the occurrence that opened Mar 4 23:00 and closes Mar 5 02:00.
        let remaining = c.remainingUsableOccurrencesInCycle(now: date(year: 2026, month: 3, day: 5, hour: 1))

        #expect(remaining.first?.start == date(year: 2026, month: 3, day: 4, hour: 23))
        #expect(remaining.first?.end == date(year: 2026, month: 3, day: 5, hour: 2))
    }

    // MARK: - Saturation window boundary

    @Test("out-of-window check-in does NOT saturate the active slot")
    @MainActor func outOfWindowCheckInDoesNotSaturate() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11), maxCheckIns: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 3)
        )
        ctx.insert(c)
        ctx.insert(slot)
        // A check-in at 8am is OUTSIDE the 9–11 window → must not saturate it.
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 8), in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)  // inside the slot
        let remaining = c.remainingUsableOccurrencesInCycle(now: now)

        // The 9–11 occurrence is still usable (not saturated by the out-of-window check-in).
        #expect(remaining.first?.start == date(year: 2026, month: 3, day: 5, hour: 9))
    }

    @Test("in-window check-in saturates a cap=1 slot → occurrence excluded")
    @MainActor func inWindowCheckInSaturates() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11), maxCheckIns: 1)
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 3)
        )
        ctx.insert(c)
        ctx.insert(slot)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)

        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        // Saturated (cap 1, one in-window check-in) → no remaining usable occurrence this cycle.
        #expect(c.remainingUsableOccurrencesInCycle(now: now).isEmpty)
    }
}
