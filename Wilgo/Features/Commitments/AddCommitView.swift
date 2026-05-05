import SwiftData
import SwiftUI

@MainActor
private var nextAddCommitmentViewDebugID = 0

struct AddCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var cycle: Cycle = Cycle.makeDefault(.daily)
    @State private var target: Target = Target(count: 5, isEnabled: true)
    @State private var slotWindows: [SlotDraft]
    @State private var proofOfWorkType: ProofOfWorkType = .manual
    @State private var punishment: String = ""
    @State private var encouragements: [String] = []
    @State private var selectedTags: [Tag] = []
    @State private var isRemindersEnabled: Bool = true
    @State private var debugID: Int

    @State private var graceDialog = GraceDialogState()

    init() {
        nextAddCommitmentViewDebugID += 1
        let debugID = nextAddCommitmentViewDebugID
        _debugID = State(initialValue: debugID)
        let (start, end) = ReminderWindowsSection.defaultFirstWindow()
        _slotWindows = State(initialValue: [SlotDraft(start: start, end: end)])
        MemoryProbe.log("AddCommitment.init", extra: "view=\(debugID)")
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(
                    title: $title,
                    cycle: $cycle,
                    slotWindows: $slotWindows,
                    target: $target,
                    proofOfWorkType: $proofOfWorkType,
                    punishment: $punishment,
                    encouragements: $encouragements,
                    selectedTags: $selectedTags,
                    isRemindersEnabled: $isRemindersEnabled
                )
            }
            .navigationTitle("New Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        MemoryProbe.log("AddCommitment.cancel", extra: debugExtra)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { handleSaveTap() }
                        .disabled(!canSave)
                }
            }
            .graceDialog(state: graceDialog) { grace in
                persistCommitment(grace: grace)
            }
        }
        .onAppear {
            MemoryProbe.log("AddCommitment.appear", extra: debugExtra)
        }
        .onDisappear {
            MemoryProbe.log("AddCommitment.disappear", extra: debugExtra)
        }
        .onChange(of: title) {
            MemoryProbe.log("AddCommitment.title.change", extra: debugExtra)
        }
        .onChange(of: cycle) {
            MemoryProbe.log("AddCommitment.cycle.change", extra: debugExtra)
        }
        .onChange(of: target) {
            MemoryProbe.log("AddCommitment.target.change", extra: debugExtra)
        }
        .onChange(of: punishment) {
            MemoryProbe.log("AddCommitment.punishment.change", extra: debugExtra)
        }
        .onChange(of: encouragements) {
            MemoryProbe.log("AddCommitment.encouragements.change", extra: debugExtra)
        }
        .onChange(of: isRemindersEnabled) {
            MemoryProbe.log("AddCommitment.reminders.change", extra: debugExtra)
        }
    }

    private var debugExtra: String {
        "view=\(debugID) slots=\(slotWindows.count) encouragements=\(encouragements.count) tags=\(selectedTags.count) reminders=\(isRemindersEnabled) target=\(target.count)/\(target.isEnabled)"
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!isRemindersEnabled || slotWindows.allSatisfy { $0.recurrence.isValidSelection })
    }

    /// Shows the grace dialog, or saves directly if target is disabled (no goal to penalize against).
    private func handleSaveTap() {
        MemoryProbe.log("AddCommitment.save.tap", extra: debugExtra)
        guard target.isEnabled else {
            persistCommitment(grace: false)
            return
        }
        let today = Time.startOfDay(for: Time.now())
        MemoryProbe.log("AddCommitment.grace.trigger", extra: debugExtra)
        graceDialog.trigger(
            context: .creation,
            cycle: cycle,
            cycleStart: cycle.startDayOfCycle(including: today),
            cycleEnd: cycle.endDayOfCycle(including: today)
        )
    }

    private func persistCommitment(grace: Bool) {
        MemoryProbe.log("AddCommitment.persist.start", extra: "\(debugExtra) grace=\(grace)")
        let effectiveRemindersEnabled = isRemindersEnabled && !slotWindows.isEmpty
        let slots: [Slot] =
            effectiveRemindersEnabled
            ? slotWindows.map { window in
                let slot = Slot(
                    start: window.start,
                    end: window.end,
                    recurrence: window.recurrence,
                    maxCheckIns: window.maxCheckIns
                )
                modelContext.insert(slot)
                return slot
            } : []
        MemoryProbe.log(
            "AddCommitment.persist.slotsBuilt",
            extra: "\(debugExtra) effectiveReminders=\(effectiveRemindersEnabled) slots=\(slots.count)"
        )
        let trimmedPunishment = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitment = Commitment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            cycle: cycle,
            slots: slots.sorted(),
            target: target,
            proofOfWorkType: proofOfWorkType,
            punishment: trimmedPunishment.isEmpty ? nil : trimmedPunishment,
            isRemindersEnabled: effectiveRemindersEnabled
        )
        if grace {
            commitment.gracePeriods.append(
                GracePeriod(
                    startPsychDay: graceDialog.cycleStart,
                    endPsychDay: graceDialog.cycleEnd,
                    reason: .creation
                )
            )
        }
        modelContext.insert(commitment)
        MemoryProbe.log("AddCommitment.persist.inserted", extra: "\(debugExtra) id=\(commitment.id)")
        commitment.encouragements = encouragements.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        commitment.tags = selectedTags
        MemoryProbe.log("AddCommitment.persist.beforeSave", extra: "\(debugExtra) id=\(commitment.id)")
        try? modelContext.save()
        MemoryProbe.log("AddCommitment.persist.afterSave", extra: "\(debugExtra) id=\(commitment.id)")
        MemoryProbe.log("AddCommitment.persist.beforeDismiss", extra: "\(debugExtra) id=\(commitment.id)")
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, Tag.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    AddCommitmentView()
        .modelContainer(container)
}
