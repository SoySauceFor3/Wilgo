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
        target: Target = Target(count: 5),
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
            && inspirationOnlyUntilValidation == nil
    }

    var effectiveRemindersEnabled: Bool {
        isRemindersEnabled && !slotWindows.isEmpty
    }

    var inspirationOnlyUntilValidation: String? {
        inspirationOnlyUntilValidation(on: Time.startOfDay(for: Time.now()))
    }

    func inspirationOnlyUntilValidation(on psychToday: Date) -> String? {
        guard case .inspirationOnly(_, let until) = target.configuredMode else { return nil }
        guard let until else { return nil }

        let untilDay = Time.startOfDay(for: until)
        let today = Time.startOfDay(for: psychToday)

        if untilDay <= today {
            return "Choose a date after today."
        }

        if cycle.startDayOfCycle(including: untilDay) != untilDay {
            switch cycle.kind {
            case .daily:
                return nil
            case .weekly:
                return "Choose a Monday so Inspiration Only ends at the start of a week."
            case .monthly:
                return "Choose the 1st of a month so Inspiration Only ends at the start of a month."
            }
        }

        return nil
    }

    mutating func reanchorInspirationOnlyTarget(
        to cycle: Cycle,
        including psychDay: Date = Time.startOfDay(for: Time.now())
    ) {
        guard case .inspirationOnly(_, let until) = target.configuredMode else { return }
        let start = cycle.startDayOfCycle(including: psychDay)
        target.setConfiguredMode(
            .inspirationOnly(start: start, until: until.map { Time.startOfDay(for: $0) })
        )
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
