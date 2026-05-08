import SwiftData
import SwiftUI

@MainActor
private var nextAddCommitmentViewDebugID = 0

struct AddCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CommitmentFormDraft
    @State private var debugID: Int

    @State private var currentCycleDialog = CurrentCycleDialogState()

    init() {
        nextAddCommitmentViewDebugID += 1
        let debugID = nextAddCommitmentViewDebugID
        _debugID = State(initialValue: debugID)
        let (start, end) = ReminderWindowsSection.defaultFirstWindow()
        _draft = State(
            initialValue: CommitmentFormDraft(
                slotWindows: [SlotDraft(start: start, end: end)]
            )
        )
        MemoryProbe.log("AddCommitment.init", extra: "view=\(debugID)")
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(
                    title: $draft.title,
                    cycle: $draft.cycle,
                    slotWindows: $draft.slotWindows,
                    target: $draft.target,
                    proofOfWorkType: $draft.proofOfWorkType,
                    punishment: $draft.punishment,
                    encouragements: $draft.encouragements,
                    selectedTags: $draft.selectedTags,
                    isRemindersEnabled: $draft.isRemindersEnabled
                )
            }
            .navigationTitle("New Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        MemoryProbe.log("AddCommitment.cancel", extra: debugExtra)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { handleSaveTap() }
                        .disabled(!draft.canSave)
                }
            }
            .currentCycleDialog(state: currentCycleDialog) { makeCurrentCycleInspirationOnly in
                persistCommitment(makeCurrentCycleInspirationOnly: makeCurrentCycleInspirationOnly)
            }
        }
        .onAppear {
            MemoryProbe.log("AddCommitment.appear", extra: debugExtra)
        }
        .onDisappear {
            MemoryProbe.log("AddCommitment.disappear", extra: debugExtra)
        }
        .onChange(of: draft.title) {
            MemoryProbe.log("AddCommitment.title.change", extra: debugExtra)
        }
        .onChange(of: draft.cycle) {
            MemoryProbe.log("AddCommitment.cycle.change", extra: debugExtra)
        }
        .onChange(of: draft.target) {
            MemoryProbe.log("AddCommitment.target.change", extra: debugExtra)
        }
        .onChange(of: draft.punishment) {
            MemoryProbe.log("AddCommitment.punishment.change", extra: debugExtra)
        }
        .onChange(of: draft.encouragements) {
            MemoryProbe.log("AddCommitment.encouragements.change", extra: debugExtra)
        }
        .onChange(of: draft.isRemindersEnabled) {
            MemoryProbe.log("AddCommitment.reminders.change", extra: debugExtra)
        }
    }

    private var debugExtra: String {
        "view=\(debugID) slots=\(draft.slotWindows.count) encouragements=\(draft.encouragements.count) tags=\(draft.selectedTags.count) reminders=\(draft.isRemindersEnabled) target=\(draft.target.count)/\(draft.target.configuredMode)"
    }

    /// Shows the current-cycle dialog only when Target On is selected.
    private func handleSaveTap() {
        MemoryProbe.log("AddCommitment.save.tap", extra: debugExtra)
        guard draft.target.configuredMode == .on else {
            persistCommitment(makeCurrentCycleInspirationOnly: false)
            return
        }
        let today = Time.startOfDay(for: Time.now())
        MemoryProbe.log("AddCommitment.currentCycleDialog.trigger", extra: debugExtra)
        currentCycleDialog.trigger(
            context: .creation,
            cycle: draft.cycle,
            cycleStart: draft.cycle.startDayOfCycle(including: today),
            cycleEnd: draft.cycle.endDayOfCycle(including: today)
        )
    }

    private func persistCommitment(makeCurrentCycleInspirationOnly: Bool) {
        MemoryProbe.log(
            "AddCommitment.persist.start",
            extra: "\(debugExtra) inspirationOnlyCurrentCycle=\(makeCurrentCycleInspirationOnly)"
        )
        var draftToSave = draft
        if makeCurrentCycleInspirationOnly {
            draftToSave.target.setConfiguredMode(
                .inspirationOnly(
                    start: currentCycleDialog.cycleStart,
                    until: currentCycleDialog.cycleEnd
                )
            )
        }
        let commitment = draftToSave.insertCommitment(in: modelContext)
        MemoryProbe.log(
            "AddCommitment.persist.slotsBuilt",
            extra:
                "\(debugExtra) effectiveReminders=\(draftToSave.effectiveRemindersEnabled) slots=\(commitment.slots.count)"
        )
        MemoryProbe.log(
            "AddCommitment.persist.inserted", extra: "\(debugExtra) id=\(commitment.id)")
        MemoryProbe.log(
            "AddCommitment.persist.beforeSave", extra: "\(debugExtra) id=\(commitment.id)")
        try? modelContext.save()
        MemoryProbe.log(
            "AddCommitment.persist.afterSave", extra: "\(debugExtra) id=\(commitment.id)")
        MemoryProbe.log(
            "AddCommitment.persist.beforeDismiss", extra: "\(debugExtra) id=\(commitment.id)")
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
