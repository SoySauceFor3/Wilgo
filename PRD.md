# 📝 Project Doc: Wilgo (MVP)

**Tagline:** *The Sassy Digital Bestie that manages your laziness.*

## 1. Core Philosophy

- **Self-Control as a Budget:** We don't expect perfection. We manage "laziness" as a currency (**Skip Credits**).
- **Active Accountability:** Moving from passive tracking to "in-your-face" persistence (Lock Screen occupation).
- **Zero-Friction:** Automating "Proof of Work" via APIs (Notion, HealthKit) so the user doesn't have to log manually.

---

## 2. The Data Model (The "Will-O-Bank")

Each habit is defined by these parameters:

- **Frequency:** Times per day/week (MVP: 1/day).
- **Ideal Window:** e.g., 5 PM – 8 PM (The "Golden Hours").
- **Soft Deadline:** 12 AM (When a Skip Credit is automatically burned).
- **Monthly Budget:** e.g., 5 Skip Credits per month.
- **Proof of Work Type:** `Manual (MVP)`, `Notion API (later)`, or `HealthKit(later)`.

---

## 3. The Behavior Cycle (The "Pressure Spectrum")

Wilgo’s personality and UI evolve throughout the day for each task (assuming the window is set as 5-8 pm, and deadline at 12am):

1. **Phase 1: Gentle (5 PM - 8 PM)**

- *UI:* Green/Positive.
- *Tone:* Encouraging. "Do it now, be free later."

1. **Phase 2: Judgmental (8 PM - 10 PM)**

- *UI:* Orange/Sassy.
- *Tone:* Sarcastic. "Still on the couch? Classic you."

1. **Phase 3: Critical (10 PM - 12 AM)**

- *UI:* Red/Aggressive.
- *Tone:* Urgent. "Last chance before we burn a credit, boss."

1. **Phase 4: The Settlement (12 AM)**

- *Auto-Action:* If task = Incomplete, `SkipCredits -= 1`.
- *Next Morning:* "Debt notification" sent at 10 AM.

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

- **Time Settings:** Pick start/end/deadline times.
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

---

---

