import Foundation
import SwiftData
import Testing

@testable import Wilgo

@Suite("Commitment form draft", .serialized)
final class CommitmentFormDraftTests {
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Commitment.self, Slot.self, CheckIn.self,
            SlotSnooze.self, Tag.self, PositivityToken.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func date(hour: Int) -> Date {
        var components = DateComponents()
        components.year = 2000
        components.month = 1
        components.day = 1
        components.hour = hour
        return Calendar.current.date(from: components)!
    }

    @Test("draft creates normalized commitment and slots")
    @MainActor func createsNormalizedCommitment() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let tag = Tag(name: "Health", displayOrder: 0)
        context.insert(tag)

        var draft = CommitmentFormDraft()
        draft.title = "  Workout  "
        draft.cycle = Cycle.makeDefault(.daily)
        draft.target = Target(count: 2)
        draft.slotWindows = [
            SlotDraft(
                start: date(hour: 9),
                end: date(hour: 10),
                recurrence: .specificWeekdays([2, 4]),
                maxCheckIns: 3
            )
        ]
        draft.punishment = "  Pay 20 RMB  "
        draft.encouragements = ["  show up  ", "  ", "one rep"]
        draft.selectedTags = [tag]
        draft.isRemindersEnabled = true

        let commitment = draft.insertCommitment(in: context)
        try context.save()

        #expect(commitment.title == "Workout")
        #expect(commitment.punishment == "Pay 20 RMB")
        #expect(commitment.encouragements == ["show up", "one rep"])
        #expect(commitment.tags.map { $0.id } == [tag.id])
        #expect(commitment.isRemindersEnabled)
        #expect(commitment.slots.count == 1)
        #expect(commitment.slots.first?.maxCheckIns == 3)
        #expect(commitment.slots.first?.recurrence == .specificWeekdays([2, 4]))
    }

    @Test("draft applies scalar edits but preserves slots when reminders are disabled")
    @MainActor func appliesEditAndPreservesSlotsWhenRemindersDisabled() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let originalSlot = Slot(start: date(hour: 8), end: date(hour: 9), maxCheckIns: 1)
        let commitment = Commitment(
            title: "Read",
            cycle: Cycle.makeDefault(.daily),
            slots: [originalSlot],
            target: Target(count: 1)
        )
        context.insert(originalSlot)
        context.insert(commitment)

        var draft = CommitmentFormDraft(commitment: commitment)
        draft.title = "  Read slowly  "
        draft.punishment = "   "
        draft.encouragements = [" page one ", ""]
        draft.isRemindersEnabled = false
        draft.slotWindows = []

        draft.apply(to: commitment, in: context)
        try context.save()

        #expect(commitment.title == "Read slowly")
        #expect(commitment.punishment == nil)
        #expect(commitment.encouragements == ["page one"])
        #expect(commitment.isRemindersEnabled == false)
        #expect(commitment.slots.map(\.id) == [originalSlot.id])
        #expect(commitment.slots.first?.maxCheckIns == 1)
    }

    @Test("draft persists inspiration only target mode")
    @MainActor func persistsInspirationOnlyTargetMode() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let start = date(hour: 0)
        let until = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let mode = TargetMode.inspirationOnly(start: start, until: until)
        var draft = CommitmentFormDraft()
        draft.title = "Recover"
        draft.target = Target(count: 2, mode: mode)

        let commitment = draft.insertCommitment(in: context)
        try context.save()

        #expect(commitment.target.configuredMode == mode)
    }

    @Test("draft persists disabled target mode")
    @MainActor func persistsDisabledTargetMode() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var draft = CommitmentFormDraft()
        draft.title = "Recover"
        draft.target = Target(count: 2, mode: .disabled)

        let commitment = draft.insertCommitment(in: context)
        try context.save()

        #expect(commitment.target.configuredMode == .disabled)
    }

    @Test("draft reanchors inspiration only start but preserves selected until date")
    @MainActor func reanchorsInspirationOnlyStartAndPreservesUntilDate() {
        let originalStart = date(hour: 0)
        let originalUntil = Calendar.current.date(byAdding: .day, value: 1, to: originalStart)!
        let psychDay = Calendar.current.date(byAdding: .day, value: 8, to: originalStart)!
        let cycle = Cycle.makeDefault(.weekly, on: psychDay)
        var draft = CommitmentFormDraft(
            target: Target(
                count: 2,
                mode: .inspirationOnly(start: originalStart, until: originalUntil)
            )
        )

        draft.reanchorInspirationOnlyTarget(to: cycle, including: psychDay)

        #expect(
            draft.target.configuredMode == .inspirationOnly(
                start: cycle.startDayOfCycle(including: psychDay),
                until: originalUntil
            )
        )
    }

    @Test("finite inspiration only is invalid when until is not after today")
    @MainActor func finiteInspirationOnlyRequiresUntilAfterToday() {
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        Time.now = { today }
        defer { Time.now = { Date() } }

        let draft = CommitmentFormDraft(
            title: "Recover",
            cycle: Cycle.makeDefault(.daily, on: today),
            target: Target(
                count: 2,
                mode: .inspirationOnly(start: today, until: today)
            )
        )

        #expect(!draft.canSave)
    }

    @Test("weekly inspiration only requires until to be a cycle start")
    @MainActor func weeklyInspirationOnlyRequiresCycleStartUntil() {
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        Time.now = { monday }
        defer { Time.now = { Date() } }

        let tuesday = Calendar.current.date(byAdding: .day, value: 1, to: monday)!
        let nextMonday = Calendar.current.date(byAdding: .day, value: 7, to: monday)!

        var draft = CommitmentFormDraft(
            title: "Recover",
            cycle: Cycle.makeDefault(.weekly, on: monday),
            target: Target(
                count: 2,
                mode: .inspirationOnly(start: monday, until: tuesday)
            )
        )

        #expect(!draft.canSave)

        draft.target.setConfiguredMode(.inspirationOnly(start: monday, until: nextMonday))

        #expect(draft.canSave)
    }

    @Test("monthly inspiration only requires until to be a cycle start")
    @MainActor func monthlyInspirationOnlyRequiresCycleStartUntil() {
        let monthStart = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        Time.now = { monthStart }
        defer { Time.now = { Date() } }

        let midMonth = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 2))!
        let nextMonthStart = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1))!

        var draft = CommitmentFormDraft(
            title: "Recover",
            cycle: Cycle.makeDefault(.monthly, on: monthStart),
            target: Target(
                count: 2,
                mode: .inspirationOnly(start: monthStart, until: midMonth)
            )
        )

        #expect(!draft.canSave)

        draft.target.setConfiguredMode(.inspirationOnly(start: monthStart, until: nextMonthStart))

        #expect(draft.canSave)
    }
}
