import Testing

@testable import Wilgo

@Suite("StageViewModel lifetime", .serialized)
final class StageViewModelLifetimeTests {
    @Test("scheduled timer does not retain the view model")
    @MainActor
    func scheduledTimerDoesNotRetainViewModel() async {
        // `weakViewModel` lets the test observe whether ARC deallocated the object.
        // A weak reference does not keep the `StageViewModel` alive.
        weak var weakViewModel: StageViewModel?

        // `viewModel` is the only strong reference this test intentionally owns.
        // As long as this variable is non-nil, the object must stay alive.
        var viewModel: StageViewModel? = StageViewModel()

        // Point the weak reference at the same object so we can inspect it later
        // after releasing the strong reference.
        weakViewModel = viewModel

        // `refresh` recomputes Stage lists and schedules the internal timer task.
        // This is the behavior under test: the scheduled task must not retain the view model.
        viewModel?.refresh(commitments: [])

        // Give the newly-created timer task a chance to start before we release `viewModel`.
        // This makes the test exercise the task's capture behavior, not just object creation.
        await Task.yield()

        // Release the test's only strong reference. If the timer task accidentally
        // holds `self` strongly while sleeping, the object will not deallocate here.
        viewModel = nil

        // Weak references automatically become nil after their object is deallocated.
        // If this is still non-nil, some other owner is retaining the view model.
        #expect(weakViewModel == nil)
    }
}
