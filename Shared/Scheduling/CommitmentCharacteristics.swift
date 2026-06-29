import Foundation

/// All the facts about one commitment at a moment `now`, derived from the commitment + its
/// check-ins/slots. This is the **characterization** layer: one commitment in → one fact bundle out,
/// with no knowledge of other commitments.
///
/// Every Stage surface (Stage view, widget, Live Activity, catch-up notifications) is built from
/// these snapshots, so they can never drift. Placement into rows (Current / Upcoming / Catch-up) and
/// the catch-up reminder filter are pure functions *over* snapshots — see `CommitmentAndSlot`.
///
/// Fields are raw values (occurrences, counts), never formatted/localized strings — formatting is a
/// view concern. Flat stored fields + computed accessors, grouped by concern.
struct CommitmentCharacteristics: Equatable {
    let commitment: Commitment

    // MARK: - Current / remaining-this-cycle

    /// The slot whose window is open right now (the first remaining in-cycle occurrence that has
    /// already started), or `nil`. Reproduces the old `.insideSlot` notion; the Current row reads it
    /// for the slot's time + snooze target.
    let currentOccurrence: SlotOccurrence?

    /// How many unfinished, unsnoozed, unsaturated occurrences remain in the current cycle (=
    /// `status.remainingSlots.count`). **Includes the currently-open slot** (if any) — it's a raw
    /// "how many remain" fact; rows that show one slot separately subtract 1 themselves (e.g. the
    /// Current row's "Next Up: N more" and Upcoming's "+k more"). We store the count, not the array —
    /// no consumer needs the full list (only `currentOccurrence` and this count are used).
    let remainingThisCycleCount: Int

    /// True when a slot is open right now → this commitment belongs in the Current row.
    var isCurrent: Bool { currentOccurrence != nil }

    // MARK: - Upcoming (closest-N)

    /// The commitment's soonest *usable* slot occurrence with `start >= now`, across all its slots,
    /// possibly in a future cycle. `nil` when no upcoming usable slot exists.
    let nearestUsable: SlotOccurrence?

    /// True when there is a usable upcoming slot → eligible for the Upcoming bucket.
    var hasUpcoming: Bool { nearestUsable != nil }

    /// True when `nearestUsable` falls in the cycle containing `now`. When false, the Upcoming row
    /// is a future-cycle row (dated label + "future cycle" marker).
    let nearestUsableInCurrentCycle: Bool

    // MARK: - Goal / behind

    /// `max(0, leftToDo - remainingThisCycle.count)` — how many check-ins the goal still needs that
    /// no remaining in-cycle slot can cover. `0` when on track / no goal.
    let behindCount: Int

    /// True when the cycle goal still needs check-ins the remaining slots can't cover. Catch-up
    /// reminders fire for behind commitments (that aren't currently in an open slot).
    var isBehind: Bool { behindCount > 0 }

    // MARK: - Cycle progress (UI)

    /// Check-ins recorded in the current target cycle.
    let checkInCount: Int
    /// The cycle's target count.
    let targetCount: Int
}

extension CommitmentAndSlot {
    /// Characterizes a single commitment at `now`. Computed uniformly for every commitment the caller
    /// passes (callers pass the `isActiveForReminders`-filtered set, so the goal-met/continue rule is
    /// applied once at the boundary). `nearestUsable` is computed for all — including current-slot
    /// commitments — for one uniform code path.
    static func characteristics(of commitment: Commitment, now: Date = Time.now())
        -> CommitmentCharacteristics
    {
        let status = commitment.status(now: now)
        let remaining = status.remainingSlots ?? []
        // The open-now slot is the first remaining occurrence that has already started (= .insideSlot).
        let currentOccurrence: SlotOccurrence? = {
            guard let first = remaining.first, first.start <= now else { return nil }
            return first
        }()
        let nearest = commitment.nearestUsableUpcomingOccurrence(now: now)
        let nearestUsableInCurrentCycle: Bool = nearest.map {
            let bounds = commitment.cycle.bounds(including: now)
            return $0.start >= bounds.start && $0.start < bounds.end
        } ?? false
        return CommitmentCharacteristics(
            commitment: commitment,
            currentOccurrence: currentOccurrence,
            remainingThisCycleCount: remaining.count,
            nearestUsable: nearest,
            nearestUsableInCurrentCycle: nearestUsableInCurrentCycle,
            behindCount: status.behindCount ?? 0,
            checkInCount: commitment.checkInsInCycle(containing: now).count,
            targetCount: commitment.target.count
        )
    }
}
