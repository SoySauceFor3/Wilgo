//
//  HabitScheduling.swift
//  Wilgo
//
//  Reusable scheduling and "today" time helpers for habits.
//

import Foundation

/// Shared scheduling and calendar utilities for habits.
enum HabitScheduling {
    static let calendar = Calendar.current
    static let config = PhaseConfig.default

    /// Resolves a habit's time-of-day `Date` to today's date with that time.
    static func today(at timeOfDay: Date) -> Date {
        let comps = calendar.dateComponents([.hour, .minute], from: timeOfDay)
        return calendar.date(
            bySettingHour: comps.hour ?? 0,
            minute: comps.minute ?? 0,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    /// Soft deadline for "today": end of day (e.g. midnight as start of next day).
    static func todaySoftDeadline() -> Date {
        var day = calendar.startOfDay(for: Date())
        if config.softDeadlineHour >= 24 {
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return calendar.date(
                bySettingHour: 0,
                minute: config.softDeadlineMinute,
                second: 0,
                of: day
            ) ?? day
        }
        return calendar.date(
            bySettingHour: config.softDeadlineHour,
            minute: config.softDeadlineMinute,
            second: 0,
            of: day
        ) ?? day
    }

    /// Soft deadline used for ordering (e.g. pick "earliest deadline" among active habits).
    static func softDeadline(for habit: Habit, now: Date = Date()) -> Date {
        todaySoftDeadline()
    }

    /// Window start on the current reference day (for sorting upcoming).
    static func windowStartToday(for habit: Habit) -> Date {
        today(at: habit.idealWindowStart)
    }

    /// Window end on the current reference day.
    static func windowEndToday(for habit: Habit) -> Date {
        today(at: habit.idealWindowEnd)
    }

    /// Whether this habit's window start is still later today (for "upcoming" list).
    static func isUpcomingToday(_ habit: Habit, now: Date = Date()) -> Bool {
        let windowStart = windowStartToday(for: habit)
        let windowEnd = windowEndToday(for: habit)
        if windowEnd <= windowStart {
            // Crosses midnight: "upcoming" if we're before window start or in early part of next day
            return now < windowStart
        }
        return now < windowStart
    }

    /// Start of the critical window before today's soft deadline.
    static func criticalStart(now: Date = Date()) -> Date {
        let softDeadline = todaySoftDeadline()
        return calendar.date(
            byAdding: .hour,
            value: -Int(config.criticalWindowHours),
            to: softDeadline
        ) ?? softDeadline
    }
}

