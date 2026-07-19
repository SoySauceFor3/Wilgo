import SwiftData
import SwiftUI

struct FinishedCycleReportView: View {
    let request: FinishedCycleReportRequest
    let onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: Commitment.activePredicate,
           sort: \Commitment.createdAt, order: .forward)
    private var commitments: [Commitment]
    @Query private var allTokens: [PositivityToken]

    /// Per-cycle editable state, keyed by `CycleReport.id`. Persists across
    /// re-renders as backfills mutate the live report.
    @State private var cardStates: [String: FCRCycleCardState] = [:]

    /// PT assigned to each failed cycle, keyed by `CycleReport.id`.
    @State private var assignedPTs: [String: PositivityToken] = [:]

    /// The `CycleReport.id` the shared mint sheet should attach its minted PT to.
    /// Non-nil ⇒ the sheet is presented. A card's `onRequestMint` sets this.
    @State private var mintTarget: String?

    /// The single shared mint draft for the whole report. Carries across cards,
    /// is preserved on non-save dismiss, and is consumed on save. See `MintDraft`.
    @State private var mintDraft = MintDraft()

    private var report: [CommitmentReport] {
        CycleReportBuilder.build(
            commitments: commitments,
            startPsychDay: request.startPsychDay,
            endPsychDay: request.endPsychDay
        )
    }

    private var allCycles: [(commitment: Commitment, cycle: CycleReport)] {
        report.flatMap { cr in cr.cycles.map { (cr.commitment, $0) } }
    }

    private var canClose: Bool {
        FCRCompletion.canClose(states: Array(cardStates.values))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(allCycles, id: \.cycle.id) { pair in
                        if let binding = stateBinding(for: pair.cycle) {
                            FCRCycleCardView(
                                cycle: pair.cycle,
                                commitment: pair.commitment,
                                state: binding,
                                streakSummary: StreakSummary.compute(
                                    for: pair.commitment,
                                    currentCycleEnd: pair.cycle.cycleEndPsychDay
                                ),
                                onRequestMint: {
                                    // Carry-over: do NOT reset the draft on open.
                                    mintDraft.onOpen()
                                    mintTarget = pair.cycle.id
                                }
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Cycle Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Cancel dismisses without persisting or advancing the
                    // watermark — the report reappears on next activation.
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        persistRecords()
                        onFinished()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canClose)
                }
            }
            .overlay(alignment: .bottom) {
                CheckInUndoBannerOverlay()
            }
            .sheet(item: mintTargetBinding) { target in
                mintSheet(for: target.id)
            }
            .onAppear(perform: reconcileStates)
            .onChange(of: report.map { $0.cycles.map(\.id) }) { _, _ in
                reconcileStates()
            }
            .onChange(of: checkInCountSignature) { _, _ in
                reconcileStates()
            }
            .onChange(of: outcomeSignature) { _, _ in
                reconcileStates()
            }
            .onAppear {
                if report.isEmpty {
                    onFinished()
                    dismiss()
                }
            }
        }
    }

    /// A signature that changes whenever any cycle's check-in count changes
    /// (e.g. after backfill), so card states re-sync their counts.
    private var checkInCountSignature: [Int] {
        allCycles.map(\.cycle.actualCheckIns)
    }

    /// A signature that changes whenever any cycle's outcome label changes, so
    /// PT assignments release/acquire correctly (a label can toggle a cycle
    /// between needs-PT and no-PT).
    private var outcomeSignature: [String] {
        allCycles.map { cardStates[$0.cycle.id]?.outcome?.rawValue ?? "" }
    }

    private func stateBinding(for cycle: CycleReport) -> Binding<FCRCycleCardState>? {
        guard cardStates[cycle.id] != nil else { return nil }
        return Binding(
            get: { cardStates[cycle.id] ?? FCRCycleCardState(targetCount: cycle.targetCheckIns, checkInCount: cycle.actualCheckIns) },
            set: { cardStates[cycle.id] = $0 }
        )
    }

    /// Create missing card states and push live check-in counts into existing
    /// ones. The count setter on `FCRCycleCardState` handles the failed→passed
    /// flip automatically.
    private func reconcileStates() {
        for (_, cycle) in allCycles {
            if var existing = cardStates[cycle.id] {
                if existing.checkInCount != cycle.actualCheckIns {
                    existing.checkInCount = cycle.actualCheckIns
                    cardStates[cycle.id] = existing
                }
            } else {
                cardStates[cycle.id] = FCRCycleCardState(
                    targetCount: cycle.targetCheckIns,
                    checkInCount: cycle.actualCheckIns
                )
            }
        }
        // Drop states for cycles no longer present.
        let liveIDs = Set(allCycles.map(\.cycle.id))
        for key in cardStates.keys where !liveIDs.contains(key) {
            cardStates[key] = nil
        }
        // Release PT assignments for cycles that no longer REQUIRE a PT — covers
        // both "flipped to passed" and "label changed to a no-PT outcome"
        // (Intended/Excused). Releasing only clears the assignment; it never
        // deletes the token. An auto-assigned free token simply returns to
        // `freeTokens`; a minted token stays inserted & unconsumed in the
        // context, persisting as a re-assignable wins-journal entry.
        for (cycleID, _) in assignedPTs where !ptRequiringCycleIDs.contains(cycleID) {
            assignedPTs[cycleID] = nil
        }
        reconcilePTAssignments()
    }

    /// Failed cycles whose current outcome requires a PT (Move on / Punished).
    /// These are the only cycles eligible for auto-assignment.
    private var ptRequiringCycleIDs: [String] {
        allCycles
            .filter { cardStates[$0.cycle.id]?.outcome?.requiresPT == true }
            .map(\.cycle.id)
    }

    /// Free tokens = not consumed by any prior CycleRecord and not already
    /// assigned to a cycle in this session.
    private var freeTokens: [PositivityToken] {
        let assignedIDs = Set(assignedPTs.values.map(\.id))
        return allTokens.filter { $0.consumedByCycleRecord == nil && !assignedIDs.contains($0.id) }
    }

    /// Auto-assign free tokens to PT-requiring cycles, then sync `hasAssignedPT`.
    private func reconcilePTAssignments() {
        assignedPTs = FCRPTAssignment.autoAssign(
            eligibleCycleIDs: ptRequiringCycleIDs,
            freeTokens: freeTokens,
            alreadyAssigned: assignedPTs
        )
        syncAssignmentFlags()
    }

    private func syncAssignmentFlags() {
        for (_, cycle) in allCycles {
            guard var state = cardStates[cycle.id] else { continue }
            let assigned = assignedPTs[cycle.id] != nil
            if state.hasAssignedPT != assigned {
                state.hasAssignedPT = assigned
                cardStates[cycle.id] = state
            }
        }
    }

    /// Mint a new PT inline and assign it to the given failed cycle.
    private func mintAndAssign(reason: String, to cycleID: String) {
        let token = PositivityToken(reason: reason)
        modelContext.insert(token)
        assignedPTs[cycleID] = token
        syncAssignmentFlags()
    }

    // MARK: - Shared mint sheet

    /// Bridges the `String?` `mintTarget` to `.sheet(item:)`, which needs an
    /// Identifiable. Non-nil target ⇒ sheet presented; dismiss ⇒ target cleared.
    private var mintTargetBinding: Binding<MintTarget?> {
        Binding(
            get: { mintTarget.map(MintTarget.init(id:)) },
            set: { mintTarget = $0?.id }
        )
    }

    /// The shared "mint a PT" sheet. Text entry lives here in the parent, backed
    /// by the single shared `mintDraft`: it carries over across cards, is
    /// preserved on Cancel / swipe-down, and is consumed on save.
    private func mintSheet(for cycleID: String) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved to your wins journal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField(
                    "Something good happened…",
                    text: Binding(get: { mintDraft.text }, set: { mintDraft.edit($0) }),
                    axis: .vertical
                )
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                Button {
                    guard let reason = mintDraft.trimmedReason else { return }
                    mintAndAssign(reason: reason, to: cycleID)
                    mintDraft.consumeOnSave()
                    mintTarget = nil
                } label: {
                    Text("Save & use as PT")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(mintDraft.isBlank)
                Spacer()
            }
            .padding(16)
            .navigationTitle("✨ One good thing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { mintTarget = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    /// Persist one CycleRecord per cycle when the report is closed via Done.
    private func persistRecords() {
        for (commitment, cycle) in allCycles {
            guard let state = cardStates[cycle.id] else { continue }
            let record = CycleRecordBuilder.makeRecord(
                commitment: commitment,
                cycle: cycle,
                state: state,
                consumedPT: assignedPTs[cycle.id]
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
    }
}

/// Identifiable wrapper so a `CycleReport.id` string can drive `.sheet(item:)`.
private struct MintTarget: Identifiable {
    let id: String
}

// MARK: - Preview helpers

struct FinishedCycleReportViewPreview: View {
    var body: some View {
        let endPsychDay = Calendar.current.startOfDay(for: Date())
        let startPsychDay =
            Calendar.current.date(byAdding: .day, value: -21, to: endPsychDay) ?? endPsychDay
        let request = FinishedCycleReportRequest(
            startPsychDay: startPsychDay,
            endPsychDay: endPsychDay
        )
        FinishedCycleReportView(request: request, onFinished: {})
    }
}

#Preview {
    let container = HeatmapPreviewFactory.richHistoryContainer()
    FinishedCycleReportViewPreview()
        .modelContainer(container)
        .environmentObject(CheckInUndoManager())
}
