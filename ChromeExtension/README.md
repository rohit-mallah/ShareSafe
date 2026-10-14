# ShareSafe Chrome companion

A standalone, local Manifest V3 prototype for Chrome 114 or later. Cover parts of a webpage, then use your meeting app’s normal share button. Direct Blur is the default: masks blur the real webpage pixels and are visible on your own screen. Select **Style: Solid** for opaque covers on new selections. No native app, account, build step, or network service is required.

## Install in Chrome

1. Open `chrome://extensions`.
2. Turn on **Developer mode** in the top-right corner.
3. Click **Load unpacked** and choose this **ChromeExtension** folder — the folder containing `manifest.json`.
4. Pin **ShareSafe Companion** using Chrome’s Extensions menu.
5. Open a normal website and click the ShareSafe icon, or press **⌘⇧H** on Mac / **Ctrl+Shift+H** elsewhere. Change a conflicting shortcut at `chrome://extensions/shortcuts`.

The packaged Mac app includes the same folder inside its Resources. The current menu-bar app does not include an extension-setup button. To install a source zip, extract it first and select the resulting folder.

## Use it

- **Hide element:** click content to conceal that element and its descendants. Keep clicking to add separate covers. Duplicate or nested selections leave existing protection intact.
- **Hide area:** drag a rectangle. It stays at that position in the **viewport**; scrolling moves webpage content underneath it. For content that must stay hidden while scrolling, use Hide element.
- **Escape** or **Done:** finish selecting and resume ordinary page interaction. Existing covers remain. The small toolbar stays available so **Undo** and **Clear** are always accessible.
- **Undo:** remove the newest cover. **Clear:** remove every cover, restore original inline styles and finish selecting. Clearing ends active element tracking; you can start selecting again.

Reopening the extension enters element selection without duplicating the toolbar or losing covers. Covers stay in the current document only. Reloading, navigating away, or closing the tab discards them. Always check the shared view after navigation or major page updates. Page code that replaces a covered node creates new content that must be selected again; this prototype does not store or reapply selectors.

## What is covered

Element selection applies immediate `filter: blur(18px) !important` to the selected source composite, including its descendants and overflow, with transitions and animations disabled on that source. The transparent tracking rectangle follows its geometry on animation frames. Area selection uses a fixed `backdrop-filter` blur over live webpage pixels. **Style: Blur / Solid** changes the style for new selections only. Solid element masks suppress the source subtree with opacity and add an opaque rectangle.

New descendants and inline style changes are observed. Independent top-layer descendants escape ancestor filters, so they receive solid source suppression. Opening page dialogs/popovers switches existing area masks to protective solid coverage until Undo/Clear. Undo/Clear restores each saved inline style attribute exactly, including absent attributes and `!important` values. Page changes to saved inline styles are replaced by those originals on restoration.

The toolbar uses its own shadow root and a manual top-layer popover rooted outside protected content. Selection intercepts page clicks only while selecting. After Done or Escape, covered source controls can still receive clicks, so avoid interacting with hidden content. No DOM copies or screenshots are sent anywhere.

## Limits of this prototype

- Chrome settings, new-tab pages, the Web Store, browser UI, built-in PDF viewers and other restricted pages cannot be changed. A help popup explains how to continue.
- For local files, enable **Allow access to file URLs** in the extension’s details. A normal local HTTP server works without that setting.
- Only the top-level document is injected. You cannot click-select content inside an iframe, including cross-origin frames. You can place a viewport area cover over a frame; do not depend on it while scrolling. Closed shadow roots and other unusual rendering should be checked in your own sharing view.
- Chrome can render the covers above a page’s fullscreen video, iframe or element while preventing clicks on the toolbar. While protection or selection is active, ShareSafe immediately conceals that fullscreen source, leaves unsupported page fullscreen, restores its saved source styles and keeps your existing covers. A visible status explains the recovery. If Chrome cannot leave fullscreen automatically, the source stays covered and the status asks you to press Escape.
- A page-native modal dialog can similarly block toolbar interaction. Area covers switch to solid above the dialog; selection ends and a status asks you to close the page dialog before using ShareSafe controls. ShareSafe does not dismiss the page’s dialog itself.
- Blur reduces readability but is not a guarantee that information cannot be inferred; choose Solid for stronger visual concealment. This is webpage rendering protection, not deletion or encryption. The underlying DOM and accessibility data still exist. The page itself remains in control of its document and can remove extension UI or replace nodes.
- A webpage modified this way can be visible in tab, browser-window or whole-display shares that capture its rendered pixels. Validate your meeting’s actual receiver view before sharing sensitive content. The extension neither detects nor changes another app’s capture source.
- Native messaging, settings synchronization, automatic share detection, cross-navigation persistence and Web Store publication are deferred.

## Permissions and data

The only permissions are **activeTab** and **scripting**. Injection happens after an explicit action/shortcut. There are no broad host permissions, content scripts running on every site, storage permissions, analytics, accounts, external libraries, remote code, or network calls. All cover state and original styles live in memory in the current document.

## Local demo and verification

Open `demo/index.html` after allowing file URLs, or serve this folder locally and visit the demo through HTTP. The demo contains only fictional data and interactive controls for checking selection, scrolling, layout changes and restoration.

From this folder, run `node tests/browser.mjs` for disposable real-browser checks. See `tests/README.md` for the Playwright/runtime requirements and exact command. The tests never attach to an existing browser or use your normal profile. Automated pixel/DOM checks do not replace a receiver-side meeting check.

To make an install archive without test dependencies, run `bash scripts/package.sh`. It writes `dist/ShareSafe-Companion.zip` with the runtime files, fictional demo and offline guides. No upload or publication occurs.
