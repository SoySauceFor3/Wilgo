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
    /// Failed cycles require a label; a reflection and/or PT are then required
    /// per the outcome's `requiresReflection`/`requiresPT` (the single source of
    /// truth). Labels that require neither close on the label alone.
    var isComplete: Bool {
        if isPassed { return true }
        guard let outcome else { return false }
        if outcome.requiresReflection,
           reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        if outcome.requiresPT, !hasAssignedPT {
            return false
        }
        return true
    }

    /// Whether the reflection note is required given the current label.
    var isReflectionRequired: Bool {
        !isPassed && (outcome?.requiresReflection ?? false)
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
