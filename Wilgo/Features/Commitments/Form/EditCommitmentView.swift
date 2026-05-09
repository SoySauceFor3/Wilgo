import SwiftData
import SwiftUI
import WidgetKit

struct EditCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var commitment: Commitment

    @State private var draft: CommitmentFormDraft

    /// Snapshot of rule values at open time, used to detect if any rule changed.
    private let originalTarget: Target
    private let originalCycle: Cycle
    private let originalTargetMode: TargetMode

    @State private var currentCycleDialog = CurrentCycleDialogState()

    init(commitment: Commitment) {
        self.commitment = commitment

        _draft = State(initialValue: CommitmentFormDraft(commitment: commitment))

        originalTarget = commitment.target
        originalCycle = commitment.cycle
        originalTargetMode = commitment.target.configuredMode
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(draft: $draft)
            }
            .navigationTitle("Edit Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { handleSaveTap() }
                        .disabled(!draft.canSave)
                }
            }
            .currentCycleDialog(state: currentCycleDialog) { makeCurrentCycleInspirationOnly in
                saveChanges(makeCurrentCycleInspirationOnly: makeCurrentCycleInspirationOnly)
            }
        }
    }

    // MARK: - Derived state

    /// True when any rule field (timesPerDay, skipCreditCount, cycle) changed.
    /// Rule changes re-anchor the cycle to today so the new rules start from a clean slate.
    private var anyRuleChanged: Bool {
        draft.target != originalTarget || draft.cycle != originalCycle
    }

    /// True only when the target is being re-enabled this save.
    private var targetBeingReEnabled: Bool {
        originalTargetMode == .disabled && draft.target.configuredMode == .on
    }

    // MARK: - Save

    /// If rules changed and Target On is selected, shows the current-cycle dialog.
    private func handleSaveTap() {
        guard anyRuleChanged else {
            saveChanges(makeCurrentCycleInspirationOnly: false)
            return
        }
        guard draft.target.configuredMode == .on else {
            saveChanges(makeCurrentCycleInspirationOnly: false)
            return
        }
        let newCycle = Cycle.makeDefault(draft.cycle.kind)
        let today = Time.startOfDay(for: Time.now())
        let context: CurrentCycleDialogState.Context =
            targetBeingReEnabled
            ? .reEnable(targetCount: draft.target.count)
            : .ruleChange(targetCount: draft.target.count)
        currentCycleDialog.trigger(
            context: context,
            cycle: newCycle,
            cycleStart: newCycle.startDayOfCycle(including: today),
            cycleEnd: newCycle.endDayOfCycle(including: today)
        )
    }

    private func saveChanges(makeCurrentCycleInspirationOnly: Bool) {
        var draftToSave = draft
        // Rule change: re-anchor to canonical start day via makeDefault.
        if anyRuleChanged {
            draftToSave.cycle = Cycle.makeDefault(draftToSave.cycle.kind)
            if makeCurrentCycleInspirationOnly {
                draftToSave.target.setConfiguredMode(
                    .inspirationOnly(
                        start: currentCycleDialog.cycleStart,
                        until: currentCycleDialog.cycleEnd
                    )
                )
            } else {
                draftToSave.reanchorInspirationOnlyTarget(to: draftToSave.cycle)
            }
        }
        draft = draftToSave
        draftToSave.apply(to: commitment, in: modelContext)
        try? modelContext.save()  //TODO: try? means that if errors, we ignore it. Better to use a do/catch statement to properly handle it.
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, Tag.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let slot = Slot(
        start: calendar.date(from: DateComponents(hour: 6)) ?? Date(),
        end: calendar.date(from: DateComponents(hour: 8)) ?? Date()
    )
    let commitment = Commitment(
        title: "Morning reading",
        cycle: Cycle.anchored(.daily, at: .now),
        slots: [slot],
        target: Target(count: 1)
    )
    container.mainContext.insert(commitment)
    return EditCommitmentView(commitment: commitment)
        .modelContainer(container)
}
