//
//  NowLiveActivity.swift
//  Now
//

import ActivityKit
import SwiftUI
import WidgetKit

struct NowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowAttributes.self) { context in
            let _ = precondition(
                context.state.hasCurrentHabit,
                "Live Activity must only be started when there is a current habit (habitTitle and slotTimeText must be set)."
            )
            return HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.habitTitle)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.slotTimeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .activityBackgroundTint(Color(.systemFill))
            .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            let _ = precondition(
                context.state.hasCurrentHabit,
                "Live Activity must only be started when there is a current habit (habitTitle and slotTimeText must be set)."
            )
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.habitTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.slotTimeText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .font(.caption)
            } compactTrailing: {
                Text(context.state.habitTitle)
                    .font(.caption)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "sparkles")
            }
            .keylineTint(Color.accentColor)
        }
    }
}

extension NowAttributes.ContentState {
    fileprivate static var withHabit: NowAttributes.ContentState {
        NowAttributes.ContentState(
            habitTitle: "Morning reading",
            slotTimeText: "9:00 AM – 11:00 AM"
        )
    }
}

#Preview("Live Activity", as: .content, using: NowAttributes()) {
    NowLiveActivity()
} contentStates: {
    NowAttributes.ContentState.withHabit
}
