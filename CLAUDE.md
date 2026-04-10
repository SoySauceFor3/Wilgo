# General

1. Refer me as 3Sauce and greet me every time you talk to me.
2. Ask any clarification questions if needed before you make decisions.
3. No filler/preamble
4. Reflect on the rules you think should be put into this file (./CLAUDE.md), and put into them while keeping this file organized. You should note the date and the author of each rules you added.

## Plan mode

When you are in plan mode:

1. PRD: First focus on planing the feature's expected behavor, UI/UX, PRD like elements. Light considerations about implementations like feasibility are OK, but the focus should NOT be implementation. I need to review and say yes to this document before moving on to implementation design. Most of the time I will write PRD in Notion.
2. Second, you plan on implementation in a seperate file (most of time in `./documentation/`). Always
  1. Link to the PRD, bi-directional.
  2. summarize the overall solution/architecture,
  3. record major model changes
  4. document major alternatives, their pros and cons and why choose the direction we choose
  5. commitment plan (i.e. step by step plan), note:
    1. make each individual commit complete and self-contained. You can make branches and commitment chains as needed.
    2. declare the dependency between commits, so parallel sub-agent can work.
    3. For each commit, include Unit Test of the actual code change. Make sure testing coverage is as much as possible.
    4. Make it clear when you need manual verification/interception, e.g. if you need me to manually verify a migration works in testing iphone.
    5. The commit message:
      1. include a `#tag` of a concise name of the "thing" you are working on, e.g. `#PTSimplification` `#commitmentEncouragement`
      2. Include the link to the tracking to-do in notion, I will provide this in the implementation markdown file. If NOT, ASK ME.

## When you execute

1. Use `superpowers:subagent-driven-development` skill.
2. If needed, create worktree branches on `./.worktrees`

# Simulator

1. (Author: Claude, 2026-04-10) Always run iOS Simulator tests and builds on **iPhone 17 (iOS 26.2)**, UDID `4D4E7E2F-1CE5-4697-A734-85AB68DC55D4`. Do not use other devices unless explicitly asked. 

# Repo specific rules

1. When you create/update SwiftData Model definitions:
  1. When dealing with relationships: prefer direct reference to the other types, instead of using UUID, and remember to include good deletion rule.
2. (Author: Cursor) SwiftData tests: keep a strong reference to `ModelContainer` for the whole test (e.g. `let container = try makeContainer(); let ctx = container.mainContext`). Do not use `makeContainer().mainContext` alone — the context only weakly references the container, and insert/save will crash after the container is released.

