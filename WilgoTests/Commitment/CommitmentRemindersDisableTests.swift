import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Reminders-disabled is encoded as `isActiveForReminders == false` — the single gate every Stage
/// surface filters on before characterizing. (Replaces the old `.disabled` slotKind, which no longer
/// exists after the characterization/placement refactor.)
@Suite(.serialized)
final class CommitmentRemindersDisableTests {
    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = 0
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = 0
        c.second = 0
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitment(remindersEnabled: Bool, in ctx: ModelContext) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        let c = Commitment(
            title: "Draw",
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: remindersEnabled
        )
        ctx.insert(c)
        ctx.insert(slot)
        return c
    }

    @Test("reminders disabled → isActiveForReminders is false (even with a slot open now)")
    @MainActor func remindersDisabled_notActive() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(remindersEnabled: false, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)  // inside the 9–11 slot
        #expect(!c.isActiveForReminders(now: now))
    }

    @Test("reminders enabled → isActiveForReminders is true while the goal is unmet")
    @MainActor func remindersEnabled_active() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(remindersEnabled: true, in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.isActiveForReminders(now: now))
    }

    @Test("disabled commitment is dropped before placement → no Stage bucket")
    @MainActor func remindersDisabled_excludedFromBuckets() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let off = makeCommitment(remindersEnabled: false, in: ctx)
        let on = makeCommitment(remindersEnabled: true, in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        // Mirror the production boundary: callers filter on isActiveForReminders, then characterize.
        let characteristics = [off, on]
            .filter { $0.isActiveForReminders(now: now) }
            .map { CommitmentAndSlot.characteristics(of: $0, now: now) }
        let buckets = CommitmentAndSlot.stageBuckets(characteristics: characteristics, now: now, n: 3)

        let placed = buckets.current + buckets.upcoming + buckets.catchUp
        #expect(placed.map(\.commitment.title) == ["Draw"])  // only the enabled one
        #expect(placed.allSatisfy { $0.commitment.id == on.id })
    }
}
