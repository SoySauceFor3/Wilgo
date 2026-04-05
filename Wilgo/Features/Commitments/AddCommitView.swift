import SwiftData
import SwiftUI

struct AddCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var target: Target = Target(
        cycle: Cycle.makeDefault(.daily), count: 1)
    @State private var slotWindows: [SlotWindow]
    @State private var proofOfWorkType: ProofOfWorkType = .manual
    @State private var punishment: String = ""

    @State private var showingGraceDialog = false
    /// Cached cycle boundaries used when the grace dialog is presented.
    @State private var pendingCycleStart: Date = .now
    @State private var pendingCycleEnd: Date = .now

    init() {
        let (start, end) = ReminderWindowsSection.defaultFirstWindow()
        _slotWindows = State(initialValue: [SlotWindow(start: start, end: end)])
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
            .navigationTitle("New Commitment")
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
                Button("Yes — I'm committed") { persistCommitment(grace: false) }
                Button("No — grace period") { persistCommitment(grace: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "The goal changes take effect immediately. This only decides whether the current period counts toward penalties."
                )
            }
        }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && slotWindows.allSatisfy { $0.recurrence.isValidSelection }
    }

    /// Checks if creation is mid-cycle. If so, shows the grace dialog; otherwise saves directly.
    private func handleSaveTap() {
        let cycle = target.cycle
        let today = Time.psychDay(for: Time.now())
        let cycleStart = cycle.startDayOfCycle(including: today)
        let cycleEnd = cycle.endDayOfCycle(including: today)

        pendingCycleStart = cycleStart
        pendingCycleEnd = cycleEnd
        showingGraceDialog = true

    }

    /// Human-readable title for the grace confirmation dialog.
    private var graceDialogTitle: String {
        let cal = Time.calendar
        let today = Time.psychDay(for: Time.now())
        var addOn = ""
        switch target.cycle.kind {
        case .weekly:
            let weekdayFmt = DateFormatter()
            weekdayFmt.dateFormat = "EEEE"
            weekdayFmt.calendar = cal
            let weekday = weekdayFmt.string(from: today)
            addOn = "Today is \(weekday) of \(target.cycle.kind.thisNoun). "
        case .monthly:
            let day = cal.component(.day, from: today)
            let ordinalFmt = NumberFormatter()
            ordinalFmt.numberStyle = .ordinal
            let ordinal = ordinalFmt.string(from: NSNumber(value: day)) ?? "\(day)"
            addOn =
                "Today is the \(ordinal) day of \(target.cycle.kind.thisNoun). "
        case .daily:
            break
        }
        return addOn + "Should \(target.cycle.kind.thisNoun) count toward penalties?"
    }

    private func persistCommitment(grace: Bool) {
        let slots: [Slot] = slotWindows.map { window in
            let slot = Slot(start: window.start, end: window.end, recurrence: window.recurrence)
            modelContext.insert(slot)
            return slot
        }
        let sortedSlots = slots.sorted()
        let trimmedPunishment = punishment.trimmingCharacters(in: .whitespacesAndNewlines)
        let commitment = Commitment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            slots: sortedSlots,
            target: target,
            proofOfWorkType: proofOfWorkType,
            punishment: trimmedPunishment.isEmpty ? nil : trimmedPunishment,
        )
        if grace {
            commitment.gracePeriods.append(
                GracePeriod(
                    startPsychDay: pendingCycleStart,
                    endPsychDay: pendingCycleEnd,
                    reason: .creation
                )
            )
        }
        modelContext.insert(commitment)
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    AddCommitmentView()
        .modelContainer(container)
}
