import SwiftUI

// MARK: - CurrentCycleDialogState

/// Observable state owned by the parent view. Pass it to `.currentCycleDialog(state:onConfirm:)`.
/// Call `state.trigger(...)` to present the dialog.
@Observable
final class CurrentCycleDialogState {
    enum Context {
        /// Commitment is being created for the first time.
        case creation
        /// An existing commitment's rules changed (new target count or cycle kind).
        case ruleChange(targetCount: Int)
        /// Target was previously disabled and is now being re-enabled.
        case reEnable(targetCount: Int)
    }

    var isPresented = false
    var cycle: Cycle = Cycle.makeDefault(.daily)
    var cycleStart: Date = .distantPast
    var cycleEnd: Date = .distantPast
    var context: Context = .creation

    func trigger(context: Context, cycle: Cycle, cycleStart: Date, cycleEnd: Date) {
        self.context = context
        self.cycle = cycle
        self.cycleStart = cycleStart
        self.cycleEnd = cycleEnd
        isPresented = true
    }
}

// MARK: - CurrentCycleDialogModifier

private struct CurrentCycleDialogModifier: ViewModifier {
    @Bindable var state: CurrentCycleDialogState
    let onConfirm: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $state.isPresented, titleVisibility: .visible) {
                Button("Count current cycle") { onConfirm(false) }
                Button("Inspiration only until next cycle") { onConfirm(true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This only decides whether the current cycle counts toward target results.")
            }
    }

    // MARK: - Title

    private var title: String {
        switch state.context {
        case .creation:
            return creationTitle
        case .ruleChange(let count):
            return "Your target changes to \(count) per \(state.cycle.kind.nounSingle.lowercased()) now. Should \(state.cycle.kind.thisNoun) count?"
        case .reEnable(let count):
            return "Target is on again (\(count)× per \(state.cycle.kind.nounSingle.lowercased())). Should \(state.cycle.kind.thisNoun) count?"
        }
    }

    private var creationTitle: String {
        let cal = Time.calendar
        let today = Time.startOfDay(for: Time.now())
        switch state.cycle.kind {
        case .weekly:
            let fmt = DateFormatter()
            fmt.dateFormat = "EEEE"
            fmt.calendar = cal
            let weekday = fmt.string(from: today)
            return "Today is \(weekday) of \(state.cycle.kind.thisNoun). Should \(state.cycle.kind.thisNoun) count?"
        case .monthly:
            let day = cal.component(.day, from: today)
            let ordinalFmt = NumberFormatter()
            ordinalFmt.numberStyle = .ordinal
            let ordinal = ordinalFmt.string(from: NSNumber(value: day)) ?? "\(day)"
            return "Today is the \(ordinal) day of \(state.cycle.kind.thisNoun). Should \(state.cycle.kind.thisNoun) count?"
        case .daily:
            return "Should \(state.cycle.kind.thisNoun) count?"
        }
    }
}

// MARK: - View extension

extension View {
    /// Attaches the shared current-cycle confirmation dialog.
    ///
    /// Create `@State private var currentCycleDialog = CurrentCycleDialogState()` in the parent view,
    /// then call `currentCycleDialog.trigger(context:cycle:cycleStart:cycleEnd:)` to present it.
    func currentCycleDialog(
        state: CurrentCycleDialogState,
        onConfirm: @escaping (Bool) -> Void
    ) -> some View {
        modifier(CurrentCycleDialogModifier(state: state, onConfirm: onConfirm))
    }
}
