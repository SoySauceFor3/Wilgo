//
//  WilgoApp.swift
//  Wilgo
//
//  Created by Xinya Yang on 2/24/26.
//

import BackgroundTasks
import SwiftData
import SwiftUI

// MARK: - PersistentIdentifier coding helpers

extension PersistentIdentifier {
    /// Encodes the identifier to a base64 JSON string suitable for URL query parameters.
    func encoded() -> String {
        (try? JSONEncoder().encode(self)).map { $0.base64EncodedString() } ?? ""
    }

    /// Decodes a base64 JSON string previously produced by `encoded()`.
    static func decode(from base64: String) -> PersistentIdentifier? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
    }
}

@main
struct WilgoApp: App {

    /// Static container so the BGTask handler closure can reach it without a global.
    /// Swift's lazy static initialiser is thread-safe; it's fine to access from the handler.
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Habit.self,
            Slot.self,
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
            forTaskWithIdentifier: DayStartReportService.backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                let habits =
                    (try? WilgoApp.sharedModelContainer.mainContext.fetch(FetchDescriptor<Habit>()))
                    ?? []
                DayStartReportService.handleBackgroundTask(for: habits)
                refreshTask.setTaskCompleted(success: true)
            }
        }

        liveActivityManager = LiveActivityManager(
            modelContext: Self.sharedModelContainer.mainContext)

        // Bootstrap: queue the day-start report wakeup at the user's preferred day-start hour.
        // After it fires once, handleBackgroundTask re-schedules it each day automatically.
        DayStartReportService.scheduleBackgroundTask()

        // migrateExistingHabitsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(liveActivityManager)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(Self.sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                liveActivityManager.sync()
                // Watchdog: re-queue in case iOS skipped a BGTask fire.
                DayStartReportService.scheduleBackgroundTask()
            }
        }
    }

    // MARK: - Deep link handling

    /// Handles `wilgo://done?habitId=...` and `wilgo://snooze?habitId=...&slotId=...`
    /// deep links produced by the Live Activity's Done / Snooze buttons.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "wilgo" else { return }
        let context = Self.sharedModelContainer.mainContext
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        func queryValue(_ name: String) -> String? {
            queryItems?.first(where: { $0.name == name })?.value
        }

        switch url.host {
        case "done":
            guard
                let habitIdStr = queryValue("habitId"),
                let habitId = PersistentIdentifier.decode(from: habitIdStr)
            else { return }
            let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            guard let habit = habits.first(where: { $0.persistentModelID == habitId }) else {
                return
            }
            let checkIn = HabitCheckIn(habit: habit)
            context.insert(checkIn)
            habit.checkIns.append(checkIn)  // keep inverse in sync immediately, as inverse relationship propogation takes time.
            liveActivityManager.sync()

        case "snooze":
            guard
                let habitIdStr = queryValue("habitId"),
                let slotIdStr = queryValue("slotId"),
                let habitId = PersistentIdentifier.decode(from: habitIdStr),
                let slotId = PersistentIdentifier.decode(from: slotIdStr)
            else { return }
            let habits = (try? context.fetch(FetchDescriptor<Habit>())) ?? []
            guard let habit = habits.first(where: { $0.persistentModelID == habitId }) else {
                return
            }
            let allSlots = (try? context.fetch(FetchDescriptor<Slot>())) ?? []
            guard let slot = allSlots.first(where: { $0.persistentModelID == slotId }) else {
                return
            }
            guard habit.skipCreditCount > 0 else { return }
            context.insert(SnoozedSlot(habit: habit, slot: slot))
            liveActivityManager.sync()

        default:
            break
        }
    }

    /// One-off data migration for introducing `goalCountPerDay` on `Habit`.
    ///
    /// For existing habits on disk that predate this field, `goalCountPerDay` will
    /// have the default `0`. For those, we backfill it to `max(1, slots.count)`
    /// so behaviour matches the previous implicit "times per day" semantics.
    private func migrateExistingHabitsIfNeeded() {
        let context = Self.sharedModelContainer.mainContext
        let descriptor = FetchDescriptor<Habit>()

        // Best-effort migration: failures shouldn't crash the app.
        guard let habits = try? context.fetch(descriptor) else { return }

        var didChange = false
        for habit in habits {
            let inferred = max(1, habit.slots.count)
            // Only update if we actually change the value, to avoid unnecessary writes.
            habit.goalCountPerDay = inferred
            didChange = true

        }

        if didChange, context.hasChanges {
            try? context.save()
        }
    }
}
