/// Shared copy builders for the notification schedulers.
enum NotificationText {
    /// "A · B · C · +2 more" — the folder-wide body format for multi-commitment notifications.
    static func joinedTitles(_ titles: [String], visibleCount: Int = 3) -> String {
        let primary = titles.prefix(visibleCount).joined(separator: " · ")
        return titles.count > visibleCount
            ? "\(primary) · +\(titles.count - visibleCount) more"
            : primary
    }
}
