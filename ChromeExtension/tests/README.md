# Chrome companion behavioral tests

Run these tests from a terminal after `content.js` is present:

```sh
cd ChromeExtension/tests
npm ci
npm test
```

`npm test` runs five dependency-free manifest/service-worker checks followed by sixteen Chrome behavioral cases. The browser runner uses installed Google Chrome on macOS. Set `CHROME_PATH` to another Chrome/Chromium executable on other platforms; otherwise Playwright uses its installed Chromium. Set `HEADED=1` to watch the disposable test browser, `TEST_FILTER=Undo` to run a matching case, or `TEST_FILTER='top layer'` for fullscreen/modal regressions. If Playwright and pngjs are already installed in a shared runtime, set `NODE_PATH` to that runtime's `node_modules` instead of installing dependencies here.

Each case gets a fresh browser context. Playwright launches its own temporary browser profile, serves the fictional demo on an ephemeral localhost port, and closes every context and the browser at the end. It never attaches to the user's browser, opens real accounts, or retains screenshots.

The tests inject `content.js` directly into an ordinary page to make its diagnostic API accessible. They verify actual blur mixing of black/white source screenshot pixels, selectable solid coverage, suppression of page actions during selection, ordinary interaction after Done/Escape, multiple masks, Undo/Clear and exact style restoration, duplicate/nested selection, scroll/layout/resize tracking, dynamic descendants, viewport-clipped fixed area masks, reinjection, and loss of masks on navigation without writing page storage.

Fullscreen regressions use a real trusted button click to enter iframe, video, and masked-element fullscreen. Chrome can paint a companion popover above fullscreen while blocking interaction with its controls. In that situation the companion hides the fullscreen source, automatically returns to document view, restores the exact prior source style, retains existing covers, and explains the change in its toolbar. Tests record the actual fullscreen entry and source opacity during the transition, then require the automatic exit, retained masks, and a usable Clear button. They do not claim controls remain interactive inside fullscreen.

A separate modal-dialog case verifies that covers remain opaque above a newly opened page dialog. The companion asks the user to close that page dialog to use its controls; the test closes the dialog and verifies Clear works afterward.

The separate service-worker checks simulate Chrome's APIs to verify action injection, clearing an old error state, actionable help when injection fails, rejected popup handling, and invalid tab ids. Manifest checks require exactly `activeTab` and `scripting`, with no host access or automatically injected content scripts.

Run the actual unpacked-extension load smoke with a Playwright-managed Chromium installation, or set `EXTENSION_CHROME_PATH` to a Chromium/Chrome for Testing executable that supports `--load-extension`:

```sh
npm run test:extension
```

This bounded smoke launches a fresh temporary profile, checks the live MV3 worker and the packaged help page, then removes that profile. Branded Chrome may disallow unpacked loading through command-line flags, and a missing Playwright browser needs a separate browser installation.

These checks exercise the real Chrome renderer and pointer/keyboard behavior, plus actual MV3 loading. They do not prove Web Store approval, a manual extension toolbar click/permission prompt, browser-owned pages, cross-origin frames, other applications, or resistance to a hostile page that deliberately removes the companion.

For a manual smoke test, run the following from `ChromeExtension/tests`, then activate the unpacked extension on the localhost page. The demo page labels all data as fictional and makes no external requests.

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory ../demo
```

Open `http://127.0.0.1:8765/`.
