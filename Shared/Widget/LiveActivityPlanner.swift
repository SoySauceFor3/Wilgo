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
            .flatMap { c in c.slotOccurrences(from: now, until: horizon).map { ($0, c) } }
            .filter { $0.0.end > now }  // softFrom lets open occurrences in; drop fully-past ones
            .sorted { $0.0 < $1.0 }
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

    /// Reconciliation decision, computed purely so it can be unit-tested. An existing activity
    /// whose state exactly equals a planned state is kept (zero churn on unchanged cards —
    /// this is why planned content must be deterministic); every other existing activity is
    /// ended; every unmatched planned card is requested.
    static func diff(
        existing: [(id: String, state: NowAttributes.ContentState)],
        planned: [PlannedLiveActivity]
    ) -> (toEnd: [String], toRequest: [PlannedLiveActivity]) {
        var toRequest = planned
        var toEnd: [String] = []
        for activity in existing {
            if let matched = toRequest.firstIndex(where: { $0.state == activity.state }) {
                toRequest.remove(at: matched)
            } else {
                toEnd.append(activity.id)
            }
        }
        return (toEnd, toRequest)
    }
}
