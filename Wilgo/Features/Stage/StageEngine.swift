import Foundation

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

enum StageEngine {
    static func makeState(
        habits: [Habit],
        snoozedSlots: [SnoozedSlot],
        now: Date
    ) -> StageState {
        let psychDay = HabitScheduling.todayPsychDay(now: now)
        let todaysSnoozes = snoozedSlots.filter { $0.psychDay == psychDay && $0.resolvedAt == nil }

        let current = computeCurrentHabitSlots(
            habits: habits,
            todaysSnoozes: todaysSnoozes,
            now: now,
            psychDay: psychDay
        )
        let upcoming = computeUpcomingHabitSlots(
            habits: habits,
            now: now,
            psychDay: psychDay
        )
        let missed = computeMissedSlots(
            habits: habits,
            todaysSnoozes: todaysSnoozes,
            now: now,
            psychDay: psychDay
        )
        let contentState = makeFirstLiveActivityContentState(from: current)
        let staleDate = current.first.map { HabitScheduling.windowEndToday(for: $0.1) }
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

    // MARK: - Current

    private static func computeCurrentHabitSlots(
        habits: [Habit],
        todaysSnoozes: [SnoozedSlot],
        now: Date,
        psychDay: Date
    ) -> [(Habit, HabitSlot)] {
        print("computeCurrentHabitSlots called, psychDay: \(psychDay), now: \(now)")
        var result: [(Habit, HabitSlot)] = []

        for habit in habits {
            let todaysCheckIns = habit.checkIns.filter { $0.pyschDay == psychDay }
            let slots = habit.slots.sorted()
            let n = todaysCheckIns.count

            if n < slots.count {
                // Consider only slots from (n) onward (0-based), so n+1th is at index n
                let remainingSlots = slots.dropFirst(n)
                for slot in remainingSlots {
                    // If this specific slot was snoozed for today, skip it from "current".
                    if todaysSnoozes.contains(where: { $0.habit == habit && $0.slot == slot }) {
                        continue
                    }
                    let start = HabitScheduling.windowStartToday(for: slot)
                    let end = HabitScheduling.windowEndToday(for: slot)
                    if start <= now && now <= end {
                        result.append((habit, slot))
                        break  // Only first such slot
                    }
                }
            }
        }

        // Sort by fraction of window remaining: time left / full window length.
        result.sort { lhs, rhs in
            let leftSlot = lhs.1
            let rightSlot = rhs.1

            let leftStart = HabitScheduling.windowStartToday(for: leftSlot)
            let leftEnd = HabitScheduling.windowEndToday(for: leftSlot)
            let rightStart = HabitScheduling.windowStartToday(for: rightSlot)
            let rightEnd = HabitScheduling.windowEndToday(for: rightSlot)

            let leftDuration = max(leftEnd.timeIntervalSince(leftStart), 1)
            let rightDuration = max(rightEnd.timeIntervalSince(rightStart), 1)

            let leftRemaining = max(leftEnd.timeIntervalSince(now), 0)
            let rightRemaining = max(rightEnd.timeIntervalSince(now), 0)

            let leftRatio = leftRemaining / leftDuration
            let rightRatio = rightRemaining / rightDuration

            return leftRatio < rightRatio
        }

        return result
    }

    // MARK: - Upcoming

    private static func computeUpcomingHabitSlots(
        habits: [Habit],
        now: Date,
        psychDay: Date
    ) -> [(Habit, HabitSlot)] {
        var result: [(Habit, HabitSlot)] = []

        for habit in habits {
            let todaysCheckIns = habit.checkIns.filter { $0.pyschDay == psychDay }
            let slots = habit.slots.sorted()
            let n = todaysCheckIns.count
            if n < slots.count {
                // Consider only slots from (n) onward (0-based), so n+1th is at index n
                let remainingSlots = slots.dropFirst(n)
                for slot in remainingSlots {
                    let start = HabitScheduling.windowStartToday(for: slot)

                    if now <= start {
                        result.append((habit, slot))
                        break  // Only first such slot
                    }
                }
            }
        }

        result.sort { lhs, rhs in
            lhs.1 < rhs.1
        }
        return result
    }

    // MARK: - Missed

    private static func computeMissedSlots(
        habits: [Habit],
        todaysSnoozes: [SnoozedSlot],
        now: Date,
        psychDay: Date
    ) -> [MissedHabit] {
        var result: [MissedHabit] = []

        for habit in habits {
            let slots = habit.slots.sorted()
            guard !slots.isEmpty else { continue }

            // All check-ins for today (completions only).
            let todaysCheckIns = habit.checkIns
                .filter { $0.pyschDay == psychDay }

            let completedCount = todaysCheckIns.count

            var missedCount = 0
            var latestMissedSlot: HabitSlot?

            for (index, slot) in slots.enumerated() {
                let windowEnd = HabitScheduling.windowEndToday(for: slot)

                // Slots before completedCount are treated as done.
                if index < completedCount {
                    continue
                }

                let isSnoozed = todaysSnoozes.contains { $0.habit === habit && $0.slot === slot }

                if isSnoozed || windowEnd <= now {
                    missedCount += 1
                    latestMissedSlot = slot
                }
            }

            guard missedCount > 0 else { continue }

            // Use the latest missed slot (by time in the schedule) for "overdue" display.
            guard let displaySlot = latestMissedSlot else { continue }
            let latestEnd = HabitScheduling.windowEndToday(for: displaySlot)
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
                let start = HabitScheduling.windowStartToday(for: slot)
                let end = HabitScheduling.windowEndToday(for: slot)
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
        return NowAttributes.ContentState(
            habitTitle: habit.title,
            slotTimeText: slotTimeText(for: slot)
        )
    }

    private static func slotTimeText(for slot: HabitSlot) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let start = HabitScheduling.windowStartToday(for: slot)
        let end = HabitScheduling.windowEndToday(for: slot)
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }
}
