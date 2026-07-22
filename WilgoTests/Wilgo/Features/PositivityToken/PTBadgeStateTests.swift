import Foundation
import Testing
@testable import Wilgo

/// Exercises `PTBadgeState`: the PT-tab badge state machine that decides whether "new"
/// positivity-token capacity exists (`hasNewCapacity`) and persists the last-seen count
/// across launches. All logic is pure in-memory arithmetic over an injectable `UserDefaults`,
/// so each test gets its own private suite to stay isolated from the parallel runner.
@Suite
struct PTBadgeStateTests {
    /// A private, empty UserDefaults so nothing leaks to `.standard` or across tests.
    private func makeState(seenValue: Int? = nil) -> (PTBadgeState, UserDefaults, String) {
        let suiteName = "test.PTBadge.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        if let seenValue {
            defaults.set(seenValue, forKey: "PTBadge.capacitySeenByUser")
        }
        return (PTBadgeState(defaults: defaults), defaults, suiteName)
    }

    @Test("fresh state: no persisted value → seen is 0, capacity 0, no new capacity")
    func freshState() {
        let (state, _, suiteName) = makeState()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        #expect(state.capacitySeenByUser == 0)
        #expect(state.currentCapacity == 0)
        #expect(state.hasNewCapacity == false)
    }

    @Test("hasNewCapacity is true once current capacity exceeds the seen count")
    func newCapacityAppears() {
        let (state, _, suiteName) = makeState()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        state.update(currentCapacity: 3)
        #expect(state.hasNewCapacity == true)
    }

    @Test("hasNewCapacity is false when current capacity equals the seen count")
    func equalCapacityIsNotNew() {
        let (state, _, suiteName) = makeState(seenValue: 5)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        state.update(currentCapacity: 5)
        #expect(state.hasNewCapacity == false)
    }

    @Test("hasNewCapacity is false when current capacity is below the seen count")
    func belowSeenIsNotNew() {
        let (state, _, suiteName) = makeState(seenValue: 5)
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        state.update(currentCapacity: 2)
        #expect(state.hasNewCapacity == false)
    }

    @Test("markAsSeen catches the badge up to the current capacity, clearing 'new'")
    func markAsSeenClearsBadge() {
        let (state, _, suiteName) = makeState()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        state.update(currentCapacity: 4)
        #expect(state.hasNewCapacity == true)

        state.markAsSeen()
        #expect(state.capacitySeenByUser == 4)
        #expect(state.hasNewCapacity == false)
    }

    @Test("markAsSeen persists the seen count to the injected store")
    func markAsSeenPersists() {
        let (state, defaults, suiteName) = makeState()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        state.update(currentCapacity: 7)
        state.markAsSeen()

        #expect(defaults.integer(forKey: "PTBadge.capacitySeenByUser") == 7)
    }

    @Test("a persisted seen count is restored on init and suppresses stale 'new' badges")
    func persistedSeenCountSurvivesRestart() throws {
        let suiteName = "test.PTBadge.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        // First session: mark capacity 6 as seen.
        let first = PTBadgeState(defaults: defaults)
        first.update(currentCapacity: 6)
        first.markAsSeen()

        // Simulate relaunch: a new instance reading the same store.
        let second = PTBadgeState(defaults: defaults)
        #expect(second.capacitySeenByUser == 6)

        // Capacity unchanged at relaunch → no new badge.
        second.update(currentCapacity: 6)
        #expect(second.hasNewCapacity == false)

        // A later mint pushes capacity past what was seen → badge returns.
        second.update(currentCapacity: 8)
        #expect(second.hasNewCapacity == true)
    }
}
