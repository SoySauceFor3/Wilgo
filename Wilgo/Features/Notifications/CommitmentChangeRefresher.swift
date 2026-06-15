import WidgetKit

enum CommitmentChangeRefresher {
    @MainActor
    static func refreshAll() {
        SlotStartNotificationScheduler.refresh()
        CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
        CycleEndNotificationScheduler.refresh()
        NowLiveActivityManager.workAndScheduleNextBGTask()
        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)
    }
}
