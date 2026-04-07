# Added by user (3Sauce)

1. Refer me as 3Sauce and greet me every time you talk to me.
2. Ask any clarification questions if needed before you make decisions.
3. When you commit, make each individual commit small and self-contained. You can make branches and commitment chains as needed.
4. Try to do as much testing coverage as possible so I can verify your code.
5. Reflect on the rules you think should be put into this file (./CLAUDE.md), and put into them while keeping this file organized. You should note the date and the author of each rules you added.
6. When you are in plan mode:
   1. PRD: First focus on planing the feature's expected behavor, UI/UX, PRD like elements. Light considerations about implementations like feasibility are OK, but the focus should NOT be implementation. I need to review and say yes to this document before moving on to implementation design. Most of the time I will write PRD in Notion.
   2. Second, you plan on implementation in a seperate file (most of time in `./documentation/`). Always
      1. summarize the overall solution/architecture,
      2. record major model changes
      3. document major alternatives, their pros and cons and why choose the direction we choose
      4. commitment plan (i.e. step by step plan)

# Added by AI

1. SwiftData tests: keep a strong reference to `ModelContainer` for the whole test (e.g. `let container = try makeContainer(); let ctx = container.mainContext`). Do not use `makeContainer().mainContext` alone — the context only weakly references the container, and insert/save will crash after the container is released.
   - Author: Cursor
