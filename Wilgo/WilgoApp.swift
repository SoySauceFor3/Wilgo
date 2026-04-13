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
            SlotSnooze.self,
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
    @State private var deepLinkedCommitment: Commitment?
    @State private var ptBadgeState = PTBadgeState()

    init() {
        // Set up CatchUpReminderService.
        CatchUpReminder.registerBackgroundTask()
        CatchUpReminder.startHourlyRunWhileActive()

        // Register the Live Activity background sync task. Must come before any submit() call.
        NowLiveActivityManager.registerBackgroundTask()
        // Observe Darwin notifications posted by widget extension intents (CheckInIntent, SnoozeIntent)
        // so the Live Activity refreshes immediately when the user taps a button.
        NowLiveActivityManager.startObservingIntentNotifications()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(ptBadgeState)
                .environmentObject(checkInUndoManager)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .fullScreenCover(item: $deepLinkedCommitment) { commitment in
                    DeepLinkedDetailView(commitment: commitment)
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

    /// Handles deep links for opening commitments and other deeplink actions.
    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "wilgo" else { return }
        let context = Self.sharedModelContainer.mainContext
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems

        func queryValue(_ name: String) -> String? {
            queryItems?.first(where: { $0.name == name })?.value
        }

        switch url.host {
        case "commitment":
            guard
                let idStr = queryValue("id"),
                let commitmentUUID = UUID(uuidString: idStr)
            else { return }
            let descriptor = FetchDescriptor<Commitment>(
                predicate: #Predicate { $0.id == commitmentUUID })
            deepLinkedCommitment = (try? context.fetch(descriptor))?.first

        default:
            break
        }
    }
}

/// Wraps `CommitmentDetailView` inside a `fullScreenCover` with a working Edit sheet.
private struct DeepLinkedDetailView: View {
    let commitment: Commitment
    @State private var isPresentingEdit = false

    var body: some View {
        NavigationStack {
            CommitmentDetailView(commitment: commitment, onEdit: { isPresentingEdit = true })
        }
        .sheet(isPresented: $isPresentingEdit) {
            EditCommitmentView(commitment: commitment)
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
