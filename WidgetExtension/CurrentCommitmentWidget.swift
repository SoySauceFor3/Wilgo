import AppIntents
import SwiftData
import SwiftUI
import WidgetKit

// MARK: - Data model

enum CommitmentStage {
    case current, catchUp, future
}

/// Plain-value snapshot extracted from SwiftData in getTimeline/getSnapshot.
/// No SwiftData objects cross the timeline boundary.
struct CommitmentSnapshot {
    let title: String
    let checkedInCount: Int
    let targetCount: Int
    let cycleLabel: String
    /// Stage-dependent secondary detail:
    /// .current  → active slot window, e.g. "3–5 PM"
    /// .future   → slot start time, e.g. "starts 3 PM"
    /// .catchUp  → nil
    let slotDetail: String?
    let behindCount: Int
    let stage: CommitmentStage
    let commitmentId: UUID

    var isOverTarget: Bool { checkedInCount >= targetCount }
    var progressFraction: Double {
        targetCount > 0 ? min(1.0, Double(checkedInCount) / Double(targetCount)) : 0.0
    }
}

struct CurrentCommitmentEntry: TimelineEntry {
    let date: Date
    /// Ordered list: current → catchUp → future.
    let snapshots: [CommitmentSnapshot]
}

// MARK: - Timeline provider

struct CurrentCommitmentProvider: TimelineProvider {

    private func makeContainer() throws -> ModelContainer {
        guard
            let groupContainer = FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: WilgoConstants.appGroupID)
        else { throw URLError(.fileDoesNotExist) }
        let storeURL =
            groupContainer
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("default.store")
        let schema = Schema([Commitment.self, Slot.self, CheckIn.self, PositivityToken.self, SlotSnooze.self])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func buildSnapshots(commitments: [Commitment], now: Date) -> [CommitmentSnapshot] {
        let psychDay = Time.psychDay(for: now)
        let shortTime = DateFormatter()
        shortTime.dateFormat = "h:mm a"
        shortTime.amSymbol = "AM"
        shortTime.pmSymbol = "PM"

        func cycleLabel(for commitment: Commitment) -> String {
            let cycle = commitment.target.cycle
            return "\(cycle.multiplier == 1 ? "" : "\(cycle.multiplier)") \(cycle.kind.abbr)"
        }

        func makeSnapshot(
            _ wb: CommitmentAndSlot.WithBehind,
            stage: CommitmentStage
        ) -> CommitmentSnapshot {
            let c = wb.commitment
            let count = c.checkInsInCycle(
                cycle: c.target.cycle, until: psychDay, inclusive: true
            ).count

            let slotDetail: String?
            switch stage {
            case .current:
                slotDetail = wb.slots.first?.timeOfDayText
            case .future:
                if let start = wb.slots.first?.start {
                    slotDetail = "starts \(shortTime.string(from: start))"
                } else {
                    slotDetail = nil
                }
            case .catchUp:
                slotDetail = nil
            }

            return CommitmentSnapshot(
                title: c.title,
                checkedInCount: count,
                targetCount: c.target.count,
                cycleLabel: cycleLabel(for: c),
                slotDetail: slotDetail,
                behindCount: wb.behindCount,
                stage: stage,
                commitmentId: c.id
            )
        }

        var result: [CommitmentSnapshot] = []
        result += CommitmentAndSlot.currentWithBehind(commitments: commitments, now: now)
            .map { makeSnapshot($0, stage: .current) }
        result += CommitmentAndSlot.catchUpWithBehind(commitments: commitments, now: now)
            .map { makeSnapshot($0, stage: .catchUp) }
        result += CommitmentAndSlot.upcomingWithBehind(commitments: commitments, after: now)
            .map { makeSnapshot($0, stage: .future) }
        return result
    }

    private func buildEntry(at date: Date) -> CurrentCommitmentEntry {
        guard let container = try? makeContainer() else {
            return CurrentCommitmentEntry(date: date, snapshots: [])
        }
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<Commitment>())) ?? []
        return CurrentCommitmentEntry(
            date: date, snapshots: buildSnapshots(commitments: all, now: date))
    }

    func placeholder(in context: Context) -> CurrentCommitmentEntry {
        CurrentCommitmentEntry(
            date: .now,
            snapshots: [
                CommitmentSnapshot(
                    title: "洗鼻子", checkedInCount: 0, targetCount: 4,
                    cycleLabel: "today", slotDetail: "7–8 AM", behindCount: 0,
                    stage: .current, commitmentId: UUID()),
                CommitmentSnapshot(
                    title: "用牙线", checkedInCount: 4, targetCount: 3,
                    cycleLabel: "today", slotDetail: "9–10 PM", behindCount: 0,
                    stage: .current, commitmentId: UUID()),
                CommitmentSnapshot(
                    title: "Workout 啊啊啊", checkedInCount: 0, targetCount: 5,
                    cycleLabel: "today", slotDetail: "6–7 PM", behindCount: 0,
                    stage: .current, commitmentId: UUID()),
            ])
    }

    func getSnapshot(in context: Context, completion: @escaping (CurrentCommitmentEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : buildEntry(at: .now))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<CurrentCommitmentEntry>) -> Void
    ) {
        print("CurrentCommitmentWidget getTimeline")
        let now = Date.now
        let entry = buildEntry(at: now)
        let allCommitments: [Commitment]
        if let container = try? makeContainer() {
            allCommitments =
                (try? ModelContext(container).fetch(FetchDescriptor<Commitment>())) ?? []
        } else {
            allCommitments = []
        }
        let policy: TimelineReloadPolicy
        if let nextDate = CommitmentAndSlot.nextTransitionDate(
            commitments: allCommitments, now: now)
        {
            print("Next date: \(nextDate), now: \(now)")
            policy = .after(nextDate)
        } else {
            policy = .after(now.addingTimeInterval(3_600))
        }
        completion(Timeline(entries: [entry], policy: policy))
    }
}

// MARK: - Stage dot

private struct StageDotView: View {
    let snapshot: CommitmentSnapshot

    var body: some View {
        switch snapshot.stage {
        case .current:
            EmptyView()
        case .catchUp:
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 16, height: 16)
                Text("-\(snapshot.behindCount)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        case .future:
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 16, height: 16)
                Image(systemName: "clock")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }
}

// MARK: - Layout constants

private enum WidgetLayout {
    static let cardHeight: CGFloat = 41
    static let cardSpacing: CGFloat = 7
    static let columnSpacing: CGFloat = 8
}

// MARK: - Card view

private struct CommitmentCardView: View {
    let snapshot: CommitmentSnapshot

    // STUB: deep-link URL — app-side handler added in Commit 2.
    private var deepLinkURL: URL {
        URL(string: "wilgo://commitment?id=\(snapshot.commitmentId.uuidString)")!
    }

    private var fillColor: Color {
        switch snapshot.stage {
        case .current:
            return snapshot.isOverTarget
                ? Color.accentColor.opacity(0.55)
                : Color.accentColor.opacity(0.2)
        case .catchUp, .future:
            return Color.orange.opacity(0.15)
        }
    }

    var body: some View {
        Link(destination: deepLinkURL) {
            ZStack(alignment: .leading) {
                // Progress-fill background
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(fillColor)
                        .frame(width: geo.size.width * snapshot.progressFraction)
                }

                HStack(alignment: .center, spacing: 6) {
                    StageDotView(snapshot: snapshot)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .opacity(snapshot.stage == .future ? 0.6 : 1.0)

                        HStack(spacing: 3) {
                            Text("\(snapshot.checkedInCount)/\(snapshot.targetCount)")
                                .font(.caption2.monospacedDigit())
                            Text("·")
                            Text(snapshot.cycleLabel)
                                .font(.caption2)
                            if let detail = snapshot.slotDetail {
                                Text("·")
                                Text(detail)
                                    .font(.caption2)
                            }
                            if snapshot.isOverTarget {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                        }
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(intent: CheckInIntent(commitmentId: snapshot.commitmentId)) {
                        Image(
                            systemName: snapshot.isOverTarget ? "plus.circle" : "plus.circle.fill"
                        )
                        .font(.callout)
                        .foregroundColor(snapshot.isOverTarget ? .secondary : .accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .frame(width: .infinity, height: WidgetLayout.cardHeight)
            .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Empty slot

private struct EmptySlotView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.07))
            .frame(height: WidgetLayout.cardHeight)
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "moon.stars")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No commitments")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Grid layout helpers

/// One column of `capacity` slots, vertically centered.
private struct ColumnView: View {
    let snapshots: [CommitmentSnapshot]
    let capacity: Int

    var body: some View {
        VStack(spacing: WidgetLayout.cardSpacing) {
            ForEach(0..<capacity, id: \.self) { i in
                if i < snapshots.count {
                    CommitmentCardView(snapshot: snapshots[i])
                } else {
                    EmptySlotView()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Distributes snapshots into two columns, left-first per row.
private func twoColumns(
    _ snapshots: [CommitmentSnapshot], capacity: Int
) -> (left: [CommitmentSnapshot], right: [CommitmentSnapshot]) {
    var left: [CommitmentSnapshot] = []
    var right: [CommitmentSnapshot] = []
    for (i, snap) in snapshots.prefix(capacity * 2).enumerated() {
        if i % 2 == 0 { left.append(snap) } else { right.append(snap) }
    }
    return (left, right)
}

// MARK: - Widget entry views

struct CurrentCommitmentWidgetEntryView: View {
    var entry: CurrentCommitmentEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshots.isEmpty {
            EmptyWidgetView()
        } else {
            Group {
                switch family {
                case .systemSmall:
                    ColumnView(snapshots: entry.snapshots, capacity: 3)
                case .systemMedium:
                    let cols = twoColumns(entry.snapshots, capacity: 3)
                    HStack(alignment: .top, spacing: WidgetLayout.columnSpacing) {
                        ColumnView(snapshots: cols.left, capacity: 3)
                        ColumnView(snapshots: cols.right, capacity: 3)
                    }
                case .systemLarge:
                    let cols = twoColumns(entry.snapshots, capacity: 7)
                    HStack(alignment: .top, spacing: WidgetLayout.columnSpacing) {
                        ColumnView(snapshots: cols.left, capacity: 7)
                        ColumnView(snapshots: cols.right, capacity: 7)
                    }
                default:
                    ColumnView(snapshots: entry.snapshots, capacity: 3)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Widget

struct CurrentCommitmentWidget: Widget {
    let kind = WilgoConstants.currentCommitmentWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CurrentCommitmentProvider()) { entry in
            CurrentCommitmentWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Focus Commitments")
        .description("See and check in to your active focus commitments.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Previews

private let previewSnapshots: [CommitmentSnapshot] = [
    CommitmentSnapshot(
        title: "洗鼻子", checkedInCount: 0, targetCount: 4,
        cycleLabel: "today", slotDetail: "7–8 AM", behindCount: 0,
        stage: .current, commitmentId: UUID()),
    CommitmentSnapshot(
        title: "用牙线", checkedInCount: 4, targetCount: 3,
        cycleLabel: "today", slotDetail: "9–10 PM", behindCount: 0,
        stage: .current, commitmentId: UUID()),
    CommitmentSnapshot(
        title: "Workout 啊啊啊", checkedInCount: 0, targetCount: 5,
        cycleLabel: "today", slotDetail: "6–7 PM", behindCount: 0,
        stage: .current, commitmentId: UUID()),
    CommitmentSnapshot(
        title: "Read 30 min", checkedInCount: 1, targetCount: 5,
        cycleLabel: "this week", slotDetail: nil, behindCount: 2,
        stage: .catchUp, commitmentId: UUID()),
    CommitmentSnapshot(
        title: "Meditate", checkedInCount: 0, targetCount: 7,
        cycleLabel: "this week", slotDetail: nil, behindCount: 3,
        stage: .catchUp, commitmentId: UUID()),
    CommitmentSnapshot(
        title: "Evening Walk", checkedInCount: 0, targetCount: 1,
        cycleLabel: "today", slotDetail: "starts 8 PM", behindCount: 0,
        stage: .future, commitmentId: UUID()),
    CommitmentSnapshot(
        title: "Journal", checkedInCount: 0, targetCount: 1,
        cycleLabel: "today", slotDetail: "starts 10 PM", behindCount: 0,
        stage: .future, commitmentId: UUID()),
]

#Preview("Small", as: .systemSmall) {
    CurrentCommitmentWidget()
} timeline: {
    CurrentCommitmentEntry(date: .now, snapshots: previewSnapshots)
}

#Preview("Medium", as: .systemMedium) {
    CurrentCommitmentWidget()
} timeline: {
    CurrentCommitmentEntry(date: .now, snapshots: previewSnapshots)
}

#Preview("Large", as: .systemLarge) {
    CurrentCommitmentWidget()
} timeline: {
    CurrentCommitmentEntry(date: .now, snapshots: previewSnapshots)
}

#Preview("Empty", as: .systemSmall) {
    CurrentCommitmentWidget()
} timeline: {
    CurrentCommitmentEntry(date: .now, snapshots: [])
}
