import ActivityKit
import Foundation
import SwiftData

/// Reconciles the set of Wilgo Live Activities (live + pending-scheduled) against the pure plan
/// from `LiveActivityPlanner`.
///
/// Lives in `Shared/Widget` (compiled into both the app and the WidgetExtension targets) so that a
/// `LiveActivityIntent`'s `perform()` — which always runs in the **app process** — can drive the Live
/// Activity directly. The caller supplies the `ModelContext`: the app passes its `mainContext`; an
/// intent passes the context it already opened for its write.
///
/// Legal calling contexts for *requesting*: foreground, or a `LiveActivityIntent` `perform()`.
/// From the background (BGAppRefreshTask) requests throw `.visibility` and are swallowed — the BG
/// task degrades to a janitor that can still *end* stale cards. That is by design for this scope
/// (see documentation/ScheduledLiveActivity-implementation.md: BG work is deferred).
enum LiveActivityRefresher {
    @MainActor
    static func refresh(context: ModelContext, now: Date? = nil) async {
        let now = now ?? Time.now()
        let commitments = (try? context.fetch(.activeOnly)) ?? []
        let planned = LiveActivityPlanner.plan(commitments: commitments, now: now)

        // Only these states occupy one of the scarce activity slots and can display content.
        // Ended/dismissed activities linger in `activities` until the system prunes them;
        // letting one match the plan would "keep" a card that no longer displays, silently
        // suppressing the re-request of its replacement.
        let seated = Activity<NowAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
                || $0.activityState == .pending
        }
        let actions = LiveActivityPlanner.diff(
            existing: seated.map {
                ExistingActivity(
                    id: $0.id, state: $0.content.state, isPending: $0.activityState == .pending)
            },
            planned: planned
        )

        for activity in seated where actions.toEnd.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        for (id, item) in actions.toUpdate {
            guard let activity = seated.first(where: { $0.id == id }) else { continue }
            await activity.update(
                ActivityContent(
                    state: item.state,
                    staleDate: item.staleDate,
                    relevanceScore: item.relevanceScore
                )
            )
        }

        // Nearest-first so the scarce system queue (undocumented cap, ~5 observed) is spent on
        // the most imminent occurrences. On a capacity throw, evict the farthest-future kept
        // pending card (invisible, so eviction is free) and retry — without this, far-future
        // pendings seated on an earlier wake permanently starve newly current occurrences: iOS
        // admission is a pure counter (first-come-first-served), so the "keep the nearest K"
        // policy has to be implemented here. Eviction happens only on capacity errors: a
        // capacity error proves requests are legal in this context, so the retry can succeed.
        // Any other error (.visibility from a background wake, .denied) stops the loop without
        // evicting — ending a pending we cannot replace would only destroy scheduled coverage.
        var evictablePendings = actions.keptPendings.sorted { $0.state.windowStart > $1.state.windowStart }
        requestLoop: for item in actions.toRequest.sorted(by: { ($0.scheduledStart ?? now) < ($1.scheduledStart ?? now) }) {
            let content = ActivityContent(
                state: item.state,
                staleDate: item.staleDate,
                relevanceScore: item.relevanceScore
            )
            while true {
                do {
                    if let start = item.scheduledStart {
                        // Scheduled start: the system starts the card at `start` even if the app
                        // is dead by then. The alert configuration is mandatory for scheduled
                        // requests.
                        _ = try Activity.request(
                            attributes: NowAttributes(),
                            content: content,
                            pushType: nil,
                            style: .standard,
                            alertConfiguration: AlertConfiguration(
                                title: "\(item.state.commitmentTitle)",
                                body: "\(item.state.slotTimeText)",
                                sound: .default
                            ),
                            start: start
                        )
                    } else {
                        _ = try Activity.request(
                            attributes: NowAttributes(),
                            content: content,
                            pushType: nil
                        )
                    }
                    break
                } catch let authError as ActivityAuthorizationError
                    where authError == .targetMaximumExceeded || authError == .globalMaximumExceeded
                {
                    // Evict only a pending strictly LESS imminent than what we're requesting —
                    // evicting a nearer one would be self-defeating, and not evicting on ties
                    // prevents equally-urgent cards from oscillating across reconciles.
                    guard let candidate = evictablePendings.first,
                        candidate.state.windowStart > (item.scheduledStart ?? now)
                    else {
                        break requestLoop
                    }
                    evictablePendings.removeFirst()
                    if let pending = seated.first(where: { $0.id == candidate.id }) {
                        await pending.end(nil, dismissalPolicy: .immediate)
                    }
                    // retry the same item
                } catch {
                    print("LiveActivityRefresher.refresh() - request stopped: \(error)")
                    break requestLoop
                }
            }
        }
    }
}
