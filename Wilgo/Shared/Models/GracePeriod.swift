import Foundation

/// A time window during which a commitment's cycles are exempt from
/// penalty and positivity-token evaluation.
///
/// Grace periods arise from several sources (see `GraceReason`). A cycle is
/// considered a grace cycle if it overlaps with any `GracePeriod` recorded on
/// the parent `Commitment`. Overlap is checked via ``overlaps(cycleStart:cycleEnd:)``.
///
/// Both single-cycle windows (creation, rule-change) and multi-cycle ranges
/// (future vacation/disable use case) are represented identically — the
/// `overlaps` interval logic handles both uniformly.
struct GracePeriod: Codable, Hashable {
    /// First psych-day of the grace window (inclusive).
    var startPsychDay: Date
    /// First psych-day after the grace window (exclusive).
    var endPsychDay: Date
    /// Why this grace period was created.
    var reason: GraceReason

    /// Returns `true` if this grace window overlaps with the cycle `[cycleStart, cycleEnd)`.
    func overlaps(cycleStart: Date, cycleEnd: Date) -> Bool {
        startPsychDay < cycleEnd && endPsychDay > cycleStart
    }
}

/// The reason a `GracePeriod` was created.
enum GraceReason: String, Codable {
    /// Commitment was created mid-cycle and the user opted in to a grace period
    /// for the partial first cycle.
    case creation
    /// Target rules changed mid-cycle and the user chose not to be penalized
    /// for the current cycle.
    case ruleChange
    /// Commitment was temporarily disabled (e.g. vacation). Reserved for future use.
    case disabled
}
