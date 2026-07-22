import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Covers `StageCharacterization.characteristics(of:now:)` — the per-commitment characterization that
/// every Stage surface is built from. One commitment in → its facts (isCurrent, isBehind,
/// nearestUsable, nearestUsableInCurrentCycle, counts).
@Suite(.serialized)
final class CommitmentCharacteristicsTests {
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
            target: Target(count: targetCount)
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

    // MARK: - isCurrent / currentOccurrence

    @Test("open slot now → isCurrent true, currentOccurrence is the open slot")
    @MainActor func openSlotIsCurrent() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(9, 11, nil)], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)  // inside 9–11

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(snap.isCurrent)
        #expect(snap.currentOccurrence?.start == date(year: 2026, month: 3, day: 5, hour: 9))
    }

    @Test("remainingThisCycleCount counts the usable slots left in the cycle")
    @MainActor func remainingCount() throws {
        let container = try makeTestContainer()
        // Two slots; at 7am both are still ahead and usable → count 2.
        let c = makeCommitment(slots: [(9, 11, nil), (18, 20, nil)], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(snap.remainingThisCycleCount == 2)
        #expect(snap.currentOccurrence == nil)  // neither has started yet
    }

    @Test("remainingThisCycleCount INCLUDES the currently-open slot")
    @MainActor func remainingCountIncludesCurrent() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(9, 11, nil), (18, 20, nil)], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)  // inside the 9–11 slot

        let snap = StageCharacterization.characteristics(of: c, now: now)

        // The open 9–11 slot is still "remaining", so the count is 2 (open + the 6pm one), not 1.
        #expect(snap.currentOccurrence?.start == date(year: 2026, month: 3, day: 5, hour: 9))
        #expect(snap.remainingThisCycleCount == 2)
    }

    @Test("slot later today → not current, but has upcoming")
    @MainActor func laterSlotNotCurrentHasUpcoming() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(9, 11, nil)], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)  // before 9

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(!snap.isCurrent)
        #expect(snap.currentOccurrence == nil)
        #expect(snap.hasUpcoming)
        #expect(snap.nearestUsable?.start == date(year: 2026, month: 3, day: 5, hour: 9))
    }

    // MARK: - nearestUsable / nearestUsableInCurrentCycle

    @Test("nearestUsable in the current cycle → nearestUsableInCurrentCycle true")
    @MainActor func nearestInCurrentCycle() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(9, 11, nil)], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(snap.nearestUsableInCurrentCycle)
    }

    @Test("nearestUsable crossing into next cycle → nearestUsableInCurrentCycle false")
    @MainActor func nearestInNextCycle() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(7, 9, nil)], in: container.mainContext)
        // 11pm: today's 7am passed; nearest usable is tomorrow 7am, in the next daily cycle.
        let now = date(year: 2026, month: 3, day: 5, hour: 23)

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(snap.nearestUsable?.start == date(year: 2026, month: 3, day: 6, hour: 7))
        #expect(!snap.nearestUsableInCurrentCycle)
    }

    @Test("no usable upcoming slot → nearestUsable nil, hasUpcoming false, nearestUsableInCurrentCycle false")
    @MainActor func noUpcoming() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(snap.nearestUsable == nil)
        #expect(!snap.hasUpcoming)
        #expect(!snap.nearestUsableInCurrentCycle)
    }

    // MARK: - behind / counts

    @Test("behind: target unmet with no remaining in-cycle slots → isBehind true")
    @MainActor func behindWhenUnmetAndNoSlots() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        // target 3, daily, single slot already passed and snoozed-out is complex; instead use a
        // single slot whose only occurrence today has passed by `now` and is the only one.
        let c = makeCommitment(slots: [(9, 11, nil)], targetCount: 3, in: ctx)
        // now after the slot window → no remaining in-cycle slot; 0 check-ins; target 3.
        let now = date(year: 2026, month: 3, day: 5, hour: 12)

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(snap.remainingThisCycleCount == 0)
        #expect(snap.isBehind)
        #expect(snap.behindCount == 3)
    }

    @Test("on track: enough remaining slots to meet target → not behind")
    @MainActor func notBehindWhenSlotsCover() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(slots: [(9, 11, nil), (18, 20, nil)], targetCount: 1, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 7)  // both slots still ahead

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(!snap.isBehind)
        #expect(snap.behindCount == 0)
    }

    @Test("counts: checkInCount and targetCount reflect the current cycle")
    @MainActor func counts() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(slots: [(9, 11, nil)], targetCount: 5, in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 9, minute: 30), in: ctx)
        addCheckIn(to: c, at: date(year: 2026, month: 3, day: 5, hour: 10), in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 12)

        let snap = StageCharacterization.characteristics(of: c, now: now)

        #expect(snap.checkInCount == 2)
        #expect(snap.targetCount == 5)
    }
}
