import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Reminders-disabled is encoded as `isActiveForReminders == false` — the single gate every Stage
/// surface filters on before characterizing. (Replaces the old `.disabled` slotKind, which no longer
/// exists after the characterization/placement refactor.)
extension SchedulingSuite {
@Suite(.serialized)
final class CommitmentRemindersDisableTests {
    @MainActor
    private func makeCommitment(remindersEnabled: Bool, in ctx: ModelContext) -> Commitment {
        let anchor = testDate(year: 2026, month: 1, day: 1)
        let slot = Slot(start: timeOfDay(hour: 9), end: timeOfDay(hour: 11))
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
        let now = testDate(year: 2026, month: 3, day: 5, hour: 10)  // inside the 9–11 slot
        #expect(!c.isActiveForReminders(now: now))
    }

    @Test("reminders enabled → isActiveForReminders is true while the goal is unmet")
    @MainActor func remindersEnabled_active() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(remindersEnabled: true, in: container.mainContext)
        let now = testDate(year: 2026, month: 3, day: 5, hour: 10)
        #expect(c.isActiveForReminders(now: now))
    }

    @Test("disabled commitment is dropped before placement → no Stage bucket")
    @MainActor func remindersDisabled_excludedFromBuckets() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let off = makeCommitment(remindersEnabled: false, in: ctx)
        let on = makeCommitment(remindersEnabled: true, in: ctx)
        let now = testDate(year: 2026, month: 3, day: 5, hour: 10)

        // Mirror the production boundary: callers filter on isActiveForReminders, then characterize.
        let characteristics = [off, on]
            .filter { $0.isActiveForReminders(now: now) }
            .map { StageCharacterization.characteristics(of: $0, now: now) }
        let buckets = StageCharacterization.stageBuckets(characteristics: characteristics, now: now, n: 3)

        let placed = buckets.current + buckets.upcoming + buckets.catchUp
        #expect(placed.map(\.commitment.title) == ["Draw"])  // only the enabled one
        #expect(placed.allSatisfy { $0.commitment.id == on.id })
    }
}
}
