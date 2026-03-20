import SwiftData
import SwiftUI

struct AddCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var target: Target = Target(
        cycle: Cycle.anchored(.daily, at: .now), count: 1)
    @State private var slotWindows: [SlotWindow]
    @State private var skipBudget: SkipBudget
    @State private var proofOfWorkType: ProofOfWorkType = .manual
    @State private var punishment: String = ""

    init() {
        let (start, end) = ReminderWindowsSection.defaultFirstWindow()
        _slotWindows = State(initialValue: [SlotWindow(start: start, end: end)])
        _skipBudget = State(
            initialValue: SkipBudget(
                cycle: Cycle.anchored(.weekly, at: .now), count: 0)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(
                    title: $title,
                    slotWindows: $slotWindows,
                    target: $target,
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
            && slotWindows.allSatisfy { $0.recurrence.isValidSelection }
    }

    private func saveCommitment() {
        let slots: [Slot] = slotWindows.map { window in
            let slot = Slot(start: window.start, end: window.end, recurrence: window.recurrence)
            modelContext.insert(slot)
            return slot
        }
        let sortedSlots = slots.sorted()
        let trimmedPunishment = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitment = Commitment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            slots: sortedSlots,
            target: target,
            skipBudget: skipBudget,
            proofOfWorkType: proofOfWorkType,
            punishment: trimmedPunishment.isEmpty ? nil : trimmedPunishment,
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
