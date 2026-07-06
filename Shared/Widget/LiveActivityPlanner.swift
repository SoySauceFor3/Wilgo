import Foundation

/// One Live Activity card the app intends to exist: either already-open (request immediately,
/// app is in foreground / an intent) or future (request with `start:` so the system starts it
/// even if the app is dead). Pure value — building and diffing these is unit-tested; only the
/// thin shell in `LiveActivityRefresher` touches ActivityKit.
struct PlannedLiveActivity: Equatable {
    let state: NowAttributes.ContentState
    /// System start date. Nil = the occurrence is already open → request immediately.
    let scheduledStart: Date?
    /// Occurrence end: the card flips to the stale ("Ended") rendering here with no app runtime.
    let staleDate: Date
    /// Higher = owns the Dynamic Island. Earlier deadline → higher score.
    let relevanceScore: Double
}

/// A live-or-pending activity as the refresher sees it, reduced to what reconciliation needs.
struct ExistingActivity {
    let id: String
    let state: NowAttributes.ContentState
    /// True while scheduled but not yet started (`ActivityState.pending`). Pending cards are
    /// invisible, so ending + re-requesting one has zero user-visible cost; started cards must
    /// be updated in place instead (end+recreate blinks).
    let isPending: Bool
}

/// The reconciliation decision, computed purely so it can be unit-tested.
struct ReconcileActions {
    /// Orphans (no planned counterpart) — end immediately.
    var toEnd: [String] = []
    /// Started activities whose firing is still planned but whose content changed — update
    /// in place (`Activity.update` is legal even from the background and does not blink).
    var toUpdate: [(id: String, item: PlannedLiveActivity)] = []
    /// Planned cards with no counterpart — request, nearest-first.
    var toRequest: [PlannedLiveActivity] = []
    /// Matching pending cards kept as-is. Ordered eviction candidates if capacity later
    /// blocks a more imminent request (see the refresher's request loop).
    var keptPendings: [(id: String, state: NowAttributes.ContentState)] = []
}

enum LiveActivityPlanner {
    /// More than any plausible device queue cap (undocumented, ~5): the refresher requests
    /// nearest-first and stops at the first capacity throw, so planning extra is free.
    static let maxPlanned = 8
    /// Same enumeration horizon as `SlotStartNotificationScheduler` — see its rationale.
    static let horizonDays = 14

    /// The cards that should exist at `now`: the nearest `maxPlanned` usable occurrences across
    /// all reminder-active commitments, each mapped to a per-occurrence card. Occurrences whose
    /// window is already open (start ≤ now < end) come first with `scheduledStart == nil`.
    static func plan(
        commitments: [Commitment],
        now: Date,
        calendar: Calendar = Time.calendar
    ) -> [PlannedLiveActivity] {
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now
        let occurrences: [(SlotOccurrence, Commitment)] =
            commitments
            .filter { $0.isActiveForReminders(now: now) }
            .flatMap { c in c.slotOccurrences(from: now, until: horizon, calendar: calendar).map { ($0, c) } }
            .filter { $0.0.end > now }  // softFrom lets open occurrences in; drop fully-past ones
            // SlotOccurrence `<` ties on identical windows and Swift's sort is not stable, so a
            // tie straddling the `prefix(maxPlanned)` cutoff would make plan membership depend on
            // fetch order — churning cards between wakes. Slot id breaks the tie deterministically.
            .sorted {
                if $0.0 < $1.0 { return true }
                if $1.0 < $0.0 { return false }
                return $0.0.slot.id.uuidString < $1.0.slot.id.uuidString
            }
        return occurrences.prefix(maxPlanned).map { occ, commitment in
            PlannedLiveActivity(
                state: makeState(occurrence: occ, commitment: commitment),
                scheduledStart: occ.start > now ? occ.start : nil,
                staleDate: occ.end,
                relevanceScore: relevanceScore(windowEnd: occ.end)
            )
        }
    }

    static func makeState(
        occurrence: SlotOccurrence, commitment: Commitment
    ) -> NowAttributes.ContentState {
        let counts = progressCounts(for: commitment, occurrence: occurrence)
        return NowAttributes.ContentState(
            commitmentTitle: commitment.title,
            slotTimeText: occurrence.timeOfDayText,
            commitmentId: commitment.id,
            slotId: occurrence.slot.id,
            windowStart: occurrence.start,
            windowEnd: occurrence.end,
            encouragementText: encouragement(for: commitment, occurrence: occurrence),
            checkInCount: counts.checkInCount,
            targetCount: counts.targetCount
        )
    }

    /// Cycle progress baked into the card: check-ins in the **occurrence's own** cycle (a future
    /// occurrence may fall in a future cycle → counts start at 0) / the target count. Nil pair when
    /// the target is disabled. Safe to freeze: counts only change through the app process
    /// (check-in / undo paths), and every such path triggers a reconcile — the diff then ends and
    /// re-requests the card with the fresh count.
    static func progressCounts(
        for commitment: Commitment, occurrence: SlotOccurrence
    ) -> (checkInCount: Int?, targetCount: Int?) {
        if case .disabled = commitment.target.configuredMode {
            return (nil, nil)
        }
        return (
            commitment.checkInsInCycle(containing: occurrence.start).count,
            commitment.target.count
        )
    }

    /// Deterministic pick: rotates daily, stable within a day. Randomness would change the
    /// `ContentState` on every re-plan, making the diff end+recreate unchanged cards (flicker,
    /// re-fired start alerts).
    static func encouragement(
        for commitment: Commitment, occurrence: SlotOccurrence
    ) -> String? {
        let all = commitment.encouragements
        guard !all.isEmpty else { return nil }
        let dayOrdinal = Int(occurrence.psychDay.timeIntervalSince1970 / 86_400)
        let index = ((dayOrdinal % all.count) + all.count) % all.count  // non-negative mod
        return all[index]
    }

    /// Earlier deadline → higher score → owns the Dynamic Island / tops the Lock Screen stack.
    /// Anchored so scores stay positive for any date before year ~2096.
    static func relevanceScore(windowEnd: Date) -> Double {
        max(0, 4_000_000_000 - windowEnd.timeIntervalSince1970)
    }

    /// An existing activity whose state exactly equals a planned state is kept (zero churn on
    /// unchanged cards — this is why planned content must be deterministic). A *started* activity
    /// matching a planned card's firing identity (`slotId` + `windowStart`) with different content
    /// is updated in place. Everything else existing is ended; every unmatched planned card is
    /// requested.
    static func diff(
        existing: [ExistingActivity],
        planned: [PlannedLiveActivity]
    ) -> ReconcileActions {
        var actions = ReconcileActions()
        var remaining = planned
        for activity in existing {
            if let matched = remaining.firstIndex(where: { $0.state == activity.state }) {
                let item = remaining.remove(at: matched)
                if activity.isPending {
                    actions.keptPendings.append((id: activity.id, state: item.state))
                }
            } else if !activity.isPending,
                let sameFiring = remaining.firstIndex(where: {
                    $0.state.slotId == activity.state.slotId
                        && $0.state.windowStart == activity.state.windowStart
                })
            {
                actions.toUpdate.append((id: activity.id, item: remaining.remove(at: sameFiring)))
            } else {
                actions.toEnd.append(activity.id)
            }
        }
        actions.toRequest = remaining
        return actions
    }
}
