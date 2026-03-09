import Foundation

enum HabitAndSlot {
    // For each habit that has NOT yet met today's goal, return the first slot that overlaps with `now` skipping snoozed ones.
    static func current(
        habits: [Habit],
        snoozedSlots: [SnoozedSlot],
        now: Date = HabitScheduling.now()
    ) -> [(Habit, Slot)] {
        let psychDay = HabitScheduling.psychDay(for: now)
        let todaysSnoozes = snoozedSlots.filter { $0.psychDay == psychDay && $0.resolvedAt == nil }
        var result = habits.compactMap { habit -> (Habit, Slot)? in
            if habit.hasMetDailyGoal(for: psychDay) { return nil }
            guard
                let slot = habit.firstCurrentSlot(
                    now: now,
                    excluding: todaysSnoozes.filter { $0.habit === habit }.compactMap { $0.slot })
            else { return nil }
            return (habit, slot)
        }

        // Sort by fraction of window remaining: time left / full window length.
        result.sort { $0.1.remainingFraction(at: now) < $1.1.remainingFraction(at: now) }

        return result
    }

    static func upcoming(
        habits: [Habit],
        now: Date = HabitScheduling.now()
    ) -> [(Habit, Slot)] {
        var result = habits.compactMap { habit -> (Habit, Slot)? in
            guard let slot = habit.firstFutureSlot(now: now)
            else { return nil }
            return (habit, slot)
        }

        result.sort { $0.1 < $1.1 }
        return result
    }

    // TODO: I will move some of the logic here to the Missed View.
    static func missed(
        habits: [Habit],
        snoozedSlots: [SnoozedSlot],
        now: Date = HabitScheduling.now()
    ) -> [MissedHabit] {
        let psychDay = HabitScheduling.psychDay(for: now)
        let todaysSnoozes = snoozedSlots.filter { $0.psychDay == psychDay && $0.resolvedAt == nil }

        var result: [MissedHabit] = []

        for habit in habits {
            guard !habit.slots.isEmpty else { continue }

            let completedCount = habit.completedCount(for: psychDay)

            var missedCount = 0
            var latestMissedSlot: Slot?

            for slot in habit.unfinishedSlots(for: psychDay) {
                let isSnoozed = todaysSnoozes.contains { $0.habit === habit && $0.slot === slot }

                if isSnoozed || slot.endToday <= now {
                    missedCount += 1
                    latestMissedSlot = slot
                }
            }

            guard missedCount > 0 else { continue }

            // Use the latest missed slot (by time in the schedule) for "overdue" display.
            guard let displaySlot = latestMissedSlot else { continue }
            let latestEnd = displaySlot.endToday
            let overdueBy = now.timeIntervalSince(latestEnd)

            result.append(
                MissedHabit(
                    habit: habit,
                    slot: displaySlot,
                    completedCount: completedCount,
                    missedCount: missedCount,
                    overdueBy: overdueBy
                )
            )
        }

        // Show the most overdue habits first.
        result.sort { $0.overdueBy > $1.overdueBy }
        return result
    }

    /// Earliest upcoming windowStart, windowEnd, or psychDay boundary across all habits' slots.
    static func nextTransitionDate(habits: [Habit], now: Date = HabitScheduling.now()) -> Date? {
        var candidates: [Date] = []
        for habit in habits {
            for slot in habit.slots {
                let start = slot.startToday
                let end = slot.endToday
                if start > now { candidates.append(start) }
                if end > now { candidates.append(end) }
            }
        }
        // Wake up exactly at the next psychDay boundary so the Stage resets on time
        // even when no slot transitions remain in the current day.
        let currentPsychDayBase = HabitScheduling.psychDay(for: now)
        if let nextPsychDayBase = HabitScheduling.calendar.date(
            byAdding: .day, value: 1, to: currentPsychDayBase)
        {
            let nextPsychDayStart = nextPsychDayBase.addingTimeInterval(
                TimeInterval(HabitScheduling.dayStartHourOffset * 3_600))
            if nextPsychDayStart > now { candidates.append(nextPsychDayStart) }
        }

        return candidates.min()
    }
}
