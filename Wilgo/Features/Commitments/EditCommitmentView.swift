import SwiftData
import SwiftUI
import WidgetKit

struct EditCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var commitment: Commitment

    @State private var title: String
    @State private var cycle: Cycle
    @State private var slotWindows: [SlotWindow]
    @State private var target: Target
    @State private var proofOfWorkType: ProofOfWorkType
    @State private var punishment: String
    @State private var encouragements: [String]
    @State private var selectedTags: [Tag]

    /// Snapshot of rule values at open time, used to detect if any rule changed.
    private let originalTarget: Target
    private let originalCycle: Cycle

    @State private var graceDialog = GraceDialogState()

    init(commitment: Commitment) {
        self.commitment = commitment

        _title = State(initialValue: commitment.title)
        _cycle = State(initialValue: commitment.cycle)
        _slotWindows = State(
            initialValue: commitment.slots.sorted().map {
                SlotWindow(start: $0.start, end: $0.end, recurrence: $0.recurrence)
            }
        )
        _target = State(initialValue: commitment.target)
        _proofOfWorkType = State(initialValue: commitment.proofOfWorkType)
        _punishment = State(initialValue: commitment.punishment ?? "")
        _encouragements = State(initialValue: commitment.encouragements)
        _selectedTags = State(initialValue: commitment.tags)

        originalTarget = commitment.target
        originalCycle = commitment.cycle
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
                    selectedTags: $selectedTags
                )
            }
            .navigationTitle("Edit Commitment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { handleSaveTap() }
                        .disabled(!canSave)
                }
            }
            .graceDialog(state: graceDialog) { grace in
                saveChanges(grace: grace)
            }
        }
    }

    // MARK: - Derived state

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && slotWindows.allSatisfy { $0.recurrence.isValidSelection }
    }

    /// True when any rule field (timesPerDay, skipCreditCount, cycle) changed.
    /// Rule changes re-anchor the cycle to today so the new rules start from a clean slate.
    private var anyRuleChanged: Bool {
        target != originalTarget || cycle != originalCycle  // || skipBudget != originalSkipBudget
    }

    // MARK: - Save

    /// If rules changed, shows the grace dialog; otherwise saves directly.
    private func handleSaveTap() {
        guard anyRuleChanged else {
            saveChanges(grace: false)
            return
        }
        let newCycle = Cycle.makeDefault(cycle.kind)
        let today = Time.startOfDay(for: Time.now())
        graceDialog.trigger(
            context: .ruleChange(targetCount: target.count),
            cycle: newCycle,
            cycleStart: newCycle.startDayOfCycle(including: today),
            cycleEnd: newCycle.endDayOfCycle(including: today)
        )
    }

    private func saveChanges(grace: Bool) {
        // Apply scalar field changes.
        commitment.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        commitment.proofOfWorkType = proofOfWorkType
        let trimmed = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        commitment.punishment = trimmed.isEmpty ? nil : trimmed
        commitment.encouragements = encouragements.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        // Rule change: re-anchor to canonical start day via makeDefault.
        if anyRuleChanged {
            cycle = Cycle.makeDefault(cycle.kind)
            if grace {
                commitment.gracePeriods.append(
                    GracePeriod(
                        startPsychDay: graceDialog.cycleStart,
                        endPsychDay: graceDialog.cycleEnd,
                        reason: .ruleChange
                    )
                )
            }
        }
        commitment.cycle = cycle
        commitment.target = target
        commitment.tags = selectedTags

        // Replace slots only if the count or any window changed.
        let newWindows = slotWindows
        let oldSlots = commitment.slots.sorted()
        let slotsChanged =
            newWindows.count != oldSlots.count
            || zip(newWindows, oldSlots).contains { w, s in
                w.start != s.start || w.end != s.end || w.recurrence != s.recurrence
            }

        if slotsChanged {
            for old in commitment.slots { modelContext.delete(old) }
            let newSlots: [Slot] = newWindows.map { window in
                let slot = Slot(start: window.start, end: window.end, recurrence: window.recurrence)
                modelContext.insert(slot)
                return slot
            }
            commitment.slots = newSlots.sorted()
        }
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
