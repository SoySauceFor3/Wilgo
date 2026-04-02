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
            Commitment.self,
            Slot.self,
            CheckIn.self,
            PositivityToken.self,
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
    @StateObject private var checkInUndoManager = CheckInUndoManager()

    init() {
        // BGTask handler registration MUST come first — before any submit() call and
        // before any other code that could race with a pending task being dispatched.
        // BGTaskScheduler crashes if an identifier listed in BGTaskSchedulerPermittedIdentifiers
        // has no registered handler at the moment the system tries to dispatch it.
        DayStartReport.registerBackgroundTask()

        // Bootstrap: queue the day-start report wakeup at the user's preferred day-start hour.
        // After it fires once, handleBackgroundTask re-schedules it each day automatically.
        DayStartReport.scheduleBackgroundTask()

        // Set up CatchUpReminderService.
        CatchUpReminder.registerBackgroundTask()
        CatchUpReminder.startHourlyRunWhileActive()

        liveActivityManager = LiveActivityManager(
            modelContext: Self.sharedModelContainer.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(liveActivityManager)
                .environmentObject(checkInUndoManager)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(Self.sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                liveActivityManager.sync()
                // Watchdog: re-queue in case iOS skipped a BGTask fire.
                DayStartReport.scheduleBackgroundTask()
            } else {
                // the app is not active (inactive, or background), use this "last chance" to update and schedule the catch-up reminders.
                CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
            }
        }
    }

    // MARK: - Deep link handling

    /// Handles `wilgo://done?commitmentId=...` deep links produced by the Live Activity's Done button.
    @MainActor
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
                let commitmentIdStr = queryValue("commitmentId"),
                let commitmentId = PersistentIdentifier.decode(from: commitmentIdStr)
            else { return }
            let commitments = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
            guard
                let commitment = commitments.first(where: { $0.persistentModelID == commitmentId })
            else {
                return
            }
            let checkIn = CheckIn(commitment: commitment)
            context.insert(checkIn)
            commitment.checkIns.append(checkIn)  // keep inverse in sync immediately, as inverse relationship propogation takes time.
            checkInUndoManager.enqueue(
                checkIn: checkIn, title: "A check-in made for \(commitment.title)"
            ) {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    if let token = checkIn.positivityToken {
                        context.delete(token)
                    }
                    context.delete(checkIn)
                }
            }
            liveActivityManager.sync()

        default:
            break
        }
    }
}

private struct AppRootView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            MainTabView()
                .modifier(FinishedCycleReportModifier())

            CheckInUndoBannerOverlay()
        }
    }
}
