## Habit check-in time model – decision record

### Problem

We need a robust way to answer questions like:

- “Did I do this habit **today**?”
- “How many times did I do it **on a given day**?”
- “Is this occurrence **late / missed / upcoming**?”

while also:

- Supporting **multiple slots** per day (N× daily).
- Handling **custom day start** (e.g. “day starts at 3am, not midnight”).
- Being reasonably resilient to **time zone changes / travel**.
- Preserving **user motivation framing** (e.g. “I still owe one not-too-late workout” instead of “one that’s been overdue all day”).

### Decision

We will:

- **Store absolute truth**:
  - `createdAt` (Date, treated as UTC ground truth).
- **Store contextual info at creation**:
  - `timeZoneIdentifier` (e.g. `"America/Los_Angeles"`).
- **Store a derived, logical “habit day”**:
  - `habitDay` (Date pinned to start of that day).
  - Computed at creation time using:
    - `createdAt`
    - `timeZoneIdentifier`
    - a configurable `dayStartHourOffset` (e.g. 0 for midnight, 3 for “day starts at 3am”).

We keep slots (`HabitSlot` with `start`, `end`) and **do not store a per-slot index on `HabitCheckIn`**. For daily progress / streaks / lateness UX, we use the psychological day (`psychDay`) and time-based greedy pairing between slots and check-ins.

### Rationale

- **Separate “truth” from “user’s calendar”**:
  - `createdAt` is the raw timestamp.
  - `habitDay` is “the day this should count toward,” respecting local timezone + custom day start.
- **Custom day start support**:
  - Night owls: 2–3am actions can still count as “yesterday”.
  - We don’t have to reinterpret past data when adding “day starts at X” later.
- **Time zone changes are manageable**:
  - Each check-in captures the time zone at creation, and `habitDay` is baked in.
  - Future changes in device time zone do not silently reassign old check-ins to different days.
- **Good UX framing for N× daily**:
  - For any given `habitDay`, we can:
    - Sort slots by ideal time.
    - Sort that day’s check-ins by time.
    - Greedily pair earliest check-ins to earliest slots to decide what’s “fulfilled” vs “still owed”.
  - This lets us say “you still owe one not-too-late occurrence” instead of “that 8am slot has been late all day” when that’s more motivating.

### Implementation snapshot

- `**HabitCheckIn`:
  - Existing:
    - `habit: Habit?`
    - `slotIndex: Int`
    - `status: HabitCheckInStatus`
    - `createdAt: Date`
  - New:
    - `timeZoneIdentifier: String` (defaults to `TimeZone.current.identifier`).
    - `habitDay: Date` (computed via `HabitScheduling.habitDay` at init).
- `**HabitScheduling`\*\*:
  - `dayStartHourOffset: Int = 0` (placeholder; later configurable per user).
  - `habitDay(for:timeZoneIdentifier:dayStartHourOffset:)`:
    - Uses the specified time zone.
    - Applies the hour offset before taking the calendar day.
    - Returns a `Date` at the start of that “habit day”.

### Future use

- “Today’s check-ins” and “streaks by day” should be computed by grouping on `habitDay`, not `Calendar.current.isDate(createdAt, inSameDayAs:)`.
- Once we implement time-based pairing for N× daily, we’ll use `habitDay` + sorted slots + sorted check-ins to decide:
  - which occurrences are fulfilled,
  - which are overdue,
  - and how late they are, in a way that matches the motivational model we want.

# TODOs

- [] The customized start of a day is not supported or handled.
