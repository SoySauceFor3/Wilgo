# Widgets Implementation

PRD: [https://www.notion.so/Type-1-PRD-3394b58e32c380a78848edaf8276ee6f?source=copy_link](https://www.notion.so/Type-1-PRD-3394b58e32c380a78848edaf8276ee6f?source=copy_link)

We deisgn the implementation of "current commitment here". But a lot of the design is generic to all the widgets which will be created in the future.

Overall framework to use: ios's WidgetKit and AppIntent --- common pattern to implement Widget in ios.

## Reuse the existing `WidgetExtension` Target

Apple requires all widgets and Live Activities from the same app to live in one widget extension bundle. If you created a second widget extension target, the App Store would reject it — apps are only allowed one widget extension. The WidgetBundle is exactly the mechanism for hosting multiple widgets/Live Activities in that single target:

```swift
@main
struct WidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        NowLiveActivity()  // existing
        Widget()              // new widget goes here
    }
}
```

NowLiveActivity and the new Now widget coexist in the same target, compiled together, sharing the same sandbox. That's the intended design.

## Prerequisite - Manual Set Up

1. **Apple Developer Portal** ([developer.apple.com](http://developer.apple.com) → Certificates, Identifiers & Profiles → Identifiers → App Groups → "+"): Create App Group `group.xyz.soysaucefor3.wilgo`. Enable it on both App IDs: `xyz.soysaucefor3.Wilgo` (main app) and `xyz.soysaucefor3.Wilgo.WidgetExtension` (widget).
   **NOTE**: not creating the group beforehand on web is fine. The step below allows group creation directly from XCode.
2. **Xcode — main app target**: Signing & Capabilities → "+" → App Groups → add `group.xyz.soysaucefor3.wilgo`
3. **Xcode — WidgetExtension target**: same as above
4. **[ ] Xcode — target membership**: After creating the two new `Shared/` files, set Target Membership to both `Wilgo` and `WidgetExtension` in the File Inspector (same pattern as `Shared/NowAttributes.swift`)
