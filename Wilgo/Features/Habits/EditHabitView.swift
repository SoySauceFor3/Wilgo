import SwiftData
import SwiftUI

struct EditHabitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var habit: Habit

    @State private var title: String
    @State private var goalCountPerDay: Int
    @State private var slotWindows: [SlotWindow]
    @State private var skipCreditCount: Int
    @State private var cycle: Cycle
    @State private var proofOfWorkType: ProofOfWorkType
    @State private var punishment: String

    /// Snapshot of rule values at open time, used to detect if any rule changed.
    private let originalGoalCountPerDay: Int
    private let originalSkipCreditCount: Int
    private let originalCycle: Cycle

    init(habit: Habit) {
        self.habit = habit

        _title = State(initialValue: habit.title)
        _goalCountPerDay = State(initialValue: habit.goalCountPerDay)
        _slotWindows = State(
            initialValue: habit.slots.sorted().map { SlotWindow(start: $0.start, end: $0.end) })
        _skipCreditCount = State(initialValue: habit.skipCreditCount)
        _cycle = State(initialValue: habit.cycle)
        _proofOfWorkType = State(initialValue: habit.proofOfWorkType)
        _punishment = State(initialValue: habit.punishment ?? "")

        originalGoalCountPerDay = habit.goalCountPerDay
        originalSkipCreditCount = habit.skipCreditCount
        originalCycle = habit.cycle
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
                    punishment: $punishment,
                    rulesChangedNote: anyRuleChanged
                        ? "Changing rules starts a fresh cycle from today." : nil
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

    /// True when any rule field (timesPerDay, skipCreditCount, cycle) changed.
    /// Rule changes re-anchor the cycle to today so the new rules start from a clean slate.
    private var anyRuleChanged: Bool {
        goalCountPerDay != originalGoalCountPerDay || skipCreditCount != originalSkipCreditCount
            || cycle != originalCycle
    }

    // MARK: - Save

    private func saveChanges() {
        // Apply scalar field changes.
        habit.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.skipCreditCount = skipCreditCount
        habit.proofOfWorkType = proofOfWorkType
        let trimmed = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        habit.punishment = trimmed.isEmpty ? nil : trimmed

        // Any change to a rule field signals a new commitment — re-anchor the cycle
        // to today so the new rules apply from a clean slate.
        // See documentation/Edit Habit Feature.md for rationale.
        var resolvedCycle = cycle
        if anyRuleChanged {
            let cal = Calendar.current
            switch cycle {
            case .daily: break
            case .weekly: resolvedCycle = .weekly(weekday: cal.component(.weekday, from: .now))
            case .monthly: resolvedCycle = .monthly(day: cal.component(.day, from: .now))
            }
        }
        habit.cycle = resolvedCycle

        // Replace slots only if the count or any window changed.
        let newWindows = slotWindows
        let oldSlots = habit.slots.sorted()
        let slotsChanged =
            newWindows.count != oldSlots.count
            || zip(newWindows, oldSlots).contains { w, s in w.start != s.start || w.end != s.end }

        if slotsChanged {
            for old in habit.slots { modelContext.delete(old) }
            let newSlots: [Slot] = newWindows.map { window in
                let slot = Slot(start: window.start, end: window.end)
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
        for: Habit.self, Slot.self, HabitCheckIn.self, SnoozedSlot.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let slot = Slot(
        start: calendar.date(from: DateComponents(hour: 6)) ?? Date(),
        end: calendar.date(from: DateComponents(hour: 8)) ?? Date()
    )
    let habit = Habit(
        title: "Morning reading",
        slots: [slot],
        skipCreditCount: 3,
        cycle: .weekly(weekday: 2),
        goalCountPerDay: 1
    )
    container.mainContext.insert(habit)
    return EditHabitView(habit: habit)
        .modelContainer(container)
}
