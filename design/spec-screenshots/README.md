# Spec screenshots

Regenerates the screenshots of the Apple implementation notes, [spec/platforms/apple/screenshots/](../../spec/platforms/apple/screenshots/README.md): one PNG per page state and device, taken from the running iPhone, iPad and Mac apps with a synthetic sample library. They exist so that an agent on Windows or Android, which cannot run the Apple apps, can see each screen and port it ([spec/platforms/README.md](../../spec/platforms/README.md), Screenshots).

```sh
mise exec -- design/spec-screenshots/capture.sh                 # iPhone, iPad and Mac, about 45 minutes
mise exec -- design/spec-screenshots/capture.sh iphone          # one device
JOURNAL_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" mise exec -- design/spec-screenshots/capture.sh mac
```

It needs Xcode 26.6 and the tools pinned by mise ([docs/development.md](../../docs/development.md)), Python 3 with Pillow (as for `design/app-store/make_screenshots.py`; without it the files are resized with `sips` and are larger), and an iOS simulator runtime. The Mac capture also needs your Apple Development identity in `JOURNAL_SIGNING_IDENTITY`: the sandboxed app can only keep its keys in the data protection keychain when it is team-signed, and an ad-hoc signature brings back the keychain prompts ([docs/development.md](../../docs/development.md), Team-signed Mac build). The Mac capture opens the app's windows on your screen while it runs, and needs the screen unlocked.

Environment variables, all optional: `JOURNAL_SPEC_OUTPUT` (where the processed files go, default `spec/platforms/apple/screenshots`), `JOURNAL_SCREENSHOT_DERIVED_DATA` (default `artifacts/DD-spec`; delete it afterwards), `JOURNAL_SPEC_TESTS` (iPhone and iPad: a space-separated list of test classes to run, for example `SpecEditorCaptureTests`), `JOURNAL_SPEC_KEEP_RAW=1` (keep the unprocessed captures and the accessibility trees of the iPhone and iPad screens in `artifacts/spec-raw/`, which shows what a screen is made of).

## What it does

1. Seeds the sample library of the App Store captures with `design/app-store/seed-library.sh` (three journals, sixteen entries with images, a table, checklists, templates, an entry with earlier versions). `JOURNAL_SCREENSHOT_FIXED_DATES=1` gives the templates a fixed date, so the lists do not change from one day to the next.
2. Starts two disposable servers on `127.0.0.1:18765` (with the public address `https://journal.example.net`, which Agent Access shows) and `127.0.0.1:18766`, for the states that connect to a server. Nothing leaves the machine.
3. iPhone and iPad: creates one simulator named "iPhone" (iPhone 17) or "iPad" (iPad Pro 11-inch M5), sets its status bar to 9:41 with full battery, builds the opt-in `JournalScreenshots` scheme once, runs the `Spec*CaptureTests` XCUITest classes (light, then dark for a few key screens) and deletes the simulator, also when something fails. Never use a simulator you did not create.
4. Mac: builds the `JournalMacScreenshots` scheme, team-signed, and runs `SpecMacCapture` in the app itself. It opens a copy of the sample library inside the app's container, so your own library and keychain are never touched.
5. Resamples every capture with `process.py` into `spec/platforms/apple/screenshots/<device>/<page-id>-<state>.png`: half of native size (iPhone 603 x 1311, iPad 1210 x 834 in landscape, a Mac window at one pixel per point, 1280 x 800 for the journal window), no alpha, at most 256 colours, typically 50 to 200 KB. A state that failed leaves `failed-*` files that are not copied, and the script exits with an error.

Only the sample library is ever shown. Two guards keep other things out: the Connect to a Server screen lists servers that Bonjour finds on the local network, so it is captured only when none is found (the skipped state is printed), and a Mac capture refuses to write a window that has a sheet open when none was expected.

## Where the code is

| Part | Files |
| --- | --- |
| iPhone and iPad tests | `apps/apple/JournalScreenshots/iOS/Spec*CaptureTests.swift`; `SpecCaptureCase.swift` is the base class (launching on a copy of the sample library, finding, capturing). Classes run in the order in `capture.sh`: warm-up (closes a new simulator's keyboard tips), browse, editor, library, settings, start, data, conflict, journal, sync, then dark |
| Mac test | `apps/apple/JournalScreenshots/Mac/SpecMacCapture.swift` (the states), `SpecMacSupport.swift` (opening, arranging, capturing, sheets), `SpecMacSyncStates.swift` (server, devices in Sync, agent), `SpecMacLibraryStates.swift` (welcome, library problems, conflicts kept as two versions in a second window) |
| Shared fixtures | `apps/apple/JournalScreenshots/Shared/SpecLibraryFixtures.swift`: conflicts to settle (kept as two, and one held) and the damage that makes a library unopenable (the same as `JournalTests/LibraryFixture.swift`) |
| Project | `apps/apple/screenshots.yml` (the scheme and targets; generated into `JournalScreenshots.xcodeproj`, not committed) |
| Seed | `design/app-store/seed-library.sh` and `apps/apple/Packages/JournalCore/Sources/JournalMeasure/ScreenshotLibrary.swift` |

The App Store captures (`design/app-store/capture-ios.sh`, `capture-mac.sh`) are separate and unchanged; the spec classes are opt-in and not part of any check.

## How the states are reached

- iPhone and iPad drive the real UI with XCUITest: taps, typing and menus, from a launch with `JOURNAL_DATA_DIR` set to a copy of the sample library. The seeded library has no device key, so each launch first types the master password. Device authentication is answered by `JOURNAL_UI_TEST_DEVICE_AUTH=success` (a debug build). The simulator's screenshots are always portrait; `process.py` turns the iPad's.
- Library problems are crafted on copies, as `JournalTests` do: unreadable settings, a missing database, a migration from a newer version. Conflicts are recorded with the store's own calls and the app settles them when it opens the library.
- The Mac test cannot click SwiftUI controls (the app's accessibility tree is not built in its own process), so it arranges the model (`AppModel.show`, the sheet flags), runs the toolbar menus' own actions (`JournalToolbarController.configuration.entryActions()`), and posts mouse events at places that come from the captures themselves (`SpecMacSupport.tap`). A change to a Settings pane's layout can move a button: if a state fails or shows the wrong control, look at the capture and update the place. Windows are captured as the window server draws them, with their sheets drawn on top.
- Dark appearance: `simctl ui appearance dark` for the simulators, `NSApp.appearance` on the Mac. Other states are light.

## Not captured, and why

- Scan Code (the camera view): the simulator has no camera. Debug builds read `JOURNAL_TEST_SCANNED_CODE` instead; the page's notes describe the view from the source.
- The Add Device window on the Mac: the app hides it from screen capture (the window comes back black); the iPhone and iPad captures show the same screen.
- The system rating request: simulators show no rating prompt.
- System sheets and panels (the file picker, the share sheet, save and open panels, Face ID and Touch ID prompts): they belong to the system and are not drawn by the app. Menus of the Mac menu bar and context menus are not windows the test can capture; the menu structure is in the Apple commands file.
- The Mac Formatting popover: the popover window comes back as a dark panel without its material; the iPad capture shows the same panel.
- The first step of Connect to a Server where the machine's network lists a server (see above), and Recovery Key (only for libraries created by early builds).
- Dates that are not the sample library's: Settings ▸ Sync ▸ Devices shows the day the capture was made ("Added during server setup on …").

## Adding or changing a state

Add a test method to the class for its area (iOS) or a state function (Mac) and capture with `shot(app, "<page-id>-<state>")` (`capture(window, ...)`; `captureSheet` when a sheet is open). The page's note lists the file under `screenshots:`; `python3 spec/tools/check-spec.py` checks the name, that the file exists, and warns about files no page lists. Run the one class with `JOURNAL_SPEC_TESTS=SpecEditorCaptureTests`, look at the files, then run the whole script for the device before committing: a change to the UI sets the page back to draft until its screenshots are regenerated ([spec/platforms/apple/README.md](../../spec/platforms/apple/README.md)).
