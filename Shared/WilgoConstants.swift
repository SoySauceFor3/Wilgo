import Foundation

enum WilgoConstants {
    /// Shared App Group identifier. Both the main app and WidgetExtension targets are members
    /// of this group, allowing them to share a SwiftData store and other sandbox resources.
    static let appGroupID = "group.xyz.soysaucefor3.wilgo"

    /// WidgetKit kind string for the Current Commitment widget.
    static let currentCommitmentWidgetKind = "CurrentCommitment"

    /// Darwin notification name posted by widget extension intents (CheckInIntent, SnoozeIntent)
    /// to signal the main app to refresh the Live Activity state immediately.
    static let liveActivitySyncNotification = "xyz.soysaucefor3.wilgo.liveActivitySync"
}
