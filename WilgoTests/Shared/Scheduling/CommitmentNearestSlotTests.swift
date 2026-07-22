import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Covers `Commitment.nearestUsableUpcomingOccurrence(now:)` — the per-commitment
/// nearest usable slot that drives Stage's Upcoming. Key properties: it is the `min`
/// over slots, it crosses cycle boundaries (no midnight cliff), and saturation is judged
/// against each occurrence's OWN cycle.
extension SchedulingSuite {
@Suite(.serialized)
final class CommitmentNearestSlotTests {
    // MARK: - Helpers
    @MainActor
    private func makeCommitment(
        slots slotDefs: [(start: Int, end: Int, maxCheckIns: Int?)],
        targetCount: Int = 3,
        cycleKind: CycleKind = .daily,
        continueAfterGoalMet: Bool = false,
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = testDate(year: 2026, month: 1, day: 1)
        let slots = slotDefs.map {
            Slot(start: timeOfDay(hour: $0.start), end: timeOfDay(hour: $0.end), maxCheckIns: $0.maxCheckIns)
        }
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: cycleKind, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: targetCount),
            continueRemindersAfterGoalMet: continueAfterGoalMet
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

    @MainActor
    private func addSnooze(to slot: Slot, at date: Date, in ctx: ModelContext) {
        slot.snooze(at: date, in: ctx)
    }

    // MARK: - Tests

    @Test("future occurrence today is returned")
    @MainActor func futureToday_returned() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(9, 11, nil)], in: container.mainContext)
        let now = testDate(year: 2026, month: 3, day: 5, hour: 7)

        let occ = c.nearestUsableUpcomingOccurrence(now: now)

        #expect(occ?.start == testDate(year: 2026, month: 3, day: 5, hour: 9))
    }

    @Test("min across multiple slots returns the soonest")
    @MainActor func minAcrossSlots() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(18, 20, nil), (9, 11, nil)], in: container.mainContext)
        let now = testDate(year: 2026, month: 3, day: 5, hour: 7)

        let occ = c.nearestUsableUpcomingOccurrence(now: now)

        // 9am is sooner than 6pm.
        #expect(occ?.start == testDate(year: 2026, month: 3, day: 5, hour: 9))
    }

    @Test("no cliff: at 11pm the nearest usable slot is tomorrow's 7am (next cycle)")
    @MainActor func crossesMidnightToNextCycle() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(7, 9, nil)], in: container.mainContext)
        // 11pm today — today's 7am slot has long passed; nearest is tomorrow 7am (next daily cycle).
        let now = testDate(year: 2026, month: 3, day: 5, hour: 23)

        let occ = c.nearestUsableUpcomingOccurrence(now: now)

        #expect(occ?.start == testDate(year: 2026, month: 3, day: 6, hour: 7))
    }

    @Test("snoozed today's occurrence falls through to the next day")
    @MainActor func snoozedFallsThrough() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, nil)], in: ctx)
        let slot = try #require(c.slots.first)
        // Snooze the 5th's 9am occurrence; nearest usable should be the 6th's 9am.
        addSnooze(to: slot, at: testDate(year: 2026, month: 3, day: 5, hour: 9), in: ctx)
        let now = testDate(year: 2026, month: 3, day: 5, hour: 7)

        let occ = c.nearestUsableUpcomingOccurrence(now: now)

        #expect(occ?.start == testDate(year: 2026, month: 3, day: 6, hour: 9))
    }

    @Test("saturated current occurrence falls through to the next day")
    @MainActor func saturatedFallsThrough() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, 1)], in: ctx)  // capacity 1
        // A check-in inside the 5th's 9-11 window saturates that occurrence.
        addCheckIn(to: c, at: testDate(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)
        // now is before the slot start so the occurrence is still "upcoming" but saturated.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 8)

        let occ = c.nearestUsableUpcomingOccurrence(now: now)

        // 5th is saturated → nearest usable is the 6th's 9am (fresh, empty window).
        #expect(occ?.start == testDate(year: 2026, month: 3, day: 6, hour: 9))
    }

    @Test("cross-cycle saturation: a check-in in the current cycle does NOT saturate a future-cycle occurrence")
    @MainActor func crossCycleSaturationIsolated() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // Daily cycle, capacity 1. A check-in saturates only its own day's occurrence.
        let c = makeCommitment(slots: [(9, 11, 1)], in: ctx)
        // Saturate the 5th's occurrence.
        addCheckIn(to: c, at: testDate(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)
        let now = testDate(year: 2026, month: 3, day: 5, hour: 8)

        let occ = c.nearestUsableUpcomingOccurrence(now: now)

        // The 6th's occurrence is in a DIFFERENT daily cycle; the 5th's check-in must not count
        // against it. So the 6th's 9am is usable and returned.
        #expect(occ?.start == testDate(year: 2026, month: 3, day: 6, hour: 9))
    }

    @Test("goal met + continue: still searches from now, surfacing the current cycle's slot")
    @MainActor func goalMetContinueSearchesFromNow() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // Daily cycle, target 1, continue-after-met ON. One check-in today meets the goal, but the
        // slot itself has unlimited capacity (maxCheckIns nil) so its occurrence is not saturated.
        let c = makeCommitment(
            slots: [(9, 11, nil)], targetCount: 1, continueAfterGoalMet: true, in: ctx
        )
        addCheckIn(to: c, at: testDate(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)
        // now is 7am; today's 9am slot is still upcoming. Goal met + continue → keep showing the
        // current cycle, so the search starts at `now` and returns TODAY's 9am.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 7)

        let occ = c.nearestUsableUpcomingOccurrence(now: now)

        #expect(occ?.start == testDate(year: 2026, month: 3, day: 5, hour: 9))
    }

    @Test("specificWeekdays recurrence: nextMatch jumps to the next matching weekday")
    @MainActor func specificWeekdaysJumpsToNextMatch() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, nil)], in: ctx)
        let slot = try #require(c.slots.first)
        // Restrict to Mondays only (Calendar weekday 2).
        slot.recurrence = .specificWeekdays([2])
        // 2026-03-05 is a Thursday; the next Monday is 2026-03-09.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 7)

        let occ = c.nearestUsableUpcomingOccurrence(now: now)

        #expect(occ?.start == testDate(year: 2026, month: 3, day: 9, hour: 9))
    }

    @Test("no usable upcoming occurrence on any slot → nil")
    @MainActor func noneReturnsNil() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // Single slot restricted to a weekday that never matches within the lookahead is hard to
        // construct without recurrence; instead use a saturated slot whose every occurrence in
        // the lookahead is saturated. Simpler: capacity 0 means unlimited (not saturated), so use
        // a snooze-blanket approach is also awkward. Use the cleanest available: no slots.
        let c = makeCommitment(slots: [], in: ctx)
        let now = testDate(year: 2026, month: 3, day: 5, hour: 7)

        #expect(c.nearestUsableUpcomingOccurrence(now: now) == nil)
    }
}
}
