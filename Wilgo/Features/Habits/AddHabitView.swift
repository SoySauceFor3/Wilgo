import SwiftUI
import SwiftData

private struct SlotWindow: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
}

struct AddHabitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var timesPerDay: Int = 1
    @State private var slotWindows: [SlotWindow]
    @State private var skipCreditCount: Int = 1
    @State private var skipCreditPeriod: Period = .weekly
    @State private var proofOfWorkType: ProofOfWorkType = .manual
    @State private var punishment: String = ""

    private static func defaultWindow() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        let end = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        return (start, end)
    }

    init() {
        let (start, end) = AddHabitView.defaultWindow()
        _slotWindows = State(initialValue: [SlotWindow(start: start, end: end)])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Title", text: $title)

                    Stepper(value: $timesPerDay, in: 1...21) {
                        Text("Times per day: \(timesPerDay)")
                    }
                }

                Section("Ideal windows") {
                    ForEach(Array(slotWindows.enumerated()), id: \.element.id) { index, _ in
                        Section("Slot \(index + 1)") {
                            DatePicker(
                                "Start",
                                selection: startBinding(for: index),
                                displayedComponents: .hourAndMinute
                            )
                            DatePicker(
                                "End",
                                selection: endBinding(for: index),
                                displayedComponents: .hourAndMinute
                            )
                        }
                    }
                }
                .onChange(of: timesPerDay) { _, newCount in
                    let (defaultStart, defaultEnd) = Self.defaultWindow()
                    if slotWindows.count < newCount {
                        let toAdd = newCount - slotWindows.count
                        slotWindows.append(contentsOf: (0..<toAdd).map { _ in SlotWindow(start: defaultStart, end: defaultEnd) })
                    } else if slotWindows.count > newCount {
                        slotWindows = Array(slotWindows.prefix(newCount))
                    }
                }

                Section("Skip credits") {
                    Picker("Reset period", selection: $skipCreditPeriod) {
                        ForEach([Period.daily, .weekly, .monthly], id: \.self) { period in
                            Text(period.rawValue)
                                .tag(period)
                        }
                    }

                    Stepper(value: $skipCreditCount, in: 0...30) {
                        Text("Skip credits: \(skipCreditCount)")
                    }
                }

                Section {
                    TextField("e.g. Give robaroba 20 RMB", text: $punishment, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Punishment if credits run out")
                } footer: {
                    Text("Leave blank for no punishment.")
                }

                Section("Proof of work") {
                    Picker("Type", selection: $proofOfWorkType) {
                        Text(ProofOfWorkType.manual.rawValue)
                            .tag(ProofOfWorkType.manual)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("New Habit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveHabit()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startBinding(for index: Int) -> Binding<Date> {
        Binding(
            get: { slotWindows[index].start },
            set: { newValue in
                var copy = slotWindows
                copy[index].start = newValue
                slotWindows = copy
            }
        )
    }

    private func endBinding(for index: Int) -> Binding<Date> {
        Binding(
            get: { slotWindows[index].end },
            set: { newValue in
                var copy = slotWindows
                copy[index].end = newValue
                slotWindows = copy
            }
        )
    }

    private func saveHabit() {
        let slots: [HabitSlot] = slotWindows.map { window in
            let slot = HabitSlot(
                start: window.start,
                end: window.end
            )
            modelContext.insert(slot)
            return slot
        }
        // this uses the Comparable conformance for HabitSlot in @Wilgo/Shared/Models/Habit.swift.
        let sortedSlots = slots.sorted()

        let trimmedPunishment = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let habit = Habit(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            slots: sortedSlots,
            skipCreditCount: skipCreditCount,
            skipCreditPeriod: skipCreditPeriod,
            proofOfWorkType: proofOfWorkType,
            punishment: trimmedPunishment.isEmpty ? nil : trimmedPunishment
        )

        modelContext.insert(habit)
        print(habit)
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Habit.self, HabitSlot.self, HabitCheckIn.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    AddHabitView()
        .modelContainer(container)
}

