import Foundation
import SwiftData
import Testing
@testable import Wilgo

@Suite(.serialized)
final class CommitmentFormDraftTests {
    @Test("draft creates normalized commitment and slots")
    @MainActor func createsNormalizedCommitment() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let tag = Tag(name: "Health", displayOrder: 0)
        context.insert(tag)

        var draft = CommitmentFormDraft()
        draft.title = "  Workout  "
        draft.cycle = Cycle.makeDefault(.daily)
        draft.target = Target(count: 2)
        draft.slotWindows = [
            SlotDraft(
                start: timeOfDay(hour: 9),
                end: timeOfDay(hour: 10),
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
        #expect(commitment.tags.map(\.id) == [tag.id])
        #expect(commitment.isRemindersEnabled)
        #expect(commitment.slots.count == 1)
        #expect(commitment.slots.first?.maxCheckIns == 3)
        #expect(commitment.slots.first?.recurrence == .specificWeekdays([2, 4]))
    }

    @Test("draft applies scalar edits but preserves slots when reminders are disabled")
    @MainActor func appliesEditAndPreservesSlotsWhenRemindersDisabled() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let originalSlot = Slot(start: timeOfDay(hour: 8), end: timeOfDay(hour: 9), maxCheckIns: 1)
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

    @Test("draft persists disabled target mode")
    @MainActor func persistsDisabledTargetMode() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        var draft = CommitmentFormDraft()
        draft.title = "Recover"
        draft.target = Target(count: 2, mode: .disabled)

        let commitment = draft.insertCommitment(in: context)
        try context.save()

        #expect(commitment.target.configuredMode == .disabled)
    }
}
