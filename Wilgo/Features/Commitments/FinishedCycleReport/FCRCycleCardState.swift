import Foundation

/// Per-card editable state for one cycle in the Finished Cycle Report.
///
/// The "purposeful stop" fields (`outcome`, `reflectionText`, `hasAssignedPT`)
/// only apply to failed cycles. When `checkInCount` rises to meet `targetCount`
/// (e.g. via backfill), the cycle flips to passed and those fields are cleared —
/// the user passed, so the reflection is discarded (by design; see FCR PRD).
struct FCRCycleCardState {
    let targetCount: Int

    var checkInCount: Int {
        didSet {
            if isPassed { clearFailureFields() }
        }
    }

    // Failed cycles only — cleared on flip to passed
    var outcome: CycleOutcome?
    var reflectionText: String
    /// Whether a Positivity Token has been assigned to cover this failed cycle.
    var hasAssignedPT: Bool

    // Passed cycles only
    var emojiReactions: [String]

    init(
        targetCount: Int,
        checkInCount: Int,
        outcome: CycleOutcome? = nil,
        reflectionText: String = "",
        hasAssignedPT: Bool = false,
        emojiReactions: [String] = []
    ) {
        self.targetCount = targetCount
        self.checkInCount = checkInCount
        self.outcome = outcome
        self.reflectionText = reflectionText
        self.hasAssignedPT = hasAssignedPT
        self.emojiReactions = emojiReactions
    }

    var isPassed: Bool { checkInCount >= targetCount }

    /// Whether this card is ready for the FCR to close.
    /// Passed cycles are always complete (no required action).
    /// Failed cycles require a label, non-empty reflection, and an assigned PT.
    var isComplete: Bool {
        if isPassed { return true }
        guard outcome != nil else { return false }
        guard !reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return hasAssignedPT
    }

    private mutating func clearFailureFields() {
        outcome = nil
        reflectionText = ""
        hasAssignedPT = false
    }

    // MARK: - Emoji reactions

    func reactionCount(_ emoji: String) -> Int {
        emojiReactions.count(where: { $0 == emoji })
    }

    mutating func addReaction(_ emoji: String) {
        emojiReactions.append(emoji)
    }

    /// Removes a single instance of `emoji` (no-op if none present).
    mutating func removeReaction(_ emoji: String) {
        if let idx = emojiReactions.firstIndex(of: emoji) {
            emojiReactions.remove(at: idx)
        }
    }
}
