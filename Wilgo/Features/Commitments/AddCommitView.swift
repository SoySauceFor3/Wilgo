import SwiftData
import SwiftUI

struct AddCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var cycle: Cycle = Cycle.makeDefault(.daily)
    @State private var target: Target = Target(count: 5, isEnabled: true)
    @State private var slotWindows: [SlotDraft]
    @State private var proofOfWorkType: ProofOfWorkType = .manual
    @State private var punishment: String = ""
    @State private var encouragements: [String] = []
    @State private var selectedTags: [Tag] = []
    @State private var isRemindersEnabled: Bool = true

    @State private var graceDialog = GraceDialogState()

    init() {
        let (start, end) = ReminderWindowsSection.defaultFirstWindow()
        _slotWindows = State(initialValue: [SlotDraft(start: start, end: end)])
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(
                    title: $title,
                    cycle: $cycle,
                    slotWindows: $slotWindows,
                    target: $target,
                    proofOfWorkType: $proofOfWorkType,
                    punishment: $punishment,
                    encouragements: $encouragements,
                    selectedTags: $selectedTags,
                    isRemindersEnabled: $isRemindersEnabled
                )
            }
            .navigationTitle("New Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { handleSaveTap() }
                        .disabled(!canSave)
                }
            }
            .graceDialog(state: graceDialog) { grace in
                persistCommitment(grace: grace)
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!isRemindersEnabled || slotWindows.allSatisfy { $0.recurrence.isValidSelection })
    }

    /// Shows the grace dialog, or saves directly if target is disabled (no goal to penalize against).
    private func handleSaveTap() {
        guard target.isEnabled else {
            persistCommitment(grace: false)
            return
        }
        let today = Time.startOfDay(for: Time.now())
        graceDialog.trigger(
            context: .creation,
            cycle: cycle,
            cycleStart: cycle.startDayOfCycle(including: today),
            cycleEnd: cycle.endDayOfCycle(including: today)
        )
    }

    private func persistCommitment(grace: Bool) {
        let effectiveRemindersEnabled = isRemindersEnabled && !slotWindows.isEmpty
        let slots: [Slot] =
            effectiveRemindersEnabled
            ? slotWindows.map { window in
                let slot = Slot(start: window.start, end: window.end, recurrence: window.recurrence)
                modelContext.insert(slot)
                return slot
            } : []
        let trimmedPunishment = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitment = Commitment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            cycle: cycle,
            slots: slots.sorted(),
            target: target,
            proofOfWorkType: proofOfWorkType,
            punishment: trimmedPunishment.isEmpty ? nil : trimmedPunishment,
            isRemindersEnabled: effectiveRemindersEnabled
        )
        if grace {
            commitment.gracePeriods.append(
                GracePeriod(
                    startPsychDay: graceDialog.cycleStart,
                    endPsychDay: graceDialog.cycleEnd,
                    reason: .creation
                )
            )
        }
        modelContext.insert(commitment)
        commitment.encouragements = encouragements.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        commitment.tags = selectedTags
        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, Tag.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    AddCommitmentView()
        .modelContainer(container)
}
