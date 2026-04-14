# Commitment Tags — Implementation Plan

**PRD:** [https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f](https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f)  
**Notion task link (for commit messages):** [https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f](https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f)

---

## Context

Users with growing commitment lists need organization. This adds a lightweight **Tags** system: plain text labels, many-to-many with Commitment, user-managed, with OR-based list filtering. No colors on tags (commitment color is a future independent concept). Grace/archived remain first-class system concepts, not tags.

---

## Architecture Summary

- New `Tag` SwiftData `@Model` entity with a native many-to-many relationship to `Commitment` (direct object references, `deleteRule: .nullify` on both sides).
- `Tag` is added to the main app `Schema` only — **not** to the Widget Extension (it reads commitments but doesn't need tags; SwiftData is forward-compatible).
- All existing test `makeContainer()` helpers need `Tag.self` added to their `Schema`.
- No migration plan needed — adding a new entity with default `[]` relationship is a lightweight migration SwiftData handles automatically.

---

## Design Decisions

### `displayOrder` on `Tag`

**Decision:** Keep `displayOrder: Int` as a property on `Tag` (not a separate ordering model).

**Why not a separate ordered list?** A central `TagOrder` model or a global ordered-ID array would add unnecessary complexity for a feature of this scale. `displayOrder: Int` is the standard SwiftData/CoreData pattern and works fine.

**Risk: duplicate `displayOrder` values.** This can happen if there is a bug in the reorder logic. Mitigations:
- Never assume uniqueness — always sort by `displayOrder` then break ties deterministically (e.g. by `id`).
- When reordering, always renumber **all** tags sequentially (not just the moved one). This means any duplicates are self-healing after the next reorder.

**Default value for new tags:** No static default — the correct value depends on existing data. New tags use `(allTags.map(\.displayOrder).max() ?? -1) + 1`, which appends to the end. First tag gets `0`.

**Write sites (exhaustive):** `displayOrder` is written in exactly two places:
1. **Tag creation** — set once as `max + 1` at creation time.
2. **Settings reorder** — all tags renumbered sequentially after a drag reorder.

No other code should write `displayOrder`. `@Query(sort: \Tag.displayOrder)` is a live query, so all views (filter chips, tag picker, commitment row) automatically reflect the persisted order without extra wiring.

### Delete Rules (both sides of the many-to-many)

SwiftData requires the delete rule to be declared on both sides of a relationship.

- **`Commitment.tags` (`deleteRule: .nullify`):** When a Commitment is deleted, the Tag survives. The Commitment is removed from `tag.commitments`.
- **`Tag.commitments` (`deleteRule: .nullify`):** When a Tag is deleted, the Commitment survives. The Tag is removed from `commitment.tags`.

**On nulls in the array:** `.nullify` does **not** leave `nil` entries in `[Commitment]` or `[Tag]`. SwiftData removes the deleted object from the array entirely. The array shrinks; it never contains a nil slot. This is different from optional scalar columns — for to-many arrays, nullify means "remove from array."

---

## Major Model Changes


| Entity                             | Change                                                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| **New:** `Shared/Models/Tag.swift` | `@Model` with `id: UUID`, `name: String`, `createdAt: Date`, `displayOrder: Int`, `commitments: [Commitment]` |
| `Shared/Models/Commitment.swift`   | Add `@Relationship(deleteRule: .nullify, inverse: \Tag.commitments) var tags: [Tag] = []`                     |
| `Wilgo/WilgoApp.swift`             | Add `Tag.self` to `Schema([...])`                                                                             |
| All test `makeContainer()` helpers | Add `Tag.self`                                                                                                |


---

## Commit Plan

### Dependency Graph

```
Commit 1: Tag model + Commitment relationship + container/schema registration
    |
    +-- Commit 2: CommitmentRowView tag display          [parallel after 1]
    +-- Commit 3: TagPickerSection in CommitmentFormFields [parallel after 1]
    |       |
    |       +-- Commit 4: Wire picker in Add + Edit forms [after 3]
    +-- Commit 5: Filter chip row in ListCommitmentView  [parallel after 1]
    +-- Commit 6: Settings tag management screen         [parallel after 1]
```

Commits 2, 3, 5, 6 are independent of each other and can be parallelized after Commit 1.

---

### Commit 1 — Tag model, Commitment relationship, schema registration

`#CommitmentTags` · [https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f](https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f)

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

### Commit 2 — Tag display in CommitmentRowView

`#CommitmentTags` · [https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f](https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f)

**Modify:** `Wilgo/Features/Commitments/SingleCommitment/CommitmentRowView.swift`  
After the last row in the `VStack`, add:

```swift
if !commitment.tags.isEmpty {
    Text(commitment.tags.sorted { $0.displayOrder < $1.displayOrder }
        .map(\.name).joined(separator: ", "))
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

**Create:** `WilgoTests/Tag/CommitmentRowTagDisplayTests.swift`  
Tests: model-level — commitment with no tags has empty `.tags`; tag names join correctly in sorted order.

---

### Commit 3 — TagPickerSection view + wire into CommitmentFormFields

`#CommitmentTags` · [https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f](https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f)

**Create:** `Wilgo/Features/Tags/TagPickerSection.swift`

A self-contained `View` that owns all tag-picking logic:
- `@Binding var selectedTags: [Tag]` — the current selection, owned by the parent form.
- `@Query(sort: \Tag.displayOrder) private var allTags: [Tag]` — live query.
- `@Environment(\.modelContext) private var modelContext`.
- `@State private var isAddingTag = false`, `@State private var newTagName = ""`.
- Body: a `Section("Tags")` containing:
  - `ForEach(allTags)` — each row: tag name + checkmark if in `selectedTags`. Tap toggles.
  - "Add new tag…" `Button` row → sets `isAddingTag = true`.
  - `.alert("New Tag", isPresented: $isAddingTag)` with `TextField` + confirm: guard non-empty trimmed name, compute `displayOrder` as `(allTags.map(\.displayOrder).max() ?? -1) + 1`, insert new `Tag` into `modelContext`, append to `selectedTags`.
  - Summary `Text` above the list showing selected tag names (comma-separated), hidden if empty.

**Modify:** `Wilgo/Features/Commitments/CommitmentFormFields.swift`
- Add `@Binding var selectedTags: [Tag]` parameter.
- Embed `TagPickerSection(selectedTags: $selectedTags)` at the end of `body`. No tag logic in this file.

**Create:** `WilgoTests/Tag/TagPickerLogicTests.swift`  
Tests: displayOrder calculation (first tag → 0, next → max+1); tag toggle add/remove; blank name rejection.

---

### Commit 4 — Wire tag picker through Add and Edit forms

`#CommitmentTags` · [https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f](https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f)

Depends on Commit 3.

**Modify:** `Wilgo/Features/Commitments/AddCommitView.swift`

- Add `@State private var selectedTags: [Tag] = []`.
- Pass `selectedTags: $selectedTags` to `CommitmentFormFields`.
- In `persistCommitment(grace:)`: after `modelContext.insert(commitment)`, set `commitment.tags = selectedTags`.

**Modify:** `Wilgo/Features/Commitments/EditCommitmentView.swift`

- Add `@State private var selectedTags: [Tag]` initialized from `commitment.tags` in `init`.
- Pass `selectedTags: $selectedTags` to `CommitmentFormFields`.
- In `saveChanges(grace:)`: set `commitment.tags = selectedTags`.

**Create:** `WilgoTests/Tag/TagPersistenceTests.swift`  
Tests: commitment saved with tags carries correct tags through save/fetch; editing and changing tags persists new set; removing all tags → `commitment.tags` empty, tags themselves survive.

**Manual verification:**

- Add Commitment → Tags section shows "Add new tag…" → create "Health" → checkmark appears → save → row shows "Health".
- Edit that commitment → "Health" checked → uncheck → save → row no longer shows "Health". Tag still exists in Settings.

---

### Commit 5 — TagFilterChipsView + wire into ListCommitmentView

`#CommitmentTags` · [https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f](https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f)

**Create:** `Wilgo/Features/Tags/TagFilterChipsView.swift`

A self-contained `View` for the horizontal filter chip row:
- `@Binding var selectedTagIDs: Set<UUID>` — selection state owned by the parent.
- `@Query(sort: \Tag.displayOrder) private var allTags: [Tag]` — live query.
- Body: `ScrollView(.horizontal, showsIndicators: false) { HStack { ... } }`:
  - "All" chip: filled when `selectedTagIDs` is empty, tap clears selection.
  - `ForEach(allTags)` chips: filled capsule when selected, outlined when not. Tap toggles UUID in `selectedTagIDs`.
  - Chip style: `.caption` font, `Capsule` shape, accent color fill when selected.
- Hidden (not rendered) when `allTags.isEmpty`.

**Modify:** `Wilgo/Features/Commitments/ListCommitmentView.swift`
- Add `@State private var selectedFilterTagIDs: Set<UUID> = []`.
- Add computed `filteredCommitments: [Commitment]`:
  - Empty filter → return full `commitments` array.
  - Otherwise: `commitments.filter { c in c.tags.contains { selectedFilterTagIDs.contains($0.id) } }` (OR logic).
- Embed `TagFilterChipsView(selectedTagIDs: $selectedFilterTagIDs)` above the `List`.
- Replace `ForEach(commitments)` with `ForEach(filteredCommitments)`.
- Update `deleteCommitments(offsets:)` to index into `filteredCommitments`.

**Create:** `WilgoTests/Tag/CommitmentFilterTests.swift`  
Tests: OR logic (tag A → shows only commitment with A; tags A+B → shows both); "All" (empty set → all shown); untagged commitment hidden when any filter active; pure in-memory logic (no model writes).

---

### Commit 6 — Settings tag management screen

`#CommitmentTags` · [https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f](https://www.notion.so/3414b58e32c3803a9389c29c323eeb4f)

**Create:** `Wilgo/Features/Tags/TagsSettingsView.swift`

- `@Query(sort: \Tag.displayOrder) private var tags: [Tag]`
- `@Environment(\.modelContext) private var modelContext`
- `List` with `.onMove` and `.onDelete`:
  - Each row: `@Bindable var tag: Tag` → inline `TextField` bound to `tag.name` (SwiftData auto-persists on commit).
  - `.onMove`: after move, renumber all tags sequentially (`for (i, tag) in tags.enumerated() { tag.displayOrder = i }`).
  - `.onDelete`: compute `tag.commitments.count`, show `.confirmationDialog("Delete '\(tag.name)'? Used in \(count) commitment(s).")` before `modelContext.delete(tag)`.
- No color picker.

**Modify:** `Wilgo/Features/Settings/SettingsView.swift`  
Add `NavigationLink("Tags", destination: TagsSettingsView())` in a `Section("Tags")`.  
Import from `Features/Tags/TagsSettingsView.swift`.

**Create:** `WilgoTests/Tag/TagSettingsTests.swift`  
Tests: reorder logic (3 tags, move last to first → displayOrder renumbered 0/1/2); delete tag → commitment survives, `commitment.tags` empty; rename persists.

**Manual verification:**

- Settings → Tags: list appears. Drag to reorder → order persists. Tap name to rename → persists. Delete with confirmation dialog → correct commitment count shown. Commitment row no longer shows deleted tag.

---

## Critical Files


| File                                                                  | Role                               |
| --------------------------------------------------------------------- | ---------------------------------- |
| `Shared/Models/Tag.swift` (new)                                       | New model                          |
| `Shared/Models/Commitment.swift`                                      | Add `tags` relationship            |
| `Wilgo/WilgoApp.swift`                                                | Schema registration                |
| `Wilgo/Features/Tags/TagPickerSection.swift` (new)                   | Tag picker UI — used in forms      |
| `Wilgo/Features/Tags/TagFilterChipsView.swift` (new)                 | Filter chip row UI — used in list  |
| `Wilgo/Features/Tags/TagsSettingsView.swift` (new)                   | Tag management screen              |
| `Wilgo/Features/Commitments/CommitmentFormFields.swift`               | Embeds `TagPickerSection`          |
| `Wilgo/Features/Commitments/SingleCommitment/CommitmentRowView.swift` | Tag display (inline text)          |
| `Wilgo/Features/Commitments/ListCommitmentView.swift`                 | Embeds `TagFilterChipsView`        |
| `Wilgo/Features/Settings/SettingsView.swift`                          | Tags nav link → `TagsSettingsView` |
| All 10 test `makeContainer()` files                                   | Schema update                      |


