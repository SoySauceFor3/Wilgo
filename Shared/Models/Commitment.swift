import Foundation
import SwiftData

enum ProofOfWorkType: String, Codable {
    case manual = "Manual"
    // case notionAPI = "Notion API"
    // case healthKit = "HealthKit"
}

struct Target: Codable, Hashable {
    var count: Int  // “how many per that cycle”
    private var mode: TargetMode = .on

    init(count: Int, mode: TargetMode = .on) {
        self.count = count
        self.mode = mode
    }
}

// Legacy code, can be removed and replaced with just `var mode: TargetMode` if needed later
extension Target {
    var configuredMode: TargetMode { mode }

    mutating func setConfiguredMode(_ mode: TargetMode) {
        self.mode = mode
    }
}

// MARK: - Commitment

@Model
final class Commitment {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var createdAt: Date
    /// When the commitment was archived. Nil means the commitment is active.
    var archivedAt: Date?

    /// Historical completion / skip records for this commitment.
    @Relationship(deleteRule: .cascade, inverse: \CheckIn.commitment)
    var checkIns: [CheckIn] = []

    /// N× daily: each slot has its own ideal window.
    @Relationship(deleteRule: .cascade, inverse: \Slot.commitment)
    var slots: [Slot] = []

    /// The time window used for grouping check-ins and triggering cycle reports.
    /// Always present, independent of whether a goal is set.
    var cycle: Cycle
    var target: Target

    /// How completion is verified.
    var proofOfWorkType: ProofOfWorkType
    /// What the user owes if skip credits are exhausted (e.g. "Give robaroba 20 RMB").
    /// Nil means no punishment is set.
    var punishment: String?

    var encouragements: [String] = []

    @Relationship(deleteRule: .nullify, inverse: \Tag.commitments)
    var tags: [Tag] = []  // nullify: deleting a Tag removes it from this array; Commitment survives

    @Relationship(deleteRule: .cascade, inverse: \CycleRecord.commitment)
    var cycleRecords: [CycleRecord] = []

    /// When false, this commitment is excluded from Stage reminders and CatchUpReminder notifications.
    var isRemindersEnabled: Bool = true

    /// When true, reminders keep firing even after the daily goal has been met.
    var continueRemindersAfterGoalMet: Bool = false

    init(
        title: String,
        createdAt: Date = .now,
        cycle: Cycle,
        slots: [Slot],
        target: Target,
        proofOfWorkType: ProofOfWorkType = .manual,
        punishment: String? = nil,
        isRemindersEnabled: Bool = true,
        continueRemindersAfterGoalMet: Bool = false,
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.cycle = cycle
        self.slots = slots
        self.target = target
        self.proofOfWorkType = proofOfWorkType
        self.punishment = punishment
        self.isRemindersEnabled = isRemindersEnabled
        self.continueRemindersAfterGoalMet = continueRemindersAfterGoalMet
    }

    // checkins of a commitment in a given psych-day range [startPsychDay, endPsychDay)
    func checkInsInRange(startPsychDay: Date, endPsychDay: Date) -> [CheckIn] {
        let checkInsInRange = checkIns.filter {
            $0.psychDay >= startPsychDay && $0.psychDay < endPsychDay
        }
        return checkInsInRange.sorted { $0.createdAt < $1.createdAt }
    }

    /// Check-ins falling in the target cycle that contains `day`, sorted by `createdAt`.
    /// Uses the half-open cycle range `[startDay, exclusiveEndDay)` — the same window the status
    /// engine (`goalProgress`) counts against, so UI counts stay consistent with goal-met logic.
    func checkInsInCycle(containing day: Date = Time.now()) -> [CheckIn] {
        let psychDay = Time.startOfDay(for: day)
        let startDay = cycle.startDayOfCycle(including: psychDay)
        let endDay = cycle.endDayOfCycle(including: psychDay)
        return checkInsInRange(startPsychDay: startDay, endPsychDay: endDay)
    }

}

// MARK: - Slot queries

extension Commitment {
    /// Cycle-level goal progress, independent of slot mechanics.
    struct GoalProgress {
        /// `max(0, target.count - checkInsInCycle.count)`. Nil when target is disabled
        /// (no meaningful "left to do" exists in that mode).
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
        let nowPsychDay = Time.startOfDay(for: now)
        let startDay = cycle.startDayOfCycle(including: nowPsychDay)
        let endDay = cycle.endDayOfCycle(including: nowPsychDay)
        let cycleCheckIns = checkInsInRange(startPsychDay: startDay, endPsychDay: endDay)
        let remainingSlots = remainingUsableOccurrences(
            in: slotOccurrences(from: startDay, until: endDay),
            now: now,
            checkIns: cycleCheckIns
        )

        let todayEnd =
            Time.calendar.date(byAdding: .day, value: 1, to: nowPsychDay) ?? nowPsychDay

        let kind: SlotStatusKind
        if let first = remainingSlots.first, first.start <= now {
            kind = .insideSlot
        } else if remainingSlots.contains(where: { $0.start < todayEnd }) {
            kind = .beforeNextToday
        } else {
            kind = .noSlotToday
        }
        return SlotStatus(kind: kind, remainingSlots: remainingSlots)
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
        let nowPsychDay = Time.startOfDay(for: now)
        if case .disabled = target.configuredMode {
            return GoalProgress(leftToDo: nil)
        }
        let startDay = cycle.startDayOfCycle(including: nowPsychDay)
        let endDay = cycle.endDayOfCycle(including: nowPsychDay)
        let checkInsInCycle = checkInsInRange(startPsychDay: startDay, endPsychDay: endDay)
        let leftToDo = max(0, target.count - checkInsInCycle.count)
        return GoalProgress(leftToDo: leftToDo)
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

    /// Returns the combined slot + goal status for `now`. Prefer this over calling
    /// `slotStatus` and `goalProgress` separately when both are needed, as it avoids
    /// computing cycle check-ins twice.
    ///
    /// When `isRemindersEnabled` is false, treats the commitment as having no slots:
    /// `slotKind` is `.noSlotToday` and `remainingSlots` is empty.
    func status(now: Date = Time.now()) -> CommitmentStatus {
        if !isRemindersEnabled {
            return CommitmentStatus(
                slotKind: .disabled,
                remainingSlots: nil,
                leftToDo: nil,
                behindCount: nil
            )
        }
        let slot: SlotStatus = slotStatus(now: now)
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
            guard !occ.slot.isSnoozed(at: start) else { return nil }
            guard !occ.slot.isSaturated(at: start, checkIns: cycleCheckIns) else { return nil }
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
            guard !occ.slot.isSnoozed(at: now) else { return nil }
            guard !occ.slot.isSaturated(at: now, checkIns: checkIns) else { return nil }
            return occ
        }
    }
}
