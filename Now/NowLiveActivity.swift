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
                context.state.hasCurrentCommitment,
                "Live Activity must only be started when there is a current commitment (commitmentTitle and slotTimeText must be set)."
            )
            return VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.commitmentTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.slotTimeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Link(destination: doneURL(commitmentId: context.state.commitmentId)) {
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
                context.state.hasCurrentCommitment,
                "Live Activity must only be started when there is a current commitment (commitmentTitle and slotTimeText must be set)."
            )
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.commitmentTitle)
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
                        Link(destination: doneURL(commitmentId: context.state.commitmentId)) {
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
                Text(context.state.commitmentTitle)
                    .font(.caption)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "sparkles")
            }
            .keylineTint(Color.accentColor)
        }
    }

    // MARK: - URL helpers

    private func doneURL(commitmentId: String) -> URL {
        var components = URLComponents()
        components.scheme = "wilgo"
        components.host = "done"
        components.queryItems = [URLQueryItem(name: "commitmentId", value: commitmentId)]
        return components.url ?? URL(string: "wilgo://done")!
    }

}

extension NowAttributes.ContentState {
    fileprivate static var withCommitment: NowAttributes.ContentState {
        NowAttributes.ContentState(
            commitmentTitle: "Morning reading",
            slotTimeText: "9:00 AM – 11:00 AM",
            commitmentId: "",
            slotId: "",
            secondaryTitles: ["Walk dog", "Email inbox"]
        )
    }
}

#Preview("Live Activity", as: .content, using: NowAttributes()) {
    NowLiveActivity()
} contentStates: {
    NowAttributes.ContentState.withCommitment
}
