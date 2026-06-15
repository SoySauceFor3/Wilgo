import Foundation

/// Gating logic for whether the Finished Cycle Report can be closed.
enum FCRCompletion {
    /// The FCR can close only when every cycle card is complete.
    /// Passed cycles are always complete; failed cycles require
    /// label + reflection + assigned PT (see `FCRCycleCardState.isComplete`).
    static func canClose(states: [FCRCycleCardState]) -> Bool {
        states.allSatisfy(\.isComplete)
    }
}
