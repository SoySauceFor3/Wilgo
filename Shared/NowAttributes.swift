//
//  NowAttributes.swift
//  Wilgo
//
//  Created by Xinya Yang on 3/1/26.
//

import ActivityKit

struct NowAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Primary (first) current commitment's title (empty when no commitment in window).
        var commitmentTitle: String
        /// Current slot time range, e.g. "9:00 AM – 11:00 AM".
        var slotTimeText: String

        /// Base64-encoded JSON of the commitment's `PersistentIdentifier` — used by
        /// Live Activity buttons to deep-link back into the app.
        var commitmentId: String
        /// Base64-encoded JSON of the slot's `PersistentIdentifier`.
        var slotId: String

        /// Non-primary current commitments. Empty when there is at most one commitment in the
        /// current window. Does not affect ``hasCurrentCommitment``.
        var secondaryTitles: [String]

        /// Only start or update the Live Activity when this is true (primary commitment + slot set).
        public var hasCurrentCommitment: Bool {
            !commitmentTitle.isEmpty && !slotTimeText.isEmpty
        }
    }
}
