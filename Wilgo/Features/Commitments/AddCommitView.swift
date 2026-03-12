import SwiftData
import SwiftUI

struct AddCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var goalCountPerDay: Int = 1
    @State private var slotWindows: [SlotWindow]
    @State private var skipCreditCount: Int = 1
    @State private var cycle: Cycle = Cycle.anchored(.weekly, at: .now)
    @State private var proofOfWorkType: ProofOfWorkType = .manual
    @State private var punishment: String = ""

    init() {
        let (start, end) = CommitmentFormFields.defaultFirstWindow()
        _slotWindows = State(initialValue: [SlotWindow(start: start, end: end)])
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(
                    title: $title,
                    goalCountPerDay: $goalCountPerDay,
                    slotWindows: $slotWindows,
                    skipCreditCount: $skipCreditCount,
                    cycle: $cycle,
                    proofOfWorkType: $proofOfWorkType,
                    punishment: $punishment
                )
            }
            .navigationTitle("New Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCommitment() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveCommitment() {
        let slots: [Slot] = slotWindows.map { window in
            let slot = Slot(start: window.start, end: window.end)
            modelContext.insert(slot)
            return slot
        }
        let sortedSlots = slots.sorted()
        let trimmedPunishment = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitment = Commitment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            slots: sortedSlots,
            skipCreditCount: skipCreditCount,
            cycle: cycle,
            proofOfWorkType: proofOfWorkType,
            punishment: trimmedPunishment.isEmpty ? nil : trimmedPunishment,
            goalCountPerDay: goalCountPerDay
        )
        modelContext.insert(commitment)
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    AddCommitmentView()
        .modelContainer(container)
}
