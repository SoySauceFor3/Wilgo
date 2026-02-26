//
//  HabitCheckIn.swift
//  Wilgo
//
//

import Foundation
import SwiftData

enum HabitCheckInStatus: String, Codable {
    case completed
    case skipped
}

@Model
final class HabitCheckIn {
    @Relationship var habit: Habit?

    /// Which slot (0-based) was completed or skipped. Matches Habit.slots order.
    var slotIndex: Int

    /// Whether the habit was completed or intentionally skipped.
    var status: HabitCheckInStatus

    var createdAt: Date

    init(
        habit: Habit,
        slotIndex: Int,
        status: HabitCheckInStatus,
        createdAt: Date = .now
    ) {
        self.habit = habit
        self.slotIndex = slotIndex
        self.status = status
        self.createdAt = createdAt
    }
}
