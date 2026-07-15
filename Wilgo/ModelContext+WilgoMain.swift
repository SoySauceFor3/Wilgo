import Foundation
import SwiftData

/// The app process's canonical context — read AND write through this, never a fresh
/// `ModelContext(container)`: a fresh context can't see another context's unsaved changes
/// (e.g. a view mutation awaiting autosave), so it can act on a stale snapshot. `mainContext`
/// is the same object graph `@Query` drives the views with, so readers here see exactly what
/// the user sees. The WidgetExtension runs in a separate process and must build its own
/// container over the shared store instead — this accessor deliberately doesn't compile there
/// (`WilgoApp` is app-target-only).
/// Prioritize using this, unless a separate context is absolutely necessary.
extension ModelContext {
    @MainActor
    static var wilgoMain: ModelContext {
        WilgoApp.sharedModelContainer.mainContext
    }
}
