import Foundation

/// One concrete firing of a `Slot` on one logical day.
///
/// A value type — **NEVER PERSISTED**. It stores only the minimal identity (`slot` +
/// `psychDay`); the concrete window (`start`/`end`) is **computed** from the live slot on
/// demand, so an occurrence can never carry a window that disagrees with the slot.
///
/// The only way to build one is `Slot.occurrence(on:)`, which returns `nil` when the slot's
/// recurrence excludes the day — so a `SlotOccurrence` for a day the slot does not fire
/// cannot be constructed.
///
/// This replaces the former "resolved `Slot` copy" returned by `Slot.resolveOccurrence`,
/// which was a non-inserted `@Model` carrying meaningless `recurrence`/`maxCheckIns`/`snoozes`.
struct SlotOccurrence: Comparable {
    /// The template this firing belongs to (owns recurrence, maxCheckIns, snoozes).
    let slot: Slot
    /// The logical/anchor day this firing belongs to (the day the window *starts* on;
    /// for cross-midnight windows the post-midnight tail still belongs to this day).
    let psychDay: Date

    /// Concrete window start: the slot's start time-of-day resolved onto `psychDay`.
    var start: Date { Time.resolve(timeOfDay: slot.start, on: psychDay) }

    /// Concrete window end: the slot's end time-of-day resolved onto `psychDay`, bumped to
    /// the following calendar day for a cross-midnight window (e.g. 23:00–01:00).
    var end: Date {
        slot.endTime(onDayStarting: psychDay)
    }

    /// **Identity**: two occurrences are equal iff they are the *same firing* — same slot, same day.
    /// This is deliberately NOT window-based: two different slots can share an identical window on a
    /// day, yet they are distinct firings. Distinct from `<`, which is *chronological* (see below).
    static func == (lhs: SlotOccurrence, rhs: SlotOccurrence) -> Bool {
        lhs.slot.id == rhs.slot.id && lhs.psychDay == rhs.psychDay
    }

    /// **Chronological** order — earlier window first, then shorter (the `(start, end)` tie-break,
    /// mirroring `Slot`'s own `Comparable`). This answers a *different* question than `==`: `<` asks
    /// "does this fire earlier?", `==` asks "is this the same firing?". Consequently two distinct
    /// firings with identical windows tie under `<` (neither is `<` the other) without being `==`.
    /// That is safe for `sorted()`/`min()` — ties simply come out adjacent.
    static func < (lhs: SlotOccurrence, rhs: SlotOccurrence) -> Bool {
        if lhs.start == rhs.start { return lhs.end < rhs.end }
        return lhs.start < rhs.start
    }
}

// MARK: - Window helpers (meaningful only on a resolved firing)

extension SlotOccurrence {
    /// Fraction of the window remaining at `time`, in `[0, 1]`.
    /// Uses the concrete window, so cross-midnight windows are handled by the datetimes
    /// themselves (no time-of-day wraparound math needed).
    func remainingFraction(at time: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        let remaining = end.timeIntervalSince(time)
        return min(1, max(0, remaining / total))
    }

    /// Human-readable time-of-day window, delegating to the slot's formatting.
    var timeOfDayText: String { slot.timeOfDayText }

    /// This occurrence's anchor date + its time-of-day window, e.g. "Mar 14 · 7:00 – 9:00 AM".
    /// The date is the occurrence's start (anchor) day; for a cross-midnight window the end is
    /// still shown as time-of-day only. Use when a row must disambiguate *which day* the firing
    /// is on (e.g. an Upcoming slot in a future cycle).
    var datedLabel: String {
        "\(Self.dateFormatter.string(from: start)) · \(timeOfDayText)"
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// True if this firing's capacity is used up: the count of `checkIns` whose `createdAt`
    /// falls in this occurrence's own window `[start, end)` reaches the slot's `maxCheckIns`.
    /// Always false when `maxCheckIns` is nil (unlimited). Pass the full check-in set — only
    /// those inside this window are counted.
    func isSaturated(checkIns: [CheckIn]) -> Bool {
        guard let cap = slot.maxCheckIns, cap > 0 else { return false }
        let count = checkIns.reduce(0) { acc, checkIn in
            (checkIn.createdAt >= start && checkIn.createdAt < end) ? acc + 1 : acc
        }
        return count >= cap
    }

    /// True if this firing has been snoozed: the slot has a snooze whose frozen `psychDay`
    /// matches this occurrence's `psychDay`. (`SlotSnooze.psychDay` is set once at create and
    /// never re-derived, so a stale snooze for a different day never matches.)
    var isSnoozed: Bool {
        slot.snoozes.contains { Time.calendar.isDate($0.psychDay, inSameDayAs: psychDay) }
    }

    /// True if this firing can be acted on: neither snoozed nor saturated. Pass the full check-in
    /// set — saturation only counts those inside this occurrence's window. `&&` short-circuits, so
    /// the costlier saturation count is skipped when the firing is already snoozed.
    func isUsable(checkIns: [CheckIn]) -> Bool {
        !isSnoozed && !isSaturated(checkIns: checkIns)
    }
}
