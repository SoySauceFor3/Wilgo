import Foundation
import SwiftData
import Testing
@testable import Wilgo

/// Unit tests for the pure planning half of the scheduled-Live-Activity design.
/// The ActivityKit side (request/end) cannot run in the test host; it is covered by
/// on-device manual verification (see the implementation plan).
@Suite(.serialized)
final class LiveActivityPlannerTests {
    private func tod(hour: Int, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2000
        c.month = 1
        c.day = 1
        c.hour = hour
        c.minute = minute
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
        slots: [Slot],
        encouragements: [String] = [],
        in ctx: ModelContext
    ) -> Commitment {
        let anchor = date(year: 2026, month: 1, day: 1)
        let c = Commitment(
            title: title,
            cycle: Cycle(kind: .daily, referencePsychDay: anchor),
            slots: slots,
            target: Target(count: 1),
            isRemindersEnabled: true
        )
        c.encouragements = encouragements
        ctx.insert(c)
        for s in slots {
            ctx.insert(s)
        }
        return c
    }

    @Test("open occurrence → immediate (nil scheduledStart); future → scheduled at its start")
    @MainActor func openVsFutureStart() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)  // inside today's 9–11

        let planned = LiveActivityPlanner.plan(commitments: [c], now: now)

        #expect(planned.count >= 2)
        #expect(planned[0].scheduledStart == nil)  // today's open occurrence
        #expect(planned[0].staleDate == date(year: 2026, month: 3, day: 5, hour: 11))
        #expect(planned[1].scheduledStart == date(year: 2026, month: 3, day: 6, hour: 9))
    }

    @Test("plan caps at maxPlanned nearest occurrences")
    @MainActor func capsAtMaxPlanned() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],  // daily → 14 in horizon
            in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 8)

        let planned = LiveActivityPlanner.plan(commitments: [c], now: now)

        #expect(planned.count == LiveActivityPlanner.maxPlanned)
        // Nearest-first ordering.
        let starts = planned.map { $0.scheduledStart ?? now }
        #expect(starts == starts.sorted())
    }

    @Test("reminder-inactive commitments are excluded")
    @MainActor func remindersGateApplies() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            in: container.mainContext)
        c.isRemindersEnabled = false
        let now = date(year: 2026, month: 3, day: 5, hour: 8)

        #expect(LiveActivityPlanner.plan(commitments: [c], now: now).isEmpty)
    }

    @Test("state carries occurrence window + ids; relevance favors earlier deadline")
    @MainActor func stateFieldsAndRelevance() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let a = makeCommitment(
            title: "Ends sooner",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 10))], in: ctx)
        let b = makeCommitment(
            title: "Ends later",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 12))], in: ctx)
        let now = date(year: 2026, month: 3, day: 5, hour: 9).addingTimeInterval(30 * 60)

        let planned = LiveActivityPlanner.plan(commitments: [a, b], now: now)
        let sooner = try #require(planned.first { $0.state.commitmentTitle == "Ends sooner" })
        let later = try #require(planned.first { $0.state.commitmentTitle == "Ends later" })

        #expect(sooner.state.commitmentId == a.id)
        #expect(sooner.state.slotId == a.slots[0].id)
        #expect(sooner.state.windowStart == date(year: 2026, month: 3, day: 5, hour: 9))
        #expect(sooner.state.windowEnd == date(year: 2026, month: 3, day: 5, hour: 10))
        #expect(sooner.relevanceScore > later.relevanceScore)
    }

    @Test("encouragement is deterministic for a given slot + day")
    @MainActor func encouragementDeterministic() throws {
        let container = try makeTestContainer()
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            encouragements: ["a", "b", "c"],
            in: container.mainContext)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)

        let first = LiveActivityPlanner.plan(commitments: [c], now: now)
        let second = LiveActivityPlanner.plan(commitments: [c], now: now)

        #expect(first[0].state == second[0].state)
        #expect(first[0].state.encouragementText != nil)
        // Different days may rotate; same day must not.
    }

    @Test("progress counts: baked from the occurrence's own cycle; nil when target disabled")
    @MainActor func progressCountsBaked() throws {
        let container = try makeTestContainer()
        let ctx = container.mainContext
        let c = makeCommitment(
            title: "Draw",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            in: ctx)
        c.target = Target(count: 3)
        let now = date(year: 2026, month: 3, day: 5, hour: 10)
        CheckIn.insert(
            commitment: c, createdAt: date(year: 2026, month: 3, day: 5, hour: 9), into: ctx)

        let planned = LiveActivityPlanner.plan(commitments: [c], now: now)
        #expect(planned[0].state.checkInCount == 1)  // today's open occurrence, 1 of 3 done
        #expect(planned[0].state.targetCount == 3)
        #expect(planned[1].state.checkInCount == 0)  // tomorrow = next daily cycle, fresh count
        #expect(planned[1].state.targetCount == 3)

        let noTarget = makeCommitment(
            title: "NoTarget",
            slots: [Slot(start: tod(hour: 9), end: tod(hour: 11))],
            in: ctx)
        noTarget.target = Target(count: 1, mode: .disabled)
        let plannedNoTarget = LiveActivityPlanner.plan(commitments: [noTarget], now: now)
        #expect(plannedNoTarget[0].state.checkInCount == nil)
        #expect(plannedNoTarget[0].state.targetCount == nil)
    }

    private func state(title: String, slotId: UUID, start: Date, end: Date)
        -> NowAttributes.ContentState
    {
        NowAttributes.ContentState(
            commitmentTitle: title, slotTimeText: "9:00 AM – 11:00 AM",
            commitmentId: UUID(), slotId: slotId,
            windowStart: start, windowEnd: end, encouragementText: nil,
            checkInCount: nil, targetCount: nil)
    }

    private func plannedItem(_ s: NowAttributes.ContentState) -> PlannedLiveActivity {
        PlannedLiveActivity(
            state: s, scheduledStart: s.windowStart, staleDate: s.windowEnd,
            relevanceScore: 1)
    }

    @Test("diff keeps exact matches, ends orphans, requests the rest")
    func diffPartitions() {
        let slotA = UUID()
        let slotB = UUID()
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let d2 = Date(timeIntervalSince1970: 1_010_000)
        let matching = state(title: "A", slotId: slotA, start: d1, end: d2)
        let orphanState = state(title: "gone", slotId: UUID(), start: d1, end: d2)
        let newState = state(title: "B", slotId: slotB, start: d2, end: d2.addingTimeInterval(3600))

        let (toEnd, toRequest) = LiveActivityPlanner.diff(
            existing: [(id: "act-1", state: matching), (id: "act-2", state: orphanState)],
            planned: [plannedItem(matching), plannedItem(newState)]
        )

        #expect(toEnd == ["act-2"])
        #expect(toRequest.map(\.state) == [newState])
    }

    @Test("diff with changed content for same slot ends the old and requests the new")
    func diffContentChanged() {
        let slot = UUID()
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let d2 = Date(timeIntervalSince1970: 1_010_000)
        let old = state(title: "Old title", slotId: slot, start: d1, end: d2)
        let new = state(title: "New title", slotId: slot, start: d1, end: d2)

        let (toEnd, toRequest) = LiveActivityPlanner.diff(
            existing: [(id: "act-1", state: old)],
            planned: [plannedItem(new)]
        )

        #expect(toEnd == ["act-1"])
        #expect(toRequest.map(\.state) == [new])
    }

    @Test("diff with empty plan ends everything")
    func diffEmptyPlan() {
        let s = state(
            title: "A", slotId: UUID(),
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60))
        let (toEnd, toRequest) = LiveActivityPlanner.diff(
            existing: [(id: "act-1", state: s)], planned: [])
        #expect(toEnd == ["act-1"])
        #expect(toRequest.isEmpty)
    }
}
