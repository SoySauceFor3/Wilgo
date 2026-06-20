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

    @Test("empty current list → nil content state")
    @MainActor func emptyCurrent_returnsNil() {
        #expect(LiveActivityRefresher.makeContentState(from: []) == nil)
    }

    @Test("single current commitment → maps title, ids, no secondary titles")
    @MainActor func singleCurrent_mapsPrimaryFields() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(title: "Draw", in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let current = CommitmentAndSlot.currentWithBehind(commitments: [c], now: now)
        #expect(current.count == 1)

        let state = try #require(LiveActivityRefresher.makeContentState(from: current))
        #expect(state.commitmentTitle == "Draw")
        #expect(state.commitmentId == c.id)
        #expect(state.slotId == current[0].slots[0].slot.id)
        #expect(state.secondaryTitles.isEmpty)
    }

    @Test("empty encouragements → encouragementText is nil")
    @MainActor func noEncouragements_textIsNil() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(title: "Draw", encouragements: [], in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let current = CommitmentAndSlot.currentWithBehind(commitments: [c], now: now)

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
        let current = CommitmentAndSlot.currentWithBehind(commitments: [c], now: now)

        let state = try #require(LiveActivityRefresher.makeContentState(from: current))
        #expect(state.encouragementText == "Keep going")
    }

    @Test("multiple current commitments → first is primary, rest become secondary titles")
    @MainActor func multipleCurrent_primaryPlusSecondaries() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let a = makeCommitment(title: "Draw", in: ctx)
        let b = makeCommitment(title: "Run", in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        let current = CommitmentAndSlot.currentWithBehind(commitments: [a, b], now: now)
        #expect(current.count == 2)

        let state = try #require(LiveActivityRefresher.makeContentState(from: current))
        // Primary is the first element of `current`; secondaries are the remaining titles.
        #expect(state.commitmentTitle == current[0].commitment.title)
        #expect(state.secondaryTitles == [current[1].commitment.title])
    }
}
