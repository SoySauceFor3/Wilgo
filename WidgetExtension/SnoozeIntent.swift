import AppIntents
import SwiftData
import WidgetKit

struct SnoozeIntent: AppIntent {
    static var title: LocalizedStringResource = "Snooze"

    @Parameter(title: "Slot ID")
    var slotId: String  // UUID isn't directly supported as an AppIntent parameter type.

    init() { self.slotId = "" }

    init(slotId: UUID) {
        self.slotId = slotId.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: slotId) else {
            return .result()
        }

        guard
            let groupContainer = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: WilgoConstants.appGroupID)
        else {
            return .result()
        }
        let storeURL =
            groupContainer
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store")

        let schema = Schema([
            Commitment.self, Slot.self, CheckIn.self, PositivityToken.self, SlotSnooze.self,
        ])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Slot>(predicate: #Predicate { $0.id == id })
        let slots = try context.fetch(descriptor)
        guard let slot = slots.first else {
            return .result()
        }

        SlotSnooze.create(slot: slot, at: Time.now(), in: context)
        try context.save()

        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)

        return .result()
    }
}
