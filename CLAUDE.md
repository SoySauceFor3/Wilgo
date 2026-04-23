# General

1. Refer me as 3Sauce and greet me every time you talk to me.
2. Ask any clarification questions if needed before you make decisions.
3. No filler/preamble
4. Reflect on the rules you think should be put into this file `./CLAUDE.md`), and put into them while keeping this file organized. You should note the date and the author of each rules you added.

## Plan mode

When you are in plan mode:

### 1. PRD

First focus on planing the feature's expected behavor, UI/UX, PRD like elements. Light considerations about implementations like feasibility are OK, but the focus should NOT be implementation. I need to review and say yes to this document before moving on to implementation design. Most of the time I will write PRD in Notion.

### 2. Implementation plan

Second, you plan on implementation in a seperate file (most of time in `./documentation/`). 

Always

1. Have a "header" recording some metadata
  1. Link to the PRD, bi-directional.
  2. Tracking link: I will provide you. If not, ASK ME.
  3. The #tag to use for commit messages (see below): a concise name of the "thing" you are working on, e.g. `#PTSimplification` `#commitmentEncouragement`
2. summarize the overall solution/architecture,
3. record major model changes
4. document major alternatives, their pros and cons and why choose the direction we choose
5. commitment plan (i.e. step by step plan), note:
  1. declare the dependency between commits, so parallel sub-agent can work.
  2. You can make branches and commitment chains as needed.
  3. make each individual commit
    1. logically complete and self-contained. At least (unless huge exception), the app should still build and do not cause new failing tests.
    2. include Unit Test of the actual code change. Make sure testing coverage is as much as possible.
    3. Make it clear when you need manual verification/interception, e.g. if you need me to manually verify a migration works in testing iphone.

To help you better understand what i want, please refer to the template at ./documentation/TEMPLATE.md

## When you implement

1. Use `superpowers:subagent-driven-development` skill.
2. If needed, create worktree branches on `./.worktrees`
3. at the end of the commit message:
  1. include the `#tag` provided in the implementation markdown file. If NOT, ASK ME.
  2. Include a separate line as `tracking: {trackingLink}`. TrackingLink is a link to the tracking to-do in notion, which is provided in the implementation markdown file. If NOT, ASK ME.
4. When you run test: first only run the test relative to your change. Only these passed should you run the other tests.

# Simulator

1. (Author: Claude, 2026-04-19) Always run iOS Simulator tests and builds on **iPhone 17 (iOS 26.4)**, UDID `4492FF84-2E83-4350-8008-B87DE7AE2588`. Do not use other devices unless explicitly asked.

# Build & Test

1. (Author: Claude, 2026-04-14) **Stale SourceKit warnings are pre-existing and should be ignored.** After a build or test run, warnings with `vitality: stale` in `XcodeListNavigatorIssues` are leftover from a prior build and do NOT indicate regressions. Known pre-existing stale warnings:
  - `CatchUpReminder.swift:15` — Swift 6 main-actor isolation warning
  - SwiftData macro generated file — main-actor `Encodable` conformance warning
  - `CheckInUndoManager.swift:121` — non-optional `??` warning
   Only treat warnings/errors as actionable if they are **not** stale, or if the build itself fails.
2. (Author: Claude, 2026-04-14) **Pre-existing failing test — do not count as a regression.** The following test was already failing before any new work:
  - `CommitmentStageSnoozeTests/stageStatus_snoozeDoesNotAffectFutureOccurrence()` — failing as of 2026-04-14, cause unknown. Do not treat this as caused by your changes.
3. (Author: Claude, 2026-04-14) **Run tests via `xcodebuild`, not the Xcode MCP `RunAllTests` tool.** The MCP tool runs against the physical device and reports all tests as "not run" when the device is unavailable. Always use: `xcodebuild test -project Wilgo.xcodeproj -scheme Wilgo -destination 'platform=iOS Simulator,id=4492FF84-2E83-4350-8008-B87DE7AE2588'`

# When I ask you to fix your previous implementation

Please make each bug at least a seperate commit. Do not commit the fix to multiple bugs in one commit. 

# Repo specific rules

1. When you create/update SwiftData Model definitions:
  1. When dealing with relationships: prefer direct reference to the other types, instead of using UUID, and remember to include good deletion rule.
2. (Author: Cursor) SwiftData tests: keep a strong reference to `ModelContainer` for the whole test (e.g. `let container = try makeContainer(); let ctx = container.mainContext`). Do not use `makeContainer().mainContext` alone — the context only weakly references the container, and insert/save will crash after the container is released.

