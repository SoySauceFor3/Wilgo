import Foundation
import SwiftData

/// Records that a specific slot firing has been snoozed by the user for one logical day.
///
/// A `SlotSnooze` is a **frozen occurrence reference**: it is identified by `slot` + `psychDay`,
/// where `psychDay` is the anchor day of the firing (the day the window *starts* on), captured
/// once at create time and **never re-derived from the live slot**. It is therefore *not* a
/// `SlotOccurrence` — a `SlotOccurrence` recomputes its window from the live slot on demand,
/// whereas a `SlotSnooze.psychDay` is a persisted fact. (If a snooze recomputed its day, editing
/// the slot's recurrence would silently change which day was silenced.) It does not carry over to
/// the same slot on any other day.
///
/// Staleness from slot edits is handled without any active invalidation here:
/// - The supported edit flow (`CommitmentFormDraft.apply`) deletes and recreates `Slot`s, so the
///   `Slot.snoozes` cascade-delete wipes a slot's snoozes on edit.
/// - `Slot.isSnoozed`'s `isScheduled` guard renders any leftover snooze inert (a day the slot no
///   longer fires never matches), and lazy cleanup eventually removes it.
///   **Invariant:** any future in-place slot editor (mutating `start`/`end`/`recurrence` without
///   delete-and-recreate) must clear that slot's snoozes.
///
/// Lifecycle:
/// - Created via `Slot.snooze(at:in:)` — returns nil if `time` is outside the slot's active
///   window (wrong time or wrong recurrence day).
/// - Deleted automatically (cascade) when its parent `Slot` is deleted.
/// - Stale entries (where the firing's window has fully closed, or no longer resolves) are
///   lazily deleted on each `Slot.snooze(at:in:)` call.
@Model
final class SlotSnooze {
    @Attribute(.unique)
    var id: UUID = UUID()

    /// Logical/anchor day this snooze applies to — the day the snoozed firing *starts* on.
    /// Frozen at create from `slot.anchorDate(for: tapTime)`, never re-derived.
    /// For cross-midnight slots (e.g. 11pm–1am), a snooze tapped at 12am Jan 1 records
    /// psychDay = Dec 31 (the anchor day of the 11pm start).
    var psychDay: Date

    /// Wall-clock time the snooze was triggered.
    var snoozedAt: Date

    /// The slot being snoozed.
    /// The inverse relationship (Slot.snoozes) declares the cascade delete rule.
    var slot: Slot

    init(slot: Slot, psychDay: Date, snoozedAt: Date) {
        self.slot = slot
        self.psychDay = psychDay
        self.snoozedAt = snoozedAt
    }
}
