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
            return VStack(spacing: 8) {
                HStack(spacing: 12) {
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

                HStack(spacing: 8) {
                    Link(destination: doneURL(habitId: context.state.habitId)) {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 8)
                            )
                            .foregroundStyle(.green)
                    }
                }
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
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Link(destination: doneURL(habitId: context.state.habitId)) {
                            Label("Done", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(
                                    Color.green.opacity(0.2), in: RoundedRectangle(cornerRadius: 8)
                                )
                                .foregroundStyle(.green)
                        }
                    }
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

    // MARK: - URL helpers

    private func doneURL(habitId: String) -> URL {
        var components = URLComponents()
        components.scheme = "wilgo"
        components.host = "done"
        components.queryItems = [URLQueryItem(name: "habitId", value: habitId)]
        return components.url ?? URL(string: "wilgo://done")!
    }

}

extension NowAttributes.ContentState {
    fileprivate static var withHabit: NowAttributes.ContentState {
        NowAttributes.ContentState(
            habitTitle: "Morning reading",
            slotTimeText: "9:00 AM – 11:00 AM",
            habitId: "",
            slotId: ""
        )
    }
}

#Preview("Live Activity", as: .content, using: NowAttributes()) {
    NowLiveActivity()
} contentStates: {
    NowAttributes.ContentState.withHabit
}
