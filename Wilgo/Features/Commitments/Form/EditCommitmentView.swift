import SwiftData
import SwiftUI
import WidgetKit

@MainActor
private var nextEditCommitmentViewDebugID = 0

struct EditCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var commitment: Commitment

    @State private var draft: CommitmentFormDraft
    @State private var debugID: Int

    /// Snapshot of rule values at open time, used to detect if any rule changed.
    private let originalTarget: Target
    private let originalCycle: Cycle
    private let originalTargetMode: TargetMode

    @State private var currentCycleDialog = CurrentCycleDialogState()

    init(commitment: Commitment) {
        self.commitment = commitment

        nextEditCommitmentViewDebugID += 1
        let debugID = nextEditCommitmentViewDebugID
        _debugID = State(initialValue: debugID)
        _draft = State(initialValue: CommitmentFormDraft(commitment: commitment))

        originalTarget = commitment.target
        originalCycle = commitment.cycle
        originalTargetMode = commitment.target.configuredMode

        MemoryProbe.log(
            "EditCommitment.init",
            extra:
                "view=\(debugID) id=\(commitment.id) slots=\(commitment.slots.count) checkIns=\(commitment.checkIns.count) tags=\(commitment.tags.count)"
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(
                    title: $draft.title,
                    cycle: $draft.cycle,
                    slotWindows: $draft.slotWindows,
                    target: $draft.target,
                    proofOfWorkType: $draft.proofOfWorkType,
                    punishment: $draft.punishment,
                    encouragements: $draft.encouragements,
                    selectedTags: $draft.selectedTags,
                    isRemindersEnabled: $draft.isRemindersEnabled
                )
            }
            .navigationTitle("Edit Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        MemoryProbe.log("EditCommitment.cancel", extra: debugExtra)
                        dismiss()
                    }
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
        .onAppear {
            MemoryProbe.log("EditCommitment.appear", extra: debugExtra)
        }
        .onDisappear {
            MemoryProbe.log("EditCommitment.disappear", extra: debugExtra)
        }
        .onChange(of: draft.title) {
            MemoryProbe.log("EditCommitment.title.change", extra: debugExtra)
        }
        .onChange(of: draft.cycle) {
            MemoryProbe.log("EditCommitment.cycle.change", extra: debugExtra)
        }
        .onChange(of: draft.target) {
            MemoryProbe.log("EditCommitment.target.change", extra: debugExtra)
        }
        .onChange(of: draft.punishment) {
            MemoryProbe.log("EditCommitment.punishment.change", extra: debugExtra)
        }
        .onChange(of: draft.encouragements) {
            MemoryProbe.log("EditCommitment.encouragements.change", extra: debugExtra)
        }
        .onChange(of: draft.isRemindersEnabled) {
            MemoryProbe.log("EditCommitment.reminders.change", extra: debugExtra)
        }
    }

    // MARK: - Derived state

    private var debugExtra: String {
        "view=\(debugID) id=\(commitment.id) slots=\(draft.slotWindows.count) encouragements=\(draft.encouragements.count) tags=\(draft.selectedTags.count) reminders=\(draft.isRemindersEnabled) target=\(draft.target.count)/\(draft.target.configuredMode)"
    }

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
        MemoryProbe.log(
            "EditCommitment.save.tap",
            extra: "\(debugExtra) ruleChanged=\(anyRuleChanged)"
        )
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
        MemoryProbe.log("EditCommitment.currentCycleDialog.trigger", extra: debugExtra)
        currentCycleDialog.trigger(
            context: context,
            cycle: newCycle,
            cycleStart: newCycle.startDayOfCycle(including: today),
            cycleEnd: newCycle.endDayOfCycle(including: today)
        )
    }

    private func saveChanges(makeCurrentCycleInspirationOnly: Bool) {
        MemoryProbe.log(
            "EditCommitment.save.start",
            extra: "\(debugExtra) inspirationOnlyCurrentCycle=\(makeCurrentCycleInspirationOnly)"
        )
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
        MemoryProbe.log(
            "EditCommitment.save.scalarsApplied",
            extra: "\(debugExtra) effectiveReminders=\(draftToSave.effectiveRemindersEnabled)"
        )

        if draftToSave.effectiveRemindersEnabled {
            MemoryProbe.log(
                "EditCommitment.save.slots.inserted",
                extra: "\(debugExtra) newSlots=\(commitment.slots.count)"
            )
        }
        MemoryProbe.log("EditCommitment.save.beforeContextSave", extra: debugExtra)
        try? modelContext.save()  //TODO: try? means that if errors, we ignore it. Better to use a do/catch statement to properly handle it.
        MemoryProbe.log("EditCommitment.save.afterContextSave", extra: debugExtra)
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
        MemoryProbe.log("EditCommitment.save.beforeDismiss", extra: debugExtra)
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
