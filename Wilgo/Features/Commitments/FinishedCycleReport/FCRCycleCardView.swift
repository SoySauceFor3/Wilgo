import SwiftData
import SwiftUI

/// A single cycle card in the redesigned Finished Cycle Report.
///
/// Renders the collapsed/expanded states, the history expansion (reusing
/// `CommitmentHeatmapInfoCard`), backfill (reusing `BackfillSheet`), the
/// purposeful-stop fields for failed cycles (outcome pills + per-outcome
/// reflection/PT requirements), and the celebration row for passed cycles.
/// The "+ Mint one now" button opens the parent's shared mint sheet.
struct FCRCycleCardView: View {
    let cycle: CycleReport
    let commitment: Commitment

    /// Editable per-card state. Owned by the parent so the FCR can read it on close.
    @Binding var state: FCRCycleCardState

    /// Streak summary line (e.g. "4 consecutive failed weeks"), nil if none.
    var streakSummary: String?

    /// Called when the user taps "+ Mint one now" to ask the parent to open the
    /// shared mint sheet for THIS card. The parent owns the sheet, the draft
    /// text, and the actual mint-and-assign.
    var onRequestMint: (() -> Void)?

    @State private var isExpanded: Bool
    @State private var isHistoryShown = false
    @State private var showingHelp = false

    init(
        cycle: CycleReport,
        commitment: Commitment,
        state: Binding<FCRCycleCardState>,
        streakSummary: String? = nil,
        onRequestMint: (() -> Void)? = nil
    ) {
        self.cycle = cycle
        self.commitment = commitment
        _state = state
        self.streakSummary = streakSummary
        self.onRequestMint = onRequestMint
        // Passed cycles start collapsed (no required action); failed start expanded.
        _isExpanded = State(initialValue: !state.wrappedValue.isPassed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isExpanded {
                if isHistoryShown {
                    // The card derives its check-ins/goal/etc. live from the commitment and range,
                    // and owns its own delete + backfill sheet. onDismiss is nil here — the FCR card
                    // owns its own expand/collapse, so tap-to-dismiss is inert.
                    CommitmentHeatmapInfoCard(
                        commitment: commitment,
                        range: cycle.cycleStartPsychDay..<cycle.cycleEndPsychDay,
                        rangeKind: commitment.cycle.kind,
                        showsHeatmapChrome: false,
                        onDismiss: nil
                    )
                    .padding(.top, 8)
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
                HStack(spacing: 4) {
                    Text("HOW ARE YOU CLOSING THIS?")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Button {
                        showingHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingHelp) {
                        labelHelpPopover
                    }
                }
                labelPills
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(
                    state.isReflectionRequired
                        ? "WRITE SOMETHING (REQUIRED)" : "WRITE SOMETHING (OPTIONAL)"
                )
                .font(.caption2.weight(.bold))
                .foregroundStyle(state.isReflectionRequired ? .orange : .secondary)
                TextField(
                    state.isReflectionRequired ? "Why did you miss? (required)" : "Optional note",
                    text: $state.reflectionText,
                    axis: .vertical
                )
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
            }
            if state.outcome?.requiresPT == true {
                ptRow
            }
        }
    }

    private var labelHelpPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            helpRow(.intended, "You meant for this to fail (e.g. a test run). Nothing required.")
            helpRow(.excused, "A real reason got in the way. Nothing required.")
            helpRow(.moveOn, "No reason, no penalty. Jot down why, then move on. (note required)")
            helpRow(
                .punished,
                "You took a consequence for the miss. Add a win to balance it. (PT required)")
        }
        .padding(16)
        .frame(maxWidth: 320)
        .presentationCompactAdaptation(.popover)
    }

    private func helpRow(_ outcome: CycleOutcome, _ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(outcome.displayName)
                .font(.caption.weight(.bold))
                .foregroundStyle(outcome.tint)
            Text(explanation)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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

    static let selectableOutcomes: [CycleOutcome] = [.intended, .excused, .moveOn, .punished]

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
                    onRequestMint?()
                } label: {
                    statusChip("+ Mint one now", color: .blue)
                }
                .buttonStyle(.plain)
            }
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
        case .moveOn: return "Move on"
        case .intended: return "Intended"
        }
    }

    var tint: Color {
        switch self {
        case .passed: return .green
        case .excused: return .blue
        case .punished: return .red
        case .moveOn: return .yellow
        case .intended: return .gray
        }
    }
}
