import SwiftUI

/// Shared form body used by both AddHabitView and EditHabitView.
/// Owns no SwiftData interactions — all state is passed in via bindings.
struct HabitFormFields: View {
    @Binding var title: String
    @Binding var goalCountPerDay: Int
    @Binding var slotWindows: [SlotWindow]
    @Binding var skipCreditCount: Int
    @Binding var cycle: Cycle
    @Binding var proofOfWorkType: ProofOfWorkType
    @Binding var punishment: String

    /// When non-nil, a neutral info note is shown at the top of the form.
    /// Used by EditHabitView to indicate that rule changes start a fresh period.
    var rulesChangedNote: String?

    var body: some View {
        if let note = rulesChangedNote {
            Section {
                Label(note, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Basics") {
            TextField("Title", text: $title)

            Stepper(value: $goalCountPerDay, in: 1...21) {
                Text("Goal per day: \(goalCountPerDay)")
            }
        }

        Section("Ideal windows") {
            Text("Optional. Leave empty to allow any time of the day.")
                .font(.footnote)
                .foregroundStyle(.secondary)

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
            Button {
                let (defaultStart, defaultEnd) = Self.defaultWindow()
                slotWindows.append(SlotWindow(start: defaultStart, end: defaultEnd))
            } label: {
                Label("Add window", systemImage: "plus")
            }
        }

        Section("Skip credits") {
            Picker("Reset cycle", selection: cycleKindBinding) {
                ForEach(CycleKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue).tag(kind)
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
                Text(ProofOfWorkType.manual.rawValue).tag(ProofOfWorkType.manual)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Helpers

    /// Maps the cycle binding to/from a CycleKind for the Picker.
    /// When the kind changes, a new Cycle is constructed anchored to today(PsychDay).
    private var cycleKindBinding: Binding<CycleKind> {
        Binding(
            get: { cycle.kind },
            set: { newKind in
                let cal = Calendar.current
                let today = HabitScheduling.psychDay(for: .now)
                switch newKind {
                case .daily:
                    cycle = .daily
                case .weekly:
                    cycle = .weekly(weekday: cal.component(.weekday, from: today))
                case .monthly:
                    cycle = .monthly(day: cal.component(.day, from: today))
                }
            }
        )
    }

    static func defaultWindow() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now) ?? now
        let end = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now) ?? now
        return (start, end)
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
}

// MARK: - SlotWindow (shared value type)

struct SlotWindow: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
}
