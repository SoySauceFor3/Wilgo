# 📝 Project Doc: Wilgo (MVP)

**Tagline:** _The Sassy Digital Bestie that manages your laziness._

## 1. Core Philosophy

- **Self-Control as a Budget:** We don't expect perfection. We manage "laziness" as a currency (**Skip Credits**).
- **Active Accountability:** Moving from passive tracking to "in-your-face" persistence (Lock Screen occupation).
- **Zero-Friction:** Automating "Proof of Work" via APIs (Notion, HealthKit) so the user doesn't have to log manually.

---

## 2. The Data Model (The "Will-O-Bank")

Each habit is defined by these parameters:

- **Frequency:** Times per day/week
- **Ideal Window:** e.g., 5 PM – 8 PM (The "Golden Hours").
- **Customizable Day Start Hour** e.g. 8AM (When a Skip Credit is automatically burned) - This is now a global setting value.
- **Monthly Budget:** e.g., 5 Skip Credits per month.
- **Proof of Work Type:** `Manual (MVP)`, `Notion API (later)`, or `HealthKit(later)`.

---

## 3. The Behavior Cycle (The "Pressure Spectrum")

Wilgo’s personality and UI evolve throughout the day for each task (assuming the window is set as 5-8 pm, and day start hour at 12am):

1. **Phase 1: Gentle (5 PM - 8 PM)**

- _UI:_ Green/Positive.
- _Tone:_ Encouraging. "Do it now, be free later."

1. **Phase 2: Judgmental (8 PM - 10 PM)**

- _UI:_ Orange/Sassy.
- _Tone:_ Sarcastic. "Still on the couch? Classic you."

1. **Phase 3: Critical (10 PM - 12 AM)**

- _UI:_ Red/Aggressive.
- _Tone:_ Urgent. "Last chance before we burn a credit, boss."

1. **Phase 4: The Settlement (12 AM)**

- _Auto-Action:_ If task = Incomplete, `SkipCredits -= 1`.
- _Next Morning:_ "Debt notification" sent at 10 AM.

---

## 4. Basic UI Plan (The "System-First" Skeleton)

### **Page 1: The Stage (Dynamic Dashboard)**

- **Mascot Area:** Placeholder for Wilgo (the character).
- **Priority Slot:** The habit currently in its "Reminder Window" becomes the largest element.
- **Quick Action:** Large "Done" button and a "Burn Credit" button.
- **Credit Counter:** Big bold number showing remaining Skip Credits.

### **Page 2: Habit Manager (The List)**

- A clean iOS-style List of all habits.
- Visual status indicators (Green dots for Done, Gray for Pending).
- **Floating Action Button (+):** To add new habits.

### **Page 3: Configuration (Setup)**

- **Time Settings:** Pick start/end/dayStart times.
- **API Connect:** Input fields for Notion API Key/Page ID or GitHub username.
- **Penalty Note:** A text area to record the "bet" (e.g., "I owe my friend $50").

### Interactive Notification Area

to show the message and reminder etc on the face.

---

## 5. Technical Stack (The "Foundation")

- **Framework:** SwiftUI (Declarative UI).
- **Persistence:** SwiftData (Local + CloudKit for Watch sync).
- **Visibility:** ActivityKit (Live Activities for the Lock Screen).
- **Automation:**
- `URLSession` for Notion/GitHub API fetches.
- `HealthKit` for workout detection.
- `iOS Shortcuts` for "App Open" triggers (e.g., WeChat monitoring).

# Problem to solve

我还没想明白对于一天多次，或者weekly monthly的task 怎么做reminder window。
可以思考几个use case：

1. 站起来，护眼时间，喝水
2. 和爷爷奶奶打电话

me大思考了一下我觉得说到底这类应该是说明gap period的类型。比如对于我来说，站起来就是上次站起来之后1个小时。和爷爷奶奶打电话也是上次打电话之后1个月。所以我们回头可以做一下这个！这个应该看overdue时间吧！就是gap/overdue时间来做priority算法。

普通类型比如every day，或者every some weekday，几次，应该每次给一个“ideal window”？其实我也不是很了解。。毕竟人类需要的reminder类型很多很杂，比如“说不定有人就想要一个事一个ideal window中做两次”？但是不如！我们就先这样弄，然后再说？也不应该为了1%的usecase来弄的很复杂，是吧。。。
