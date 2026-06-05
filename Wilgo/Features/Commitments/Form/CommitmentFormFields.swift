import SwiftData
import SwiftUI

struct CommitmentFormFields: View {
    @Binding var draft: CommitmentFormDraft

    var body: some View {
        Section("Basics") {
            TextField("Title", text: $draft.title)
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
            switch draft.cycle.kind {
            case .weekly:
                Text("Starts on Monday.")
            case .monthly:
                Text("Starts on the 1st of the month.")
            case .daily:
                EmptyView()
            }
        }

        Section {
            Toggle("Reminders", isOn: $draft.isRemindersEnabled)
            if draft.isRemindersEnabled {
                ReminderWindowsSection(slotWindows: $draft.slotWindows)
                Toggle("Continue after goal met", isOn: $draft.continueRemindersAfterGoalMet)
            }
        } header: {
            Text("Reminder Windows")
        } footer: {
            if !draft.isRemindersEnabled {
                Text("No reminders. Commitment won't appear in Stage view or send notifications.")
            } else if draft.continueRemindersAfterGoalMet {
                Text("Slots will still appear in Stage and send notifications even after you've hit your target for this cycle.")
            }
        }
        EncouragementSection(encouragements: $draft.encouragements)

        Section("Target") {
            Picker("Mode", selection: targetModeChoiceBinding) {
                ForEach(TargetModeChoice.allCases, id: \.self) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            if draft.target.configuredMode != .disabled {
                HStack(spacing: 4) {
                    Picker("", selection: targetCountBinding) {
                        ForEach(0..<31, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .labelsHidden()

                    Text("times every \(draft.cycle.kind.rawValue.lowercased())")
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            TextField("e.g. Give robaroba 20 RMB", text: $draft.punishment, axis: .vertical)
                .lineLimit(2...4)
        } header: {
            Text("Punishment if credits run out")
        } footer: {
            Text("Leave blank for no punishment.")
        }

        Section("Proof of work") {
            Picker("Type", selection: $draft.proofOfWorkType) {
                Text(ProofOfWorkType.manual.rawValue).tag(ProofOfWorkType.manual)
            }
            .pickerStyle(.segmented)
        }

        TagPickerSection(selectedTags: $draft.selectedTags)
    }

    // MARK: - Helpers

    /// Maps the cycle binding to/from a CycleKind for the Picker.
    /// When the kind changes, a new Cycle is constructed anchored to the canonical start day
    /// (Monday for weekly, 1st for monthly, today for daily).
    private var targetCycleKindBinding: Binding<CycleKind> {
        Binding(
            get: { draft.cycle.kind },
            set: { newKind in
                draft.cycle = Cycle.makeDefault(newKind)
            }
        )
    }

    private var targetModeChoiceBinding: Binding<TargetModeChoice> {
        Binding(
            get: {
                switch draft.target.configuredMode {
                case .on: return .on
                case .disabled: return .disabled
                }
            },
            set: { choice in
                switch choice {
                case .on: draft.target.setConfiguredMode(.on)
                case .disabled: draft.target.setConfiguredMode(.disabled)
                }
            }
        )
    }

    private var targetCountBinding: Binding<Int> {
        Binding(
            get: { draft.target.count },
            set: { draft.target.count = $0 }
        )
    }
}

private enum TargetModeChoice: String, CaseIterable, Hashable {
    case on = "On"
    case disabled = "Disabled"
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
