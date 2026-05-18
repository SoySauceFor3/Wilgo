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

extension Target {
    var configuredMode: TargetMode {
        mode
    }

    func effectiveMode(on psychDay: Date) -> TargetMode {
        do {
            return try mode.effectiveMode(on: psychDay)
        } catch {
            return .on
        }

    }

    func effectiveMode(from startPsychDay: Date, to endPsychDay: Date) -> TargetMode {
        do {
            return try mode.effectiveMode(from: startPsychDay, to: endPsychDay)
        } catch {
            return .on
        }

    }

    mutating func setConfiguredMode(_ mode: TargetMode) {
        self.mode = mode
    }

    mutating func normalizeMode(afterReportedThrough reportedEndPsychDay: Date) {
        mode = mode.normalized(afterReportedThrough: reportedEndPsychDay)
    }

}

// MARK: - Commitment

@Model
final class Commitment {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var createdAt: Date

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

    /// When false, this commitment is excluded from Stage reminders and CatchUpReminder notifications.
    var isRemindersEnabled: Bool = true

    init(
        title: String,
        createdAt: Date = .now,
        cycle: Cycle,
        slots: [Slot],
        target: Target,
        proofOfWorkType: ProofOfWorkType = .manual,
        punishment: String? = nil,
        isRemindersEnabled: Bool = true,
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
    }

    // checkins of a commitment in a given psych-day range [startPsychDay, endPsychDay)
    func checkInsInRange(startPsychDay: Date, endPsychDay: Date) -> [CheckIn] {
        let checkInsInRange = checkIns.filter {
            $0.psychDay >= startPsychDay && $0.psychDay < endPsychDay
        }
        return checkInsInRange.sorted { $0.createdAt < $1.createdAt }
    }

}

// MARK: - Slot queries

extension Commitment {
    private typealias ResolvedSlotPair = (occurrence: Slot, original: Slot)

    func checkInsInCycle(
        cycle: Cycle,
        until psychDay: Date = Time.startOfDay(for: Time.now()),
        inclusive: Bool = true
    ) -> [CheckIn] {
        let start = cycle.startDayOfCycle(including: psychDay)
        return checkIns.filter {
            start <= $0.psychDay && (inclusive ? $0.psychDay <= psychDay : $0.psychDay < psychDay)
        }
    }

    // MARK: - Stage categorization

    enum StageCategory {
        case metGoal
        case current
        case future
        case catchUp
        case others
    }

    struct StageStatus {
        let category: StageCategory
        /// All unfinished slots whose windows have not yet ended in the target cycle, sorted.
        /// Includes the current slot (if any) and any later slots.
        /// IMPORTANT: it contains date info, not just time of day.
        let nextUpSlots: [Slot]
        /// Minimal number of extra check-ins that must be done
        /// outside the remaining scheduled slots in this cycle
        /// in order to still hit the target.
        let behindCount: Int
    }

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
    /// built over the full target cycle regardless of `target.effectiveMode`. The
    /// `stageStatus(now:)` wrapper consumes the same list in both modes. For daily
    /// cycles the cycle window equals the psych-day window; for longer cycles it
    /// is strictly wider, so `remainingSlots` may include slots beyond today.
    struct SlotStatus {
        /// Classification of where `now` falls relative to `remainingSlots`.
        let kind: SlotStatusKind
        /// Unfinished, unsnoozed, unsaturated slot occurrences in the target cycle,
        /// sorted by start time. Includes the current slot (if any) and any later slots.
        /// Carries date info, not just time of day.
        let remainingSlots: [Slot]
    }

    /// Returns the slot mechanics for `now`. Mode-agnostic — always uses the
    /// target cycle as the window, regardless of `target.effectiveMode`.
    ///
    /// `remainingSlots` matches what `stageStatus` builds today for the enabled
    /// branch: occurrences whose window has not yet ended, with the current slot
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
            in: resolvedSlotPairs(from: startDay, until: endDay),
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
        let remainingSlots: [Slot]?
        /// Nil when target is disabled or reminders are off.
        let leftToDo: Int?
        /// `max(0, leftToDo - remainingSlots.count)`. Nil when target is disabled or reminders are off.
        let behindCount: Int?
    }

    /// Returns the cycle-level goal progress for the cycle containing `now`.
    ///
    /// Mirrors the `leftToDo` arithmetic inside `stageStatus(now:)`. When the target
    /// is disabled on the psych day of `now`, returns `GoalProgress(leftToDo: nil)`
    /// — there is no meaningful "left to do" in that mode, and `isMet` will be `false`,
    /// matching today's behavior where target-disabled commitments are never `.metGoal`.
    func goalProgress(now: Date = Time.now()) -> GoalProgress {
        let nowPsychDay = Time.startOfDay(for: now)
        if case .disabled = target.effectiveMode(on: nowPsychDay) {
            return GoalProgress(leftToDo: nil)
        }
        let startDay = cycle.startDayOfCycle(including: nowPsychDay)
        let endDay = cycle.endDayOfCycle(including: nowPsychDay)
        let checkInsInCycle = checkInsInRange(startPsychDay: startDay, endPsychDay: endDay)
        let leftToDo = max(0, target.count - checkInsInCycle.count)
        return GoalProgress(leftToDo: leftToDo)
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
        let pairs = resolvedSlotPairs(from: startDay, until: to, includeCarryOver: false)
        return pairs.compactMap { pair -> Date? in
            let start = pair.occurrence.start
            guard start >= from, start < to else { return nil }
            guard !pair.original.isSnoozed(at: start) else { return nil }
            guard !pair.original.isSaturated(at: start, checkIns: cycleCheckIns) else { return nil }
            return start
        }
    }

    private func resolvedSlotPairs(
        from startDay: Date,
        until endDay: Date,
        includeCarryOver: Bool = true,  // if we include slots that end on StartDay but start on PreviousDay.
        calendar: Calendar = Time.calendar
    ) -> [ResolvedSlotPair] {
        var pairs: [ResolvedSlotPair] = []

        if includeCarryOver,
            let previousDay = calendar.date(byAdding: .day, value: -1, to: startDay)
        {
            for slot in slots {
                guard let occurrence = slot.resolveOccurrence(on: previousDay) else { continue }
                guard occurrence.end > startDay else { continue }
                pairs.append((occurrence: occurrence, original: slot))
            }
        }

        var dayCursor = startDay
        while dayCursor < endDay {
            for slot in slots {
                guard let occurrence = slot.resolveOccurrence(on: dayCursor) else { continue }
                pairs.append((occurrence: occurrence, original: slot))
            }
            dayCursor = calendar.date(byAdding: .day, value: 1, to: dayCursor) ?? endDay
        }

        pairs.sort {
            let lhs = $0.occurrence
            let rhs = $1.occurrence
            if lhs.start == rhs.start { return lhs.end < rhs.end }
            return lhs.start < rhs.start
        }
        return pairs
    }

    private func remainingUsableOccurrences(
        in pairs: [ResolvedSlotPair],
        now: Date,
        checkIns: [CheckIn]
    ) -> [Slot] {
        pairs.compactMap { pair in
            guard pair.occurrence.end >= now else { return nil }
            guard pair.occurrence.start <= now else { return pair.occurrence }
            guard !pair.original.isSnoozed(at: now) else { return nil }
            guard !pair.original.isSaturated(at: now, checkIns: checkIns) else { return nil }
            return pair.occurrence
        }
    }

    /// Classifies this commitment for the current psychological day at the given time.
    ///
    /// Thin wrapper over `slotStatus(now:)` and `goalProgress(now:)`. Precedence:
    /// - `metGoal`: if cycle's goal already met (target-enabled only).
    /// - `current`: elif there is a slot whose window contains `now`.
    /// - `future`: elif there are slots within today (psych day).
    /// - `catchUp`: elif the count of remaining slots < leftToDo (target-enabled only).
    /// - `others`: all other cases.
    func stageStatus(
        now: Date = Time.now()
    ) -> StageStatus {
        let nowPsychDay = Time.startOfDay(for: now)
        let slot = slotStatus(now: now)

        if case .disabled = target.effectiveMode(on: nowPsychDay) {
            // Target-disabled: no goal progress, no behindCount. Map kind directly.
            switch slot.kind {
            case .disabled:
                return StageStatus(category: .others, nextUpSlots: [], behindCount: 0)
            case .insideSlot:
                return StageStatus(
                    category: .current, nextUpSlots: slot.remainingSlots, behindCount: 0)
            case .beforeNextToday:
                return StageStatus(
                    category: .future, nextUpSlots: slot.remainingSlots, behindCount: 0)
            case .noSlotToday:
                return StageStatus(
                    category: .others, nextUpSlots: slot.remainingSlots, behindCount: 0)
            }
        }

        let progress = goalProgress(now: now)
        if progress.isMet {
            return StageStatus(category: .metGoal, nextUpSlots: [], behindCount: 0)
        }
        // Invariant: enabled branch — `leftToDo` is non-nil and > 0.
        guard let leftToDo = progress.leftToDo else {
            preconditionFailure("goalProgress.leftToDo must be non-nil when target is not disabled")
        }
        let behindCount = max(0, leftToDo - slot.remainingSlots.count)

        switch slot.kind {
        case .disabled:
            return StageStatus(category: .others, nextUpSlots: [], behindCount: 0)
        case .insideSlot:
            return StageStatus(
                category: .current, nextUpSlots: slot.remainingSlots, behindCount: behindCount)
        case .beforeNextToday:
            return StageStatus(
                category: .future, nextUpSlots: slot.remainingSlots, behindCount: behindCount)
        case .noSlotToday:
            let category: StageCategory = behindCount > 0 ? .catchUp : .others
            return StageStatus(
                category: category, nextUpSlots: slot.remainingSlots, behindCount: behindCount)
        }
    }
}
