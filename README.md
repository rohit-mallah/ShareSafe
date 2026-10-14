# ShareSafe

**Drag to blur. Share your screen as usual.**

ShareSafe is a small macOS utility for hiding parts of your desktop. Open its floating toolbar, click **Blur area**, drag a rectangle, and keep using your normal screen-sharing workflow. Add areas on one or several monitors. Blur is visible on your own screen too.

There is no dashboard, window enrollment, account, or separate audience window in the default workflow.

> Share your **entire screen** in your meeting app. Individual app-window or browser-tab sharing can omit desktop overlays. Check the view on a second device before relying on it for private content.

## Features

- Draw multiple blur areas directly on the desktop, before or during screen sharing.
- Keep a small draggable toolbar nearby for adding, moving, removing, undoing, and clearing areas.
- Automatically attach each area to the window under your drag, follow that window when it moves, and keep the blur off overlapping windows.
- Click through the areas to interact with the underlying app outside edit mode.
- Move, select, undo, and remove areas using the mouse or keyboard.
- Hide all connected displays with an emergency shortcut and restore them using an on-screen button.
- Run entirely locally. The default desktop mode does not capture, record, or upload screen pixels.
- Use native macOS backdrop effects without Screen Recording, Accessibility, camera, microphone, or Input Monitoring permission.

ShareSafe is an early-stage project. Meeting-client compatibility, native keyboard interactions, and physical multi-monitor changes need further hands-on testing. Automated tests do not establish what a remote participant receives.

## Requirements

- **macOS 13 or later** to run the native app.
- **Swift 6 or later** and a **macOS SDK 15.2 or later** to build and run all tests. Install current Xcode Command Line Tools or Xcode and select its toolchain.
- Tested locally on Apple Silicon with macOS 15.3.1 and Apple Swift 6.1.2. Intel builds have not been verified.
- No third-party dependencies for the native Swift package.

There is currently no notarized installer or automatic updater. Build the app from source using the steps below.

## Build and run

Clone the repository, then build and open the app:

```sh
git clone https://github.com/rohit-mallah/ShareSafe.git
cd ShareSafe
./scripts/build-app.sh
open dist/ShareSafe.app
```

The build script compiles a release executable, creates `dist/ShareSafe.app`, and applies a local ad-hoc signature. It also packages the optional Chrome companion when its source directory is present. No Apple developer certificate is required for a local build; ad-hoc signing is not Developer ID signing or notarization.

Alternatively, run:

```sh
./scripts/run.sh
```

`run.sh` builds the app if it is missing, then opens it. After editing the source, run `build-app.sh` again and quit/reopen ShareSafe to load the new binary. Finder users can also open `Launch ShareSafe.command`.

## Use ShareSafe

1. **Open ShareSafe.** A small floating toolbar appears near the bottom of the monitor under your pointer.
2. **Click Blur area**, then drag inside the app window you want to protect. The area attaches to that window automatically. Repeat on any connected monitor. Press Escape or **Done** to cancel selection.
3. **Share your entire screen** through Meet, Zoom, Teams, or your usual meeting app. You can also add areas after screen sharing has started.
4. **Click Move/remove** to edit. Click an area or use Tab to select it, then drag or use the arrow keys to move it. Click **Remove** or press Delete to remove the selected area. The selected area has a thick mint outline.
5. **Click Done** or press Escape to finish editing. Areas become click-through again. **Undo** removes the newest area; **Clear** removes all areas.
6. **Drag the dotted grip** to move the toolbar. Its **×** hides only the controls and leaves your areas in place. Click the menu-bar icon or reopen ShareSafe to bring the toolbar back; right-click the icon for shortcuts, emergency coverage, and quit.

The toolbar does not take keyboard focus from your apps. Global shortcuts still work while it is hidden. During emergency coverage the primary button becomes **Restore**, and editing/undo/clear stay disabled.

Areas stay at a fixed offset from their **source window's top-left corner**. They follow that window when it moves, including between displays. Switching apps or opening another window does not transfer an area to the new window: ShareSafe clips the overlay around windows in front of the source. If the source is fully covered, minimized, hidden, closed, or on another desktop, its overlay disappears. Returning to the same window restores it.

This is window tracking, not content tracking. Areas do not follow a message, paragraph, browser tab, or scrolling page. Resizing keeps the area's point size and top-left offset, clipping it to the source bounds; it cannot account for content reflow. Review areas after scrolling, resizing, changing tabs, or switching to fullscreen. Closing/reopening a window can create a different window identity and require a new area. Areas are session-only: clearing them or quitting ShareSafe removes them, and reopening does not restore them.

### Keyboard shortcuts

Global shortcuts use **Control + Option + Command** (`⌃⌥⌘`) and work independently of which app is active, provided macOS can register them.

| Action | Shortcut |
| --- | --- |
| Blur another area | `⌃⌥⌘H` |
| Enter or finish edit mode | `⌃⌥⌘E` |
| Undo the last area | `⌃⌥⌘Z` |
| Clear all areas | `⌃⌥⌘C` |
| Hide or restore all displays | `⌃⌥⌘B` |

While editing:

| Action | Key or gesture |
| --- | --- |
| Select an area | Click it |
| Select next or previous area | `Tab` / `Shift + Tab` |
| Move selected area by one screen point | Arrow keys |
| Move selected area by ten screen points | `Shift + arrow keys` |
| Remove selected area | `Delete` / `Backspace`, or right-click the area |
| Move an area with the mouse | Drag it |
| Finish editing | `Escape` |

If a global shortcut conflicts with another app, the status menu reports the conflict and the mouse controls remain available. Emergency coverage disables edits, undo, and clear until you restore the displays. Its on-screen **Restore desktop** button provides recovery without a working keyboard shortcut.

## How desktop blur works

The active desktop workflow uses AppKit's `NSVisualEffectView` with behind-window blending. macOS supplies the backdrop effect; ShareSafe does not read or copy other applications' screen pixels in this mode.

To place each overlay, ShareSafe reads public WindowServer metadata: window IDs, owner process IDs, bounds, layers, opacity, and front-to-back ordering. It does not use window titles, Accessibility access, or screen-capture APIs. Window IDs and positions are available without a Screen Recording authorization prompt ([Apple's privacy explanation](https://developer.apple.com/videos/play/wwdc2019/701/?time=1460)). Areas are clipped around higher windows so a different app or a second window in the same app does not inherit the blur. A source window that remains visible beside the active app stays protected.

Window placement refreshes approximately every 100 milliseconds while areas exist, plus app and desktop changes. It is not synchronized with meeting capture frames: fast moves, transitions, animations, transparent windows, rounded corners, and window shadows can produce brief gaps or imperfect clipping. Test with fictional content and review the receiving device before relying on it.

macOS controls the material appearance and blur strength. If **Reduce transparency** is enabled in Accessibility settings, selected areas use solid black coverage instead. Existing areas update when that setting changes.

Display layout changes activate solid emergency coverage. Restore the desktop and review all areas before continuing. Only areas with a visible portion on connected displays can be edited; undo and clear remain available for saved areas on hidden windows.

## Privacy and limitations

- The default native app has no account, analytics, upload service, or recording writer. It does not change or reset existing macOS privacy permissions.
- Desktop overlays affect what is visible locally. They appear in screen sharing only when the capture includes the overlay windows. ShareSafe does not detect, intercept, or replace another app's sharing stream.
- Sharing one application window or browser tab can bypass the desktop overlays.
- Blur is a visual obscuring effect, not secure redaction or removal of the underlying data. Use full-display emergency coverage when the whole display must be hidden.
- Content tracking, persistence, automatic share detection, and a guarantee of protection in every meeting client are not implemented in the native workflow.
- Older ScreenCaptureKit/mirror experiments remain in the source and tests. They are not reachable from the current launch flow or menus. Enabling those experiments can require capture permission; the default direct desktop workflow does not invoke them.

Use fictional content when checking receiver behavior, fast scrolling, full-screen apps, monitor changes, keyboard shortcuts, and recovery.

## Optional Chrome companion

[`ChromeExtension/`](ChromeExtension/README.md) contains a separate, experimental Manifest V3 extension. It modifies rendered webpages locally and is not required for the macOS app.

- **Hide element** blurs a selected webpage element and follows that element as it moves.
- **Hide area** draws a fixed viewport rectangle.
- Covers appear locally too, and reset when the page reloads or navigates.
- The extension uses `activeTab` and `scripting`, with injection initiated by a user action. It does not automatically run on every website.

This prototype does not identify the same content after a site replaces or recycles the selected element. Browser-owned pages, cross-origin frames, fullscreen, and page dialogs have additional limits described in its README. It has no native-app synchronization or automatic meeting integration.

See the [installation guide](ChromeExtension/INSTALL.html) and [extension tests](ChromeExtension/tests/README.md).

## Development and tests

Run the native suite from the repository root:

```sh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift test --disable-sandbox --disable-xctest \
  --cache-path "$PWD/.build/cache" \
  --config-path "$PWD/.build/config" \
  --security-path "$PWD/.build/security"
```

The suite checks window identity, movement and occlusion geometry, native overlay lifecycle and editing, pixel rendering, keyboard routing, menu actions, accessibility-style fallback, and legacy capture-model lifecycle behavior using fictional data. The native window tests and legacy Core Image tests need normal access to macOS window/graphics services; running them inside a restrictive execution sandbox can cause failures. The direct desktop mode itself does not use Core Image capture.

Run the dependency-free Chrome service-worker and manifest checks:

```sh
node ChromeExtension/tests/background.mjs
```

Browser tests need Node.js, the extension's development dependencies, and Chrome/Chromium. Follow the [browser-test instructions](ChromeExtension/tests/README.md).

### Repository layout

```text
Sources/ShareSafe/       Native menu-bar app, overlays, and legacy experiments
Sources/ShareSafeCore/   Geometry and image-rendering helpers
Tests/                  Swift Testing suites
Resources/Info.plist    Native app metadata
scripts/                Build and launch scripts
ChromeExtension/        Optional browser companion, demo, and tests
```

## Contributing

Bug reports and focused pull requests are welcome. For a native issue, include the macOS version, processor architecture, relevant shortcuts, meeting client and sharing mode, and steps to reproduce using fictional content. For a browser issue, include the browser version and a minimal non-sensitive example.

Run the relevant tests before submitting a change. Keep the default experience small, preserve click-through and emergency recovery, and avoid adding capture permissions or external data transfer without clearly documenting the change. Do not include credentials, real screen captures, local permission diagnostics, generated builds, or planning documents in commits.

## License

ShareSafe is licensed under the [MIT License](LICENSE).
