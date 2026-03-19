import SwiftData
import SwiftUI

struct ListPositivityTokenView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PositivityToken.createdAt, order: .reverse) private var tokens: [PositivityToken]

    var body: some View {
        NavigationStack {
            List {
                ForEach(tokens) { token in
                    TokenRowView(token: token)
                }
                .onDelete(perform: deleteTokens)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Positivity Tokens")
            // .toolbar {
            //     // ToolbarItem(placement: .topBarTrailing) {
            //     //     EditButton()
            //     // }
            // }
        }
    }

    private func deleteTokens(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(tokens[index])
            }
        }
    }
}

private struct TokenRowView: View {
    let token: PositivityToken

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(token.reason)
                    .font(.body)
                Spacer()
                StatusBadge(status: token.status)
            }
            Text(token.createdAt.formatted(date: .abbreviated, time: .omitted))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let detail = statusDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusDetail: String? {
        switch token.status {
        case .active:
            return nil
        case .used(let date):
            return "Used on \(date.formatted(date: .abbreviated, time: .omitted))"
        case .expired(let date):
            return "Expired on \(date.formatted(date: .abbreviated, time: .omitted))"
        }
    }
}

private struct StatusBadge: View {
    let status: PositivityToken.Status

    var body: some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var label: String {
        switch status {
        case .active: "Available"
        case .used: "Used"
        case .expired: "Expired"
        }
    }

    private var color: Color {
        switch status {
        case .active: .green
        case .used: .blue
        case .expired: .secondary
        }
    }
}

private func makePreviewContainer() throws -> ModelContainer {
    let container = try ModelContainer(
        for: PositivityToken.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    let now = Date.now
    let calendar = Calendar.current

    func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now) ?? now
    }

    let samples: [(String, Date, PositivityToken.Status)] = [
        ("Completed a full week of workouts", daysAgo(1), .active),
        ("Meditated every morning this week", daysAgo(4), .used(daysAgo(2))),
        ("Finished the book I started", daysAgo(10), .active),
        ("Helped a friend move", daysAgo(15), .expired(daysAgo(5))),
        ("Drank 2L of water for 7 days straight", daysAgo(20), .used(daysAgo(12))),
        ("Journaled every night this week", daysAgo(30), .expired(daysAgo(20))),
    ]

    for (reason, createdAt, status) in samples {
        let token = PositivityToken(reason: reason, createdAt: createdAt)
        token.status = status
        ctx.insert(token)
    }

    return container
}

struct ListPositivityTokenView_Previews: PreviewProvider {
    static var previews: some View {
        ListPositivityTokenView()
            .modelContainer(try! makePreviewContainer())

    }
}
