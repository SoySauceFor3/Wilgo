import SwiftData
import SwiftUI

struct ListPositivityTokenView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PositivityToken.createdAt, order: .reverse) private var tokens: [PositivityToken]
    @Query private var allCheckIns: [CheckIn]
    @Environment(PTBadgeState.self) private var badgeState
    @State private var isPresentingAddToken: Bool = false

    var body: some View {
        NavigationStack {
            List {
                summarySection
                if capacity > 0 {
                    Section {
                        Text("You have \(capacity) check-in\(capacity == 1 ? "" : "s") worth of positivity to capture. What's been going well?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                capacityRow
                ForEach(tokens) { token in
                    TokenRowView(token: token)
                }
                .onDelete(perform: deleteTokens)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Positivity Tokens")
            .onAppear { badgeState.markAsSeen() }
            .onChange(of: capacity) { badgeState.markAsSeen() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingAddToken = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(capacity == 0)
                }
            }
            .sheet(isPresented: $isPresentingAddToken) {
                AddPositivityTokenView()
            }
        }
    }

    // MARK: - Computed

    private var capacity: Int {
        PositivityTokenMinting.mintCapacity(tokenCount: tokens.count, checkInCount: allCheckIns.count)
    }

    // MARK: - Sections

    @ViewBuilder
    private var summarySection: some View {
        Section("Summary") {
            SummaryRow(label: "Created", value: tokens.count)
            SummaryRow(label: "Used", value: tokens.filter { $0.status == .used }.count)
            SummaryRow(label: "Active", value: tokens.filter { $0.status == .active }.count)
            SummaryRow(label: "Monthly budget remaining", value: monthlyBudgetRemaining())
        }
    }

    @ViewBuilder
    private var capacityRow: some View {
        Section {
            if capacity > 0 {
                HStack {
                    Text("\(capacity) mint\(capacity == 1 ? "" : "s") available")
                        .font(.subheadline)
                    Spacer()
                    Button("Mint") { isPresentingAddToken = true }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            } else {
                Text("Create more check-ins to mint more PTs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    private func monthlyBudgetRemaining() -> Int {
        let cap = AfterPositivityTokenReportBuilder.positivityTokenMonthlyCap()
        let usedThisMonth = tokens.filter { token in
            token.status == .used &&
            Calendar.current.isDate(token.dayOfStatus ?? .distantPast, equalTo: .now, toGranularity: .month)
        }.count
        return max(0, cap - usedThisMonth)
    }

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
        case .used:
            guard let date = token.dayOfStatus else { return nil }
            return "Used on \(date.formatted(date: .abbreviated, time: .omitted))"
        case .expired:
            guard let date = token.dayOfStatus else { return nil }
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

// MARK: - Preview

private func makePreviewContainer() throws -> ModelContainer {
    let container = try ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, PositivityToken.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let ctx = container.mainContext

    let now = Date.now
    let calendar = Calendar.current

    func daysAgo(_ n: Int) -> Date {
        calendar.date(byAdding: .day, value: -n, to: now) ?? now
    }

    let samples: [(String, Date, PositivityToken.Status, Date?)] = [
        ("Completed a full week of workouts", daysAgo(1), .active, nil),
        ("Meditated every morning this week", daysAgo(4), .used, daysAgo(2)),
        ("Finished the book I started", daysAgo(10), .active, nil),
        ("Helped a friend move", daysAgo(15), .expired, daysAgo(5)),
        ("Drank 2L of water for 7 days straight", daysAgo(20), .used, daysAgo(12)),
        ("Journaled every night this week", daysAgo(30), .expired, daysAgo(20)),
    ]

    for (reason, createdAt, status, day) in samples {
        let token = PositivityToken(reason: reason, createdAt: createdAt)
        token.status = status
        token.dayOfStatus = day
        ctx.insert(token)
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
