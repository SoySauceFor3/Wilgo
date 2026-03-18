//  The Stage — dynamic dashboard highlighting the in-window commitment with phase-based styling.
//  Schedule: N× daily; each slot has its own ideal window.
//

import SwiftData
import SwiftUI

struct StageView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(LiveActivityManager.self) private var liveActivityManager
    @Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]
    /// Observed only to force a re-render when check-ins are inserted/deleted,
    /// since @Query for Commitment does not re-fire on child relationship changes.
    @Query private var checkIns: [CheckIn]

    /// actually change the value of it will trigger a rerender.
    @State private var rewrite = false

    private var current: [CommitmentAndSlot.WithBehind] {
        CommitmentAndSlot.currentWithBehind(commitments: commitments, now: Date())
    }

    private var upcoming: [CommitmentAndSlot.WithBehind] {
        CommitmentAndSlot.upcomingWithBehind(commitments: commitments, after: Date())
    }

    private var catchUp: [CommitmentAndSlot.WithBehind] {
        CommitmentAndSlot.catchUpWithBehind(commitments: commitments, now: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if !current.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(current, id: \.commitment.id) { item in
                                CurrentCommitmentRow(
                                    commitment: item.commitment,
                                    slots: item.slots
                                )
                            }
                        }
                    }

                    if !catchUp.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Catch up")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(catchUp, id: \.commitment.id) { item in
                                CatchUpCommitmentRow(
                                    commitment: item.commitment,
                                    slots: item.slots
                                )
                            }
                        }
                    }

                    if !upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(upcoming, id: \.commitment.id) { item in
                                UpcomingCommitmentRow(
                                    commitment: item.commitment,
                                    slots: item.slots
                                )
                            }
                        }
                    }

                    if current.isEmpty && upcoming.isEmpty && catchUp.isEmpty {
                        EmptyStageCard()
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(
                CommitmentScheduling.psychDay(for: CommitmentScheduling.now()).formatted(
                    date: .abbreviated, time: .omitted)
            )
            .task(id: rewrite) {
                let nextTransitionDate = CommitmentAndSlot.nextTransitionDate(
                    commitments: commitments, now: Date())
                let delay = nextTransitionDate?.timeIntervalSince(Date()) ?? 60
                if delay > 0 {
                    try? await Task.sleep(until: .now + .seconds(delay), clock: .continuous)
                }
                rewrite.toggle()
            }
            .onAppear {
                rewrite.toggle()
            }
            .onChange(of: scenePhase) { _, phase in
                // When the app is brought back to the foreground, force a re-render.
                // Not very necessary, just a safety net.
                if phase == .active { rewrite.toggle() }
            }
            .onChange(
                of: liveActivityManager.makeFirstLiveActivityContentState(
                    from: current
                )
            ) {
                _, _ in
                liveActivityManager.sync()
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
            slots: [slot(23, 0, 23, 10)],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1),
            skipBudget: SkipBudget(cycle: Cycle.anchored(.monthly, at: .now), count: 5),
            proofOfWorkType: .manual,
        )
        let commitment2 = Commitment(
            title: "commitment 2",
            slots: [slot(23, 1, 23, 59)],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1),
            skipBudget: SkipBudget(cycle: Cycle.anchored(.weekly, at: .now), count: 3),
            proofOfWorkType: .manual,
        )
        let commitment3 = Commitment(
            title: "commitment 3",
            slots: [slot(23, 0, 23, 30)],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1),
            skipBudget: SkipBudget(cycle: Cycle.anchored(.weekly, at: .now), count: 2),
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
            slots: [slot],
            target: Target(cycle: Cycle.anchored(.daily, at: .now), count: 1),
            skipBudget: SkipBudget(cycle: Cycle.anchored(.monthly, at: .now), count: 5),
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
