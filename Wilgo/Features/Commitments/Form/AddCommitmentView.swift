import SwiftData
import SwiftUI

struct AddCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CommitmentFormDraft

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
                    Button("Save") { persistCommitment() }
                        .disabled(!draft.canSave)
                }
            }
        }
    }

    private func persistCommitment() {
        draft.insertCommitment(in: modelContext)
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
