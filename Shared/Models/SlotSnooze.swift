import Foundation
import SwiftData

/// Records that a specific slot instance has been snoozed by the user for its current occurrence.
///
/// A `SlotSnooze` is scoped to a single slot firing — identified by `slot` + `psychDay`
/// (derived from `slot.start`'s psychDay, not the tap time). It does not carry over to the
/// same slot on any other day.
///
/// Lifecycle:
/// - Created via `SlotSnooze.create(slot:at time:in:)` — returns nil if `time` is outside the
///   slot's active window (wrong time or wrong recurrence day).
/// - Deleted automatically (cascade) when its parent `Slot` is deleted.
/// - Stale entries (where the slot window has fully closed) are lazily deleted on each
///   `create` call.
@Model
final class SlotSnooze {
    @Attribute(.unique)
    var id: UUID = UUID()

    /// Logical day this snooze applies to, derived from `Time.startOfDay(for: slot.start)`.
    /// Always the psychDay of the **slot's start time**, not the moment snooze was tapped.
    /// For cross-midnight slots (e.g. 11pm–1am), a snooze tapped at 12am Jan 1 records
    /// psychDay = Dec 31 (the psychDay of 11pm).
    var psychDay: Date

    /// Wall-clock time the snooze was triggered.
    var snoozedAt: Date

    /// The slot being snoozed.
    /// The inverse relationship (Slot.snoozes) declares the cascade delete rule.
    var slot: Slot?

    init(slot: Slot, psychDay: Date, snoozedAt: Date) {
        self.slot = slot
        self.psychDay = psychDay
        self.snoozedAt = snoozedAt
    }
}

// MARK: - Factory

extension SlotSnooze {
    /// Creates and inserts a `SlotSnooze` for the given slot at `time`, or returns `nil` if
    /// `time` is outside the slot's active window (wrong time-of-day or wrong recurrence day).
    ///
    /// Always performs lazy cleanup first: deletes existing stale snoozes on `slot` where
    /// the slot window has fully closed (`resolvedSlotEnd < time`). This cleanup runs even
    /// when `create` returns nil.
    ///
    /// - Parameters:
    ///   - slot: The slot to snooze. SwiftData `@Model` objects require an explicit `ModelContext`
    ///     for insert/delete — there is no implicit context on the model itself (unlike CoreData).
    ///   - time: The creation time (injectable for testing), and effective time.
    ///   - context: The SwiftData context to insert into.
    /// - Returns: The newly created `SlotSnooze`, or `nil` if `time` is not in the slot's window.
    @discardableResult
    static func create(slot: Slot, at time: Date = Time.now(), in context: ModelContext)
        -> SlotSnooze?
    {
        let calendar = Time.calendar

        // Lazy cleanup: always remove stale snoozes, regardless of whether we'll insert a new one.
        let stale = slot.snoozes.filter { existing in
            resolvedSlotEnd(slot: slot, psychDay: existing.psychDay, calendar: calendar) < time
        }
        for s in stale {
            slot.snoozes.removeAll { $0.id == s.id }
            context.delete(s)
        }

        // Guard: `time`` must be within an active window for this slot.
        guard slot.isActive(on: time) else { return nil }

        // psychDay is the psychDay of the slot's start occurrence at `time`.
        // For cross-midnight slots (e.g. 11pm–1am), a snooze tapped at 12am Jan 1
        // belongs to the Dec 31 occurrence (start was 11pm Dec 31), so psychDay = Dec 31.
        // slotPsychDay can't throw here — we already guarded isActive above.
        guard let psychDay = try? slotPsychDay(slot: slot, at: time, calendar: calendar) else {
            return nil
        }

        let snooze = SlotSnooze(slot: slot, psychDay: psychDay, snoozedAt: time)
        context.insert(snooze)
        return snooze
    }

    enum SlotPsychDayError: Error {
        /// `time` is not within the slot's active window.
        case slotNotActive
    }

    /// Returns the psychDay of the slot's current occurrence at `time`.
    ///
    /// For normal slots (start < end), this is `Time.startOfDay(for: time)`.
    /// For cross-midnight slots (start > end), if `time` is in the post-midnight portion
    /// (i.e. before the end time), the occurrence started the previous calendar day,
    /// so we return `Time.startOfDay(for: yesterday)`.
    ///
    /// - Throws: `SlotPsychDayError.slotNotActive` if `time` is outside the slot's active window.
    static func slotPsychDay(slot: Slot, at time: Date, calendar: Calendar) throws -> Date {
        guard slot.isActive(on: time, calendar: calendar) else {
            throw SlotPsychDayError.slotNotActive
        }

        let startComponents = calendar.dateComponents([.hour, .minute], from: slot.start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: slot.end)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)

        guard startMinutes >= endMinutes else {
            // Normal (non-cross-midnight) slot: psychDay is derived from time.
            return Time.startOfDay(for: time)
        }

        // Cross-midnight slot: check if time is in the post-midnight tail (before endMinutes).
        let targetTimeComponents = calendar.dateComponents([.hour, .minute], from: time)
        let targetMinutes =
            (targetTimeComponents.hour ?? 0) * 60 + (targetTimeComponents.minute ?? 0)

        if targetMinutes < startMinutes {
            // Post-midnight portion: this occurrence started yesterday.
            let yesterday = calendar.date(byAdding: .day, value: -1, to: time) ?? time
            return Time.startOfDay(for: yesterday)
        } else {
            // Pre-midnight portion: occurrence starts today.
            return Time.startOfDay(for: time)
        }
    }

    /// Resolves the absolute end time of `slot` for the occurrence on `psychDay`.
    ///
    /// For normal slots (start < end), the end falls on the same calendar day as `psychDay`.
    /// For cross-midnight slots (start > end), the end falls on the calendar day *after* `psychDay`.
    private static func resolvedSlotEnd(slot: Slot, psychDay: Date, calendar: Calendar) -> Date {
        let startComponents = calendar.dateComponents([.hour, .minute], from: slot.start)
        let endComponents = calendar.dateComponents([.hour, .minute], from: slot.end)
        let startMinutes = (startComponents.hour ?? 0) * 60 + (startComponents.minute ?? 0)
        let endMinutes = (endComponents.hour ?? 0) * 60 + (endComponents.minute ?? 0)

        let endCalendarDay: Date
        if startMinutes < endMinutes {
            // Normal slot: end is on the same calendar day as psychDay.
            endCalendarDay = psychDay
        } else {
            // Cross-midnight slot: end is on the following calendar day.
            endCalendarDay = calendar.date(byAdding: .day, value: 1, to: psychDay) ?? psychDay
        }

        let endHour = endComponents.hour ?? 0
        let endMinute = endComponents.minute ?? 0
        return calendar.date(
            bySettingHour: endHour, minute: endMinute, second: 0, of: endCalendarDay
        ) ?? endCalendarDay
    }
}
