import SwiftUI

/// Page 1 of the FinishedCycleReport flow.
/// Displays raw check-in counts and timestamps for every completed cycle.
/// Intentionally ignores positivity token compensation so the user sees
/// exactly what was recorded — token effects live on Page 2.
///
/// Accepts `commitments` by value: any parent that re-derives the report from a
/// `@Query` source (e.g. after a check-in backfill) will cause SwiftUI to
/// re-render this page automatically.
struct CheckInSummaryPage: View {
    let commitmentReports: [CommitmentReport]

    var body: some View {
        List {
            ForEach(commitmentReports) { commitmentReport in
                Section(commitmentReport.commitment.title) {
                    ForEach(commitmentReport.cycles) { cycle in
                        CheckInCycleRow(
                            cycle: cycle,
                            commitment: commitmentReport.commitment
                        )
                    }
                }
            }
        }
    }
}

// MARK: - CheckInCycleRow

private struct CheckInCycleRow: View {
    let cycle: CycleReport
    let commitment: Commitment

    @State private var isExpanded = false
    @State private var showingBackfill = false

    // NOTE: Only meaningful when cycle.isTargetEnabled == true.
    // When disabled, targetCheckIns holds the preserved count (not zero),
    // so this comparison would be misleading — callers must guard on isTargetEnabled first.
    private var rawMetTarget: Bool { cycle.actualCheckIns >= cycle.targetCheckIns }

    private var cycleRange: ClosedRange<Date> {
        cycle.cycleStartPsychDay...cycle.cycleEndPsychDay.addingTimeInterval(-1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if cycle.isGrace {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                        .frame(width: 24)
                } else if !cycle.isTargetEnabled {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.tertiary)
                        .font(.title3)
                        .frame(width: 24)
                } else {
                    Image(
                        systemName: rawMetTarget
                            ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(rawMetTarget ? .green : .red)
                    .font(.title3)
                    .frame(width: 24)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(cycle.cycleLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if cycle.isGrace {
                        Text("\(cycle.actualCheckIns)/\(cycle.targetCheckIns) check-ins · grace")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    } else if !cycle.isTargetEnabled {
                        Text("\(cycle.actualCheckIns) check-ins · no target")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("\(cycle.actualCheckIns)/\(cycle.targetCheckIns) check-ins")
                            .font(.body)
                    }

                }

                Spacer()

                Button {
                    showingBackfill = true
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "clock.fill" : "clock")
                        .foregroundStyle(isExpanded ? .primary : .secondary)
                        .font(.body)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)

            if isExpanded {
                checkInHistoryView
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .sheet(isPresented: $showingBackfill) {
            BackfillSheet(commitment: commitment, dateRange: cycleRange)
                .presentationDetents([.medium])
        }
    }

    private var checkInHistoryView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if cycle.checkIns.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "minus")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("No check-ins recorded")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 36)
            } else {
                ForEach(cycle.checkIns, id: \.createdAt) { checkIn in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(.secondary.opacity(0.35))
                            .frame(width: 5, height: 5)
                        Text(formattedDateTime(checkIn.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 36)
                }
            }
        }
        .padding(.bottom, 6)
    }

    private func formattedDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
