import SwiftData
import SwiftUI

struct CommitmentFormFields: View {
    @Binding var title: String
    @Binding var cycle: Cycle
    @Binding var slotWindows: [SlotWindow]
    @Binding var target: Target
    @Binding var proofOfWorkType: ProofOfWorkType
    @Binding var punishment: String
    @Binding var encouragements: [String]
    @Binding var selectedTags: [Tag]

    var body: some View {
        Section("Basics") {
            TextField("Title", text: $title)
        }
        ReminderWindowsSection(slotWindows: $slotWindows)
        EncouragementSection(encouragements: $encouragements)

        Section("Target") {
            HStack(spacing: 4) {
                Picker("", selection: targetCountBinding) {
                    ForEach(0..<31, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()

                Text("every")

                Picker("", selection: targetCycleKindBinding) {
                    ForEach(CycleKind.allCases, id: \.self) { kind in
                        Text(kind.rawValue.lowercased()).tag(kind)
                    }
                }
                .labelsHidden()
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

        TagPickerSection(selectedTags: $selectedTags)
    }

    // MARK: - Helpers

    /// Maps the cycle binding to/from a CycleKind for the Picker.
    /// When the kind changes, a new Cycle is constructed anchored to the canonical start day
    /// (Monday for weekly, 1st for monthly, today for daily).
    private var targetCycleKindBinding: Binding<CycleKind> {
        Binding(
            get: { cycle.kind },
            set: { newKind in
                cycle = Cycle.makeDefault(newKind)
            }
        )
    }

    /// Allowed skip-budget cycle kinds for the current target cycle (Option B-style).
    /// - Daily target: may use daily / weekly / monthly budgets.
    /// - Weekly target: constrained to weekly budgets (multi-week in future via length multipliers).
    /// - Monthly target: constrained to monthly budgets (multi-month in future via length multipliers).
    private var allowedSkipBudgetCycleKinds: [CycleKind] {
        switch cycle.kind {
        case .daily:
            return CycleKind.allCases
        case .weekly:
            return [.weekly]
        case .monthly:
            return [.monthly]
        }
    }

    /// Exposes the target's countPerCycle as a Binding<Int> for the Stepper.
    private var targetCountBinding: Binding<Int> {
        Binding(
            get: { target.count },
            set: { newValue in
                target.count = newValue
            }
        )
    }
}

// MARK: - Encouragement section (used by commitment form)

private struct TaggedEncouragement: Identifiable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct EncouragementSection: View {
    @Binding var encouragements: [String]
    @State private var tagged: [TaggedEncouragement] = []
    @FocusState private var focusedID: UUID?

    var body: some View {
        Section {
            ForEach($tagged) { $item in
                HStack {
                    TextField("e.g. Just do a little bit", text: $item.text)
                        .focused($focusedID, equals: item.id)
                    Spacer()
                    Button(role: .destructive) {
                        tagged.removeAll { $0.id == item.id }
                        flush()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .onChange(of: item.text) { flush() }
            }

            Button {
                let newItem = TaggedEncouragement(text: "")
                tagged.append(newItem)
                focusedID = newItem.id
                flush()
            } label: {
                Label("Add encouragement", systemImage: "plus")
            }
        } header: {
            Text("Encouragement")
        } footer: {
            Text("Shown randomly while you work.")
        }
        .onAppear {
            tagged = encouragements.map { TaggedEncouragement(text: $0) }
        }
    }

    private func flush() {
        encouragements = tagged.map(\.text)
    }
}
