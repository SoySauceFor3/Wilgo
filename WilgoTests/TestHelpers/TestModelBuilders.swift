import Foundation
import SwiftData
@testable import Wilgo

// MARK: - Shared model builders

/// Builds a `Commitment` (and inserts it, plus its slots, into `ctx`) covering the common
/// shape shared across the suite. Genuine outliers — check-in loops, encouragements,
/// whole-day sentinels — keep their own bespoke helpers rather than widening this one.
///
/// `referencePsychDay` defaults to a fixed test date so cycle math is deterministic; call
/// sites that specifically depend on "now" pass `referencePsychDay: Date()`.
@MainActor func makeCommitment(
    in ctx: ModelContext,
    title: String = "Test",
    slots: [Slot] = [],
    targetCount: Int = 1,
    targetMode: TargetMode = .on,
    cycleKind: CycleKind = .daily,
    continueAfterGoalMet: Bool = false,
    referencePsychDay: Date = testDate(year: 2026, month: 1, day: 1)
) -> Commitment {
    let commitment = Commitment(
        title: title,
        cycle: Cycle(kind: cycleKind, referencePsychDay: referencePsychDay),
        slots: slots,
        target: Target(count: targetCount, mode: targetMode),
        continueRemindersAfterGoalMet: continueAfterGoalMet
    )
    ctx.insert(commitment)
    for slot in slots {
        ctx.insert(slot)
    }
    return commitment
}

/// A slot spanning `startHour..<endHour` on the y2000 time-of-day convention.
@MainActor func makeSlot(startHour: Int, endHour: Int, maxCheckIns: Int? = nil) -> Slot {
    Slot(start: timeOfDay(hour: startHour), end: timeOfDay(hour: endHour), maxCheckIns: maxCheckIns)
}
