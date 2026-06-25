import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Covers `CommitmentAndSlot.UpcomingEntry.rowDisplay` — the pure decision driving the Upcoming
/// row's time line (PRD §9): current-cycle time + "+k more" vs future-cycle exact datetime.
@Suite(.serialized)
final class UpcomingRowDisplayTests {
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
    private func makeEntry(
        isInCurrentCycle: Bool,
        currentCycleRemainingCount: Int,
        in ctx: ModelContext
    ) -> CommitmentAndSlot.UpcomingEntry {
        let slot = Slot(start: tod(hour: 7), end: tod(hour: 9))
        let c = Commitment(
            title: "Yoga",
            cycle: Cycle(kind: .daily, referencePsychDay: date(year: 2026, month: 1, day: 1)),
            slots: [slot],
            target: Target(count: 3)
        )
        ctx.insert(c)
        ctx.insert(slot)
        let occ = slot.occurrence(on: date(year: 2026, month: 3, day: 5))!
        return CommitmentAndSlot.UpcomingEntry(
            commitment: c,
            nearestSlot: occ,
            isInCurrentCycle: isInCurrentCycle,
            currentCycleRemainingCount: currentCycleRemainingCount,
            behindCount: 0
        )
    }

    @Test("current cycle, multiple remaining → time + '+k more' with k = remaining - 1")
    @MainActor func currentCycleWithExtras() throws {
        let container = try makeTestContainer()
        let entry = makeEntry(isInCurrentCycle: true, currentCycleRemainingCount: 3, in: container.mainContext)

        guard case let .currentCycle(timeText, extraCount) = entry.rowDisplay else {
            Issue.record("expected .currentCycle, got \(entry.rowDisplay)")
            return
        }
        #expect(extraCount == 2)
        #expect(timeText == entry.nearestSlot.timeOfDayText)
    }

    @Test("current cycle, single remaining → no '+k more' (extraCount 0)")
    @MainActor func currentCycleSingle() throws {
        let container = try makeTestContainer()
        let entry = makeEntry(isInCurrentCycle: true, currentCycleRemainingCount: 1, in: container.mainContext)

        guard case let .currentCycle(_, extraCount) = entry.rowDisplay else {
            Issue.record("expected .currentCycle, got \(entry.rowDisplay)")
            return
        }
        #expect(extraCount == 0)
    }

    @Test("current cycle, zero remaining count → extraCount clamps to 0 (never negative)")
    @MainActor func currentCycleZeroClamps() throws {
        let container = try makeTestContainer()
        let entry = makeEntry(isInCurrentCycle: true, currentCycleRemainingCount: 0, in: container.mainContext)

        guard case let .currentCycle(_, extraCount) = entry.rowDisplay else {
            Issue.record("expected .currentCycle, got \(entry.rowDisplay)")
            return
        }
        #expect(extraCount == 0)
    }

    @Test("future cycle → exact datetime, no count")
    @MainActor func futureCycle() throws {
        let container = try makeTestContainer()
        let entry = makeEntry(isInCurrentCycle: false, currentCycleRemainingCount: 0, in: container.mainContext)

        guard case let .futureCycle(dateTimeText) = entry.rowDisplay else {
            Issue.record("expected .futureCycle, got \(entry.rowDisplay)")
            return
        }
        // Exact datetime format "MMM d, h:mm a" — nearest slot is Mar 5, 7:00 AM.
        #expect(dateTimeText.contains("Mar 5"))
        #expect(dateTimeText.contains("7:00"))
    }
}
