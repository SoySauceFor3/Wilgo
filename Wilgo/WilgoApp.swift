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
        DayStartReportService.registerBackgroundTask()

        // Bootstrap: queue the day-start report wakeup at the user's preferred day-start hour.
        // After it fires once, handleBackgroundTask re-schedules it each day automatically.
        DayStartReportService.scheduleBackgroundTask()

        // Set up CatchUpReminderService.
        CatchUpReminderService.registerBackgroundTask()
        CatchUpReminderService.startHourlyRunWhileActive()

        liveActivityManager = LiveActivityManager(
            modelContext: Self.sharedModelContainer.mainContext)
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
            } else {
                // the app is not active (inactive, or background), use this "last chance" to update and schedule the catch-up reminders.
                CatchUpReminderService.updateAndScheduleNotificationAndBackgroundTask()
            }
        }
    }

    // MARK: - Deep link handling

    /// Handles `wilgo://done?habitId=...` deep links produced by the Live Activity's Done button.
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

        default:
            break
        }
    }
}
