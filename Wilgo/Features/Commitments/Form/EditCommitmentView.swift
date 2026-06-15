import SwiftData
import SwiftUI

struct EditCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var commitment: Commitment

    @State private var draft: CommitmentFormDraft

    private let originalTarget: Target
    private let originalCycle: Cycle

    init(commitment: Commitment) {
        self.commitment = commitment
        _draft = State(initialValue: CommitmentFormDraft(commitment: commitment))
        originalTarget = commitment.target
        originalCycle = commitment.cycle
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(draft: $draft)
            }
            .navigationTitle("Edit Commitment")
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
        }
    }

    private var anyRuleChanged: Bool {
        draft.target != originalTarget || draft.cycle != originalCycle
    }

    private func handleSaveTap() {
        if anyRuleChanged {
            draft.cycle = Cycle.makeDefault(draft.cycle.kind)
        }
        saveChanges()
    }

    private func saveChanges() {
        draft.apply(to: commitment, in: modelContext)
        try? modelContext.save()
        CommitmentChangeRefresher.refreshAll()
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, Tag.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let slot = Slot(
        start: calendar.date(from: DateComponents(hour: 6)) ?? Date(),
        end: calendar.date(from: DateComponents(hour: 8)) ?? Date()
    )
    let commitment = Commitment(
        title: "Morning reading",
        cycle: Cycle.makeDefault(.daily),
        slots: [slot],
        target: Target(count: 1)
    )
    container.mainContext.insert(commitment)
    return EditCommitmentView(commitment: commitment)
        .modelContainer(container)
}
