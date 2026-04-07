//
//  NowAttributes.swift
//  Wilgo
//
//  Created by Xinya Yang on 3/1/26.
//

import ActivityKit
import Foundation

struct NowAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Primary (first) current commitment's title (empty when no commitment in window).
        var commitmentTitle: String
        /// Current slot time range, e.g. "9:00 AM – 11:00 AM".
        var slotTimeText: String

        /// UUID of the commitment — used by Live Activity buttons to deep-link back into the app.
        var commitmentId: UUID
        /// UUID of the slot.
        var slotId: UUID

        /// Non-primary current commitments. Empty when there is at most one commitment in the
        /// current window. Does not affect ``hasCurrentCommitment``.
        var secondaryTitles: [String]

        /// Random encouragement sentence for the primary commitment. Nil if none set.
        var encouragementText: String?

        /// Only start or update the Live Activity when this is true (primary commitment + slot set).
        public var hasCurrentCommitment: Bool {
            !commitmentTitle.isEmpty && !slotTimeText.isEmpty
        }
    }
}
