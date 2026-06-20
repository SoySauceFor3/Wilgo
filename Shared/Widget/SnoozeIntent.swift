import AppIntents
import Foundation
import SwiftData
import WidgetKit

struct SnoozeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Snooze"

    @Parameter(title: "Slot ID")
    var slotId: String  // UUID isn't directly supported as an AppIntent parameter type.

    init() {
        self.slotId = ""
    }

    init(slotId: UUID) {
        self.slotId = slotId.uuidString
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
            guard let id = UUID(uuidString: slotId) else {
                return .result()
            }

            // Write through the app's shared mainContext so the post-write refresh — which also reads
            // mainContext — sees the new snooze immediately, with no cross-container merge lag.
            let context = WilgoApp.sharedModelContainer.mainContext
            let descriptor = FetchDescriptor<Slot>(predicate: #Predicate { $0.id == id })
            guard let slot = try context.fetch(descriptor).first else {
                return .result()
            }

            slot.snooze(at: Time.now(), in: context)
            try context.save()

            // Rebuild every notification surface (Live Activity included) from the single choke point,
            // so surfaces added later are picked up here automatically. Replaces the old Darwin
            // liveActivitySync ping, which was dropped whenever the app was suspended.
            CommitmentChangeRefresher.refreshAll()

            return .result()
        }
    #endif
}
