import SwiftData
import SwiftUI

struct ListCommitmentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Commitment.createdAt, order: .forward) private var commitments: [Commitment]
    @State private var isPresentingAddCommitment: Bool = false
    @State private var commitmentForDetail: Commitment?
    @State private var commitmentForEdit: Commitment?
    @State private var selectedFilterTagIDs: Set<UUID> = []

    private var filteredCommitments: [Commitment] {
        if selectedFilterTagIDs.isEmpty {
            return commitments
        }
        return commitments.filter { c in
            c.tags.contains { selectedFilterTagIDs.contains($0.id) }
        }
    }

    private var debugCounts: String {
        "commitments=\(commitments.count) filtered=\(filteredCommitments.count) selectedTags=\(selectedFilterTagIDs.count)"
    }

    var body: some View {
        NavigationStack {
            TagFilterChipsView(selectedTagIDs: $selectedFilterTagIDs)
            List {
                ForEach(filteredCommitments) { commitment in
                    CommitmentRowView(commitment: commitment)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            MemoryProbe.log(
                                "CommitmentList.row.tap",
                                extra: "id=\(commitment.id) \(debugCounts)"
                            )
                            commitmentForDetail = commitment
                        }
                }
                .onDelete(perform: deleteCommitments)
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Commitments")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        MemoryProbe.log("CommitmentList.add.tap", extra: debugCounts)
                        isPresentingAddCommitment = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
            .sheet(isPresented: $isPresentingAddCommitment) {
                let _ = MemoryProbe.log("CommitmentList.add.sheet", extra: debugCounts)
                AddCommitmentView()
            }
            .sheet(item: $commitmentForDetail) { commitment in
                let _ = MemoryProbe.log(
                    "CommitmentList.detail.sheet",
                    extra: "id=\(commitment.id) \(debugCounts)"
                )
                CommitmentDetailView(commitment: commitment) {
                    // Close the detail sheet and present the full-page editor.
                    MemoryProbe.log(
                        "CommitmentList.detail.edit",
                        extra: "id=\(commitment.id) \(debugCounts)"
                    )
                    commitmentForDetail = nil
                    commitmentForEdit = commitment
                }
                .presentationDetents([.fraction(0.65), .large])
                .presentationDragIndicator(.visible)
            }
            .fullScreenCover(item: $commitmentForEdit) { commitment in
                let _ = MemoryProbe.log(
                    "CommitmentList.edit.cover",
                    extra: "id=\(commitment.id) \(debugCounts)"
                )
                NavigationStack {
                    EditCommitmentView(commitment: commitment)
                }
            }
            .onAppear {
                MemoryProbe.log("CommitmentList.appear", extra: debugCounts)
            }
            .onDisappear {
                MemoryProbe.log("CommitmentList.disappear", extra: debugCounts)
            }
            .onChange(of: commitments) {
                MemoryProbe.log("CommitmentList.query.commitments", extra: debugCounts)
            }
            .onChange(of: selectedFilterTagIDs) {
                MemoryProbe.log("CommitmentList.filter.change", extra: debugCounts)
            }
            .onChange(of: isPresentingAddCommitment) { _, isPresented in
                MemoryProbe.log(
                    "CommitmentList.add.presentation",
                    extra: "presented=\(isPresented) \(debugCounts)"
                )
            }
            .onChange(of: commitmentForDetail) { _, commitment in
                MemoryProbe.log(
                    "CommitmentList.detail.presentation",
                    extra: "id=\(commitment?.id.uuidString ?? "nil") \(debugCounts)"
                )
            }
            .onChange(of: commitmentForEdit) { _, commitment in
                MemoryProbe.log(
                    "CommitmentList.edit.presentation",
                    extra: "id=\(commitment?.id.uuidString ?? "nil") \(debugCounts)"
                )
            }
        }
    }

    private func deleteCommitments(offsets: IndexSet) {
        MemoryProbe.log(
            "CommitmentList.delete.start",
            extra: "offsets=\(Array(offsets)) \(debugCounts)"
        )
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredCommitments[index])
            }
        }
        MemoryProbe.log("CommitmentList.delete.end", extra: debugCounts)
    }
}

private func makePreviewContainerWithSamples() throws -> ModelContainer {
    let container = try ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, Tag.self,
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

    let samples: [Commitment] = [
        Commitment(
            title: "Workout",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot(6, 0, 8, 0), slot(8, 0, 10, 0)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        ),
        Commitment(
            title: "Read 30 mins 📚",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot(9, 0, 11, 0)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        ),
        Commitment(
            title: "Drink 2L Water 💧",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot(12, 0, 14, 0)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        ),
        Commitment(
            title: "Meditate 10 mins 🧘",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot(15, 0, 17, 0)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        ),
        Commitment(
            title: "No social media after 9 PM 📵",
            cycle: Cycle.anchored(.daily, at: .now),
            slots: [slot(21, 0, 23, 0)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        ),
    ]
    for commitment in samples {
        ctx.insert(commitment)
    }
    return container
}

struct ListCommitmentView_Previews: PreviewProvider {
    static var previews: some View {
        ListCommitmentView()
            .modelContainer(try! makePreviewContainerWithSamples())
    }
}
