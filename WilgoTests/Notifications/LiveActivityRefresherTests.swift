import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Unit tests for the pure `LiveActivityRefresher.makeContentState(from:)` mapping.
/// The `refresh(context:)` side of the refresher talks to ActivityKit, which cannot run in the
/// test host, so it is covered by on-device manual verification (see the implementation plan).
@Suite(.serialized)
final class LiveActivityRefresherTests {
    private func tod(hour: Int) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        return Calendar.current.date(from: c)!
    }

    private func date(year: Int, month: Int, day: Int, hour: Int = 0) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        return Calendar.current.date(from: c)!
    }

    @MainActor
    private func makeCommitment(
        title: String,
        encouragements: [String] = [],
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let slot = Slot(start: tod(hour: 9), end: tod(hour: 11))
        let c = Commitment(
            title: title,
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: [slot],
            target: Target(count: 1),
            isRemindersEnabled: true
        )
        c.encouragements = encouragements
        ctx.insert(c)
        ctx.insert(slot)
        return c
    }

    /// The Current bucket (characteristics) for `commitments` at `now`, as production builds it.
    @MainActor
    private func currentBucket(_ commitments: [Commitment], now: Date) -> [CommitmentCharacteristics] {
        let characteristics =
            commitments
            .filter { $0.isActiveForReminders(now: now) }
            .map { StageCharacterization.characteristics(of: $0, now: now) }
        return StageCharacterization.stageBuckets(characteristics: characteristics, now: now, n: 3).current
    }

    @Test("single current commitment → maps title, ids, no secondary titles")
    @MainActor func singleCurrent_mapsPrimaryFields() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(title: "Draw", in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let current = currentBucket([c], now: now)
        #expect(current.count == 1)

        let state = try #require(LiveActivityRefresher.makeContentState(from: current))
        #expect(state.commitmentTitle == "Draw")
        #expect(state.commitmentId == c.id)
        #expect(state.slotId == current[0].currentOccurrence?.slot.id)
        #expect(state.windowStart == current[0].currentOccurrence?.start)
        #expect(state.windowEnd == current[0].currentOccurrence?.end)
        #expect(state.checkInCount == 0) // Target(count: 1), no check-ins yet
        #expect(state.targetCount == 1)
    }

    @Test("empty encouragements → encouragementText is nil")
    @MainActor func noEncouragements_textIsNil() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(title: "Draw", encouragements: [], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let current = currentBucket([c], now: now)

        let state = try #require(LiveActivityRefresher.makeContentState(from: current))
        #expect(state.encouragementText == nil)
    }

    @Test("single encouragement → encouragementText is that string")
    @MainActor func singleEncouragement_textIsThatString() throws {
        let container = try makeTestContainer()
        // With one element, randomElement() is deterministic.
        let c = makeCommitment(
            title: "Draw", encouragements: ["Keep going"], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let current = currentBucket([c], now: now)

        let state = try #require(LiveActivityRefresher.makeContentState(from: current))
        #expect(state.encouragementText == "Keep going")
    }

}
