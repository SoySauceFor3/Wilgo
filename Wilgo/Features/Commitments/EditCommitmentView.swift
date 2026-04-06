import SwiftData
import SwiftUI
import WidgetKit

struct EditCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var commitment: Commitment

    @State private var title: String
    @State private var slotWindows: [SlotWindow]
    @State private var target: Target
    @State private var proofOfWorkType: ProofOfWorkType
    @State private var punishment: String

    /// Snapshot of rule values at open time, used to detect if any rule changed.
    private let originalTarget: Target

    @State private var showingGraceDialog = false
    /// Cached cycle boundaries used when the grace dialog is presented.
    @State private var pendingCycleStart: Date = .now
    @State private var pendingCycleEnd: Date = .now

    init(commitment: Commitment) {
        self.commitment = commitment

        _title = State(initialValue: commitment.title)
        _slotWindows = State(
            initialValue: commitment.slots.sorted().map {
                SlotWindow(start: $0.start, end: $0.end, recurrence: $0.recurrence)
            }
        )
        _target = State(initialValue: commitment.target)
        _proofOfWorkType = State(initialValue: commitment.proofOfWorkType)
        _punishment = State(initialValue: commitment.punishment ?? "")

        originalTarget = commitment.target
    }

    var body: some View {
        NavigationStack {
            Form {
                CommitmentFormFields(
                    title: $title,
                    slotWindows: $slotWindows,
                    target: $target,
                    proofOfWorkType: $proofOfWorkType,
                    punishment: $punishment
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
            .confirmationDialog(
                graceDialogTitle, isPresented: $showingGraceDialog, titleVisibility: .visible
            ) {
                Button("Yes — I'm committed now") { saveChanges(grace: false) }
                Button("No — grace period") { saveChanges(grace: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The goal changes take effect immediately. This only decides whether the current period counts toward penalties."
                )
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
        target != originalTarget  // || skipBudget != originalSkipBudget
    }

    // MARK: - Save

    /// If rules changed, shows the grace dialog; otherwise saves directly.
    private func handleSaveTap() {
        guard anyRuleChanged else {
            saveChanges(grace: false)
            return
        }
        let newCycle = Cycle.makeDefault(target.cycle.kind)
        let today = Time.psychDay(for: Time.now())
        pendingCycleStart = newCycle.startDayOfCycle(including: today)
        pendingCycleEnd = newCycle.endDayOfCycle(including: today)
        showingGraceDialog = true
    }

    /// Human-readable title for the grace confirmation dialog.
    private var graceDialogTitle: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM/dd"
        return
            "Your goal changes to \(target.count) per \(target.cycle.kind.nounSingle.lowercased()) now. Should \(target.cycle.kind.thisNoun) count toward penalties?"
    }

    private func saveChanges(grace: Bool) {
        // Apply scalar field changes.
        commitment.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        commitment.proofOfWorkType = proofOfWorkType
        let trimmed = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        commitment.punishment = trimmed.isEmpty ? nil : trimmed

        // Rule change: re-anchor to canonical start day via makeDefault.
        if anyRuleChanged {
            target.cycle = Cycle.makeDefault(target.cycle.kind)
            if grace {
                commitment.gracePeriods.append(
                    GracePeriod(
                        startPsychDay: pendingCycleStart,
                        endPsychDay: pendingCycleEnd,
                        reason: .ruleChange
                    )
                )
            }
        }
        commitment.target = target

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
        for: Commitment.self, Slot.self, CheckIn.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let calendar = Calendar.current
    let slot = Slot(
        start: calendar.date(from: DateComponents(hour: 6)) ?? Date(),
        end: calendar.date(from: DateComponents(hour: 8)) ?? Date()
    )
    let commitment = Commitment(
        title: "Morning reading",
        slots: [slot],
        target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1)
    )
    container.mainContext.insert(commitment)
    return EditCommitmentView(commitment: commitment)
        .modelContainer(container)
}
