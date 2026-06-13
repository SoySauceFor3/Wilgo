import SwiftData
import SwiftUI

struct ListPositivityTokenView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PositivityToken.createdAt, order: .reverse) private var tokens: [PositivityToken]
    @Environment(PTBadgeState.self) private var badgeState
    @State private var isPresentingAddToken: Bool = false

    private var sections: [PositivityTokenGrouping.MonthSection] {
        PositivityTokenGrouping.sections(from: tokens)
    }

    var body: some View {
        NavigationStack {
            Group {
                if tokens.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(section.title) {
                                ForEach(section.tokens) { token in
                                    TokenRowView(token: token)
                                }
                                .onDelete { offsets in deleteTokens(in: section, offsets: offsets) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
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

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No wins yet", systemImage: "sparkles")
        } description: {
            Text("Tap + to record something good that happened — big or small.")
        }
    }

    // MARK: - Helpers

    private func deleteTokens(in section: PositivityTokenGrouping.MonthSection, offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(section.tokens[index])
            }
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
