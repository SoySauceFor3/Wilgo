//
//  SnoozedSlot.swift
//  Wilgo
//
//  Tracks when a specific habit slot is snoozed (moved off the current window)
//  for a particular psychological day, without counting it as a completion.
//

import Foundation
import SwiftData

@Model
final class SnoozedSlot {
    @Relationship var habit: Habit?
    @Relationship var slot: Slot?

    /// Absolute time when the snooze happened.
    var createdAt: Date

    /// Psychological day this snooze belongs to (start-of-day in local calendar).
    var psychDay: Date

    /// When non-nil, this snooze has been resolved (e.g. the user later completed it).
    var resolvedAt: Date?

    init(
        habit: Habit,
        slot: Slot,
        createdAt: Date = HabitScheduling.now()
    ) {
        self.habit = habit
        self.slot = slot
        self.createdAt = createdAt

        let tzId = TimeZone.current.identifier
        self.psychDay = HabitScheduling.psychDay(for: createdAt, timeZoneIdentifier: tzId)
    }
}
