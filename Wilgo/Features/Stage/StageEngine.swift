import Foundation
import SwiftData

struct StageState {
    let currentHabitSlots: [(Habit, HabitSlot)]
    let upcomingHabitSlots: [(Habit, HabitSlot)]
    let missedSlots: [MissedHabit]
    let firstLiveActivityContentState: NowAttributes.ContentState?
    /// Window end of the first current habit slot — used as the live activity stale date.
    let firstLiveActivityStaleDate: Date?
    /// The earliest upcoming slot boundary (windowStart or windowEnd). Used to schedule
    /// the next UI tick and the next live activity sync wake-up.
    let nextTransitionDate: Date
}

/// Minimal state needed by LiveActivityManager — avoids computing upcoming/missed rows.
struct LiveActivityUpdate {
    let contentState: NowAttributes.ContentState?
    let staleDate: Date?
    let nextTransitionDate: Date
}

enum StageEngine {
    static func makeState(
        habits: [Habit],
        snoozedSlots: [SnoozedSlot],
        now: Date
    ) -> StageState {
        let psychDay = HabitScheduling.psychDay(for: now)
        let todaysSnoozes = snoozedSlots.filter { $0.psychDay == psychDay && $0.resolvedAt == nil }

        let current = computeCurrentHabitSlots(
            habits: habits,
            todaysSnoozes: todaysSnoozes,
            now: now,
        )
        let upcoming = computeUpcomingHabitSlots(
            habits: habits,
            now: now,
        )
        let missed = computeMissedSlots(
            habits: habits,
            todaysSnoozes: todaysSnoozes,
            now: now,
        )
        let contentState = makeFirstLiveActivityContentState(from: current)
        let staleDate = current.first.map { $0.1.endToday }
        let nextTransition = computeNextTransitionDate(habits: habits, now: now)

        return StageState(
            currentHabitSlots: current,
            upcomingHabitSlots: upcoming,
            missedSlots: missed,
            firstLiveActivityContentState: contentState,
            firstLiveActivityStaleDate: staleDate,
            nextTransitionDate: nextTransition
        )
    }

    static func makeLiveActivityUpdate(
        habits: [Habit],
        snoozedSlots: [SnoozedSlot],
        now: Date
    ) -> LiveActivityUpdate {
        let psychDay = HabitScheduling.psychDay(for: now)
        let todaysSnoozes = snoozedSlots.filter { $0.psychDay == psychDay && $0.resolvedAt == nil }
        let current = computeCurrentHabitSlots(
            habits: habits,
            todaysSnoozes: todaysSnoozes,
            now: now,
        )
        return LiveActivityUpdate(
            contentState: makeFirstLiveActivityContentState(from: current),
            staleDate: current.first.map { $0.1.endToday },
            nextTransitionDate: computeNextTransitionDate(habits: habits, now: now)
        )
    }

    // MARK: - Current

    private static func computeCurrentHabitSlots(
        habits: [Habit],
        todaysSnoozes: [SnoozedSlot],
        now: Date
    ) -> [(Habit, HabitSlot)] {
        var result = habits.compactMap { habit -> (Habit, HabitSlot)? in
            guard
                let slot = habit.firstCurrentSlot(
                    now: now, excluding: todaysSnoozes)
            else { return nil }
            return (habit, slot)
        }

        // Sort by fraction of window remaining: time left / full window length.
        let remainingFraction = { (slot: HabitSlot) -> Double in
            let duration = max(slot.endToday.timeIntervalSince(slot.startToday), 1)
            let remaining = max(slot.endToday.timeIntervalSince(now), 0)
            return remaining / duration
        }
        result.sort { remainingFraction($0.1) < remainingFraction($1.1) }

        return result
    }

    // MARK: - Upcoming

    private static func computeUpcomingHabitSlots(
        habits: [Habit],
        now: Date
    ) -> [(Habit, HabitSlot)] {
        var result = habits.compactMap { habit -> (Habit, HabitSlot)? in
            guard let slot = habit.firstFutureSlot(now: now)
            else { return nil }
            return (habit, slot)
        }

        result.sort { $0.1 < $1.1 }
        return result
    }

    // MARK: - Missed

    private static func computeMissedSlots(
        habits: [Habit],
        todaysSnoozes: [SnoozedSlot],
        now: Date
    ) -> [MissedHabit] {
        var result: [MissedHabit] = []

        for habit in habits {
            guard !habit.slots.isEmpty else { continue }

            let completedCount = habit.completedCount(now: now)

            var missedCount = 0
            var latestMissedSlot: HabitSlot?

            for slot in habit.remainingSlots(now: now) {
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

    // MARK: - Transition date

    /// Earliest upcoming windowStart or windowEnd across all habits' slots.
    /// Falls back to a 60-second poll when no transitions remain today.
    static func computeNextTransitionDate(habits: [Habit], now: Date) -> Date {
        var candidates: [Date] = []
        for habit in habits {
            for slot in habit.slots {
                let start = slot.startToday
                let end = slot.endToday
                if start > now { candidates.append(start) }
                if end > now { candidates.append(end) }
            }
        }
        return candidates.min() ?? now.addingTimeInterval(60)
    }

    // MARK: - Live activity helpers

    private static func makeFirstLiveActivityContentState(
        from currentHabitSlots: [(Habit, HabitSlot)]
    ) -> NowAttributes.ContentState? {
        guard let (habit, slot) = currentHabitSlots.first else { return nil }
        let habitId = habit.persistentModelID.encoded()
        let slotId = slot.persistentModelID.encoded()
        return NowAttributes.ContentState(
            habitTitle: habit.title,
            slotTimeText: slot.slotTimeText,
            habitId: habitId,
            slotId: slotId
        )
    }
}
