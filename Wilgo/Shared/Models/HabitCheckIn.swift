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

    /// Whether the habit was completed or intentionally skipped.
    var status: HabitCheckInStatus

    var createdAt: Date

    init(
        habit: Habit,
        status: HabitCheckInStatus,
        createdAt: Date = .now
    ) {
        self.habit = habit
        self.status = status
        self.createdAt = createdAt
    }
}

