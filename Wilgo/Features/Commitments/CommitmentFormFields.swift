import SwiftData
import SwiftUI

struct CommitmentFormFields: View {
    @Binding var title: String
    @Binding var cycle: Cycle
    @Binding var slotWindows: [SlotDraft]
    @Binding var target: Target
    @Binding var proofOfWorkType: ProofOfWorkType
    @Binding var punishment: String
    @Binding var encouragements: [String]
    @Binding var selectedTags: [Tag]
    @Binding var isRemindersEnabled: Bool

    private var debugExtra: String {
        "slots=\(slotWindows.count) encouragements=\(encouragements.count) tags=\(selectedTags.count) reminders=\(isRemindersEnabled) target=\(target.count)/\(target.isEnabled)"
    }

    var body: some View {
        Section("Basics") {
            TextField("Title", text: $title)
        }

        Section {
            Picker("", selection: targetCycleKindBinding) {
                ForEach(CycleKind.allCases, id: \.self) { kind in
                    Text(kind.rawValue.lowercased()).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        } header: {
            Text("Cycle")
        } footer: {
            switch cycle.kind {
            case .weekly:
                Text("Starts on Monday.")
            case .monthly:
                Text("Starts on the 1st of the month.")
            case .daily:
                EmptyView()
            }
        }

        Section {
            Toggle("Reminders", isOn: $isRemindersEnabled)
            if isRemindersEnabled {
                ReminderWindowsSection(slotWindows: $slotWindows)
            }
        } header: {
            Text("Reminder Windows")
        } footer: {
            if !isRemindersEnabled {
                Text("No reminders. Commitment won't appear in Stage view or send notifications.")
            }
        }
        EncouragementSection(encouragements: $encouragements)

        Section("Target") {
            Toggle("Enable target", isOn: targetEnabledBinding)
            if target.isEnabled {
                HStack(spacing: 4) {
                    Picker("", selection: targetCountBinding) {
                        ForEach(0..<31, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .labelsHidden()

                    Text("times every \(cycle.kind.rawValue.lowercased())")
                        .foregroundStyle(.secondary)
                }
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
            .onAppear {
                MemoryProbe.log("CommitmentForm.appear", extra: debugExtra)
            }
            .onDisappear {
                MemoryProbe.log("CommitmentForm.disappear", extra: debugExtra)
            }
    }

    // MARK: - Helpers

    /// Maps the cycle binding to/from a CycleKind for the Picker.
    /// When the kind changes, a new Cycle is constructed anchored to the canonical start day
    /// (Monday for weekly, 1st for monthly, today for daily).
    private var targetCycleKindBinding: Binding<CycleKind> {
        Binding(
            get: { cycle.kind },
            set: { newKind in
                MemoryProbe.log(
                    "CommitmentForm.cycleKind.set",
                    extra: "from=\(cycle.kind) to=\(newKind) \(debugExtra)"
                )
                cycle = Cycle.makeDefault(newKind)
            }
        )
    }

    private var targetEnabledBinding: Binding<Bool> {
        Binding(
            get: { target.isEnabled },
            set: {
                MemoryProbe.log(
                    "CommitmentForm.targetEnabled.set",
                    extra: "from=\(target.isEnabled) to=\($0) \(debugExtra)"
                )
                target.isEnabled = $0
            }
        )
    }

    /// Exposes the target's countPerCycle as a Binding<Int> for the Stepper.
    private var targetCountBinding: Binding<Int> {
        Binding(
            get: { target.count },
            set: { newValue in
                MemoryProbe.log(
                    "CommitmentForm.targetCount.set",
                    extra: "from=\(target.count) to=\(newValue) \(debugExtra)"
                )
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
                        MemoryProbe.log(
                            "EncouragementSection.delete.tap",
                            extra: "input=\(encouragements.count) taggedBefore=\(tagged.count)"
                        )
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
                MemoryProbe.log(
                    "EncouragementSection.add.tap",
                    extra: "input=\(encouragements.count) taggedBefore=\(tagged.count)"
                )
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
            MemoryProbe.log(
                "EncouragementSection.appear",
                extra: "input=\(encouragements.count) taggedBefore=\(tagged.count)"
            )
            tagged = encouragements.map { TaggedEncouragement(text: $0) }
            MemoryProbe.log(
                "EncouragementSection.loaded",
                extra: "input=\(encouragements.count) taggedAfter=\(tagged.count)"
            )
        }
        .onDisappear {
            MemoryProbe.log(
                "EncouragementSection.disappear",
                extra: "input=\(encouragements.count) tagged=\(tagged.count)"
            )
        }
    }

    private func flush() {
        encouragements = tagged.map(\.text)
        MemoryProbe.log(
            "EncouragementSection.flush",
            extra: "input=\(encouragements.count) tagged=\(tagged.count)"
        )
    }
}
