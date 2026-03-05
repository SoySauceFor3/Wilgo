import SwiftUI
import SwiftData

struct EditHabitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var habit: Habit

    @State private var title: String
    @State private var timesPerDay: Int
    @State private var slotWindows: [SlotWindow]
    @State private var skipCreditCount: Int
    @State private var skipCreditPeriod: Period
    @State private var proofOfWorkType: ProofOfWorkType
    @State private var punishment: String

    /// Snapshot of rule values at open time, used to detect if any rule changed.
    private let originalTimesPerDay: Int
    private let originalSkipCreditCount: Int
    private let originalSkipCreditPeriod: Period

    init(habit: Habit) {
        self.habit = habit

        _title            = State(initialValue: habit.title)
        _timesPerDay      = State(initialValue: habit.slots.count)
        _slotWindows      = State(initialValue: habit.slots.sorted().map { SlotWindow(start: $0.start, end: $0.end) })
        _skipCreditCount  = State(initialValue: habit.skipCreditCount)
        _skipCreditPeriod = State(initialValue: habit.skipCreditPeriod)
        _proofOfWorkType  = State(initialValue: habit.proofOfWorkType)
        _punishment       = State(initialValue: habit.punishment ?? "")

        originalTimesPerDay      = habit.slots.count
        originalSkipCreditCount  = habit.skipCreditCount
        originalSkipCreditPeriod = habit.skipCreditPeriod
    }

    var body: some View {
        NavigationStack {
            Form {
                HabitFormFields(
                    title: $title,
                    timesPerDay: $timesPerDay,
                    slotWindows: $slotWindows,
                    skipCreditCount: $skipCreditCount,
                    skipCreditPeriod: $skipCreditPeriod,
                    proofOfWorkType: $proofOfWorkType,
                    punishment: $punishment,
                    rulesChangedNote: anyRuleChanged ? "Changing rules starts a fresh period from today." : nil
                )
            }
            .navigationTitle("Edit Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Derived state

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when any rule field (timesPerDay, skipCreditCount, skipCreditPeriod) changed.
    /// Rule changes reset the period anchor to today — see documentation/Edit Habit Feature.md.
    private var anyRuleChanged: Bool {
        timesPerDay     != originalTimesPerDay     ||
        skipCreditCount != originalSkipCreditCount ||
        skipCreditPeriod != originalSkipCreditPeriod
    }

    // MARK: - Save

    private func saveChanges() {
        // Apply scalar field changes.
        habit.title           = title.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.skipCreditCount = skipCreditCount
        habit.skipCreditPeriod = skipCreditPeriod
        habit.proofOfWorkType = proofOfWorkType
        let trimmed           = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.punishment      = trimmed.isEmpty ? nil : trimmed

        // Any change to a rule field signals a new commitment — reset the period
        // anchor to today so the new rules apply from a clean slate.
        // See documentation/Edit Habit Feature.md for rationale.
        if anyRuleChanged {
            habit.periodAnchor = .now
        }

        // Replace slots only if the count or any window changed.
        let newWindows = slotWindows
        let oldSlots   = habit.slots.sorted()
        let slotsChanged = newWindows.count != oldSlots.count
            || zip(newWindows, oldSlots).contains { w, s in w.start != s.start || w.end != s.end }

        if slotsChanged {
            for old in habit.slots { modelContext.delete(old) }
            let newSlots: [HabitSlot] = newWindows.map { window in
                let slot = HabitSlot(start: window.start, end: window.end)
                modelContext.insert(slot)
                return slot
            }
            habit.slots = newSlots.sorted()
        }

        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Habit.self, HabitSlot.self, HabitCheckIn.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let slot = HabitSlot(
        start: calendar.date(from: DateComponents(hour: 6)) ?? Date(),
        end:   calendar.date(from: DateComponents(hour: 8)) ?? Date()
    )
    let habit = Habit(
        title: "Morning reading",
        slots: [slot],
        skipCreditCount: 3,
        skipCreditPeriod: .weekly
    )
    container.mainContext.insert(habit)
    return EditHabitView(habit: habit)
        .modelContainer(container)
}
