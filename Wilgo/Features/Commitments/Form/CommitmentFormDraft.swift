import Foundation
import SwiftData

struct CommitmentFormDraft {
    var title: String
    var cycle: Cycle
    var slotWindows: [SlotDraft]
    var target: Target
    var proofOfWorkType: ProofOfWorkType
    var punishment: String
    var encouragements: [String]
    var selectedTags: [Tag]
    var isRemindersEnabled: Bool

    init(
        title: String = "",
        cycle: Cycle = Cycle.makeDefault(.daily),
        slotWindows: [SlotDraft] = [],
        target: Target = Target(count: 5, isEnabled: true),
        proofOfWorkType: ProofOfWorkType = .manual,
        punishment: String = "",
        encouragements: [String] = [],
        selectedTags: [Tag] = [],
        isRemindersEnabled: Bool = true
    ) {
        self.title = title
        self.cycle = cycle
        self.slotWindows = slotWindows
        self.target = target
        self.proofOfWorkType = proofOfWorkType
        self.punishment = punishment
        self.encouragements = encouragements
        self.selectedTags = selectedTags
        self.isRemindersEnabled = isRemindersEnabled
    }

    init(commitment: Commitment) {
        self.init(
            title: commitment.title,
            cycle: commitment.cycle,
            slotWindows: commitment.slots.sorted().map {
                SlotDraft(
                    start: $0.start,
                    end: $0.end,
                    recurrence: $0.recurrence,
                    isWholeDay: $0.isWholeDay,
                    maxCheckIns: $0.maxCheckIns
                )
            },
            target: commitment.target,
            proofOfWorkType: commitment.proofOfWorkType,
            punishment: commitment.punishment ?? "",
            encouragements: commitment.encouragements,
            selectedTags: commitment.tags,
            isRemindersEnabled: commitment.isRemindersEnabled
        )
    }

    var canSave: Bool {
        !normalizedTitle.isEmpty
            && (!isRemindersEnabled || slotWindows.allSatisfy { $0.recurrence.isValidSelection })
    }

    var effectiveRemindersEnabled: Bool {
        isRemindersEnabled && !slotWindows.isEmpty
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPunishment: String? {
        let trimmed = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var normalizedEncouragements: [String] {
        encouragements.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    @MainActor
    func insertCommitment(in modelContext: ModelContext) -> Commitment {
        let slots = effectiveRemindersEnabled ? insertedSlots(in: modelContext) : []
        let commitment = Commitment(
            title: normalizedTitle,
            cycle: cycle,
            slots: slots.sorted(),
            target: target,
            proofOfWorkType: proofOfWorkType,
            punishment: normalizedPunishment,
            isRemindersEnabled: effectiveRemindersEnabled
        )
        modelContext.insert(commitment)
        commitment.encouragements = normalizedEncouragements
        commitment.tags = selectedTags
        return commitment
    }

    @MainActor
    func apply(to commitment: Commitment, in modelContext: ModelContext) {
        commitment.title = normalizedTitle
        commitment.proofOfWorkType = proofOfWorkType
        commitment.punishment = normalizedPunishment
        commitment.encouragements = normalizedEncouragements
        commitment.cycle = cycle
        commitment.target = target
        commitment.tags = selectedTags
        commitment.isRemindersEnabled = effectiveRemindersEnabled

        guard effectiveRemindersEnabled else { return }

        for old in commitment.slots {
            modelContext.delete(old)
        }
        commitment.slots = insertedSlots(in: modelContext).sorted()
    }

    @MainActor
    private func insertedSlots(in modelContext: ModelContext) -> [Slot] {
        slotWindows.map { window in
            let slot = Slot(
                start: window.start,
                end: window.end,
                recurrence: window.recurrence,
                maxCheckIns: window.maxCheckIns
            )
            modelContext.insert(slot)
            return slot
        }
    }
}
