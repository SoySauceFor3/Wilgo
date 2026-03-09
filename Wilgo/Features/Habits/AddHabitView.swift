import SwiftData
import SwiftUI

struct AddHabitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var goalCountPerDay: Int = 1
    @State private var slotWindows: [SlotWindow]
    @State private var skipCreditCount: Int = 1
    @State private var cycle: Cycle = .weekly(
        weekday: Calendar.current.component(.weekday, from: HabitScheduling.psychDay(for: .now)))
    @State private var proofOfWorkType: ProofOfWorkType = .manual
    @State private var punishment: String = ""

    init() {
        let (start, end) = HabitFormFields.defaultFirstWindow()
        _slotWindows = State(initialValue: [SlotWindow(start: start, end: end)])
    }

    var body: some View {
        NavigationStack {
            Form {
                HabitFormFields(
                    title: $title,
                    goalCountPerDay: $goalCountPerDay,
                    slotWindows: $slotWindows,
                    skipCreditCount: $skipCreditCount,
                    cycle: $cycle,
                    proofOfWorkType: $proofOfWorkType,
                    punishment: $punishment
                )
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveHabit() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveHabit() {
        let slots: [Slot] = slotWindows.map { window in
            let slot = Slot(start: window.start, end: window.end)
            modelContext.insert(slot)
            return slot
        }
        let sortedSlots = slots.sorted()
        let trimmedPunishment = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let habit = Habit(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            slots: sortedSlots,
            skipCreditCount: skipCreditCount,
            cycle: cycle,
            proofOfWorkType: proofOfWorkType,
            punishment: trimmedPunishment.isEmpty ? nil : trimmedPunishment,
            goalCountPerDay: goalCountPerDay
        )
        modelContext.insert(habit)
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Habit.self, Slot.self, HabitCheckIn.self, SnoozedSlot.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    AddHabitView()
        .modelContainer(container)
}
