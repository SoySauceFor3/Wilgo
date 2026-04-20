import SwiftUI

// MARK: - GraceDialogState

/// Observable state owned by the parent view. Pass it to `.graceDialog(state:onConfirm:)`.
/// Call `state.trigger(...)` to present the dialog.
@Observable
final class GraceDialogState {
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

// MARK: - GraceDialogModifier

private struct GraceDialogModifier: ViewModifier {
    @Bindable var state: GraceDialogState
    let onConfirm: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $state.isPresented, titleVisibility: .visible) {
                Button("Yes — I'm committed now") { onConfirm(false) }
                Button("No — grace period") { onConfirm(true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This only decides whether the current period counts toward penalties.")
            }
    }

    // MARK: - Title

    private var title: String {
        switch state.context {
        case .creation:
            return creationTitle
        case .ruleChange(let count):
            return "Your goal changes to \(count) per \(state.cycle.kind.nounSingle.lowercased()) now. Should \(state.cycle.kind.thisNoun) count toward penalties?"
        case .reEnable(let count):
            return "Target re-enabled (\(count)× per \(state.cycle.kind.nounSingle.lowercased())). Should \(state.cycle.kind.thisNoun) count toward penalties?"
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
            return "Today is \(weekday) of \(state.cycle.kind.thisNoun). Should \(state.cycle.kind.thisNoun) count toward penalties?"
        case .monthly:
            let day = cal.component(.day, from: today)
            let ordinalFmt = NumberFormatter()
            ordinalFmt.numberStyle = .ordinal
            let ordinal = ordinalFmt.string(from: NSNumber(value: day)) ?? "\(day)"
            return "Today is the \(ordinal) day of \(state.cycle.kind.thisNoun). Should \(state.cycle.kind.thisNoun) count toward penalties?"
        case .daily:
            return "Should \(state.cycle.kind.thisNoun) count toward penalties?"
        }
    }
}

// MARK: - View extension

extension View {
    /// Attaches the shared grace-period confirmation dialog.
    ///
    /// Create `@State private var graceDialog = GraceDialogState()` in the parent view,
    /// then call `graceDialog.trigger(context:cycle:cycleStart:cycleEnd:)` to present it.
    func graceDialog(state: GraceDialogState, onConfirm: @escaping (Bool) -> Void) -> some View {
        modifier(GraceDialogModifier(state: state, onConfirm: onConfirm))
    }
}
