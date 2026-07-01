//  The Stage — dynamic dashboard highlighting the in-window commitment with phase-based styling.
//  Schedule: N× daily; each slot has its own ideal window.
//

import SwiftData
import SwiftUI

struct StageView: View {
    @Environment(\.scenePhase) private var scenePhase
    /// The active commitments. Bucketing traverses each commitment's `checkIns` and its slots'
    /// `snoozes` relationships, and the Observation framework tracks every `@Model` property a view
    /// reads during `body` — so inserting/deleting a `CheckIn` or `SlotSnooze` under one of these
    /// commitments re-runs `body` and re-buckets. That is why no separate `@Query` for those child
    /// types is needed. (Caveat: this holds only while bucketing keeps reading those relationships;
    /// a refactor that stops traversing them, or a flow that *reassigns* a child's parent, would not
    /// be covered — SwiftData's relationship-reassignment observation is unreliable.)
    @Query(
        filter: Commitment.activePredicate,
        sort: \Commitment.createdAt, order: .forward)
    private var commitments: [Commitment]

    /// Bumped to force `buckets` to recompute against the current clock when no model change has
    /// occurred: at a slot-window / psychDay boundary (by the timer), and when the view reappears
    /// after being off-screen (tab switch / foreground), during which time may have passed.
    @State private var timeTick = 0
    @State private var commitmentForDetail: Commitment?
    @State private var commitmentForEdit: Commitment?

    /// The three Stage lists, recomputed on every `body` evaluation. Cheap: a few date comparisons
    /// and sorts over the active-commitment set.
    private var buckets:
        (
            current: [CommitmentCharacteristics],
            upcoming: [CommitmentCharacteristics],
            catchUp: [CommitmentCharacteristics]
        )
    {
        StageCharacterization.stageBuckets(commitments: commitments)
    }

    /// The next slot-window / psychDay boundary. Keys the boundary timer so a slot edit that moves
    /// this instant (e.g. changing the open slot's end time) restarts it.
    private var nextTransitionDate: Date? {
        StageCharacterization.nextTransitionDate(commitments: commitments)
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
        // Register `timeTick` as a re-render dependency: SwiftUI only tracks values read during
        // `body`, and `timeTick` is a bare counter bumped (by the boundary timer and on reappearance)
        // to force a recompute when no model change occurred. Its value is unused — the read is what
        // establishes the dependency. (Check-in / snooze changes are tracked separately, via the
        // relationship traversal in bucketing — see the `commitments` doc comment.)
        let _ = timeTick
        // Compute once per render pass: a computed property re-runs `stageBuckets` on every
        // `buckets.` access (≈9 per `body`), so bind it to a local `let` and read that instead.
        let buckets = buckets
        return NavigationStack {
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
            // Time-boundary refresh: sleep until the next slot-window / psychDay transition and bump
            // `timeTick` so `buckets` recomputes even with no model change. Keyed on `nextTransitionDate`
            // so editing a slot's end time (which moves that instant) restarts the sleep with the
            // correct target. SwiftUI cancels the task on disappear — no manual lifetime management.
            .task(id: nextTransitionDate) {
                while !Task.isCancelled {
                    let now = Time.now()
                    guard
                        let next = StageCharacterization.nextTransitionDate(
                            commitments: commitments, now: now)
                    else { break }
                    let delay = next.timeIntervalSince(now)
                    if delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }
                    if Task.isCancelled { break }
                    timeTick &+= 1  // overflow safe addition
                }
            }
            // The view can be off-screen (other tab) or the app backgrounded while a boundary passes;
            // the timer is cancelled then, so recompute against the current clock on return.
            .onAppear { timeTick &+= 1 }
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
