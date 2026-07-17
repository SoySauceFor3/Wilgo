import SwiftData
import SwiftUI

struct ArchivedCommitmentsView: View {
    @Query(
        filter: #Predicate<Commitment> { $0.archivedAt != nil },
        sort: [SortDescriptor(\Commitment.archivedAt, order: .reverse)])
    private var archivedCommitments: [Commitment]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @State private var commitmentForDetail: Commitment?
    @State private var deleteTarget: DeleteTarget?
    @State private var selection: Set<Commitment.ID> = []

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    private var actions: ArchivedCommitmentsActions {
        ArchivedCommitmentsActions(modelContext: modelContext)
    }

    private var selectedCommitments: [Commitment] {
        archivedCommitments.filter { selection.contains($0.id) }
    }

    var body: some View {
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
                        ArchivedCommitmentRow(
                            commitment: commitment,
                            onTap: { tap(commitment) },
                            onUnarchive: { actions.unarchive([commitment]) },
                            onDelete: { promptDelete(commitment) }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Archived")
        .toolbar { toolbarContent }
        .sheet(item: $commitmentForDetail) { commitment in
            CommitmentDetailView(commitment: commitment)
                .presentationDetents([.fraction(0.65), .large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            deleteTarget?.title ?? "",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                confirmDelete(target)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This cannot be undone.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing, !selection.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        actions.unarchive(selectedCommitments)
                        selection.removeAll()
                    } label: {
                        Label("Unarchive Selected", systemImage: "archivebox.fill")
                    }
                    Button(role: .destructive) {
                        deleteTarget = .selection(selectedCommitments)
                    } label: {
                        Label("Delete Selected", systemImage: "trash")
                    }
                } label: {
                    Label("Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !archivedCommitments.isEmpty {
                EditButton()
            }
        }
    }

    private func tap(_ commitment: Commitment) {
        guard !isEditing else { return }
        commitmentForDetail = commitment
    }

    private func promptDelete(_ commitment: Commitment) {
        deleteTarget = .single(commitment)
    }

    private func confirmDelete(_ target: DeleteTarget) {
        actions.delete(target.commitments)
        if case .selection = target {
            selection.removeAll()
        }
    }
}

/// What a delete confirmation alert is about: a single row or the current selection.
private enum DeleteTarget: Identifiable {
    case single(Commitment)
    case selection([Commitment])

    var id: String {
        switch self {
        case let .single(commitment): commitment.id.uuidString
        case .selection: "selection"
        }
    }

    var title: String {
        switch self {
        case .single: "Delete this commitment?"
        case .selection: "Delete selected commitments?"
        }
    }

    var commitments: [Commitment] {
        switch self {
        case let .single(commitment): [commitment]
        case let .selection(commitments): commitments
        }
    }
}

/// Owns the model-layer mutations for archived commitments so they can be
/// exercised in unit tests without constructing the SwiftUI view.
struct ArchivedCommitmentsActions {
    let modelContext: ModelContext

    /// Restores commitments to the active list and resets their cycle.
    func unarchive(_ commitments: [Commitment]) {
        withAnimation {
            for commitment in commitments {
                commitment.archivedAt = nil
                commitment.cycle = Cycle.makeDefault(commitment.cycle.kind)
            }
        }
        // Save explicitly so didSave fires NOW → RefreshCoordinator's observer rebuilds the surfaces
        // immediately. Without it, autosave fires didSave ~15s later (measured). Same save, made prompt.
        try? modelContext.save()
    }

    /// Permanently removes commitments from the store.
    func delete(_ commitments: [Commitment]) {
        withAnimation {
            for commitment in commitments {
                modelContext.delete(commitment)
            }
        }
        // Save explicitly so didSave fires NOW → RefreshCoordinator's observer rebuilds the surfaces
        // immediately. Without it, autosave fires didSave ~15s later (measured). Same save, made prompt.
        try? modelContext.save()
    }
}

private struct ArchivedCommitmentRow: View {
    let commitment: Commitment
    let onTap: () -> Void
    let onUnarchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        CommitmentRowView(commitment: commitment)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .swipeActions(edge: .trailing) {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
                unarchiveButton
            }
            .swipeActions(edge: .leading) {
                unarchiveButton
            }
    }

    private var unarchiveButton: some View {
        Button(action: onUnarchive) {
            Label("Unarchive", systemImage: "archivebox.fill")
        }
        .tint(.blue)
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
