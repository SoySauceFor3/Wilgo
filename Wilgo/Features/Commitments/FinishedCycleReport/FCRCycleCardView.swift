import SwiftData
import SwiftUI

/// A single cycle card in the redesigned Finished Cycle Report.
///
/// Stub (Phase 3A): renders the collapsed/expanded states, the history
/// expansion (reusing `CommitmentHeatmapInfoCard`), backfill (reusing
/// `BackfillSheet`), the purposeful-stop fields for failed cycles, and the
/// celebration row for passed cycles. The PT gate is stubbed ("Needed") and
/// wired for real in Phase 4A. Persistence happens in Phase 4B.
struct FCRCycleCardView: View {
    let cycle: CycleReport
    let commitment: Commitment

    /// Editable per-card state. Owned by the parent so the FCR can read it on close.
    @Binding var state: FCRCycleCardState

    /// Streak summary line (e.g. "4 consecutive failed weeks"), nil if none.
    var streakSummary: String?

    /// Called when the user mints a PT inline to cover this failed cycle.
    /// The parent creates+inserts the token, links it, and updates assignment.
    var onMintPT: ((String) -> Void)?

    @State private var isExpanded: Bool
    @State private var isHistoryShown = false
    @State private var showingBackfill = false
    @State private var isMinting = false
    @State private var mintText = ""

    init(
        cycle: CycleReport,
        commitment: Commitment,
        state: Binding<FCRCycleCardState>,
        streakSummary: String? = nil,
        onMintPT: ((String) -> Void)? = nil
    ) {
        self.cycle = cycle
        self.commitment = commitment
        _state = state
        self.streakSummary = streakSummary
        self.onMintPT = onMintPT
        // Passed cycles start collapsed (no required action); failed start expanded.
        _isExpanded = State(initialValue: !state.wrappedValue.isPassed)
    }

    private var cycleRange: ClosedRange<Date> {
        cycle.cycleStartPsychDay...cycle.cycleEndPsychDay.addingTimeInterval(-1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                if isHistoryShown {
                    historySection
                }
                if let streakSummary, !state.isPassed {
                    streakBanner(streakSummary)
                }
                Divider().padding(.vertical, 8)
                if state.isPassed {
                    celebrationSection
                } else {
                    purposefulStopSection
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: 1.5)
        )
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(commitment: commitment, dateRange: cycleRange)
                .presentationDetents([.medium])
        }
    }

    private var borderColor: Color {
        if state.isComplete { return Color(.separator) }
        return .orange.opacity(0.5)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(state.isComplete ? commitment.title : commitment.title)
                    .font(.subheadline.weight(.semibold))
                Text(cycle.cycleLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            countBadge
            if isExpanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isHistoryShown.toggle() }
                } label: {
                    Image(systemName: isHistoryShown ? "calendar.circle.fill" : "calendar")
                        .foregroundStyle(isHistoryShown ? .primary : .secondary)
                }
                .buttonStyle(.plain)
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusDot: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
    }

    private var dotColor: Color {
        if state.isPassed { return .green }
        return state.isComplete ? .purple : .orange
    }

    private var countBadge: some View {
        Text("\(state.checkInCount)/\(state.targetCount)")
            .font(.caption.weight(.bold).monospacedDigit())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(state.isPassed ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
            .foregroundStyle(state.isPassed ? .green : .red)
            .clipShape(Capsule())
    }

    // MARK: - History (reused InfoCard)

    private var historySection: some View {
        let period = Heatmap.PeriodData(
            id: cycle.cycleStartPsychDay,
            periodStartPsychDay: cycle.cycleStartPsychDay,
            periodEndPsychDay: cycle.cycleEndPsychDay,
            goal: cycle.targetCheckIns,
            checkIns: cycle.checkIns,
            isBeforeCreation: false
        )
        return CommitmentHeatmapInfoCard(
            period: period,
            heatmapKind: commitment.cycle.kind,
            targetKind: commitment.cycle.kind,
            selectedPeriod: .constant(period),
            onAddCheckIn: { showingBackfill = true }
        )
        .padding(.top, 8)
    }

    private func streakBanner(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.top, 8)
    }

    // MARK: - Purposeful stop (failed)

    private var purposefulStopSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW ARE YOU CLOSING THIS?")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                labelPills
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("WRITE SOMETHING")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                TextField("Required", text: $state.reflectionText, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
            }
            ptRow
        }
    }

    private var labelPills: some View {
        HStack(spacing: 6) {
            ForEach(FCRCycleCardView.selectableOutcomes, id: \.self) { outcome in
                Button {
                    state.outcome = outcome
                } label: {
                    Text(outcome.displayName)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(
                            state.outcome == outcome
                                ? outcome.tint.opacity(0.2) : Color(.tertiarySystemFill)
                        )
                        .foregroundStyle(state.outcome == outcome ? outcome.tint : .secondary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    static let selectableOutcomes: [CycleOutcome] = [.excused, .punished, .letGo, .other]

    @ViewBuilder
    private var ptRow: some View {
        HStack {
            Label("Positivity Token", systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if state.hasAssignedPT {
                statusChip("Covered", color: .green)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isMinting.toggle() }
                } label: {
                    statusChip(isMinting ? "Needed" : "+ Mint one now", color: isMinting ? .red : .blue)
                }
                .buttonStyle(.plain)
            }
        }

        if isMinting, !state.hasAssignedPT {
            mintSheet
        }
    }

    private func statusChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var mintSheet: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("✨ One good thing")
                .font(.caption.weight(.semibold))
            Text("Saved to your wins journal")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("Something good happened…", text: $mintText, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            Button {
                let trimmed = mintText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onMintPT?(trimmed)
                mintText = ""
                isMinting = false
            } label: {
                Text("Save & use as PT")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .disabled(mintText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(10)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Celebration (passed)

    private var celebrationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CELEBRATE (OPTIONAL)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(FCRCycleCardView.celebrationEmojis, id: \.self) { emoji in
                    emojiChip(emoji)
                }
            }
            Text("Tap to add · long-press to remove")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func emojiChip(_ emoji: String) -> some View {
        let count = state.reactionCount(emoji)
        HStack(spacing: 3) {
            Text(emoji)
            if count > 0 {
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(count > 0 ? Color.blue.opacity(0.15) : Color(.tertiarySystemFill))
        .clipShape(Capsule())
        .contentShape(Capsule())
        // Long-press is evaluated first; only if it does NOT fire does the tap
        // add a reaction. This avoids the Button+longPress conflict where a tap
        // always fired even on a long press.
        .gesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in
                    guard count > 0 else { return }
                    withAnimation(.easeInOut(duration: 0.15)) { state.removeReaction(emoji) }
                }
                .exclusively(
                    before: TapGesture().onEnded {
                        withAnimation(.easeInOut(duration: 0.15)) { state.addReaction(emoji) }
                    }
                )
        )
    }

    static let celebrationEmojis = ["🔥", "💪", "🎉", "⭐", "😤"]
}

// MARK: - CycleOutcome display

extension CycleOutcome {
    var displayName: String {
        switch self {
        case .passed: return "Passed"
        case .excused: return "Excused"
        case .punished: return "Punished"
        case .letGo: return "Let go"
        case .other: return "Other"
        }
    }

    var tint: Color {
        switch self {
        case .passed: return .green
        case .excused: return .blue
        case .punished: return .red
        case .letGo: return .yellow
        case .other: return .teal
        }
    }
}
