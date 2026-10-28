# iPhone Duo compatibility

Mithka's Flutter layout uses the current window size. Native iOS windows can
show a chat list and detail pane at a minimum of 740 logical pixels wide and
600 high, in either orientation. Smaller windows use one pane.

When a selected split conversation becomes compact, the sidebar is hidden and the
detail navigator remains mounted. Back returns to the compact list. A route
opened in the compact tab navigator remains full width when the window grows;
returning to the list then adopts the split layout. Tab navigation observers
retain their route stack across resize rebuilds.

## Toolchain

Use Xcode 27.1 and its iOS 27.1 Simulator runtime to exercise Duo APIs.
`ios/Flutter/Duo.xcconfig` derives `MITHKA_HAS_RESERVED_REGIONS` from the
selected device/simulator SDK: enabled for 27.x except 27.0. The query also
has a runtime iOS 27.1 availability check. Older and unrecognized future SDK
major versions retain the status-bar fallback; verify and extend the SDK
selector before adopting a new SDK major version. Debug, Release, and Profile
inherit this configuration without raising the deployment target.

In AirBuild, select `macos-xcode-beta` for Xcode 27.1 RC and `iphone-duo` for
the preview. Standard builds use the default Xcode environment. No machine-wide
Xcode selection change is required.

## Verification

```sh
flutter test test/main_tab_motion_test.dart
```

The retained shell tests cover compact Back behavior, navigation ownership and
preservation of an existing compact navigation route when opening the display.
The previous per-screen layout permutations were retired during suite pruning;
use the simulator checks below for full display and resize verification.

Simulator checks still required for the first beta pass:

- Launch on both inner and outer displays, then open, close, and rotate while
  a conversation, keyboard, topic, or nested settings screen is active.
- Verify safe areas, sheets, media viewing, and partially folded poses.
- Check front-camera transitions and the active inner camera's occlusion.
- Extend compact detail retention to Contacts, Channels, and Moments after
  providing those detail screens with compact navigation controls.

The native bridge queries active UIKit occlusion regions for side-navigation
placement. A fully occupied edge is explicitly unavailable, and malformed
fractions fail closed. This is not general fold avoidance: division regions
are not bridged, and same-size occlusion changes do not currently invalidate
the cached geometry. The size-based changes alone do not establish support for
every partially folded pose or native vertical bars.

The selection-format menu caps its width and height to the usable area above
the keyboard, scrolling its existing actions when they do not all fit.
The previous focused viewport and format-menu tests were retired during suite
pruning. On 2026-10-24, the then-current composer/adaptive suite passed 96 tests.
On a fresh Simulator retry later that day, the inner display and accessibility
capture became available. A review-account self-chat and unsent draft survived
closed → open → half-folded → closed transitions, including rotation into both
inner-screen orientations. The composer and attachment row remained above the
keyboard in the captured open and half-folded layouts. Rotation/display changes
dismissed the keyboard; refocusing the retained draft reopened it correctly.
The 3D capture still rendered a closed exterior model despite an active inner
display, so it does not establish physical hinge clearance. General fold-region
avoidance, sheets, camera transitions, and full pose coverage remain unverified.
An accessibility-large text check exposed a separate chat-header title/status
overflow; this is not evidence of complete accessibility coverage.

References: [Apple's Duo preparation guide](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
and [Xcode 27.1 beta release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes).
Apple lists most app-extension debugging as unavailable in this Duo runtime.
