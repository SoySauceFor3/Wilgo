//
//  NowAttributes.swift
//  Wilgo
//
//  Created by Xinya Yang on 3/1/26.
//

import ActivityKit
import Foundation

struct NowAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Title of the commitment this occurrence belongs to.
        var commitmentTitle: String
        /// Current slot time range, e.g. "9:00 AM – 11:00 AM".
        var slotTimeText: String

        /// UUID of the commitment — used by Live Activity buttons to deep-link back into the app.
        var commitmentId: UUID
        /// UUID of the slot.
        var slotId: UUID

        /// Concrete occurrence window. Drives the countdown timer / progress rendering and,
        /// together with `slotId`, gives each card its per-occurrence identity for reconciling.
        var windowStart: Date
        var windowEnd: Date

        /// Deterministic per-(slot, psych-day) encouragement. Nil if none set.
        var encouragementText: String?

        /// Cycle progress at the time this content was built: check-ins done in the occurrence's
        /// cycle / target count. Both nil when the target is disabled. Safe to freeze: counts only
        /// change through the app process (check-in / undo paths), and every such path triggers a
        /// reconcile, so a visible card's count can never silently go stale.
        var checkInCount: Int?
        var targetCount: Int?
    }
}

extension NowAttributes.ContentState {
    /// Chronological order of the cards' occurrence windows — earlier start first, ties broken
    /// by earlier end (the same `(start, end)` ordering as `SlotOccurrence`'s `Comparable`).
    /// Under `max(by:)` this picks the farthest window: latest start, then latest end — i.e.
    /// the least urgent card, matching the deadline-based `relevanceScore` semantics.
    func windowPrecedes(_ other: Self) -> Bool {
        if windowStart != other.windowStart { return windowStart < other.windowStart }
        return windowEnd < other.windowEnd
    }
}
