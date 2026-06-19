import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct CheckInIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Check In"

    @Parameter(title: "Commitment ID")
    var commitmentId: String  // UUID isn't directly supported as an AppIntent parameter type.

    @Parameter(title: "Source")
    var sourceRaw: String

    init() {
        self.commitmentId = ""
        self.sourceRaw = CheckInSource.widget.rawValue
    }

    init(commitmentId: UUID, source: CheckInSource) {
        self.commitmentId = commitmentId.uuidString
        self.sourceRaw = source.rawValue
    }

    // As a LiveActivityIntent, perform() always runs in the APP process, never the widget
    // extension — so it uses the app's shared ModelContainer and the app-only schedulers directly.
    // The file still compiles into the WidgetExtension target (the widget needs the type for its
    // Button(intent:)), but perform() is never invoked there, so that build gets an empty body.
    #if WIDGET_EXTENSION
        func perform() async throws -> some IntentResult {
            .result()
        }
    #else
        @MainActor
        func perform() async throws -> some IntentResult {
            guard let id = UUID(uuidString: commitmentId) else {
                return .result()
            }

            // Write through the app's shared mainContext so the post-write refresh — which also reads
            // mainContext — sees the new check-in immediately, with no cross-container merge lag.
            let context = WilgoApp.sharedModelContainer.mainContext
            let descriptor = FetchDescriptor<Commitment>(predicate: #Predicate { $0.id == id })
            guard let commitment = try context.fetch(descriptor).first else {
                return .result()
            }

            let source = CheckInSource(rawValue: sourceRaw) ?? .widget
            CheckIn.insert(commitment: commitment, source: source, into: context)
            try context.save()

            // Rebuild every notification surface (Live Activity included) from the single choke point,
            // so surfaces added later are picked up here automatically. Replaces the old Darwin
            // liveActivitySync ping, which was dropped whenever the app was suspended.
            CommitmentChangeRefresher.refreshAll()

            return .result()
        }
    #endif
}
