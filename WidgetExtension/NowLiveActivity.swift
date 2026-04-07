//
//  NowLiveActivity.swift
//  Now
//

import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Secondary titles (one line)

/// Character budget for the secondary line when not passed explicitly (no font metrics in widgets).
private enum SecondaryTitlesLineBudget {
    static let defaultMaxLength = 120
}

/// Joins non-primary commitment titles with `", "`, fitting as many full titles as possible into
/// `maxLength` (Swift character count). Appends ` +n more` when some titles are omitted. If a single
/// title exceeds the budget, it is truncated so the suffix can still appear when needed.
func formatSecondaryTitlesLine(
    titles: [String],
    maxLength: Int = SecondaryTitlesLineBudget.defaultMaxLength
) -> String {
    let parts =
        titles
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !parts.isEmpty, maxLength > 0 else { return "" }

    let n = parts.count

    for k in stride(from: n, through: 1, by: -1) {
        let head = parts.prefix(k).joined(separator: ", ")
        let suffix = (k == n) ? "" : " +\(n - k) more"

        if head.count + suffix.count <= maxLength {
            return head + suffix
        }

        if k == 1 {
            let room = maxLength - suffix.count
            guard room > 0 else { continue }
            return String(head.prefix(room)) + suffix
        }
    }

    let fallback = "+\(n) more"
    if fallback.count <= maxLength {
        return fallback
    }
    return String(fallback.prefix(maxLength))
}

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
    let destination: URL
    var compact: Bool = false

    var body: some View {
        Link(destination: destination) {
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

private struct SecondaryCommitmentsLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "list.bullet")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct CompactTrailingTitle: View {
    let title: String
    let extraCount: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            if extraCount > 0 {
                Text("+\(extraCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.88)))
                    .accessibilityLabel("\(extraCount) more current")
            }
        }
    }
}

struct NowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowAttributes.self) { context in
            let _ = precondition(
                context.state.hasCurrentCommitment,
                "Live Activity must only be started when there is a current commitment (commitmentTitle and slotTimeText must be set)."
            )
            let secondaryLine = formatSecondaryTitlesLine(titles: context.state.secondaryTitles)

            return HStack(alignment: .top, spacing: 12) {
                LiveActivitySparkleIcon(diameter: 40)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(context.state.commitmentTitle)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(context.state.slotTimeText)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            if let encouragement = context.state.encouragementText {
                                Text(encouragement)
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                                    .italic()
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        DoneCapsuleLink(
                            destination: doneURL(commitmentId: context.state.commitmentId))
                    }
                    if !secondaryLine.isEmpty {
                        SecondaryCommitmentsLine(text: secondaryLine)
                    }
                }
            }
            .padding(.vertical, 6)
            .activityBackgroundTint(Color(.systemFill))
            .activitySystemActionForegroundColor(Color.primary)
        } dynamicIsland: { context in
            let _ = precondition(
                context.state.hasCurrentCommitment,
                "Live Activity must only be started when there is a current commitment (commitmentTitle and slotTimeText must be set)."
            )
            let secondaryLine = formatSecondaryTitlesLine(titles: context.state.secondaryTitles)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivitySparkleIcon(diameter: 28)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.state.commitmentTitle)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.slotTimeText)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        if let encouragement = context.state.encouragementText {
                            Text(encouragement)
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                                .italic()
                                .lineLimit(1)
                        }
                        if !secondaryLine.isEmpty {
                            SecondaryCommitmentsLine(text: secondaryLine)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Spacer(minLength: 0)
                        DoneCapsuleLink(
                            destination: doneURL(commitmentId: context.state.commitmentId),
                            compact: true
                        )
                        Spacer(minLength: 0)
                    }
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            } compactTrailing: {
                CompactTrailingTitle(
                    title: context.state.commitmentTitle,
                    extraCount: context.state.secondaryTitles.count
                )
            } minimal: {
                Image(systemName: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(.tint)
            }
            .keylineTint(Color.accentColor)
        }
    }

    // MARK: - URL helpers

    private func doneURL(commitmentId: UUID) -> URL {
        var components = URLComponents()
        components.scheme = "wilgo"
        components.host = "done"
        components.queryItems = [URLQueryItem(name: "commitmentId", value: commitmentId.uuidString)]
        return components.url ?? URL(string: "wilgo://done")!
    }

}

extension NowAttributes.ContentState {
    fileprivate static var withCommitment: NowAttributes.ContentState {
        NowAttributes.ContentState(
            commitmentTitle: "Morning reading",
            slotTimeText: "9:00 AM – 11:00 AM",
            commitmentId: UUID(),
            slotId: UUID(),
            secondaryTitles: ["Walk dog", "Email inbox"],
            encouragementText: "Just do a little bit"
        )
    }
}

#Preview("Live Activity", as: .content, using: NowAttributes()) {
    NowLiveActivity()
} contentStates: {
    NowAttributes.ContentState.withCommitment
}
