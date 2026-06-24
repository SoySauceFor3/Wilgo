import Foundation

// MARK: - Commitment status engine
//
// Slot + goal mechanics that drive every reminder surface (Stage, Live Activity,
// widget, slot-start notifications). Lives next to `CommitmentAndSlot`, its conjoined
// partner: the `*WithBehind` helpers there consume `status` / `isActiveForReminders`,
// and the docs below cross-reference them. Kept out of the `Commitment` @Model so the
// model file describes only what a commitment *is*, not how reminders behave.

extension Commitment {
    /// Cycle-level goal progress, independent of slot mechanics.
    struct GoalProgress {
        /// `max(0, target.count - checkInsInCycle(containing:).count)`. Nil when target is
        /// disabled (no meaningful "left to do" exists in that mode).
        let leftToDo: Int?
        /// True only when `leftToDo == 0`. False when `leftToDo` is nil (disabled) or > 0.
        var isMet: Bool { leftToDo == 0 }
    }

    /// Where `now` falls relative to the remaining usable slot occurrences.
    enum SlotStatusKind {
        case disabled  // if isRemindersEnabled == False
        /// `now` is inside the window of some remaining slot
        /// (the first remaining slot's start is at or before `now`).
        case insideSlot
        /// `now` is before the first remaining slot, and that slot starts later today.
        case beforeNextToday
        /// No remaining slot starts within today's psych-day window.
        case noSlotToday
    }

    /// Pure slot mechanics for a given `now`. Mode-agnostic: `remainingSlots` is
    /// built over the full target cycle regardless of `target.effectiveMode`. For daily
    /// cycles the cycle window equals the psych-day window; for longer cycles it
    /// is strictly wider, so `remainingSlots` may include slots beyond today.
    struct SlotStatus {
        /// Classification of where `now` falls relative to `remainingSlots`.
        let kind: SlotStatusKind
        /// Unfinished, unsnoozed, unsaturated slot occurrences in the target cycle,
        /// sorted by start time. Includes the current slot (if any) and any later slots.
        /// Each occurrence carries its concrete window (date info, not just time of day).
        let remainingSlots: [SlotOccurrence]
    }

    /// Returns the slot mechanics for `now`. Mode-agnostic — always uses the
    /// target cycle as the window, regardless of `target.effectiveMode`.
    ///
    /// `remainingSlots`: occurrences whose window has not yet ended, with the current slot
    /// dropped if it has been snoozed or its capacity is saturated by in-window
    /// check-ins.
    ///
    /// `kind` classifies `now`:
    /// - `.insideSlot` when the first remaining slot's start is at or before `now`,
    /// - `.beforeNextToday` when some remaining slot starts within today's psych-day,
    /// - `.noSlotToday` otherwise.
    func slotStatus(now: Date = Time.now()) -> SlotStatus {
        let bounds = cycle.bounds(including: now)
        let cycleCheckIns = checkInsInRange(startPsychDay: bounds.start, endPsychDay: bounds.end)
        let remainingSlots = remainingUsableOccurrences(
            in: slotOccurrences(from: bounds.start, until: bounds.end),
            now: now,
            checkIns: cycleCheckIns
        )
        return SlotStatus(kind: classifyKind(remainingSlots: remainingSlots, now: now), remainingSlots: remainingSlots)
    }

    /// Classifies where `now` falls relative to `remainingSlots` (assumed sorted by start):
    /// `.insideSlot` if the first remaining slot has already started, `.beforeNextToday` if
    /// some remaining slot starts later within today's psych-day, else `.noSlotToday`.
    private func classifyKind(remainingSlots: [SlotOccurrence], now: Date) -> SlotStatusKind {
        let nowPsychDay = Time.startOfDay(for: now)
        let todayEnd =
            Time.calendar.date(byAdding: .day, value: 1, to: nowPsychDay) ?? nowPsychDay

        if let first = remainingSlots.first, first.start <= now {
            return .insideSlot
        } else if remainingSlots.contains(where: { $0.start < todayEnd }) {
            return .beforeNextToday
        } else {
            return .noSlotToday
        }
    }

    struct CommitmentStatus: Equatable {
        let slotKind: SlotStatusKind
        let remainingSlots: [SlotOccurrence]?
        /// Nil when target is disabled or reminders are off.
        let leftToDo: Int?
        /// `max(0, leftToDo - remainingSlots.count)`. Nil when target is disabled or reminders are off.
        let behindCount: Int?
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
    /// It is `false` once the cycle goal is met, unless the user opted into
    /// `continueRemindersAfterGoalMet`. Slot-level concerns (snooze, capacity/saturation,
    /// window timing) are NOT decided here — those live in `slotStatus` /
    /// `remainingUsableOccurrences` and are applied downstream by the `*WithBehind` helpers.
    ///
    /// This is the single source of truth for the goal-met∕continue rule; every surface must
    /// go through it (directly or via the `*WithBehind` helpers, which call it) so they agree.
    func isActiveForReminders(now: Date = Time.now()) -> Bool {
        if continueRemindersAfterGoalMet { return true }
        return !goalProgress(now: now).isMet
    }

    /// Returns the combined slot + goal status for `now` — the slot kind, remaining slots,
    /// goal `leftToDo`, and derived `behindCount` in one value.
    ///
    /// When `isRemindersEnabled` is false, treats the commitment as having no slots:
    /// `slotKind` is `.disabled` and `remainingSlots` is nil.
    func status(now: Date = Time.now()) -> CommitmentStatus {
        if !isRemindersEnabled {
            return CommitmentStatus(
                slotKind: .disabled,
                remainingSlots: nil,
                leftToDo: nil,
                behindCount: nil
            )
        }
        let slot = slotStatus(now: now)
        let progress = goalProgress(now: now)
        let behind: Int? = progress.leftToDo.map { max(0, $0 - slot.remainingSlots.count) }
        return CommitmentStatus(
            slotKind: slot.kind,
            remainingSlots: slot.remainingSlots,
            leftToDo: progress.leftToDo,
            behindCount: behind
        )
    }

    /// Returns the start times of all eligible slot occurrences in `[from, to)`.
    ///
    /// Eligibility is evaluated at each occurrence's own start time, so snooze and
    /// saturation checks reflect the slot's actual state when it fires.
    func slotStarts(from: Date, to: Date) -> [Date] {
        let startDay = Time.startOfDay(for: from)
        let cycleCheckIns = checkInsInRange(startPsychDay: startDay, endPsychDay: to)
        let occurrences = slotOccurrences(from: startDay, until: to, includeCarryOver: false)
        return occurrences.compactMap { occ -> Date? in
            let start = occ.start
            guard start >= from, start < to else { return nil }
            guard occ.isUsable(checkIns: cycleCheckIns) else { return nil }
            return start
        }
    }

    private func slotOccurrences(
        from startDay: Date,
        until endDay: Date,
        includeCarryOver: Bool = true,  // if we include slots that end on StartDay but start on PreviousDay.
        calendar: Calendar = Time.calendar
    ) -> [SlotOccurrence] {
        var occurrences: [SlotOccurrence] = []

        if includeCarryOver,
            let previousDay = calendar.date(byAdding: .day, value: -1, to: startDay)
        {
            for slot in slots {
                guard let occurrence = slot.occurrence(on: previousDay) else { continue }
                guard occurrence.end > startDay else { continue }
                occurrences.append(occurrence)
            }
        }

        var dayCursor = startDay
        while dayCursor < endDay {
            for slot in slots {
                guard let occurrence = slot.occurrence(on: dayCursor) else { continue }
                occurrences.append(occurrence)
            }
            dayCursor = calendar.date(byAdding: .day, value: 1, to: dayCursor) ?? endDay
        }

        occurrences.sort {
            if $0.start == $1.start { return $0.end < $1.end }
            return $0.start < $1.start
        }
        return occurrences
    }

    private func remainingUsableOccurrences(
        in occurrences: [SlotOccurrence],
        now: Date,
        checkIns: [CheckIn]
    ) -> [SlotOccurrence] {
        occurrences.compactMap { occ -> SlotOccurrence? in
            guard occ.end >= now else { return nil }
            guard occ.start <= now else { return occ }
            // `now` is inside this occurrence's window, so usability "at now" is exactly this
            // occurrence's usability (snooze/saturation are per-occurrence).
            guard occ.isUsable(checkIns: checkIns) else { return nil }
            return occ
        }
    }
}
