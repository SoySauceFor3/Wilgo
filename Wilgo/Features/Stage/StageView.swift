//  The Stage — dynamic dashboard highlighting the in-window commitment with phase-based styling.
//  Schedule: N× daily; each slot has its own ideal window.
//

import SwiftData
import SwiftUI

struct StageView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(
        filter: Commitment.activePredicate,
        sort: \Commitment.createdAt, order: .forward)
    private var commitments: [Commitment]
    /// Observed only to force a `body` recompute when check-ins are inserted/deleted,
    /// since @Query for Commitment does not re-fire on child relationship changes.
    @Query private var checkIns: [CheckIn]
    /// Same reason — snoozing a slot must re-evaluate stage status.
    @Query private var slotSnoozes: [SlotSnooze]

    /// Bumped by the time-boundary `.task` to force a recompute when a slot window opens/closes
    /// with no model change. Also nudged when returning to the foreground.
    @State private var timeTick = 0
    @State private var commitmentForDetail: Commitment?
    @State private var commitmentForEdit: Commitment?

    /// The three Stage lists, recomputed on every `body` evaluation. Cheap: a few date comparisons
    /// and sorts over the active-commitment set. `@Query` (commitments/checkIns/slotSnoozes) and
    /// `timeTick` are all read here, so any of them changing re-renders and re-buckets.
    private var buckets:
        (
            current: [CommitmentCharacteristics],
            upcoming: [CommitmentCharacteristics],
            catchUp: [CommitmentCharacteristics]
        )
    {
        _ = timeTick  // establish dependency so time-boundary bumps recompute
        _ = checkIns  // establish dependency: child-relationship changes must re-bucket
        _ = slotSnoozes
        return StageCharacterization.stageBuckets(commitments: commitments)
    }

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
                    if !buckets.current.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(buckets.current, id: \.commitment.id) { item in
                                CurrentCommitmentRow(characteristics: item) {
                                    commitmentForDetail = item.commitment
                                }
                            }
                        }
                    }

                    if !buckets.catchUp.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Catch up")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(buckets.catchUp, id: \.commitment.id) { item in
                                CatchUpCommitmentRow(characteristics: item) {
                                    commitmentForDetail = item.commitment
                                }
                            }
                        }
                    }

                    if !buckets.upcoming.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Upcoming")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            ForEach(buckets.upcoming, id: \.commitment.id) { item in
                                UpcomingCommitmentRow(characteristics: item) {
                                    commitmentForDetail = item.commitment
                                }
                            }
                        }
                    }

                    if buckets.current.isEmpty, buckets.upcoming.isEmpty,
                        buckets.catchUp.isEmpty
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
            // Time-boundary refresh: sleep until the next slot-window transition (or psychDay
            // boundary) and bump `timeTick` so `buckets` recomputes even with no model change.
            // Restarts whenever `commitments` change so the sleep target stays current. SwiftUI
            // cancels this task on disappear — no manual lifetime management needed.
            .task(id: commitments) {
                while !Task.isCancelled {
                    let now = Date()
                    guard
                        let next = StageCharacterization.nextTransitionDate(
                            commitments: commitments, now: now)
                    else { break }
                    let delay = next.timeIntervalSince(now)
                    if delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }
                    if Task.isCancelled { break }
                    timeTick &+= 1
                }
            }
            // Returning to the foreground can cross a boundary while the task was suspended; nudge.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { timeTick &+= 1 }
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
            cycle: Cycle.makeDefault(.daily),
            slots: [slot(23, 0, 23, 10)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        )
        let commitment2 = Commitment(
            title: "commitment 2",
            cycle: Cycle.makeDefault(.daily),
            slots: [slot(23, 1, 23, 59)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        )
        let commitment3 = Commitment(
            title: "commitment 3",
            cycle: Cycle.makeDefault(.daily),
            slots: [slot(23, 0, 23, 30)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        )
        for slot in commitment1.slots {
            slot.commitment = commitment1
            ctx.insert(slot)
        }
        for slot in commitment2.slots {
            slot.commitment = commitment2
            ctx.insert(slot)
        }
        for slot in commitment3.slots {
            slot.commitment = commitment3
            ctx.insert(slot)
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
            cycle: Cycle.makeDefault(.daily),
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
