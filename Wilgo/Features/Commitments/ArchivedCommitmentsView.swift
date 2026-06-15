import SwiftData
import SwiftUI

struct ArchivedCommitmentsView: View {
    @Query(filter: #Predicate<Commitment> { $0.archivedAt != nil },
           sort: [SortDescriptor(\Commitment.archivedAt, order: .reverse)])
    private var archivedCommitments: [Commitment]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @State private var commitmentForDetail: Commitment?
    @State private var commitmentPendingDelete: Commitment?
    @State private var isPresentingDeleteConfirmation: Bool = false
    @State private var selection: Set<Commitment.ID> = []

    var body: some View {
        NavigationStack {
            Group {
                if archivedCommitments.isEmpty {
                    ContentUnavailableView(
                        "No Archived Commitments",
                        systemImage: "archivebox",
                        description: Text("Commitments you archive will appear here.")
                    )
                } else {
                    List(selection: $selection) {
                        ForEach(archivedCommitments) { commitment in
                            CommitmentRowView(commitment: commitment)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if editMode?.wrappedValue.isEditing != true {
                                        commitmentForDetail = commitment
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        commitmentPendingDelete = commitment
                                        isPresentingDeleteConfirmation = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        unarchive(commitment)
                                    } label: {
                                        Label("Unarchive", systemImage: "archivebox.fill")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Archived")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if editMode?.wrappedValue.isEditing == true, !selection.isEmpty {
                        Button("Unarchive") {
                            unarchiveSelection()
                        }
                    } else {
                        EditButton()
                    }
                }
            }
            .sheet(item: $commitmentForDetail) { commitment in
                CommitmentDetailView(commitment: commitment)
                    .presentationDetents([.fraction(0.65), .large])
                    .presentationDragIndicator(.visible)
            }
            .alert(
                "Delete this commitment?",
                isPresented: $isPresentingDeleteConfirmation,
                presenting: commitmentPendingDelete
            ) { commitment in
                Button("Delete", role: .destructive) {
                    delete(commitment)
                }
                Button("Cancel", role: .cancel) {
                    commitmentPendingDelete = nil
                }
            } message: { _ in
                Text("This cannot be undone.")
            }
        }
    }

    private func unarchive(_ commitment: Commitment) {
        withAnimation {
            commitment.archivedAt = nil
            commitment.cycle = Cycle.makeDefault(commitment.cycle.kind)
        }
        CommitmentChangeRefresher.refreshAll()
    }

    private func unarchiveSelection() {
        let toUnarchive = archivedCommitments.filter { selection.contains($0.id) }
        withAnimation {
            for commitment in toUnarchive {
                commitment.archivedAt = nil
                commitment.cycle = Cycle.makeDefault(commitment.cycle.kind)
            }
            selection.removeAll()
        }
        CommitmentChangeRefresher.refreshAll()
    }

    private func delete(_ commitment: Commitment) {
        withAnimation {
            modelContext.delete(commitment)
        }
        CommitmentChangeRefresher.refreshAll()
        commitmentPendingDelete = nil
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
            title: "Old Workout Plan",
            cycle: Cycle.makeDefault(.daily),
            slots: [slot(6, 0, 8, 0)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        ),
        Commitment(
            title: "Journaling 📓",
            cycle: Cycle.makeDefault(.daily),
            slots: [slot(9, 0, 11, 0)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        ),
        Commitment(
            title: "No Sugar Challenge 🍬",
            cycle: Cycle.makeDefault(.weekly),
            slots: [slot(12, 0, 14, 0)],
            target: Target(count: 1),
            proofOfWorkType: .manual,
        ),
    ]
    let archiveDates: [Date] = [
        Date(timeIntervalSince1970: 1_700_000_000),
        Date(timeIntervalSince1970: 1_710_000_000),
        Date(timeIntervalSince1970: 1_720_000_000),
    ]
    for (commitment, archivedAt) in zip(samples, archiveDates) {
        commitment.archivedAt = archivedAt
        ctx.insert(commitment)
    }
    return container
}

struct ArchivedCommitmentsView_Previews: PreviewProvider {
    static var previews: some View {
        ArchivedCommitmentsView()
            .modelContainer(try! makePreviewContainerWithSamples())
    }
}
