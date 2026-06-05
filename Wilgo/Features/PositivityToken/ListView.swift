import SwiftData
import SwiftUI

struct ListPositivityTokenView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PositivityToken.createdAt, order: .reverse) private var tokens: [PositivityToken]
    @Environment(PTBadgeState.self) private var badgeState
    @State private var isPresentingAddToken: Bool = false

    var body: some View {
        NavigationStack {
            List {
                summarySection
                ForEach(tokens) { token in
                    TokenRowView(token: token)
                }
                .onDelete(perform: deleteTokens)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Positivity Tokens")
            .onAppear { badgeState.markAsSeen() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddToken = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAddToken) {
                AddPositivityTokenView()
            }
        }
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section("Summary") {
            SummaryRow(label: "Total wins", value: tokens.count)
            SummaryRow(label: "Free", value: tokens.count(where: { $0.consumedByCycleRecord == nil }))
            SummaryRow(label: "Used in FCR", value: tokens.count(where: { $0.consumedByCycleRecord != nil }))
        }
    }

    // MARK: - Helpers

    private func deleteTokens(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(tokens[index])
            }
        }
    }
}

// MARK: - Supporting Views

private struct SummaryRow: View {
    let label: String
    let value: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .foregroundStyle(.secondary)
        }
    }
}

private struct TokenRowView: View {
    let token: PositivityToken

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(token.reason)
                .font(.body)
            Text(token.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Preview

private func makePreviewContainer() throws -> ModelContainer {
    let container = try ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, PositivityToken.self, CycleRecord.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    let now = Date.now
    let calendar = Calendar.current
    func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now) ?? now
    }

    let reasons = [
        ("Completed a full week of workouts", daysAgo(1)),
        ("Meditated every morning this week", daysAgo(4)),
        ("Finished the book I started", daysAgo(10)),
        ("Drank 2L of water for 7 days straight", daysAgo(20)),
    ]

    for (reason, createdAt) in reasons {
        ctx.insert(PositivityToken(reason: reason, createdAt: createdAt))
    }

    return container
}

struct ListPositivityTokenView_Previews: PreviewProvider {
    static var previews: some View {
        ListPositivityTokenView()
            .environment(PTBadgeState())
            .modelContainer(try! makePreviewContainer())
    }
}
