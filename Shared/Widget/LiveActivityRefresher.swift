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
            "  actions: end=\(actions.toEnd.count) update=\(actions.toUpdate.count) request=\(actions.toRequest.count)"
        )

        // Diagnostic (anomaly hunt, 2026-07-08 run): a card was ended + re-requested while its
        // slot still had a same-time planned occurrence — the diff failed to match a firing it
        // seemingly should have. When that happens again, this prints both sides at full
        // precision to convict or clear the sub-second-windowStart theory and name the
        // differing field. Remove with the other diagnostics once the design is validated.
        for activity in seated where actions.toEnd.contains(activity.id) {
            let s = activity.content.state
            for item in planned where item.state.slotId == s.slotId {
                let p = item.state
                print(
                    "  end-diagnostic \(s.commitmentTitle): windowStart seated=\(s.windowStart.timeIntervalSince1970) planned=\(p.windowStart.timeIntervalSince1970) | windowEnd seated=\(s.windowEnd.timeIntervalSince1970) planned=\(p.windowEnd.timeIntervalSince1970) | stateEqual=\(p == s) title=\(p.commitmentTitle == s.commitmentTitle) slotTime=\(p.slotTimeText == s.slotTimeText) enc=\(p.encouragementText == s.encouragementText) counts=\(p.checkInCount == s.checkInCount && p.targetCount == s.targetCount)"
                )
            }
        }

        // Phase order is load-bearing: ends run first because they free seats the requests
        // will need; requests run last, nearest-first, evicting the farthest live pending
        // on capacity.
        await endOrphans(actions.toEnd, in: seated)
        await updateStartedCards(actions.toUpdate, in: seated)
        await requestNearestFirst(actions.toRequest, now: now)
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
    /// Candidates are read live from `Activity.activities` at each capacity throw — the actual
    /// seated world, no bookkeeping. The strictly-later guard automatically excludes everything
    /// that must not be evicted: a *started* card's `windowStart` is in the past (and evicting a
    /// visible card would be user-facing destruction), and anything requested *earlier in this
    /// run* is nearer than the current item (nearest-first order). So a passing candidate is
    /// always a pending left over from a previous run.
    ///
    /// `evictedIds` guards termination. In the expected case it changes nothing: `end()` flips
    /// the candidate out of `.pending` and the filter drops it. But that flip's timing is
    /// undocumented (ActivityKit state lives in a system daemon and propagates back
    /// asynchronously — the update-on-pending spike showed this corner misbehaving), and if it
    /// lagged, the retry would re-pick the same candidate forever: an unbounded loop on the main
    /// actor that also blocks every future reconcile queued behind this one. Excluding by id
    /// makes termination provable from our own code — each capacity retry consumes one distinct
    /// candidate, so retries ≤ pending count, then the guard fails and the loop stops. Worst
    /// case under a lagging flip is evicting one pending more than needed, which the next
    /// reconcile re-requests (its firing is still planned): self-healing, unlike a hang.
    ///
    /// Termination, exhaustively: every retry-loop pass either succeeds (break), hits a
    /// non-capacity error (break requestLoop), fails the eviction guard (break requestLoop), or
    /// grows `evictedIds` by one — so the whole function is bounded by items × pendings
    /// iterations, with no timing assumptions. (Our own successful requests do add pendings
    /// mid-loop, but nearest-first order keeps them earlier than the current item, so the
    /// strictly-later guard can never select them.)
    ///
    /// Stale cards are never candidates and never need to be: stale ⟺ window ended (staleDate
    /// is set to the occurrence end) ⟹ absent from the plan (`end > now` filter) ⟹ orphaned and
    /// ended in phase 1 — their seats are already free before the first request runs.
    @MainActor
    private static func requestNearestFirst(_ items: [PlannedLiveActivity], now: Date) async {
        var evictedIds: Set<String> = []
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
                    let candidate = Activity<NowAttributes>.activities
                        .filter { $0.activityState == .pending && !evictedIds.contains($0.id) }
                        .max(by: { $0.content.state.windowPrecedes($1.content.state) })
                    guard let candidate,
                        candidate.content.state.windowStart > (item.scheduledStart ?? now)
                    else {
                        print(
                            "  capacity (\(authError)) and no evictable pending later than \(item.state.commitmentTitle) — stopping"
                        )
                        break requestLoop  // break the named outer loop
                    }
                    evictedIds.insert(candidate.id)
                    print(
                        "  evicting \(candidate.content.state.commitmentTitle) start=\(candidate.content.state.windowStart) to seat \(item.state.commitmentTitle)"
                    )
                    await candidate.end(nil, dismissalPolicy: .immediate)
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
