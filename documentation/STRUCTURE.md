# Wilgo app structure

Code is organized **by feature/screen**, with shared domain code in `Shared/`:

| Folder        | Purpose                                | Example contents                                     |
| ------------- | -------------------------------------- | ---------------------------------------------------- |
| **App**       | App entry point / root wiring          | `WilgoApp.swift` (`@main`, `ModelContainer`)         |
| **Features/** | User-facing screens grouped by feature | `Features/Habits`, `Features/Stage`, `Features/Root` |
| **Shared/**   | Cross-feature domain code              | `Shared/Models`, `Shared/Scheduling`                 |

- **Assets, Info.plist** stay at the root of `Wilgo/`.
- Xcode uses a **synchronized root group** for `Wilgo`, so new files and folders under `Wilgo/` are picked up automatically; no need to add them by hand in the project.

## Current feature layout

- **Features/Habits**
  - `ContentView.swift` – habits list screen (CRUD, navigation into habit details later).
  - `AddHabitView.swift` – sheet/screen for creating a new habit.

- **Features/Stage**
  - `StageView.swift` – “Stage” dashboard that highlights the in-window habit and upcoming habits.

- **Features/Root**
  - `MainTabView.swift` – top-level tab navigation that wires `StageView` and `ContentView` together.

- **Shared/Models**
  - `Habit.swift` – core habit model (SwiftData).
  - `Item.swift` – template model (kept for now; safe to remove when unused).

- **Shared/Scheduling**
  - `PhaseEngine.swift` – phase/pressure logic and UI styling used by Stage (and later notifications).
  - `HabitScheduling.swift` – reusable “today” time-window helpers for habits.

## iOS/Swift conventions (feature-first)

- Group code by **feature or screen** (`Habits`, `Stage`, `Settings`, `Onboarding`, etc.).
- Keep cross-cutting code in **Shared** (models, utilities, services).
- Within a large feature, you can still create subfolders like `Views/`, `ViewModels/`, `Logic/` for extra structure.

This layout is a common, modern pattern in SwiftUI/iOS apps, and scales better as you add more screens and logic.
