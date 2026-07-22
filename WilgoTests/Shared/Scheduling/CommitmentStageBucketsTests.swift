import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Covers `StageCharacterization.stageBuckets(commitments:now:n:)` — the single place that
/// splits commitments into Current / Upcoming / Catch-up for the Stage. Key rules:
/// active filtering, the closest-N Upcoming cap, Upcoming-takes-priority over Catch-up,
/// overflow demotion of behind commitments to Catch-up, and the per-commitment Upcoming
/// metadata (`nearestUsableInCurrentCycle`, `currentCycleRemainingCount`, `behindCount`).
extension SchedulingSuite {
@Suite(.serialized)
final class CommitmentStageBucketsTests {
    // MARK: - Helpers
    @MainActor
    private func makeCommitment(
        title: String = "C",
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
            title: title,
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

    /// Characterize the active commitments (the caller's job in production) and place into buckets.
    @MainActor
    private func buckets(_ commitments: [Commitment], now: Date, n: Int)
        -> (
            current: [CommitmentCharacteristics],
            upcoming: [CommitmentCharacteristics],
            catchUp: [CommitmentCharacteristics]
        )
    {
        let characteristics =
            commitments
            .filter { $0.isActiveForReminders(now: now) }
            .map { StageCharacterization.characteristics(of: $0, now: now) }
        return StageCharacterization.stageBuckets(characteristics: characteristics, now: now, n: n)
    }

    // MARK: - Tests

    @Test("empty commitments → all three buckets empty")
    @MainActor func emptyCommitments() throws {
        let container = try makeTestContainer()
        _ = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 7)

        let buckets = buckets([], now: now, n: 5)

        #expect(buckets.current.isEmpty)
        #expect(buckets.upcoming.isEmpty)
        #expect(buckets.catchUp.isEmpty)
    }

    @Test(
        "closest-N: more than N future-eligible → exactly N upcoming, nearest first; rest to catch-up"
    )
    @MainActor func closestN() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // now is 6am, before any slot today. All are behind (target 3, no check-ins).
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        // Slots at 8, 10, 12, 14 → ascending nearest starts.
        let c8 = makeCommitment(title: "8", slots: [(8, 9, nil)], in: ctx)
        let c10 = makeCommitment(title: "10", slots: [(10, 11, nil)], in: ctx)
        let c12 = makeCommitment(title: "12", slots: [(12, 13, nil)], in: ctx)
        let c14 = makeCommitment(title: "14", slots: [(14, 15, nil)], in: ctx)

        let buckets = buckets([c12, c8, c14, c10], now: now, n: 2)

        // Exactly N=2 in upcoming, ordered nearest-first (8 then 10).
        #expect(buckets.upcoming.count == 2)
        #expect(buckets.upcoming.map(\.commitment.id) == [c8.id, c10.id])
        // The other two are behind → catch-up.
        #expect(Set(buckets.catchUp.map(\.commitment.id)) == [c12.id, c14.id])
        #expect(buckets.current.isEmpty)
    }

    @Test("fewer than N future-eligible → all shown in upcoming")
    @MainActor func fewerThanN() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        let c8 = makeCommitment(title: "8", slots: [(8, 9, nil)], in: ctx)
        let c10 = makeCommitment(title: "10", slots: [(10, 11, nil)], in: ctx)

        let buckets = buckets([c10, c8], now: now, n: 5)

        #expect(buckets.upcoming.map(\.commitment.id) == [c8.id, c10.id])
        #expect(buckets.catchUp.isEmpty)
        #expect(buckets.current.isEmpty)
    }

    @Test("n = 0 → upcoming empty; behind ones fall to catch-up")
    @MainActor func nZero() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        let c8 = makeCommitment(title: "8", slots: [(8, 9, nil)], in: ctx)
        let c10 = makeCommitment(title: "10", slots: [(10, 11, nil)], in: ctx)

        let buckets = buckets([c8, c10], now: now, n: 0)

        #expect(buckets.upcoming.isEmpty)
        // Both behind → both demote to catch-up.
        #expect(Set(buckets.catchUp.map(\.commitment.id)) == [c8.id, c10.id])
    }

    @Test("overflow demotion: a BEHIND commitment beyond top-N appears in catch-up, not upcoming")
    @MainActor func overflowDemotion() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        let c8 = makeCommitment(title: "8", slots: [(8, 9, nil)], in: ctx)
        let c10 = makeCommitment(title: "10", slots: [(10, 11, nil)], in: ctx)
        // c14 is behind (target 3, no check-ins) but ranks 3rd by slot start → beyond n=2.
        let c14 = makeCommitment(title: "14", slots: [(14, 15, nil)], in: ctx)

        let buckets = buckets([c8, c10, c14], now: now, n: 2)

        #expect(buckets.upcoming.map(\.commitment.id) == [c8.id, c10.id])
        #expect(!buckets.upcoming.map(\.commitment.id).contains(c14.id))
        #expect(buckets.catchUp.map(\.commitment.id) == [c14.id])
    }

    @Test("non-behind overflow: a NOT-behind commitment beyond top-N appears in NEITHER bucket")
    @MainActor func nonBehindOverflow() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        let c8 = makeCommitment(title: "8", slots: [(8, 9, nil)], in: ctx)
        let c10 = makeCommitment(title: "10", slots: [(10, 11, nil)], in: ctx)
        // c14: target 1, continue ON, and one check-in today → goal met but still active.
        // Because it has a remaining usable slot, leftToDo(=0) - remainingSlots makes behindCount 0.
        let c14 = makeCommitment(
            title: "14", slots: [(14, 15, nil)], targetCount: 1, continueAfterGoalMet: true, in: ctx
        )
        addCheckIn(to: c14, at: testDate(year: 2026, month: 3, day: 5, hour: 5), in: ctx)

        // Sanity: c14 is active and NOT behind.
        #expect(c14.isActiveForReminders(now: now))
        #expect(StageCharacterization.characteristics(of: c14, now: now).behindCount == 0)

        let buckets = buckets([c8, c10, c14], now: now, n: 2)

        #expect(buckets.upcoming.map(\.commitment.id) == [c8.id, c10.id])
        #expect(!buckets.upcoming.map(\.commitment.id).contains(c14.id))
        #expect(!buckets.catchUp.map(\.commitment.id).contains(c14.id))
    }

    @Test("priority: a behind commitment within top-N is in upcoming, NOT catch-up")
    @MainActor func priorityWithinTopN() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        // c8 is behind but it is the nearest slot → in upcoming despite being behind.
        let c8 = makeCommitment(title: "8", slots: [(8, 9, nil)], in: ctx)

        let buckets = buckets([c8], now: now, n: 5)

        #expect(buckets.upcoming.map(\.commitment.id) == [c8.id])
        #expect(!buckets.catchUp.map(\.commitment.id).contains(c8.id))
        // Confirm it really is behind.
        #expect((buckets.upcoming.first?.behindCount ?? 0) > 0)
    }

    @Test("current vs upcoming disjoint: an open-now slot is in current, not upcoming")
    @MainActor func currentNotUpcoming() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // now is 8:30, inside the 8-9 window → insideSlot.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 8, minute: 30)
        let cNow = makeCommitment(title: "now", slots: [(8, 9, nil)], in: ctx)
        let cLater = makeCommitment(title: "later", slots: [(12, 13, nil)], in: ctx)

        let buckets = buckets([cNow, cLater], now: now, n: 5)

        #expect(buckets.current.map(\.commitment.id) == [cNow.id])
        #expect(!buckets.upcoming.map(\.commitment.id).contains(cNow.id))
        // cLater is upcoming.
        #expect(buckets.upcoming.map(\.commitment.id) == [cLater.id])
    }

    @Test("slot end transition: a commitment leaves current once its open slot closes")
    @MainActor func slotEndLeavesCurrent() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // Pin the clock so slot-time resolution ("today") is deterministic regardless of test order.
        let saved = Time.now
        defer { Time.now = saved }
        let inside = testDate(year: 2026, month: 3, day: 5, hour: 8, minute: 30)
        Time.now = { inside }
        // target 3, no check-ins → behind. Single slot 8-9, no later slot today.
        let c = makeCommitment(title: "c", slots: [(8, 9, nil)], in: ctx)

        // Inside the window (8:30): current, not catch-up.
        let insideBuckets = buckets([c], now: inside, n: 5)
        #expect(insideBuckets.current.map(\.commitment.id) == [c.id])
        #expect(insideBuckets.catchUp.isEmpty)

        // Just after the window closes (9:30): must leave current. On a daily cycle the next usable
        // slot is tomorrow's 8am, so the (still-behind) item becomes future-eligible → upcoming.
        // The key regression guard is that it is no longer in `current`.
        let after = testDate(year: 2026, month: 3, day: 5, hour: 9, minute: 30)
        Time.now = { after }
        let afterBuckets = buckets([c], now: after, n: 5)
        #expect(afterBuckets.current.isEmpty)
        #expect(afterBuckets.upcoming.map(\.commitment.id) == [c.id])
    }

    @Test("met-goal exclusion: goal met + not continuing → excluded from all buckets")
    @MainActor func metGoalExcluded() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        // target 1, one check-in → goal met; continue OFF → not active.
        let cMet = makeCommitment(
            title: "met", slots: [(8, 9, nil)], targetCount: 1, in: ctx)
        addCheckIn(to: cMet, at: testDate(year: 2026, month: 3, day: 5, hour: 5), in: ctx)
        let cActive = makeCommitment(title: "active", slots: [(10, 11, nil)], in: ctx)

        // Sanity: cMet is not active for reminders.
        #expect(!cMet.isActiveForReminders(now: now))

        let buckets = buckets([cMet, cActive], now: now, n: 5)

        let allIDs =
            buckets.current.map(\.commitment.id)
            + buckets.upcoming.map(\.commitment.id)
            + buckets.catchUp.map(\.commitment.id)
        #expect(!allIDs.contains(cMet.id))
        #expect(buckets.upcoming.map(\.commitment.id) == [cActive.id])
    }

    @Test("nearestUsableInCurrentCycle true for a same-day (current-cycle) nearest slot")
    @MainActor func nearestUsableInCurrentCycleTrue() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        let c = makeCommitment(title: "today", slots: [(8, 9, nil)], in: ctx)

        let buckets = buckets([c], now: now, n: 5)

        let entry = try #require(buckets.upcoming.first)
        #expect(entry.nearestUsable?.start == testDate(year: 2026, month: 3, day: 5, hour: 8))
        #expect(entry.nearestUsableInCurrentCycle)
        // remainingSlots in the current cycle (the single 8am occurrence) → remainingThisCycleCount 1.
        #expect(entry.remainingThisCycleCount == 1)
    }

    @Test("nearestUsableInCurrentCycle false for a next-cycle nearest slot (11pm, only a 7am slot)")
    @MainActor func nearestUsableInCurrentCycleFalse() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // 11pm on a daily cycle: today's 7am slot has passed; nearest usable is tomorrow's 7am,
        // which falls in the NEXT daily cycle (next psych-day) → nearestUsableInCurrentCycle false.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 23)
        let c = makeCommitment(title: "7am", slots: [(7, 9, nil)], in: ctx)

        let buckets = buckets([c], now: now, n: 5)

        let entry = try #require(buckets.upcoming.first)
        #expect(entry.nearestUsable?.start == testDate(year: 2026, month: 3, day: 6, hour: 7))
        #expect(!entry.nearestUsableInCurrentCycle)
    }

    @Test("nextTransitionTime: reflects an edited slot end (the slot-edit staleness bug)")
    @MainActor func nextTransitionTimeReflectsEditedSlotEnd() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let saved = Time.now
        defer { Time.now = saved }
        // 8:30 today, inside an 8-9 slot → the next transition is the slot's end at 9:00.
        let frozen = try #require(Calendar.current.date(
            bySettingHour: 8, minute: 30, second: 0, of: Date()))
        Time.now = { frozen }
        let c = makeCommitment(title: "c", slots: [(8, 9, nil)], in: ctx)

        func at(_ h: Int) throws -> Date {
            try #require(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date()))
        }
        #expect(try StageCharacterization.nextTransitionTime(commitments: [c], now: frozen) == at(9))

        // Edit the slot end to 10:00 (as EditCommitmentView would); the next wake must follow so the
        // Stage's boundary timer, keyed on this value, restarts toward the new end.
        c.slots[0].end = timeOfDay(hour: 10)
        #expect(try StageCharacterization.nextTransitionTime(commitments: [c], now: frozen) == at(10))
    }

    @Test("nextStageRefreshTime: with no slot edge before midnight, wakes at the next psychDay boundary")
    @MainActor func nextStageRefreshFallsBackToPsychDay() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // 10pm today; the only slot (8-9) already ended and does not fire again before midnight.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 22)
        let c = makeCommitment(title: "morning", slots: [(8, 9, nil)], in: ctx)

        // Slot-only primitive: next edge is tomorrow 8:00.
        #expect(
            StageCharacterization.nextTransitionTime(commitments: [c], now: now)
                == testDate(year: 2026, month: 3, day: 6, hour: 8))
        // Refresh helper folds in the cycle boundary (approximated by next psychDay start = midnight),
        // which is sooner — so the Stage wakes at midnight for the goal-met→un-met rollover.
        #expect(
            StageCharacterization.nextStageRefreshTime(commitments: [c], now: now)
                == testDate(year: 2026, month: 3, day: 6, hour: 0))
    }

    @Test("nextStageRefreshTime: a slot edge before midnight wins over the psychDay boundary")
    @MainActor func nextStageRefreshPrefersEarlierSlotEdge() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // 8:30, inside the 8-9 slot → its end at 9:00 is before the next midnight.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 8, minute: 30)
        let c = makeCommitment(title: "open", slots: [(8, 9, nil)], in: ctx)

        #expect(
            StageCharacterization.nextStageRefreshTime(commitments: [c], now: now)
                == testDate(year: 2026, month: 3, day: 5, hour: 9))
    }

    @Test("nextStageRefreshTime: no slots → still wakes at the next psychDay boundary")
    @MainActor func nextStageRefreshPsychDayWithoutSlots() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 12)
        let c = makeCommitment(title: "empty", slots: [], in: ctx)

        #expect(
            StageCharacterization.nextStageRefreshTime(commitments: [c], now: now)
                == testDate(year: 2026, month: 3, day: 6, hour: 0))
    }

    // MARK: - behindForReminder

    /// Builds the characteristics list the way production does (active filter + characterize).
    @MainActor
    private func chars(_ commitments: [Commitment], now: Date) -> [CommitmentCharacteristics] {
        commitments
            .filter { $0.isActiveForReminders(now: now) }
            .map { StageCharacterization.characteristics(of: $0, now: now) }
    }

    @Test("behindForReminder includes a behind commitment even when it sits in Upcoming's top-N")
    @MainActor func behindForReminderIncludesUpcoming() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // 6am, before the 8am slot: behind (target 3, no check-ins) AND future-eligible (→ Upcoming).
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        let c = makeCommitment(title: "8", slots: [(8, 9, nil)], targetCount: 3, in: ctx)

        let cs = chars([c], now: now)
        // It lands in Upcoming (not catchUp), yet behindForReminder still includes it.
        let placed = StageCharacterization.stageBuckets(characteristics: cs, now: now, n: 5)
        #expect(placed.upcoming.map(\.commitment.id) == [c.id])
        #expect(placed.catchUp.isEmpty)

        let reminded = StageCharacterization.behindForReminder(characteristics: cs)
        #expect(reminded.map(\.commitment.id) == [c.id])
    }

    @Test("behindForReminder excludes a behind commitment that is currently in an open slot")
    @MainActor func behindForReminderExcludesCurrent() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // now is inside the 9–11 slot, and target 3 with no check-ins → behind, but currently open.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 10)
        let c = makeCommitment(title: "open", slots: [(9, 11, nil)], targetCount: 3, in: ctx)

        let cs = chars([c], now: now)
        #expect(cs.first?.isBehind == true)
        #expect(cs.first?.isCurrent == true)

        let reminded = StageCharacterization.behindForReminder(characteristics: cs)
        #expect(reminded.isEmpty)  // behind, but in an open slot → no catch-up nudge (default)
    }

    @Test("behindForReminder(includeCurrent: true) → reminds behind + current commitment")
    @MainActor func behindForReminderIncludeCurrentOptIn() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // Same setup as the exclude case: behind AND currently in an open slot.
        let now = testDate(year: 2026, month: 3, day: 5, hour: 10)
        let c = makeCommitment(title: "open", slots: [(9, 11, nil)], targetCount: 3, in: ctx)

        let cs = chars([c], now: now)
        #expect(cs.first?.isBehind == true)
        #expect(cs.first?.isCurrent == true)

        // With the opt-in flag, the open-slot behind commitment IS reminded.
        let reminded = StageCharacterization.behindForReminder(
            characteristics: cs, includeCurrent: true)
        #expect(reminded.map(\.commitment.id) == [c.id])
    }

    @Test("behindForReminder excludes a not-behind commitment")
    @MainActor func behindForReminderExcludesOnTrack() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let now = testDate(year: 2026, month: 3, day: 5, hour: 6)
        // target 1, one upcoming slot → leftToDo 1 - remaining 1 = behindCount 0 (on track).
        let c = makeCommitment(title: "ok", slots: [(8, 9, nil)], targetCount: 1, in: ctx)

        let cs = chars([c], now: now)
        #expect(cs.first?.isBehind == false)
        #expect(StageCharacterization.behindForReminder(characteristics: cs).isEmpty)
    }
}
}
