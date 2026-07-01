import Foundation

// MARK: - Commitment status engine
//
// Slot + goal mechanics that drive every reminder surface (Stage, Live Activity,
// widget, slot-start notifications). These primitives — goal progress, the remaining usable
// occurrences in the cycle, and the nearest upcoming usable occurrence — are consumed by the
// Stage characterization layer (`StageCharacterization.characteristics` + `stageBuckets`). Kept out
// of the `Commitment` @Model so the model file describes only what a commitment *is*, not how
// reminders behave.

extension Commitment {
    /// Cycle-level goal progress, independent of slot mechanics.
    struct GoalProgress {
        /// `max(0, target.count - checkInsInCycle(containing:).count)`. Nil when target is
        /// disabled (no meaningful "left to do" exists in that mode).
        let leftToDo: Int?
        /// True only when `leftToDo == 0`. False when `leftToDo` is nil (disabled) or > 0.
        var isMet: Bool { leftToDo == 0 }
    }

    /// Unfinished, unsnoozed, unsaturated slot occurrences remaining in the **current cycle**, sorted
    /// by start (includes the open-now slot, if any). The Stage characterization layer
    /// (`StageCharacterization.characteristics`) reads this for `currentOccurrence` + the remaining count.
    func remainingUsableOccurrencesInCycle(now: Date = Time.now()) -> [SlotOccurrence] {
        let bounds = cycle.bounds(including: now)
        // Pass all check-ins: `isUsable`/saturation counts only those inside each occurrence's own
        // window, so narrowing to the cycle would wrongly drop a cross-midnight occurrence's tail.
        return slotOccurrences(from: bounds.start, until: bounds.end).compactMap {
            occ -> SlotOccurrence? in
            guard occ.end >= now else { return nil }  // window already ended → not remaining
            return occ
        }
    }

    /// Returns the cycle-level goal progress for the cycle containing `now`.
    ///
    /// When the target is disabled, returns `GoalProgress(leftToDo: nil)` — `isMet` is always `false`.
    func goalProgress(now: Date = Time.now()) -> GoalProgress {
        if case .disabled = target.configuredMode {
            return GoalProgress(leftToDo: nil)
        }
        return GoalProgress(leftToDo: max(0, target.count - checkInsInCycle(containing: now).count))
    }

    /// Commitment-level rule for whether this commitment should still surface as
    /// current / upcoming / catch-up on any reminder surface (Stage, Live Activity, widget,
    /// slot-start notifications).
    ///
    /// It is `false` when `isRemindersEnabled` is off, and `false` once the cycle goal is met unless
    /// the user opted into `continueRemindersAfterGoalMet`. Slot-level concerns (snooze,
    /// capacity/saturation, window timing) are NOT decided here — those live in
    /// `remainingUsableOccurrencesInCycle` / `nearestUsableUpcomingOccurrence` and are applied
    /// downstream by the Stage characterization layer (`StageCharacterization.characteristics` + `stageBuckets`).
    ///
    /// This is the single source of truth for the reminders-enabled + goal-met∕continue rule; callers
    /// apply it once when building characteristics, so every surface agrees.
    func isActiveForReminders(now: Date = Time.now()) -> Bool {
        guard isRemindersEnabled else { return false }
        if continueRemindersAfterGoalMet { return true }
        return !goalProgress(now: now).isMet
    }

    /// This commitment's slot occurrences overlapping the half-open datetime window `[from, until)`,
    /// merged across all slots and sorted by `(start, end)`. Boundaries are arbitrary instants.
    ///
    /// Per-slot enumeration and the soft-edge rules (`softFrom` / `softUntil`) are owned by
    /// `Slot.occurrences`; this method adds the two commitment-level concerns on top: merging every
    /// slot's occurrences and (when `onlyUsable`) filtering out snoozed/saturated firings against
    /// *this* commitment's check-ins.
    func slotOccurrences(
        from: Date,
        until: Date,
        softFrom: Bool = true,
        softUntil: Bool = true,
        onlyUsable: Bool = true,
        calendar: Calendar = Time.calendar
    ) -> [SlotOccurrence] {
        slots
            .flatMap {
                $0.occurrences(
                    from: from, until: until,
                    softFrom: softFrom, softUntil: softUntil, calendar: calendar)
            }
            // Usability (snooze/saturation) is a commitment-level concern: it counts against *this*
            // commitment's check-ins, which the pure `Slot.occurrences` deliberately doesn't know.
            .filter { !onlyUsable || $0.isUsable(checkIns: checkIns) }
            .sorted()  // chronological — SlotOccurrence: Comparable
    }

    /// The earliest slot-window edge (an occurrence `start` or `end`) strictly after `instant`, across
    /// all this commitment's slots — i.e. `min` over slots of `Slot.nextWindowEdge(after:)`. `nil` when
    /// no slot has any future window edge. Recurrence-aware and usability-agnostic (see `nextWindowEdge`).
    func nextSlotWindowEdge(after instant: Date) -> Date? {
        slots.compactMap { $0.nextWindowEdge(after: instant) }.min()
    }
}

// For "nearestUsableUpcomingOccurrence"
extension Commitment {
    /// The commitment's nearest *usable* slot occurrence whose `start >= searchStart`, across all
    /// its slots — i.e. `min` over slots of each slot's next usable occurrence. Returns `nil` if
    /// no slot has a usable upcoming occurrence.
    ///
    /// "Usable" = not snoozed and not saturated, evaluated at the occurrence's own start and —
    /// crucially — against **that occurrence's own cycle's** check-ins (the occurrence may fall
    /// in a future cycle, e.g. a 7 AM slot seen at 11 PM on a daily cycle). This is what lets
    /// Upcoming cross the cycle boundary without the midnight cliff.
    ///
    /// The search starts at `now` while the commitment is active for reminders — goal not met, OR
    /// met but `continueRemindersAfterGoalMet` is on (we still surface the current cycle's remaining
    /// slots). It starts at the **next cycle's start** only when the commitment is *not* active
    /// (goal met and not continuing); that case is normally filtered out upstream, so this branch
    /// is a safe fallback rather than a common path.
    ///
    /// There is no calendar-based search horizon. Per slot it walks occurrence-to-occurrence via
    /// `Slot.nextOccurrence(onOrAfter:)`, so the reach comes from the recurrence itself and stays
    /// correct for arbitrary (future, user-defined) periods.
    func nearestUsableUpcomingOccurrence(now: Date = Time.now()) -> SlotOccurrence? {
        let searchStart: Date =
            isActiveForReminders(now: now) ? now : cycle.bounds(including: now).end
        return
            slots
            .compactMap { nextUsableOccurrence(for: $0, onOrAfter: searchStart) }
            .min()  // chronological — SlotOccurrence: Comparable
    }

    /// The first usable occurrence of `slot` with `start >= searchStart`: walks the slot's
    /// occurrences via `Slot.nextOccurrence(onOrAfter:)`, skipping any that is snoozed or saturated.
    /// Saturation only counts check-ins inside each occurrence's own window, so all check-ins are
    /// passed. `nil` if the recurrence never matches or all candidates within reach are suppressed.
    ///
    /// Termination: an occurrence is skipped only when *suppressed* by stored data — a snooze for
    /// its day, or check-ins saturating its window. Both are finite, so after skipping past every
    /// such record a usable occurrence must appear. The bound is thus derived from data, never a
    /// magic calendar number. (The before-`searchStart` boundary case is owned by `nextOccurrence`.)
    private func nextUsableOccurrence(
        for slot: Slot,
        onOrAfter searchStart: Date,  // a day + time
        calendar: Calendar = Time.calendar
    ) -> SlotOccurrence? {
        let maxSuppressed = slot.snoozes.count + checkIns.count
        var cursor = searchStart
        for _ in 0...maxSuppressed {
            guard let occ = slot.nextOccurrence(onOrAfter: cursor, calendar: calendar) else {
                return nil
            }
            // Pass all check-ins: saturation counts only those inside the occurrence's own window,
            // so narrowing to the cycle would wrongly drop a cross-midnight occurrence's tail.
            if occ.isUsable(checkIns: checkIns) {
                return occ
            }
            // Suppressed: resume the search just after this occurrence's start.
            cursor = occ.start.addingTimeInterval(1)
        }
        return nil
    }
}
