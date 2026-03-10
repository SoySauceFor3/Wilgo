import Foundation

enum HabitAndSlot {
    static func current(
        habits: [Habit],
        now: Date = HabitScheduling.now()
    ) -> [(Habit, [Slot])] {
        let currentHabitAndSlots = habits.compactMap { habit -> (Habit, [Slot])? in
            let stageStatus = habit.stageStatus(now: now)
            if stageStatus.category == .current {
                return (habit, stageStatus.nextUpSlots)
            }
            return nil
        }

        // sort currentHabitAndSlots by currentHabitAndSlots.nextUpSlots[0]'s fraction of remaining time
        return currentHabitAndSlots.sorted {
            $0.1[0].remainingFraction(at: now) < $1.1[0].remainingFraction(at: now)
        }
    }

    // For each habit that has NOT yet met today (psychological day)'s goal,
    // return the first slot that hasn't started yet.
    static func upcoming(
        habits: [Habit],
        after time: Date
    ) -> [(Habit, [Slot])] {
        let upcomingHabitAndSlots = habits.compactMap { habit -> (Habit, [Slot])? in
            let stageStatus = habit.stageStatus(now: time)
            if stageStatus.category == .future {
                return (habit, stageStatus.nextUpSlots)
            }
            return nil
        }

        // sort upcomingHabitAndSlots by upcomingHabitAndSlots.nextUpSlots[0]
        return upcomingHabitAndSlots.sorted {
            if $0.1[0].start == $1.1[0].start {
                return $0.1[0].end < $1.1[0].end
            } else {
                return $0.1[0].start < $1.1[0].start
            }
        }
    }

    static func catchUp(
        habits: [Habit],
        now: Date = HabitScheduling.now()
    ) -> [(Habit, [Slot])] {
        let catchUpHabitAndSlots = habits.compactMap { habit -> (Habit, [Slot])? in
            let stageStatus = habit.stageStatus(now: now)
            if stageStatus.category == .catchUp {
                return (habit, stageStatus.nextUpSlots)
            }
            return nil
        }

        return catchUpHabitAndSlots.sorted {
            // Calculate the fraction and use it to sort, higher fraction in front.
            // If fractions are equal to 1, then habit with larger goalCountPerDay comes first.

            func catchUpFraction(_ tuple: (Habit, [Slot])) -> Double {
                let (habit, nextUpSlots) = tuple
                let catchUpCount = max(
                    habit.goalCountPerDay
                        - habit.completedCount(for: HabitScheduling.psychDay(for: now))
                        - nextUpSlots.count, 0)
                guard habit.goalCountPerDay > 0 else { return 0 }
                return Double(catchUpCount) / Double(habit.goalCountPerDay)
            }

            let lhsFraction = catchUpFraction($0)
            let rhsFraction = catchUpFraction($1)

            if lhsFraction == rhsFraction {
                if lhsFraction == 1.0 {
                    // Larger goalCountPerDay first if both at max fraction.
                    return $0.0.goalCountPerDay > $1.0.goalCountPerDay
                } else {
                    // Tiebreaker: start of first slot
                    return $0.1[0].start < $1.1[0].start
                }
            } else {
                // Higher fraction comes first
                return lhsFraction > rhsFraction
            }
        }
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
