import SwiftData
import SwiftUI

struct AddCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CommitmentFormDraft

    @State private var currentCycleDialog = CurrentCycleDialogState()

    init() {
        let (start, end) = ReminderWindowsSection.defaultFirstWindow()
        _draft = State(
            initialValue: CommitmentFormDraft(
                slotWindows: [SlotDraft(start: start, end: end)]
            )
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(draft: $draft)
            }
            .navigationTitle("New Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
    }

    /// Shows the current-cycle dialog only when Target On is selected.
    private func handleSaveTap() {
        guard draft.target.configuredMode == .on else {
            persistCommitment(makeCurrentCycleInspirationOnly: false)
            return
        }
        let today = Time.startOfDay(for: Time.now())
        currentCycleDialog.trigger(
            context: .creation,
            cycle: draft.cycle,
            cycleStart: draft.cycle.startDayOfCycle(including: today),
            cycleEnd: draft.cycle.endDayOfCycle(including: today)
        )
    }

    private func persistCommitment(makeCurrentCycleInspirationOnly: Bool) {
        var draftToSave = draft
        if makeCurrentCycleInspirationOnly {
            draftToSave.target.setConfiguredMode(
                .inspirationOnly(
                    start: currentCycleDialog.cycleStart,
                    until: currentCycleDialog.cycleEnd
                )
            )
        }
        draftToSave.insertCommitment(in: modelContext)
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
