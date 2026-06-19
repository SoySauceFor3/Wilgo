import ActivityKit
import Foundation
import SwiftData

/// Recomputes the current commitment and updates / starts / ends the Now Live Activity to match.
///
/// Lives in `Shared/Widget` (compiled into both the app and the WidgetExtension targets) so that a
/// `LiveActivityIntent`'s `perform()` — which always runs in the **app process** — can drive the Live
/// Activity directly, without the old Darwin-notification round-trip. The caller supplies the
/// `ModelContext` so this helper has no dependency on app-only singletons: the app passes its
/// `mainContext`; an intent passes the context it already opened for its write.
enum LiveActivityRefresher {
    @MainActor
    static func refresh(context: ModelContext, now: Date? = nil) async {
        let now = now ?? Time.now()
        let commitments = (try? context.fetch(.activeOnly)) ?? []
        let current = CommitmentAndSlot.currentWithBehind(commitments: commitments, now: now)

        let contentState = makeContentState(from: current)
        let staleDate = current.first.map { $0.slots[0].endToday }

        if let state = contentState, state.hasCurrentCommitment {
            let content = ActivityContent(state: state, staleDate: staleDate)
            if let activity = Activity<NowAttributes>.activities.first {
                await activity.update(content)
            } else {
                do {
                    _ = try Activity.request(
                        attributes: NowAttributes(),
                        content: content,
                        pushType: nil
                    )
                } catch {
                    print("LiveActivityRefresher.refresh() - Activity.request failed: \(error)")
                }
            }
        } else {
            for activity in Activity<NowAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    static func makeContentState(
        from currentSlots: [CommitmentAndSlot.WithBehind]
    ) -> NowAttributes.ContentState? {
        guard let (commitment, slots, _) = currentSlots.first else { return nil }
        let secondaryTitles = currentSlots.dropFirst().map(\.commitment.title)
        let encouragementText = commitment.encouragements.randomElement()
        return NowAttributes.ContentState(
            commitmentTitle: commitment.title,
            slotTimeText: slots[0].timeOfDayText,
            commitmentId: commitment.id,
            slotId: slots[0].id,
            secondaryTitles: secondaryTitles,
            encouragementText: encouragementText
        )
    }
}
