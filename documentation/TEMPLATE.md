# Commitment Tags — Implementation Plan

**PRD:** [title of the linked url](www.link.com)  
**Tracking:** [title of the linked url](www.link2.com)
**Tag**: #tag

---

## Context

Summarize the major decisions in PRD.

---

## Architecture Summary

Explain the overall solution and how it works.

---

## Design Decisions

### {Title1}

**Decision:** what decisions.

**Why not {alternatives}?** Answer

**Risk: what risks there is**. Mitigations: answer.

Add reasonings if needs

### {Title2}

Add more decisions if needed.

---

## Major Model Changes

| Entity                         | Change          |
| ------------------------------ | --------------- |
| **New:** `path/to/fileA.swift` | explain changes |
| `path/to/fileB.swift`          | explain changes |

---

Add code snippet here if needed

## Commit Plan

It is fine if you want to group some commits into phases.

---

### Phase n - summary of the phase

The goal of the phase is xxxxx. It composes of a few steps: step1, step2, step3...

#### Commit n — commit msg (i.e. summary)

**Create:** `Shared/Models/Tag.swift`

```swift
@Model final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var displayOrder: Int
    @Relationship(deleteRule: .nullify, inverse: \Commitment.tags)
    var commitments: [Commitment] = []  // nullify: deleting a Commitment removes it from this array; Tag survives

    init(name: String, displayOrder: Int) {
        self.id = UUID()
        self.name = name
        self.displayOrder = displayOrder
    }
}
```

**Modify:** `Shared/Models/Commitment.swift`  
Add after `encouragements`:

```swift
@Relationship(deleteRule: .nullify, inverse: \Tag.commitments)
var tags: [Tag] = []  // nullify: deleting a Tag removes it from this array; Commitment survives
```

**Modify:** `Wilgo/WilgoApp.swift` — add `Tag.self` to `Schema([...])`.

**Modify (preview containers only):** `ListCommitmentView.swift`, `AddCommitView.swift`, `EditCommitmentView.swift`, `MainTabView.swift` — add `Tag.self` to `#Preview` `ModelContainer` schemas.

**Modify (test schemas):** Add `Tag.self` to `Schema([...])` in all `makeContainer()` functions:

- `WilgoTests/Commitment/GracePeriodTests.swift`
- `WilgoTests/Commitment/CommitmentSlotsQueries.swift`
- `WilgoTests/Commitment/CommitmentStageSnoozeTests.swift`
- `WilgoTests/FinishedCycleReport/FinishedCycleReportBuilderTests.swift`
- `WilgoTests/PositivityToken/PositivityTokenModelTests.swift`
- `WilgoTests/PositivityToken/PositivityTokenMintingTests.swift`
- `WilgoTests/PositivityToken/PositivityTokenUndoTests.swift`
- `WilgoTests/Slot/SlotSnoozeCreateTests.swift`
- `WilgoTests/Slot/SlotPsychDayTests.swift`
- `WilgoTests/Slot/SlotIsSnoozedTests.swift`
- `WilgoTests/Slot/SlotPsychDayTests.swift`

**Create:** `WilgoTests/Tag/TagModelTests.swift`  
Tests:

- Tag persists with correct name and displayOrder
- `Commitment.tags` defaults to `[]`
- Adding a Tag to `commitment.tags` round-trips through save/fetch
- Same Tag can belong to two commitments (many-to-many)
- Deleting a Commitment: Tag survives, `tag.commitments` loses the entry
- Deleting a Tag: Commitment survives, `commitment.tags` loses the entry

**Manual verification (critical):** Launch app on iPhone 17 simulator (UDID `4D4E7E2F-1CE5-4697-A734-85AB68DC55D4`). App must launch without crash. Open commitments list, add a commitment. Verify no errors. All subsequent commits depend on this migration succeeding.

---

## Critical Files

| File                             | Role                    |
| -------------------------------- | ----------------------- |
| `Shared/Models/Tag.swift` (new)  | New model               |
| `Shared/Models/Commitment.swift` | Add `tags` relationship |
| `Wilgo/WilgoApp.swift`           | Schema registration     |

### Dependency Graph

```
Commit 1: commit msg/summary
    |
    +-- Commit 2: commit msg/summary          [parallel after 1]
    +-- Commit 3: commit msg/summary [parallel after 1]
    |       |
    |       +-- Commit 4: commit msg/summary [after 3]
    +-- Commit 5: commit msg/summary  [parallel after 1]
    +-- Commit 6: commit msg/summary         [parallel after 1]
```

Commits 2, 3, 5, 6 are independent of each other and can be parallelized after Commit 1.
