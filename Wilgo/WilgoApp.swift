//
//  WilgoApp.swift
//  Wilgo
//
//  Created by Xinya Yang on 2/24/26.
//

import BackgroundTasks
import SwiftData
import SwiftUI

@main
struct WilgoApp: App {

    /// Static container so the BGTask handler closure can reach it without a global.
    /// Swift's lazy static initialiser is thread-safe; it's fine to access from the handler.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Habit.self,
            HabitSlot.self,
            HabitCheckIn.self,
            SnoozedSlot.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    let liveActivityManager: LiveActivityManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // BGTask handler registration MUST come first — before any submit() call and
        // before any other code that could race with a pending task being dispatched.
        // BGTaskScheduler crashes if an identifier listed in BGTaskSchedulerPermittedIdentifiers
        // has no registered handler at the moment the system tries to dispatch it.
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: MorningReportService.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                let habits = (try? WilgoApp.sharedModelContainer.mainContext.fetch(FetchDescriptor<Habit>())) ?? []
                MorningReportService.handleBackgroundTask(for: habits)
                refreshTask.setTaskCompleted(success: true)
            }
        }

        liveActivityManager = LiveActivityManager(modelContext: Self.sharedModelContainer.mainContext)

        // Bootstrap: queue the first 8 AM wakeup. After it fires once,
        // handleBackgroundTask re-schedules it each day automatically.
        MorningReportService.scheduleBackgroundTask()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(liveActivityManager)
        }
        .modelContainer(Self.sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                liveActivityManager.sync()
                // Watchdog: re-queue in case iOS skipped a BGTask fire.
                MorningReportService.scheduleBackgroundTask()
            }
        }
    }
}
