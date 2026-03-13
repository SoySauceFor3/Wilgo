import SwiftUI

/// Shared form body used by both AddCommitmentView and EditCommitmentView.
/// Owns no SwiftData interactions — all state is passed in via bindings.
struct CommitmentFormFields: View {
    @Binding var title: String
    @Binding var slotWindows: [SlotWindow]
    @Binding var target: Target
    @Binding var skipBudget: SkipBudget
    @Binding var proofOfWorkType: ProofOfWorkType
    @Binding var punishment: String

    /// When non-nil, a neutral info note is shown at the top of the form.
    /// Used by EditCommitmentView to indicate that rule changes start a fresh period.
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
        }

        Section("Reminder windows") {
            Text("Optional. Leave empty to allow any time of the day.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(Array(slotWindows.enumerated()), id: \.element.id) { index, window in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Slot \(index + 1)")
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 8) {
                            DatePicker(
                                "",
                                selection: startBinding(for: index),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()

                            Text("–")
                                .foregroundStyle(.secondary)

                            DatePicker(
                                "",
                                selection: endBinding(for: index),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden()
                        }
                        .font(.footnote)

                        if window.end < window.start {
                            Text("Crosses midnight")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button(role: .destructive) {
                        slotWindows.remove(at: index)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            Button {
                let (defaultStart, defaultEnd) = defaultWindowForNewSlot()
                slotWindows.append(SlotWindow(start: defaultStart, end: defaultEnd))
            } label: {
                Label("Add window", systemImage: "plus")
            }
        }

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

        Section("Skip credits") {
            HStack(spacing: 4) {
                Picker("", selection: skipBudgetCountBinding) {
                    ForEach(0..<31, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()

                Text("every")

                Picker("", selection: skipBudgetMultiplierBinding) {
                    ForEach(1..<30, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()

                Picker("", selection: skipBudgetCycleKindBinding) {
                    ForEach(allowedSkipBudgetCycleKinds, id: \.self) { kind in
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
    /// When the kind changes, a new Cycle is constructed anchored to today(PsychDay).
    private var targetCycleKindBinding: Binding<CycleKind> {
        Binding(
            get: { target.cycle.kind },
            set: { newKind in
                target.cycle = Cycle.anchored(newKind, at: .now)
                enforceCompatibleSkipBudgetCycle()
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
    /// Maps the cycle binding to/from a CycleKind for the Picker.
    /// When the kind changes, a new Cycle is constructed anchored to today(PsychDay).
    private var skipBudgetCycleKindBinding: Binding<CycleKind> {
        Binding(
            get: { skipBudget.cycle.kind },
            set: { newKind in
                skipBudget.cycle = Cycle.anchored(newKind, at: .now)
            }
        )
    }

    /// Exposes the skipBudget's count as a Binding<Int> for the Picker.
    private var skipBudgetCountBinding: Binding<Int> {
        Binding(
            get: { skipBudget.count },
            set: { newValue in
                skipBudget.count = newValue
            }
        )
    }

    /// Exposes the skipBudget's multiplier as a Binding<Int> for the Picker.
    private var skipBudgetMultiplierBinding: Binding<Int> {
        Binding(
            get: { skipBudget.cycle.multiplier },
            set: { newValue in
                skipBudget.cycle.multiplier = newValue
            }
        )
    }

    static func defaultFirstWindow() -> (start: Date, end: Date) {
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        return (start: now, end: end)
    }

    private func defaultWindowForNewSlot() -> (start: Date, end: Date) {
        if slotWindows.isEmpty {
            return Self.defaultFirstWindow()
        }

        let last = slotWindows[slotWindows.count - 1]
        return (last.start, last.end)
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

    /// Ensures the skip-budget cycle stays compatible with the selected target cycle.
    /// If the current skip cycle kind becomes invalid under Option B rules, it is
    /// reset to the first allowed kind, anchored to "today" (current psych-day).
    private func enforceCompatibleSkipBudgetCycle() {
        let allowedKinds = allowedSkipBudgetCycleKinds
        guard !allowedKinds.isEmpty else { return }
        if !allowedKinds.contains(skipBudget.cycle.kind),
            let fallbackKind = allowedKinds.first
        {
            skipBudget.cycle = Cycle.anchored(fallbackKind, at: .now)
        }
    }
}

// MARK: - SlotWindow (shared value type)

struct SlotWindow: Identifiable {
    let id = UUID()
    var start: Date
    var end: Date
}
