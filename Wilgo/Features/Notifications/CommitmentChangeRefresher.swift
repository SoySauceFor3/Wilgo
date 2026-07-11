import WidgetKit

enum CommitmentChangeRefresher {
    /// Awaits every surface's update (the folder-wide scheduler contract: returning means the
    /// work is done). The await matters most for `LiveActivityIntent` callers — their `perform()`
    /// keeps the app process alive only until it returns. View callers may fire-and-forget with
    /// `Task { await refreshAll() }`.
    @MainActor
    static func refreshAll() async {
        await SlotStartNotificationScheduler.refresh()
        await CatchUpReminder.refresh()
        await CycleEndNotificationScheduler.refresh()
        await NowLiveActivityManager.workAndScheduleNextBGTask()
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
    }
}
