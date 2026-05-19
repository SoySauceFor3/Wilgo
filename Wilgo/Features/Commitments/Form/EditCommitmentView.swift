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
                        .currentCycleDialog(state: currentCycleDialog) {
                            makeCurrentCycleInspirationOnly in
                            if makeCurrentCycleInspirationOnly {
                                draft.target.setConfiguredMode(
                                    .inspirationOnly(
                                        start: currentCycleDialog.cycleStart,
                                        until: currentCycleDialog.cycleEnd
                                    )
                                )
                            }
                            saveChanges()
                        }
                }
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

    /// Re-anchors the cycle if rules changed, then optionally shows the current-cycle dialog
    /// (which can mutate the draft) before saving.
    private func handleSaveTap() {
        // Rule change: re-anchor to canonical start day via makeDefault.
        if anyRuleChanged {
            draft.cycle = Cycle.makeDefault(draft.cycle.kind)  // Cycle's reference date will be updated
            draft.reanchorInspirationOnlyTarget(to: draft.cycle)  // I don't think this is needed, but just a safety net.
        }
        guard anyRuleChanged, draft.target.configuredMode == .on else {
            saveChanges()
            return
        }
        let today = Time.startOfDay(for: Time.now())
        let context: CurrentCycleDialogState.Context =
            targetBeingReEnabled
            ? .reEnable(targetCount: draft.target.count)
            : .ruleChange(targetCount: draft.target.count)
        currentCycleDialog.trigger(
            context: context,
            cycle: draft.cycle,
            cycleStart: draft.cycle.startDayOfCycle(including: today),
            cycleEnd: draft.cycle.endDayOfCycle(including: today)
        )
    }

    private func saveChanges() {
        draft.apply(to: commitment, in: modelContext)
        try? modelContext.save()  // TODO: try? means that if errors, we ignore it. Better to use a do/catch statement to properly handle it.
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
        SlotStartNotificationScheduler.refresh()
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
        cycle: Cycle.makeDefault(.daily),
        slots: [slot],
        target: Target(count: 1)
    )
    container.mainContext.insert(commitment)
    return EditCommitmentView(commitment: commitment)
        .modelContainer(container)
}
