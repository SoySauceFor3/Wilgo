# How to Represent SKIP

Based on at least my own use case, say I mark 5-8pm as my workout time. There might be two types of "skip":

1. I am going to miss the 5-8pm window, but I still want to do it today.
2. I intentionally want to just skip it for the whole today. I want to take a break.

Both are plausible, but as a person who procrastinate and give up a lot, I believe that we should always give user the chance to "late but still do it", so I want to not support case 2 for now. Also, the case 2 can be "done" by just ignore the reminding window? We will see.

Thus, I will change how "SKIP" is represented in the code. Right now as of commit a1ea0822 it is represented as a enum option along with "Complete", and this is supposed to capture case 2. However, it makes representing "late, but still want to finish today" tricky, and "silent give up" is also tricky. And if we don't add support for "snooze the window reminder", then --- even if a user pressed "skip", within the window time, because we want to give user the chance to "change their mind a still do it" ---- the task will be back up again! making it look like buggy.

So, my plan is to:

1. remove the enum

```swift
CheckInStatus.skipped
```

1. add a state managing if a window should be moved from now stage to miss/make up session, which allows silent give up.

Admittedly, this might postpone the "Oh your credit is used up, time for the punishment" part to the next day (then we know the user really gives up), but I think this lost is tolerable
