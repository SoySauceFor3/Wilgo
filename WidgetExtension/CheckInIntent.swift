import AppIntents
import SwiftData
import WidgetKit

struct CheckInIntent: AppIntent {
    static var title: LocalizedStringResource = "Check In"

    @Parameter(title: "Commitment ID")
    var commitmentId: String  // UUID isn't directly supported as an AppIntent parameter type.

    init() { self.commitmentId = "" }

    init(commitmentId: UUID) {
        self.commitmentId = commitmentId.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: commitmentId) else {
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

        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, PositivityToken.self])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Commitment>(predicate: #Predicate { $0.id == id })
        let commitments = try context.fetch(descriptor)
        guard let commitment = commitments.first else {
            return .result()
        }

        let checkIn = CheckIn(commitment: commitment)
        context.insert(checkIn)
        commitment.checkIns.append(checkIn)
        try context.save()

        WidgetCenter.shared.reloadTimelines(ofKind: WilgoConstants.currentCommitmentWidgetKind)

        return .result()
    }
}
