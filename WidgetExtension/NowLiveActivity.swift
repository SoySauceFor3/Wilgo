//
//  NowLiveActivity.swift
//  Now
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Shared chrome

private struct LiveActivitySparkleIcon: View {
    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .frame(width: diameter, height: diameter)
            Image(systemName: "sparkles")
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(.tint)
        }
        .accessibilityHidden(true)
    }
}

private struct DoneCapsuleLink: View {
    let commitmentId: UUID
    var compact: Bool = false

    var body: some View {
        Button(intent: CheckInIntent(commitmentId: commitmentId, source: .liveActivity)) {
            Label("Done", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, compact ? 6 : 8)
                .background(Capsule(style: .continuous).fill(Color.green.opacity(0.22)))
                .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
    }
}

private struct SnoozeCapsuleLink: View {
    let slotId: UUID
    var compact: Bool = false

    var body: some View {
        Button(intent: SnoozeIntent(slotId: slotId)) {
            Label("Snooze", systemImage: "moon.zzz.fill")
                .labelStyle(.titleAndIcon)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .padding(.horizontal, compact ? 10 : 14)
                .padding(.vertical, compact ? 6 : 8)
                .background(Capsule(style: .continuous).fill(Color.indigo.opacity(0.22)))
                .foregroundStyle(.indigo)
        }
        .buttonStyle(.plain)
    }
}

private struct CompactTrailingTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }
}

private struct ProgressCountBadge: View {
    let checkInCount: Int
    let targetCount: Int

    var body: some View {
        Text("\(checkInCount)/\(targetCount)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.15)))
            .accessibilityLabel("\(checkInCount) of \(targetCount) done this cycle")
    }
}

private struct WindowStatusLine: View {
    let state: NowAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale {
            Label("Ended", systemImage: "checkmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Text(timerInterval: state.windowStart...state.windowEnd, countsDown: true)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.tint)
                ProgressView(timerInterval: state.windowStart...state.windowEnd, countsDown: true) {} currentValueLabel: {}
                .progressViewStyle(.linear)
                .tint(.accentColor)
            }
        }
    }
}

struct NowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowAttributes.self) { context in
            HStack(alignment: .top, spacing: 12) {
                LiveActivitySparkleIcon(diameter: 40)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(context.state.commitmentTitle)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if let done = context.state.checkInCount,
                                    let target = context.state.targetCount
                                {
                                    ProgressCountBadge(checkInCount: done, targetCount: target)
                                }
                            }
                            Text(context.state.slotTimeText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            if let encouragement = context.state.encouragementText, !context.isStale {
                                Text(encouragement)
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .italic()
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if !context.isStale {
                            HStack(spacing: 6) {
                                SnoozeCapsuleLink(slotId: context.state.slotId)
                                DoneCapsuleLink(commitmentId: context.state.commitmentId)
                            }
                        }
                    }
                    WindowStatusLine(state: context.state, isStale: context.isStale)
                }
            }
            .padding(.vertical, 6)
            .activityBackgroundTint(Color(.systemFill))
            .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivitySparkleIcon(diameter: 28)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(context.state.commitmentTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if let done = context.state.checkInCount,
                                let target = context.state.targetCount
                            {
                                ProgressCountBadge(checkInCount: done, targetCount: target)
                            }
                        }
                        Text(context.state.slotTimeText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let encouragement = context.state.encouragementText, !context.isStale {
                            Text(encouragement)
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .italic()
                                .lineLimit(1)
                        }
                        WindowStatusLine(state: context.state, isStale: context.isStale)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.isStale {
                        HStack {
                            Spacer(minLength: 0)
                            SnoozeCapsuleLink(slotId: context.state.slotId, compact: true)
                            DoneCapsuleLink(commitmentId: context.state.commitmentId, compact: true)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            } compactTrailing: {
                CompactTrailingTitle(title: context.state.commitmentTitle)
            } minimal: {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
            .keylineTint(Color.accentColor)
        }
    }

}

private extension NowAttributes.ContentState {
    static var withCommitment: NowAttributes.ContentState {
        NowAttributes.ContentState(
            commitmentTitle: "Morning reading",
            slotTimeText: "9:00 AM – 11:00 AM",
            commitmentId: UUID(),
            slotId: UUID(),
            windowStart: Date.now,
            windowEnd: Date.now.addingTimeInterval(2 * 3600),
            encouragementText: "Just do a little bit",
            checkInCount: 1,
            targetCount: 3
        )
    }
}

#Preview("Live Activity", as: .content, using: NowAttributes()) {
    NowLiveActivity()
} contentStates: {
    NowAttributes.ContentState.withCommitment
}
