import SwiftData
import SwiftUI

struct ListPositivityTokenView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PositivityToken.createdAt, order: .reverse) private var tokens: [PositivityToken]
    @State private var isPresentingAddToken: Bool = false
    @State private var sponsoringCheckIn: CheckIn?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            NavigationStack {
                List {
                    if let checkIn = sponsoringCheckIn,
                        let secondsLeft = PositivityTokenMinting.secondsRemainingInMintWindow(
                            for: checkIn,
                            now: timeline.date
                        )
                    {
                        Section {
                            MintWindowBanner(
                                secondsLeft: secondsLeft,
                                onAdd: { isPresentingAddToken = true }
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }

                    ForEach(tokens) { token in
                        TokenRowView(token: token)
                    }
                    .onDelete(perform: deleteTokens)
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Positivity Tokens")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isPresentingAddToken = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(sponsoringCheckIn == nil)
                    }
                }
                .sheet(isPresented: $isPresentingAddToken) {
                    if sponsoringCheckIn != nil {
                        AddPositivityTokenView(sponsoringCheckIn: sponsoringCheckIn!)
                    }
                }
                .task {
                    await maintainSponsoringCheckInEligibility()
                }
                .onChange(of: tokens.count) { _, _ in
                    Task { await refreshSponsoringCheckIn() }
                }
            }
        }
    }

    private func maintainSponsoringCheckInEligibility() async {
        while !Task.isCancelled {
            guard !isPresentingAddToken else {
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            await refreshSponsoringCheckIn()
            try? await Task.sleep(for: .seconds(30))
        }
    }

    private func refreshSponsoringCheckIn() async {
        let recent =
            (try? PositivityTokenMinting.fetchRecentCheckInsForMint(context: modelContext)) ?? []
        sponsoringCheckIn = PositivityTokenMinting.eligibleCheckIn(checkIns: recent, now: .now)
    }

    private func deleteTokens(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(tokens[index])
            }
        }
    }
}

private struct MintWindowBanner: View {
    let secondsLeft: TimeInterval
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Mint a Positivity Token")
                        .font(.subheadline.weight(.semibold))
                    Text(
                        "Unlocked by your latest check-in. \(timeLabel) to capture a reason you feel good."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Button(action: onAdd) {
                Text("Add now")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityElement(children: .combine)
    }

    private var timeLabel: String {
        let minutes = Int(ceil(secondsLeft / 60))
        if minutes <= 1 {
            return "About a minute"
        }
        if minutes < 60 {
            return "\(minutes) minutes"
        }
        let h = minutes / 60
        let m = minutes % 60
        if m == 0 {
            return "\(h) hour\(h == 1 ? "" : "s")"
        }
        return "\(h)h \(m)m"
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
            .modelContainer(try! makePreviewContainer())

    }
}
