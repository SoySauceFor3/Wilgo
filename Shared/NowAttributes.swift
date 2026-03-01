//
//  NowAttributes.swift
//  Wilgo
//
//  Created by Xinya Yang on 3/1/26.
//

import ActivityKit

struct NowAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// First current habit's title (empty when no habit in window).
        var habitTitle: String
        /// Current slot time range, e.g. "9:00 AM – 11:00 AM".
        var slotTimeText: String

        /// Only start or update the Live Activity when this is true (habit + slot set).
        public var hasCurrentHabit: Bool {
            !habitTitle.isEmpty && !slotTimeText.isEmpty
        }
    }
}
