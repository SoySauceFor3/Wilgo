import BackgroundTasks
import SwiftData
import SwiftUI

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

        // Shared store URL inside the App Group container so the WidgetExtension
        // can read/write the same database.
        guard
            let groupContainer = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: WilgoConstants.appGroupID)
        else {
            fatalError("App Group container not found — check entitlements")
        }
        let storeURL =
            groupContainer
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store")

        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var checkInUndoManager = CheckInUndoManager()

    init() {
        // Backfill UUID ids on any records that pre-date the id fields (v3 schema).
        Self.backfillIDs()

        // Set up CatchUpReminderService.
        CatchUpReminder.registerBackgroundTask()
        CatchUpReminder.startHourlyRunWhileActive()

        // Register the Live Activity background sync task. Must come before any submit() call.
        NowLiveActivityManager.registerBackgroundTask()
    }

    private static func backfillIDs() {
        let context = sharedModelContainer.mainContext
        var needsSave = false

        if let commitments = try? context.fetch(FetchDescriptor<Commitment>()) {
            for item in commitments where item.id == UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)) {
                item.id = UUID()
                needsSave = true
            }
        }
        if let slots = try? context.fetch(FetchDescriptor<Slot>()) {
            for item in slots where item.id == nil {
                item.id = UUID()
                needsSave = true
            }
        }
        if let checkIns = try? context.fetch(FetchDescriptor<CheckIn>()) {
            for item in checkIns where item.id == nil {
                item.id = UUID()
                needsSave = true
            }
        }
        if let tokens = try? context.fetch(FetchDescriptor<PositivityToken>()) {
            for item in tokens where item.id == nil {
                item.id = UUID()
                needsSave = true
            }
        }

        if needsSave { try? context.save() }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(checkInUndoManager)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .modelContainer(Self.sharedModelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Watchdog: re-queue in case iOS skipped a BGTask fire.
                NowLiveActivityManager.workAndScheduleNextBGTask()  // Not really necessary because LiveActivity is only needed when scene != .active, just a safe net.
            } else {
                // the app is not active (inactive, or background), use this "last chance" to update and schedule the catch-up reminders.
                CatchUpReminder.updateAndScheduleNotificationAndBackgroundTask()
                // Sync the Live Activity immediately so it's accurate the moment it becomes visible,
                // then queue a BGAppRefreshTask to keep it updated while the app stays inactive.
                NowLiveActivityManager.workAndScheduleNextBGTask()
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
                let commitmentUUID = UUID(uuidString: commitmentIdStr)
            else { return }
            let descriptor = FetchDescriptor<Commitment>(predicate: #Predicate { $0.id == commitmentUUID })
            guard let commitment = (try? context.fetch(descriptor))?.first else { return }
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
