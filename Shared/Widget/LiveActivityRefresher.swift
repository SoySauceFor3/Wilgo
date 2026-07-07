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
        let seated = seatedActivities()
        logReconcileInputs(seated: seated, planned: planned, now: now)

        let actions = LiveActivityPlanner.diff(
            existing: seated.map {
                ExistingActivity(
                    id: $0.id, state: $0.content.state, isPending: $0.activityState == .pending)
            },
            planned: planned
        )
        print(
            "  actions: end=\(actions.toEnd.count) update=\(actions.toUpdate.count) request=\(actions.toRequest.count) keptPending=\(actions.keptPendings.count)"
        )

        // Phase order is load-bearing: ends run first because they free seats the requests
        // will need; requests run last, nearest-first, evicting kept pendings on capacity.
        await endOrphans(actions.toEnd, in: seated)
        await updateStartedCards(actions.toUpdate, in: seated)
        await requestNearestFirst(
            actions.toRequest, evicting: actions.keptPendings, in: seated, now: now)
    }

    // MARK: - Inputs

    /// Only these states occupy one of the scarce activity slots and can display content.
    /// Ended/dismissed activities linger in `activities` until the system prunes them;
    /// letting one match the plan would "keep" a card that no longer displays, silently
    /// suppressing the re-request of its replacement.
    @MainActor
    private static func seatedActivities() -> [Activity<NowAttributes>] {
        Activity<NowAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .stale
                || $0.activityState == .pending  // remove .ended and .dismissed
        }
    }

    /// Diagnostic for on-device verification of the reconcile (queue cap, pending
    /// diffability, seat composition). Cheap and print-based per house style; remove or
    /// demote once the scheduled-LA design is validated in dogfood.
    @MainActor
    private static func logReconcileInputs(
        seated: [Activity<NowAttributes>], planned: [PlannedLiveActivity], now: Date
    ) {
        print(
            "LiveActivityRefresher.refresh() @\(now): \(seated.count) seated, \(planned.count) planned"
        )
        for activity in seated {
            let s = activity.content.state
            print(
                "  seated[\(activity.activityState)] \(s.commitmentTitle) start=\(s.windowStart) end=\(s.windowEnd) id=\(String(activity.id.prefix(8)))"
            )
        }
        for item in planned {
            print(
                "  planned \(item.state.commitmentTitle) start=\(item.state.windowStart) scheduled=\(String(describing: item.scheduledStart != nil))"
            )
        }
    }

    // MARK: - Phases

    @MainActor
    private static func endOrphans(_ ids: [String], in seated: [Activity<NowAttributes>]) async {
        for activity in seated where ids.contains(activity.id) {
            print(
                "  ending \(activity.content.state.commitmentTitle) id=\(String(activity.id.prefix(8)))"
            )
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @MainActor
    private static func updateStartedCards(
        _ items: [(id: String, item: PlannedLiveActivity)], in seated: [Activity<NowAttributes>]
    ) async {
        for (id, item) in items {
            guard let activity = seated.first(where: { $0.id == id }) else { continue }
            print("  updating \(item.state.commitmentTitle) id=\(String(id.prefix(8)))")
            await activity.update(content(for: item))
        }
    }

    /// Nearest-first so the scarce system queue (undocumented cap, ~5 observed) is spent on
    /// the most imminent occurrences. On a capacity throw, evict the farthest-future kept
    /// pending card (invisible, so eviction is free) and retry — without this, far-future
    /// pendings seated on an earlier wake would permanently starve newly current occurrences:
    /// iOS admission is a pure counter (first-come-first-served), so the "keep the nearest K"
    /// policy has to be implemented here. Eviction happens only on capacity errors: a
    /// capacity error proves requests are legal in this context, so the retry can succeed.
    /// Any other error (.visibility from a background wake, .denied) stops the loop without
    /// evicting — ending a pending we cannot replace would only destroy scheduled coverage.
    ///
    /// The candidate list (`keptPendings`) looks narrow but is provably complete — nothing else
    /// seated can ever be the right eviction: a *started* card's `windowStart` is in the past, so
    /// it can never pass the strictly-later guard (and evicting a visible card would be
    /// user-facing destruction); and anything requested *earlier in this run* is nearer than the
    /// current item (nearest-first order), so evicting it would trade a nearer card for a farther
    /// one. Only pendings left over from previous runs can be farther than what we're seating.
    @MainActor
    private static func requestNearestFirst(
        _ items: [PlannedLiveActivity],
        evicting keptPendings: [(id: String, state: NowAttributes.ContentState)],
        in seated: [Activity<NowAttributes>],
        now: Date
    ) async {
        var evictablePendings = keptPendings.sorted { $0.state.windowStart > $1.state.windowStart }
        requestLoop: for item in items.sorted(by: {
            ($0.scheduledStart ?? now) < ($1.scheduledStart ?? now)
        }) {
            while true {
                do {
                    try request(item)
                    print(
                        "  requested \(item.state.commitmentTitle) start=\(String(describing: item.scheduledStart ?? now)) scheduled=\(item.scheduledStart != nil)"
                    )
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
                        print(
                            "  capacity (\(authError)) and no evictable pending later than \(item.state.commitmentTitle) — stopping"
                        )
                        break requestLoop  // break the named outer loop
                    }
                    evictablePendings.removeFirst()
                    print(
                        "  evicting \(candidate.state.commitmentTitle) start=\(candidate.state.windowStart) to seat \(item.state.commitmentTitle)"
                    )
                    if let pending = seated.first(where: { $0.id == candidate.id }) {
                        await pending.end(nil, dismissalPolicy: .immediate)
                    }
                    // retry the same item
                } catch {
                    print("LiveActivityRefresher.refresh() - request stopped: \(error)")
                    break requestLoop  // break the named outer loop
                }
            }
        }
    }

    // MARK: - ActivityKit calls

    private static func content(for item: PlannedLiveActivity) -> ActivityContent<
        NowAttributes.ContentState
    > {
        ActivityContent(
            state: item.state,
            staleDate: item.staleDate,
            relevanceScore: item.relevanceScore
        )
    }

    /// Two request paths, mirroring the plan's own split — this is behavior, not convenience:
    /// only the scheduled overload can make a card appear *later* (the system holds it and
    /// starts it even if the app is dead — the whole point of this design), and Apple makes its
    /// alert configuration mandatory (an app-scheduled card appearing while the user is outside
    /// the app must announce itself). The plain overload shows the card *now, silently* — right
    /// for already-open occurrences, which get (re)created during quiet repairs where an alert
    /// would ding on every fix. Funneling immediate cards through the scheduled overload with a
    /// past start date would both force that ding and rely on unspecified API behavior.
    @MainActor
    private static func request(_ item: PlannedLiveActivity) throws {
        if let start = item.scheduledStart {
            // Scheduled start: the system starts the card at `start` even if the app is dead
            // by then. The alert configuration is mandatory for scheduled requests.
            _ = try Activity.request(
                attributes: NowAttributes(),
                content: content(for: item),
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
                content: content(for: item),
                pushType: nil
            )
        }
    }
}
