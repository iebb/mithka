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

Use Xcode 27.1 beta and its iOS 27.1 Simulator runtime. On this development Mac,
the beta is installed at `~/Applications/Xcode-27.1-beta.app`. Select it per
command without changing the system-wide Xcode selection:

```sh
DEVELOPER_DIR="$HOME/Applications/Xcode-27.1-beta.app/Contents/Developer" \
  flutter build ios --simulator --debug --no-pub
```

Xcode's required system components must finish installing before building or
creating a Duo simulator. This installation may require macOS administrator
authentication.

## Verification

```sh
flutter test test/adaptive_split_layout_test.dart \
  test/main_tab_motion_test.dart test/topic_split_navigation_test.dart \
  test/primary_chat_launcher_split_test.dart \
  test/adaptive_profile_launcher_test.dart test/general_settings_split_test.dart
```

The resize tests check that topic settings and the topic screen retain their
element/state identity across compact, tall, and wide windows, with normal and
reduced motion. They also check compact Back behavior and preservation of an
existing compact navigation route when opening the display.

Simulator checks still required for the first beta pass:

- Launch on both inner and outer displays, then open, close, and rotate while
  a conversation, keyboard, topic, or nested settings screen is active.
- Verify safe areas, sheets, media viewing, and partially folded poses.
- Check front-camera transitions and the active inner camera's occlusion.
- Extend compact detail retention to Contacts, Channels, and Moments after
  providing those detail screens with compact navigation controls.

The Flutter shell does not yet consume UIKit's new reserved-region APIs for
the folding region or camera occlusions. The size-based changes alone do not
establish support for every partially folded pose or native vertical bars.

References: [Apple's Duo preparation guide](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
and [Xcode 27.1 beta release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_1-release-notes).
Apple lists most app-extension debugging as unavailable in this Duo runtime.
