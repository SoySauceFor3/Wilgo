import SwiftUI

struct CommitmentFormFields: View {
    @Binding var title: String
    @Binding var slotWindows: [SlotWindow]
    @Binding var target: Target
    @Binding var proofOfWorkType: ProofOfWorkType
    @Binding var punishment: String
    @Binding var encouragements: [String]

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
    }

    // MARK: - Helpers

    /// Maps the cycle binding to/from a CycleKind for the Picker.
    /// When the kind changes, a new Cycle is constructed anchored to the canonical start day
    /// (Monday for weekly, 1st for monthly, today for daily).
    private var targetCycleKindBinding: Binding<CycleKind> {
        Binding(
            get: { target.cycle.kind },
            set: { newKind in
                target.cycle = Cycle.makeDefault(newKind)
            }
        )
    }

    /// Allowed skip-budget cycle kinds for the current target cycle (Option B-style).
    /// - Daily target: may use daily / weekly / monthly budgets.
    /// - Weekly target: constrained to weekly budgets (multi-week in future via length multipliers).
    /// - Monthly target: constrained to monthly budgets (multi-month in future via length multipliers).
    private var allowedSkipBudgetCycleKinds: [CycleKind] {
        switch target.cycle.kind {
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

struct EncouragementSection: View {
    @Binding var encouragements: [String]
    @FocusState private var focusedIndex: Int?

    var body: some View {
        Section {
            ForEach(encouragements.indices, id: \.self) { index in
                HStack {
                    TextField("e.g. Just do a little bit", text: $encouragements[index])
                        .focused($focusedIndex, equals: index)
                    Spacer()
                    Button(role: .destructive) {
                        encouragements.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Button {
                encouragements.append("")
                focusedIndex = encouragements.count - 1
            } label: {
                Label("Add encouragement", systemImage: "plus")
            }
        } header: {
            Text("Encouragement")
        } footer: {
            Text("Shown randomly while you work.")
        }
    }
}
