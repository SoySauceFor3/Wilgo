import SwiftData
import SwiftUI
import UIKit

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
            Tag.self,
            CycleRecord.self,
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

    /// Process-wide owner of the automatic-refresh coordinator, mirroring `sharedModelContainer`.
    /// A `static let` guarantees exactly one instance that lives for the whole process, so it's
    /// immune to SwiftUI re-creating the `App` struct (which can call `init()` more than once).
    /// `start()` is idempotent, so a repeated `init()` never arms a second timer or observer.
    private static let refreshCoordinator = RefreshCoordinator()

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var checkInUndoManager = CheckInUndoManager()
    @State private var deepLinkedCommitment: Commitment?
    @State private var ptBadgeState = PTBadgeState()

    init() {
        // Fire refreshAll() automatically at meaningful time boundaries (next slot edge / cycle
        // boundary) and on every DB write. Replaces CatchUp's old fixed-hourly in-app timer.
        // Idempotent, so it's safe even if SwiftUI runs init() more than once.
        Self.refreshCoordinator.start()

        // Set up CatchUpReminderService.
        CatchUpReminder.registerBackgroundTask()

        // Register the Live Activity background sync task. Must come before any submit() call.
        NowLiveActivityManager.registerBackgroundTask()

        // Register the per-slot-start notification scheduler. Must come before any submit() call.
        SlotStartNotificationScheduler.registerBackgroundTask()

        // One-time wipe of legacy CycleRecord rows whose removed `outcome` raw values
        // ("letGo"/"other") can crash SwiftData on fetch. Runs here, before AppRootView /
        // FinishedCycleReportModifier can fetch any CycleRecord. init() runs on the main
        // actor, and `mainContext` is the same main-actor context those views fetch from.
        MainActor.assumeIsolated {
            LegacyCycleRecordWipe.runIfNeeded(context: Self.sharedModelContainer.mainContext)
        }
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
        .onChange(of: scenePhase) { _, _ in
            // Every phase change refreshes every notification surface: on activation this is the
            // watchdog for BG wakes iOS skipped; on leaving .active it's the last chance to update
            // before suspension. The assertion buys ~30s of protected runtime so the refresh isn't
            // cut off mid-flight when backgrounding (and is harmless while active). It is released
            // on completion or by its expiration handler, whichever comes first.
            let assertion = BackgroundAssertion()
            assertion.begin()
            Task {
                await CommitmentChangeRefresher.refreshAll()
                assertion.end()
            }
        }
    }

    // MARK: - Deep link handling

    /// Handles deep links for opening commitments and other deeplink actions.
    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "wilgo" else { return }
        let context = ModelContext.wilgoMain
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

/// Ends a UIKit background-time assertion exactly once — from work completion or the
/// expiration handler, whichever comes first. A leaked assertion gets the app killed.
@MainActor
private final class BackgroundAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    func begin() {
        id = UIApplication.shared.beginBackgroundTask { [weak self] in
            // UIKit documents the expiration handler runs on the main thread.
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
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
