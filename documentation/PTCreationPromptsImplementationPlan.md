# PT Creation Prompts — Implementation Plan

**PRD:** N/A (simple UI change, no PRD required)  
**Tracking:** [PT creation specific prompt](https://www.notion.so/PT-creation-specific-prompt-3394b58e32c380518106fc289b3b2ed3?source=copy_link)  
**Tag:** #PTCreationPrompts

---

## Context

The Positivity Token creation screen (`AddPositivityTokenView`) currently shows a single static prompt: "What is one reason you feel positive about yourself?" We want to replace this with a rotating set of more varied, specific prompts to inspire richer entries. A random prompt is shown on open; tapping it cycles to the next one.

---

## Architecture Summary

Pure UI change to `AddPositivityTokenView.swift`. A static array of prompt strings is defined in the view. An `@State var promptIndex: Int` is initialized to a random value on appear and incremented on tap. A "Tap to change" hint is shown below the prompt. No model changes, no new files.

---

## Design Decisions

### Tap-to-cycle vs. swipe

**Decision:** Tap the prompt text to cycle to the next prompt.

**Why not swipe?** Swipe gestures conflict with the scroll behavior of the `Form` enclosing the view. Tap is more discoverable and works reliably in a scrollable form.

### Prompt list

**Decision:** 8 prompts, fully replacing the original English prompt.

The original prompt ("What is one reason you feel positive about yourself?") is covered by the new set, so it's dropped to avoid redundancy.

---

## Major Model Changes

| Entity | Change |
|---|---|
| `Wilgo/Features/PositivityToken/AddView.swift` | Add prompt array, `@State promptIndex`, tap gesture, hint text |

---

## Commit Plan

### Phase 1 — Replace static prompt with rotating prompts

#### Commit 1 — feat: rotate PT creation prompts on tap #PTCreationPrompts

**Modify:** `Wilgo/Features/PositivityToken/AddView.swift`

Replace the entire file with:

```swift
import SwiftData
import SwiftUI

struct AddPositivityTokenView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var reason: String = ""
    @State private var promptIndex: Int = Int.random(in: 0..<Self.prompts.count)

    private static let prompts: [String] = [
        "What's one small win you had today?",
        "What's one little thing that made you happy today?",
        "Who or what are you grateful for today?",
        "What's one thing you did for someone else today?",
        "What's something you're proud of yourself for recently?",
        "What's one moment today that felt good?",
        "What's one kind thing someone did for you lately?",
        "What's one thing you accomplished today, big or small?",
    ]

    private var currentPrompt: String {
        Self.prompts[promptIndex % Self.prompts.count]
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Prompt") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(currentPrompt)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Tap to change")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        promptIndex = (promptIndex + 1) % Self.prompts.count
                    }
                }

                Section("Reason") {
                    TextEditor(text: $reason)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("New Positivity Token")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveToken()
                    }
                    .disabled(trimmedReason.isEmpty)
                }
            }
        }
    }

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveToken() {
        let token = PositivityToken(reason: trimmedReason)
        modelContext.insert(token)
        dismiss()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: Commitment.self, Slot.self, CheckIn.self, PositivityToken.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return AddPositivityTokenView()
        .modelContainer(container)
}
```

No unit tests needed — this is pure view state with no logic to isolate. Manual verification:
- Open the Add PT sheet
- Verify a prompt is shown (not the old one)
- Tap the prompt — verify it cycles to the next
- Tap through all 8 — verify it wraps back to the first
- Verify "Tap to change" hint is visible below the prompt

```bash
git add Wilgo/Features/PositivityToken/AddView.swift
git commit -m "feat: rotate PT creation prompts on tap #PTCreationPrompts

tracking: https://www.notion.so/PT-creation-specific-prompt-3394b58e32c380518106fc289b3b2ed3"
```

---

## Critical Files

| File | Role |
|---|---|
| `Wilgo/Features/PositivityToken/AddView.swift` | Only file changed |

### Dependency Graph

```
Commit 1: feat: rotate PT creation prompts on tap
```

Single commit, no dependencies.
