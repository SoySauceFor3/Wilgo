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

        if current.isEmpty {
            for activity in Activity<NowAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let contentState = makeContentState(from: current)
        let staleDate = staleDate(for: current.first, now: now)

        let content = ActivityContent(state: contentState, staleDate: staleDate)
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

    }

    /// When the Live Activity content becomes out of date. MUST be in the future — a past staleDate
    /// makes iOS mark the activity `.stale` the moment it is requested and refuse to present it.
    ///
    /// The current slot's end can be in the past — e.g. a whole-day slot whose time-of-day is
    /// early morning, or any slot that already ended earlier today — so we only use it when it is
    /// still in the future, otherwise we fall back to the next psych-day boundary. Returns nil (never
    /// auto-stale) when there is no current commitment.
    static func staleDate(for current: CommitmentAndSlot.WithBehind?, now: Date) -> Date? {
        guard let current else { return nil }
        return current.slots[0].endTime(onDayStarting: Time.startOfDay(for: now))
    }

    // precondition: currentSlots is not empty
    static func makeContentState(
        from currentSlots: [CommitmentAndSlot.WithBehind]
    ) -> NowAttributes.ContentState {
        let (commitment, slots, _) = currentSlots.first!
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
