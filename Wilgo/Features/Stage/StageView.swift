//  The Stage — dynamic dashboard highlighting the in-window commitment with phase-based styling.
//  Schedule: N× daily; each slot has its own ideal window.
//

import SwiftData
import SwiftUI

struct StageView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]
    /// Observed only to force a refresh when check-ins are inserted/deleted,
    /// since @Query for Commitment does not re-fire on child relationship changes.
    @Query private var checkIns: [CheckIn]
    /// Same reason — snoozing a slot must re-evaluate stage status.
    @Query private var slotSnoozes: [SlotSnooze]

    @State private var viewModel = StageViewModel()
    @State private var commitmentForDetail: Commitment?
    @State private var commitmentForEdit: Commitment?

    private var todayTitle: String {
        let today = Time.startOfDay(for: Time.now())
        let date = today.formatted(
            date: .abbreviated, time: .omitted)

        // Get the weekday as a string, e.g., "Monday"
        let weekday = today.formatted(.dateTime.weekday())
        return "\(date) (\(weekday))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !viewModel.current.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(viewModel.current, id: \.commitment.id) { item in
                                CurrentCommitmentRow(
                                    commitment: item.commitment,
                                    slots: item.slots,
                                    behindCount: item.behindCount
                                ) { commitmentForDetail = item.commitment }
                            }
                        }
                    }

                    if !viewModel.catchUp.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Catch up")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(viewModel.catchUp, id: \.commitment.id) { item in
                                CatchUpCommitmentRow(
                                    commitment: item.commitment,
                                    slots: item.slots,
                                    behindCount: item.behindCount
                                ) { commitmentForDetail = item.commitment }
                            }
                        }
                    }

                    if !viewModel.upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(viewModel.upcoming, id: \.commitment.id) { item in
                                UpcomingCommitmentRow(
                                    commitment: item.commitment,
                                    slots: item.slots,
                                    behindCount: item.behindCount
                                ) { commitmentForDetail = item.commitment }
                            }
                        }
                    }

                    if viewModel.current.isEmpty && viewModel.upcoming.isEmpty
                        && viewModel.catchUp.isEmpty
                    {
                        EmptyStageCard()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(
                todayTitle
            )
            // Fire immediately on first appearance and on every commitment change.
            .onChange(of: commitments, initial: true) {
                viewModel.refresh(commitments: commitments)
            }
            // Check-ins don't surface through the commitments query; watch separately.
            .onChange(of: checkIns) {
                viewModel.refresh(commitments: commitments)
            }
            // SlotSnoozes don't surface through the commitments query; watch separately.
            .onChange(of: slotSnoozes) {
                viewModel.refresh(commitments: commitments)
            }
            // Slots edited in EditCommitmentView don't surface through the commitments query either.
            .onChange(of: commitmentForEdit) { _, newValue in
                if newValue == nil { viewModel.refresh(commitments: commitments) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { viewModel.refresh(commitments: commitments) }
            }
            .sheet(item: $commitmentForDetail) { commitment in
                CommitmentDetailView(commitment: commitment) {
                    commitmentForDetail = nil
                    commitmentForEdit = commitment
                }
                .presentationDetents([.fraction(0.65), .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $commitmentForEdit) { commitment in
                NavigationStack {
                    EditCommitmentView(commitment: commitment)
                }
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyStageCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Nothing on stage right now")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Add commitments and set their ideal times to see them here.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - Previews

private enum StagePreviewFactory {
    static var multipleCommitments: some View {
        let container = try! ModelContainer(
            for: Commitment.self, Slot.self, CheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let calendar = Calendar.current

        func slot(_ h1: Int, _ m1: Int, _ h2: Int, _ m2: Int) -> Slot {
            Slot(
                start: calendar.date(from: DateComponents(hour: h1, minute: m1)) ?? Date(),
                end: calendar.date(from: DateComponents(hour: h2, minute: m2)) ?? Date()
            )
        }

        let commitment1 = Commitment(
            title: "commitment 1",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot(23, 0, 23, 10)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        )
        let commitment2 = Commitment(
            title: "commitment 2",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot(23, 1, 23, 59)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        )
        let commitment3 = Commitment(
            title: "commitment 3",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot(23, 0, 23, 30)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        )
        commitment1.slots.forEach {
            $0.commitment = commitment1
            ctx.insert($0)
        }
        commitment2.slots.forEach {
            $0.commitment = commitment2
            ctx.insert($0)
        }
        commitment3.slots.forEach {
            $0.commitment = commitment3
            ctx.insert($0)
        }
        ctx.insert(commitment1)
        ctx.insert(commitment2)
        ctx.insert(commitment3)

        return StageView()
            .modelContainer(container)
    }

    static var singleCommitment: some View {
        let container = try! ModelContainer(
            for: Commitment.self, Slot.self, CheckIn.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let calendar = Calendar.current
        let slot = Slot(
            start: calendar.date(from: DateComponents(hour: 0, minute: 0)) ?? Date(),
            end: calendar.date(from: DateComponents(hour: 0, minute: 10)) ?? Date()
        )
        let commitment = Commitment(
            title: "Workout",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        )
        slot.commitment = commitment
        ctx.insert(slot)
        ctx.insert(commitment)

        return StageView()
            .modelContainer(container)
    }

    static var empty: some View {
        StageView()
            .modelContainer(
                try! ModelContainer(
                    for: Commitment.self, Slot.self, CheckIn.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            )
    }
}

#Preview("Stage with multiple commitments") {
    StagePreviewFactory.multipleCommitments
}

#Preview("Stage with 1 commitment") {
    StagePreviewFactory.singleCommitment
}

#Preview("Stage empty") {
    StagePreviewFactory.empty
}
