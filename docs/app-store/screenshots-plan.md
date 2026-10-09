# Screenshot plan

A designed set of App Store screenshots for iPhone, iPad and Mac, and an App Preview storyboard for later. Each screenshot is a composed frame: a real capture of the app with seeded sample content, placed in a device frame or as a floating window, on a background that echoes the app icon, with a short headline and a quiet sub-line. Everything here is specified so that another agent can seed the app, capture it and compose the frames with Python and Pillow at the exact App Store sizes.

**Release 1.1 (2026-10-09):** File > New Entry from Template…, New Blank Entry and a journal's default template are gone; the template sheet is File > Use a Template…, opened from an empty entry. Frames and captures made before 1.1 that show the earlier command (Mac 5, the storyboard's template step) are recaptured with the listing screenshots when the owner says they are ready.

**Status (2026-10-06):** a new set for build 17 was captured on 2026-10-06 and is waiting for review: seven frames per platform in `artifacts/app-store-screenshots/build-17/` (not in the repository), described in [Build 17 set](#build-17-set). The set in [screenshots/](screenshots/), made on 2026-09-28, stays in place until the new one has been reviewed. The visual style, sizes, positions, fonts and icon are the same as in the 2026-09-28 set; the screens, the sample content, the captions and the upload order changed.

## Apple's requirements

From [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), checked 2026-10-05:

| Set | Size used here | Other accepted sizes | Required |
| --- | --- | --- | --- |
| iPhone 6.9" display | **1320 × 2868** portrait | 1290 × 2796, 1260 × 2736 (and landscape) | Yes, for an app that runs on iPhone. 6.5" is required only if 6.9" is missing; smaller sizes are scaled from these. |
| iPad 13" display | **2752 × 2064** landscape | 2064 × 2752 portrait, 2048 × 2732 / 2732 × 2048 | Yes, for an app that runs on iPad |
| Mac | **2880 × 1800** | 2560 × 1600, 1440 × 900, 1280 × 800 (16:10) | Yes, for Mac apps |

- 1 to 10 screenshots per set; this plan uses 7.
- PNG or JPEG, **no alpha channel or transparency**. Use flattened sRGB, as JPEG at quality 94 without chroma subsampling (visually the same as PNG; with photos in the frames, PNGs would be about twice the size).
- The first three are shown in search results when there's no preview, so they carry the story ([Creating your product page](https://developer.apple.com/app-store/product-page/)). Apple also suggests at least one Dark Mode screenshot.
- Screenshots must show the app in use, not just title art or a login screen; text and image overlays are allowed (guideline [2.3.3](https://developer.apple.com/app-store/review/guidelines/)). No prices or pricing terms (2.3.7). Suitable for 4+ (2.3.8). No other mobile platforms (2.3.10).
- Screenshots don't carry over between the iOS and macOS platform versions; upload each set to its own version.

iPad is landscape because the three-column layout (journals, entries, editor) is the clearest picture of the app there. Keep one orientation per set.

## The story

The set is written for the people who go looking for an app like this (see [Audience](listing.md#audience) in listing.md): privacy, end-to-end encryption, self-hosting, open source and Markdown, and native apps that stay simple. App Store search results show the first three screenshots, so those three say what this audience looks for first: **end-to-end encrypted, your server or none, native and simple**. The feature frames follow.

The copy is in `design/app-store/copy.json`, which `make_screenshots.py` reads. Its keys name the content of a frame (`01` is the hero capture, `06` the dark one), not its place in the upload order.

Upload order and captions:

| Position | Copy key | Headline | Sub-line | Screen | Appearance |
| --- | --- | --- | --- | --- | --- |
| 1 | `01` | End-to-end encrypted | No account, no tracking, and open source. | The editor with a photo and a checklist (iPhone 1, iPad 1, Mac 1) | Light |
| 2 | `03` | Your server, or none at all | Sync through your own server, at home or online. | Devices synced through your own server (iPhone 3, iPad 3, Mac 3) | Light |
| 3 | `06` | Native and simple | Made for iPhone, iPad and Mac, in light and dark. | Dark mode; on the Mac, the Mac, iPad and iPhone together (iPhone 6, iPad 6, Mac 6) | Dark |
| 4 (iPhone, iPad) | `02` | Locked when you step away | App Lock with Face ID or Touch ID. | Settings > Privacy: encryption and App Lock (iPhone 2, iPad 2) | Light |
| 4 (Mac) | `04-mac` | Insights on your terms | Your AI agent, read-only, for the journals you choose. | Agent Access and the agent's answer (Mac 4) | Dark |
| 5 (iPhone, iPad) | `04` | Find it again | Pinned entries, search and Version History. | The Pinned section, Version History (iPhone 4, iPad 4) | Light |
| 5 (Mac) | `02` | Locked when you step away | App Lock with Face ID or Touch ID. | Settings > Privacy with Lock when inactive (Mac 2) | Light |
| 6 | `05` | Separate journals, your own templates | Keep personal and work apart, in the order you choose. | Journals in the chosen order, a table, templates you create (iPhone 5, iPad 5, Mac 5) | Light |
| 7 | `07` | Plain Markdown, yours to keep | Export your journals as Markdown files, with their images. | Settings > Backup with Export as Markdown… (iPhone 7, iPad 7, Mac 7) | Light |

The frame numbers elsewhere in this plan (iPhone 1 to 7 and so on) and the file names in `screenshots/` (`01-hero.jpg` … `06-dark.jpg`) still name the captures. Upload them in the order above, or have `make_screenshots.py` also write copies named by position. With light, light, dark as the first three, the search result row still shows the dark appearance.

On the Mac, Insights takes position 4 because the agents people connect usually run on a computer, such as the Mac. iPhone and iPad use that place for App Lock, and the Mac shows App Lock at 5.

Changed from the 2026-09-28 set: the order (the first three now lead with encryption, the server and native apps instead of "A calm place to write"); every headline except frames 4 and 5; and the card caption "Asked in your AI agent". The hero capture stays first: it shows the app in use, which Apple requires, under the headline people search for. Frame 3's sub-line says "Sync through your own server, at home or online." so it can't be read as syncing without a server; it no longer mentions the Mac, which stopped including a server on 2026-10-05. No frame mentions price or subscription (guideline 2.3.7).

Frame 7 (added 2026-10-06) shows Export as Markdown, new in build 17: Markdown export is one of the reasons this audience picks the app ([Audience](listing.md#audience)), and the listing already says "Export your journals as Markdown files, with their images, for any app." It comes last, so the first six keep their order.

Headlines stay at 6 words or fewer; sub-lines at 10 or fewer. No exclamation marks, no prices, no names of other apps or AI products.

## Build 17 set

Captured on 2026-10-06 from the build 17 tree (commit 1367a1b plus the harness changes below), with Xcode 26.6, the iOS 26.5 simulator runtime and macOS on a Retina display. Nothing was uploaded.

### Where the images are

`artifacts/app-store-screenshots/build-17/` (ignored by git), named by upload position:

| Folder | Size | Files |
| --- | --- | --- |
| `iphone-6.9/` | 1320 × 2868 | `1-hero`, `2-sync`, `3-dark`, `4-privacy`, `5-find`, `6-journals`, `7-markdown` |
| `ipad-13/` | 2752 × 2064 | the same names as iPhone |
| `mac/` | 2880 × 1800 | `1-hero`, `2-sync`, `3-dark`, `4-insights`, `5-privacy`, `6-journals`, `7-markdown` |

`raw/` holds the captures they were composed from, and `contact-sheet.png` all frames at a glance. All are flattened sRGB JPEGs (quality 94, no chroma subsampling), checked for exact size and RGB mode.

### What each frame shows

| Position (copy key) | iPhone | iPad (landscape) | Mac |
| --- | --- | --- | --- |
| 1 (`01`) | "Slow Sunday": photo, the Today checklist with square checkboxes, then the indented list | Three columns, Personal with its Pinned section, "Slow Sunday" open | Three columns, Personal with Pinned, "Slow Sunday" |
| 2 (`03`) | Settings > Devices: MacBook Pro, iPad, iPhone (This Device) | Add Device at "Does iPhone show this code?" | Main window, Settings > Sync connected to `https://journal.example.net` (Last Synced Just now, Sync Now, Stop Syncing…), and the iPhone's Personal list |
| 3 (`06`) | Dark, "Porto, day two" | Dark, three columns, "Porto, day two" | Dark Mac, iPad and iPhone on "Porto, day two" |
| 4 | `02`: Settings > Privacy, Require Face ID on | `02`: the same over the three columns | `04-mac`: dark main window, the agent's page (Writing Assistant reading Personal and Work, Travel off, the read-only note) and the answer card |
| 5 | `04`: Personal with "Books for the autumn" pinned, search field shown, keyboard hidden | `04`: Version History of "Bread, attempt four" over the Pinned list | `02`: Settings > Privacy, Require Touch ID on, Lock when inactive: For 30 minutes |
| 6 (`05`) | Journals list: All Entries, Personal, Work, Travel, Templates | Work with "Offsite ideas" pinned and its table | Work with "Offsite ideas" and File > Use a Template… listing the five seeded templates, opened in a new empty entry |
| 7 (`07`) | Settings > Backup: Archive and Markdown | The same over the three columns | Main window and Settings > Backup |

No frame shows a loopback address, Use This Mac or a server running on the Mac. The only address shown is `https://journal.example.net` (Mac 3, and the spare `04-settings-agents-dark`).

### How Mac frame 3 shows a public address

`capture-mac.sh` starts a disposable server with `Journal__PublicUrl=https://journal.example.net`. The test sets it up as "MacBook Pro" over the loopback port, connects "Writing Assistant" (Mac 4), then captures Settings > Sync. That name doesn't lead to the disposable server, so the library keeps syncing with it on the loopback port while the connection the pane shows names the public address, as a Mac connected to that server through its HTTPS name would. It syncs once more first, so Last Synced is a real synchronization; the test fails if sync reports an error. The connection isn't saved, and the disposable library is deleted afterwards.

The iPhone and iPad frames show no address: the simulators join the server on the loopback port, and no captured screen names it. Add Device on the iPad notes that "Other devices can't connect to 127.0.0.1:…" while the code is typed, but the frame is captured at the check-code step, which doesn't.

### Harness changes for build 17

- **Frame 7, Export as Markdown:** `test7Backup` (iOS) and the Mac test capture Settings > Backup; `make_screenshots.py` composes `07-markdown` like frame 2, and `copy.json` has the `07` caption.
- **Mac 3:** captured last, after Agent Access, connected to the server as described above. The Mac test no longer captures Sync before a server is chosen.
- **Mac frame 4:** the agent's row is opened with a queued mouse click at the first row of the pane, and the page is closed with Return. SwiftUI doesn't expose the pane's content to accessibility in the app's own process while no assistive app runs, so the earlier accessibility press never found the row. Recent Activity is a link on the agent's page in this build, so the page shows the name, the journals and the read-only note rather than the activity list.
- **iPhone 5:** the Journals list (`05-journals-list`) instead of Edit mode, where every row has a blue More button and Templates and Recently Deleted are dimmed. The non-alphabetical order Personal, Work, Travel still shows the chosen order. `05-journals-edit-light` is still captured as a spare.
- **`capture-ios.sh`:** runs the dark pass first, because the light pass ends with `test9Privacy`, which turns App Lock on; the dark run used to stop at the passcode prompt. Runs `test7Backup`.
- **`capture-sync.sh`:** Approve on the iPad asks for Face ID through `LAContext` directly, which a test build doesn't script, so the script enrolls Face ID on the iPad simulator and sends a match once the test writes `ipad-approving`. The test finds the pairing code field by its prompt, since iOS 26 doesn't expose its label. On failure the script prints the iPad run's errors.
- **Both server scripts** create `server.log` before starting the server; the wait loop could read it before it existed and stop the script.
- **`capture-mac.sh`** copies the captures also after a failure (with `failed-*` files), and waits until the files written in the app's container are visible to it.
- **`make_screenshots.py`** takes `--raw` and `--out`, so a set can be composed outside `docs/`.

### Captures that were run

With two cloned simulators (iPhone 17 Pro Max and iPad Pro 13-inch (M5), English (US), keyboard tips marked as shown), deleted afterwards:

1. `JOURNAL_SIGNING_IDENTITY=… design/app-store/capture-mac.sh artifacts/app-store-screenshots/build-17/raw/mac`
2. `design/app-store/capture-ios.sh <iPhone> artifacts/app-store-screenshots/build-17/raw/iphone`
3. `design/app-store/capture-ios.sh <iPad> artifacts/app-store-screenshots/build-17/raw/ipad`
4. `design/app-store/capture-sync.sh <iPad> <iPhone> …/raw/ipad …/raw/iphone`
5. `JOURNAL_SCREENSHOT_FONT=<Inter variable font> python3 design/app-store/make_screenshots.py --raw …/raw --out <folder> --sheet <file>`, then the files were copied to the folders above by upload position.

### Known differences, for review

- **Mac switches are grey.** The Mac windows are captured while another app is frontmost, so switches that are on (Require Touch ID on Mac 2, Personal and Work on Mac 4) are drawn in the inactive style: grey, knob on the right. The 2026-09-28 set was captured the same way. The app can't be made frontmost from the test without interrupting whoever uses the Mac.
- **Agent answer.** The card text on Mac 4 is still the 2026-09-28 text, written from what the scripted requests returned, not a real agent's answer to the question ([Agent answer](#agent-answer)). It matches the seeded entries.
- **iPad Version History** shows the photo as a strip at the bottom of the version preview, as in the 2026-09-28 set.
- **Dates.** "Added … on Oct 6, 2026" (iPhone 3), the iPad status bar date and Last Synced reflect the capture day.

The set still needs review by someone other than its author ([Checklist before upload](#checklist-before-upload)). After that, copy the frames over `docs/app-store/screenshots/` and update README.md's alt text if needed.

## Visual style

### Colors

Taken from the icon ([design/icon/README.md](../../design/icon/README.md)): navy ink `#172C59` on a warm paper gradient.

| Token | Light frames | Dark frames |
| --- | --- | --- |
| Background top | `#FEFDF9` | `#1F335F` |
| Background bottom | `#FDF3E9` | `#0D1834` |
| Background glow (radial, behind the device) | `#FFFFFF` at 45% opacity | `#2A4378` at 35% opacity |
| Headline | `#172C59` | `#F6F0E5` |
| Sub-line | `#586584` | `#BCBBBD` |
| Accent bar | `#172C59` | `#F6F0E5` |
| Device body | `#1B1B1D` | `#1B1B1D` |
| Device inner edge (3 px stroke) | `#3A3A3D` | `#4A4A4E` |
| Shadow | `#172C59` at 20%, blur σ 40 px, offset y +30 px | `#000000` at 45%, blur σ 48 px, offset y +36 px |
| Callout card (frame 4, Mac) | fill `#FBF7F0`, text `#172C59`, secondary text `#586584` | same |

The background gradient is vertical and linear from top to bottom, like the icon. The glow is a radial gradient centered on the device's center, radius 0.55 × canvas width, fading to 0. No texture or grain (it also bloats PNGs).

### Typography

- Headline: SF Pro Display Semibold, tracking −0.5%. Sub-line: SF Pro Text Regular. Both centered.
- Apple's license for the SF fonts covers mock-ups of interfaces for Apple platforms; the owner should confirm it covers these marketing frames. Otherwise use **Inter** (SIL Open Font License) Semibold and Regular with the same sizes; it is close enough in shape. Use one family for the whole set.
- In Pillow, SF Pro can be loaded from `/System/Library/Fonts/SFNS.ttf` (variable) with `font.set_variation_by_name("Semibold")`, or from the installed `SF-Pro-Display-Semibold.otf` from [Apple's fonts page](https://developer.apple.com/fonts/).
- Wrap by measured width, never by character count. Balance two-line headlines (break at the word that makes the lines closest in width). Never shrink below the sizes below; shorten the copy instead.

### Layout per canvas

All values in pixels at the final canvas size. "Top" means the top of the text box (not the baseline).

| Element | iPhone 1320 × 2868 | iPad 2752 × 2064 | Mac 2880 × 1800 |
| --- | --- | --- | --- |
| Side margin for text | 88 | 140 | 160 |
| Accent bar | 64 × 6, radius 3, centered, top 118 | 72 × 6, top 78 | 72 × 6, top 70 |
| Headline size / line height | 100 / 112 | 104 / 116 | 96 / 108 |
| Headline top | 150 | 110 | 100 |
| Headline max lines | 2 | 1 | 1 |
| Gap headline to sub-line | 28 | 24 | 22 |
| Sub-line size / line height | 46 / 60 | 50 / 64 | 46 / 60 |
| Sub-line max lines | 2 | 1 | 1 |
| Device or window | see below | see below | see below |

Frame 1 on each platform replaces the accent bar with the app icon (`design/icon/AppIcon-AppStore-1024.png`, scaled, masked to a rounded rectangle with radius 22.4% of its side): iPhone 132 px at top 104, headline top then 270; iPad 112 px at top 60, headline top 196; Mac 104 px at top 56, headline top 180. On those frames, move the device or window down by the same amount as the headline moved, and scale it down to keep its bottom margin.

#### iPhone device

- Screen: the 1320 × 2868 simulator capture scaled by 0.70 to 924 × 2008, corners masked with radius 122.
- Body: 26 px bezel on every side, so 976 × 2060 outer, corner radius 148. Position the outer frame at x 172, y 700 (bottom 2760).
- Dynamic Island: black pill 250 × 74 px, corner radius 37, centered horizontally, 24 px below the top of the screen. The simulator's screenshot doesn't include it.
- No side buttons, no Apple product bezel images. A plain generic body avoids licensing questions; if the owner prefers Apple's product bezels from [Apple Design Resources](https://developer.apple.com/design/resources/), follow their terms and keep the screen rectangle identical.

#### iPad device (landscape)

- Screen: the 2752 × 2064 capture scaled by 0.68 to 1871 × 1404, corners radius 42.
- Body: 34 px bezel, so 1939 × 1472 outer, corner radius 76, at x 406, y 470 (bottom 1942).
- Camera: 10 px circle `#2A2A2D` centered in the top bezel.

#### Mac window

- Capture the window alone without the system shadow (`screencapture -o`), at 2560 × 1600 (a 1280 × 800 point window on a Retina display). The capture keeps the window's rounded corners as transparency.
- Scale by 0.82 to 2099 × 1312 and place at x 390, y 400 (bottom 1712). Draw the shadow from the window's alpha, then flatten.

#### Composite frames

Positions are for the element's outer bounds on the canvas, drawn back to front.

- **Mac 2, 3, 5 and 7 (Settings or a sheet in front):** back: the main window at scale 0.70 (1792 × 1120) at x 240, y 430. Front: the Settings window (or sheet capture) at scale 0.82, its right edge at x 2640, its bottom at y 1730. Both with shadow; the front one with the stronger dark-frame shadow values even on light frames.
- **Mac 3 also:** an iPhone device (as above) at scale 0.52 of the iPhone outer frame (508 × 1071), at x 2250, y 640, in front of both windows, showing the Personal entries list. It shows the same journals on the phone.
- **Mac 4 (dark):** back: main window at scale 0.70 at x 200, y 430. Front: the agent's page in Settings > Agent Access (its journals) at scale 0.82, right edge x 2680, bottom y 1720. Callout card: 980 × 380, radius 28, fill and text as in the colors table, at x 200, y 1330, over the main window's lower left, with the dark-frame shadow. Card content, 36 px left and right padding: a caption "Asked in your AI agent" (26 px, SF Pro Text Semibold, secondary color, 0.5 px tracking), the question (34 px Semibold), then the answer (32 px Regular, up to 4 lines). See [Agent answer](#agent-answer).
- **Mac 6 (dark):** main window at scale 0.66 (1690 × 1056), centered at x 595, y 420. iPad device at scale 0.42 of its outer frame (814 × 618) at x 1880, y 1080. iPhone device at scale 0.40 of its outer frame (390 × 824) at x 330, y 900. All three show the Travel entry "Porto, day two" in dark mode.

## Frames and UI state

Common setup for all captures: English (U.S.), region United States, 12-hour time, default text size, the seeded library below with App Lock off (except where noted), no sync errors, no badges. iPhone and iPad status bar: 9:41, full battery, full Wi-Fi.

### iPhone (1320 × 2868)

| # | Screen | Details | Capture |
| --- | --- | --- | --- |
| 1 | Editor, Personal > "Slow Sunday" | Keyboard hidden, no selection, scrolled to the top: the title, first paragraph, photo and the "Today" checklist with square checkboxes (one checked) above the writing toolbar. | `01-writing-light` |
| 2 | Settings > Privacy | "Your Journals Are Encrypted", Change Password…; App Lock: Require Face ID on, Lock My Journal. | `02-privacy-light` |
| 3 | Settings > Devices | Three devices: MacBook Pro (added during server setup), iPad (added by MacBook Pro), iPhone (This Device, added by iPad). | `03-devices-light` |
| 4 | Personal entries list | The **Pinned** section with "Books for the autumn" at the top, then the dated entries. Search field visible but not focused; keyboard hidden. | `04-pinned-light` (new) |
| 5 | Journals | All Entries, then Personal, Work, Travel in that order, Templates and Recently Deleted. Edit mode (`05-journals-edit-light`, a spare) adds a More button to every row and dims the rest, so the list is used. | `05-journals-list` |
| 6 | Dark mode, editor, Travel > "Porto, day two" | Photo and checklist with square checkboxes visible. | `06-dark` |
| 7 | Settings > Backup | Archive (Export Archive…, Import Archive…) and Markdown (Export as Markdown…) with their footers. | `07-backup-light` |

### iPad (2752 × 2064, landscape)

| # | Screen | Details | Capture |
| --- | --- | --- | --- |
| 1 | Three columns: Personal selected, "Slow Sunday" open | Sidebar visible; the list starts with the Pinned section; the editor shows the photo and checklist. | `01-writing-light` |
| 2 | Settings sheet > Privacy over the three columns | As iPhone 2. | `02-privacy-light` |
| 3 | Settings > Devices > Add Device… at the check code step | "Does iPhone show this code?" with the six-digit code, approving the iPhone through Enter Code Instead…. Captured during a real pairing with the iPhone simulator. | `03-pairing-light` |
| 4 | Version History… of "Bread, attempt four" | Three earlier versions listed; the list column behind shows the Pinned section. | `04-history-light` |
| 5 | Three columns: Work selected, "Offsite ideas" open | "Offsite ideas" pinned at the top of Work; the table in the editor; the sidebar shows Personal, Work, Travel in that order. | `05-journals-light` |
| 6 | Dark mode, three columns: Travel, "Porto, day two" | | `06-dark` |
| 7 | Settings sheet > Backup over the three columns | As iPhone 7. | `07-backup-light` |

### Mac (2880 × 1800)

| # | Screen | Details | Capture |
| --- | --- | --- | --- |
| 1 | Main window, three columns, Personal > "Slow Sunday" | Window 1280 × 800 points. Sidebar about 220 points, list about 300 points, the Pinned section visible. Insertion point hidden (click in the list before capturing). | `01-main-light` |
| 2 | Composite: main window + Settings > Privacy | App Lock on: Require Touch ID (Require Login Password on a Mac without Touch ID), Lock when inactive: For 30 minutes, Lock My Journal. | `02-settings-privacy-light` |
| 3 | Composite: main window + Settings > Sync + iPhone | Settings > Sync connected to the frame 4 server under its public address `https://journal.example.net`: the address, Last Synced, Sync Now and Stop Syncing… ([How Mac frame 3 shows a public address](#how-mac-frame-3-shows-a-public-address)). The iPhone shows the Personal list with the Pinned section. | `03-settings-sync-light`, iPhone `03-personal-list-light` |
| 4 | Composite, dark: main window + the agent's page in Agent Access + callout card | Agent Access on a disposable server set up as "MacBook Pro": the page of "Writing Assistant", allowed to read Personal and Work and used once. | `04-main-dark`, `04-agent-detail-dark`, `04-settings-agents-dark` (spare) |
| 5 | Composite: main window with an empty entry in Work + File > Use a Template… sheet | The sheet lists the five seeded templates. The entry is empty, so "use a template" shows. | `05-main-light`, `05-sheet-light` |
| 6 | Composite, dark: Mac, iPad and iPhone | All on Travel > "Porto, day two". | `06-main-dark`, iPad and iPhone `06-dark` |
| 7 | Composite: main window + Settings > Backup | As Mac 2, with the Backup pane. | `07-settings-backup-light` |

Don't show Tailscale commands, real server addresses, the Mac's real computer name, Bonjour servers found on the capture network, or a real person's name anywhere. A sync or MCP address, if visible, is `https://journal.example.net`, never a loopback address. The Mac's computer name appears only when the Mac app itself joins a server (Connect to a Server… in the Mac app), so Mac frames 3 and 4 use a disposable server that the test sets up as "MacBook Pro".

## Sample content

Synthetic and written for this set. It must not contain real people's data, test strings or placeholder text. Dates are fixed below, in September 2026. A capture in October 2026 can keep them; only the iPad status bar date, "Added … on" lines and version dates show the capture day. If the capture is more than a month later, shift all of them by the same number of days.

### Library

- Encrypted library. Use a generated test master password stored only in the seeding script's local, untracked configuration (never commit it, never type it into the chat).
- Journals, in this order: **Personal**, **Work**, **Travel**. The order isn't alphabetical, which shows that journals keep the order you choose; the seed sets it explicitly.
- Pinned: "Books for the autumn" in Personal and "Offsite ideas" in Work.
- Journals have no default templates (a journal's default template is gone in 1.1); an entry is started from a template inside a new entry.
- New libraries have no templates ([no-built-in-templates-2026-10-04.md](../design/no-built-in-templates-2026-10-04.md)). The seeded library has five of the person's own: Daily Reflection, Gratitude, Workday Log and Weekly Reflection, with the questions earlier builds included, and **Book Notes**:

```markdown
## Title and author

## What stayed with me

## One idea to try
```

- Recently Deleted: empty.

Entries have a separate title field; the Markdown below is the body. The seed writes it directly. By hand, paste each body in the source view so the formatting is exact, then set the date with Change Date…. Images go at the marked place, with the image description in the photo table.

### Personal

**Slow Sunday** · Sunday, September 27, 2026, 9:12 AM · image `coffee.jpg`

The "Today" checklist comes before the list, so the iPhone hero shows the checkboxes above the writing toolbar.

```markdown
Woke up before the alarm and left my phone in the other room. Made coffee, opened the window and listened to the street wake up. The light comes in lower now. Autumn is arriving one morning at a time.

[image: coffee.jpg]

## Today

- [x] Feed the sourdough starter
- [ ] Call my sister
- [ ] Leave the evening empty

## Worth keeping from this week

- The evening walk along the river on Tuesday
- Finally fixing the wobbly kitchen chair
- Saying no to one more commitment, and meaning it

> Nothing is in a hurry today, including me.
```

**Books for the autumn** · Sunday, September 20, 2026, 4:30 PM · pinned

```markdown
One chapter a night, with the phone in the other room.

- [x] The island novel, finished on the train
- [ ] Something about walking
  - [ ] The one Priya mentioned by the river
- [ ] A book of short poems for the bedside table
- [ ] Reread an old favorite

When I finish one, notes go in a Book Notes entry.
```

**Daily Reflection** · Saturday, September 26, 2026, 9:40 PM (created from the Daily Reflection template)

```markdown
## What went well?

Long lunch outside with Sam. We talked about everything except work, which was exactly right.

## What felt difficult?

Staying focused in the afternoon. Too many tabs open, in the browser and in my head.

## What will I carry into tomorrow?

Close the laptop by six. Walk first, then decide what the evening is for.
```

**The last tomatoes** · Thursday, September 24, 2026, 7:05 PM · image `tomatoes.jpg`

```markdown
Picked the last of the tomatoes before the cold nights arrive. Some are still green; they're ripening on the windowsill next to the basil.

[image: tomatoes.jpg]

Evening walk after dinner. The sky was pink for ten minutes, and then it wasn't. Slept well.

Next year: fewer plants, more space between them.
```

**Gratitude** · Wednesday, September 23, 2026, 10:15 PM (from the Gratitude template)

```markdown
## What am I grateful for today?

- A neighbor who waters the plants without being asked
- The first soup of the season
- A letter from an old friend, the paper kind
```

**Bread, attempt four** · Monday, September 21, 2026, 6:30 PM · image `loaf.jpg`

```markdown
Finally a loaf with a proper ear. What changed:

1. A longer cold proof, 14 hours in the fridge
2. A little less water
3. Scoring at a shallower angle

[image: loaf.jpg]

| Attempt | Proof | Result |
| --- | --- | --- |
| 1 | 4 hours | Flat |
| 2 | 8 hours | Dense |
| 3 | 12 hours | Better |
| 4 | 14 hours | Just right |

Kept the evening free afterwards and read on the sofa.
```

Edit this entry three times while seeding (for example: add the table, then the last line, then fix a word) so Version History has entries for iPad frame 4.

**Rainy walk** · Saturday, September 19, 2026, 11:20 AM · image `path.jpg`

```markdown
It rained all morning, so I went out anyway. The woods smelled of wet leaves and nobody else was on the path. Forty minutes, no podcast, just rain on my hood.

[image: path.jpg]

Walking without headphones is when the good ideas show up.
```

**A quiet chapter** · Thursday, September 17, 2026, 10:45 PM

```markdown
Reading before bed again, one chapter a night instead of one more episode.

> Small, steady, and kind to yourself. That's the whole plan.

Wrote that on the first page of a new notebook years ago. Still true.
```

**A good conversation** · Tuesday, September 15, 2026, 9:30 PM

```markdown
Walked along the river after dinner with Priya. We talked about slowing down without falling behind.

She keeps two evenings a week free and protects them like meetings. Trying it: Tuesdays and Sundays.
```

### Work

**Workday Log** · Thursday, September 24, 2026, 5:40 PM (from the Workday Log template)

```markdown
## What I worked on

- Drafted the onboarding checklist for new team members
- Reviewed the quarterly plan with Alex

## Decisions and context

Ship the smaller version first and learn from it, rather than wait for everything.

## Blockers and open questions

- [ ] Who covers support in the first week of October?

## Where to pick up tomorrow

Finish the checklist and share it for comments.
```

**Week 39** · Friday, September 25, 2026, 4:50 PM (from the Weekly Reflection template)

```markdown
## What stood out this week?

The planning session on Wednesday: short, focused, and everyone left with one clear next step.

## What did I learn?

Writing the decision down first makes the meeting half as long.

## What would I like to change?

Fewer status meetings, more short written updates.
```

**Offsite ideas** · Tuesday, September 22, 2026, 2:10 PM

```markdown
Three options for the team day in November.

| Option | Good | Less good |
| --- | --- | --- |
| A day in the city | Easy to reach | Feels like a normal day |
| Cabin by the lake | Room to think | Long drive |
| Walk and talk | Fresh air, low cost | Depends on the weather |

Leaning towards the cabin, with a long walk on the second morning.
```

**Help center kickoff** · Wednesday, September 16, 2026, 11:00 AM

```markdown
Started the help center project. Goals for the first month:

1. Talk to five customers
2. List the ten most common questions
3. Draft answers in plain language

- [x] Book the customer calls
- [ ] Share the draft outline
```

### Travel

**Porto, day two** · Saturday, September 12, 2026, 10:05 PM · image `river.jpg`

```markdown
Walked down to the river in the late afternoon. Boats, gulls, and the whole city turning orange as the sun went down. Grilled fish at a small place with six tables and no menu.

[image: river.jpg]

- [x] Tile museum
- [x] Walk across the bridge
- [ ] Tram up the hill tomorrow
```

**Train north** · Friday, September 11, 2026, 6:40 PM

```markdown
Six hours on the train and I didn't open the laptop once. Watched the coast go by, wrote two postcards, and fell asleep somewhere after Coimbra.
```

**Packing list** · Tuesday, September 8, 2026, 8:00 PM

```markdown
- [x] Passport
- [x] Chargers
  - [x] Phone and watch
  - [ ] Camera battery
- [x] Walking shoes
- [x] Rain jacket
- [ ] Book for the train
- [ ] Notebook
```

### Photos

| File | Subject | Image description (set in the app) | Used in |
| --- | --- | --- | --- |
| `coffee.jpg` | A cup of coffee on a wooden table by a sunny window, morning light, no branding | A cup of coffee on a wooden table by a sunny window | Slow Sunday (iPhone 1, iPad 1, Mac 1) |
| `tomatoes.jpg` | A bowl of red and green garden tomatoes on a windowsill | A bowl of red and green tomatoes on a windowsill | The last tomatoes |
| `loaf.jpg` | A sourdough loaf with a clear ear, cooling on a wire rack | A sourdough loaf cooling on a wire rack | Bread, attempt four |
| `path.jpg` | A forest path covered in wet autumn leaves, no people | A forest path covered in wet autumn leaves | Rainy walk |
| `river.jpg` | Riverside houses and small boats at sunset (Porto's Ribeira, or any similar riverside; if it isn't Porto, rename the entry "By the river, day two") | Riverside houses and boats at sunset | Porto, day two (iPhone 6, iPad 6, Mac 6) |

The current photos were generated with Codex's image generation at the owner's request (2026-09-28): the prompts are in `design/app-store/photos/PROMPTS.md` and `design/app-store/make_photos.py` crops them to 4:3 and saves them as JPEG. Each was checked at full size, and any that looked artificial, distorted or off-brief was generated again. They can still be replaced; in order of preference:

1. **The owner's own photos.** No license questions. Remove location and other metadata before use.
2. **Unsplash** ([Unsplash License](https://unsplash.com/license): free commercial use, no permission or attribution required, but not for building a competing image service) or **Pexels** ([Pexels License](https://www.pexels.com/license/): similar terms).
3. **Generated photos**, from prompts that describe only the scene, checked at full size before use.

Rules: no identifiable people, no logos, brand names, readable text or other devices in the photo; landscape, 4:3; warm, natural light. Photos are shown at most about 1,350 pixels wide in the captures, so the generated 1448 × 1086 is enough; use at least that. Record each photo's source (URL, author and license, or the prompt) in `design/app-store/photos/SOURCES.md` next to the files, even where attribution isn't required.

### Agent answer

For Mac frame 4, connect a real MCP agent to the seeded library on the disposable frame 4 server (see [Build 17 set](#build-17-set)): add the server's MCP address to the agent, approve its request in Settings > Agent Access with the number its page shows, name it "Writing Assistant", and choose Personal and Work. Then ask:

> What patterns do you see in my September entries?

Use the agent's real answer, shortened to at most 4 lines on the card without changing its meaning, and note which run it came from. The seeded entries are written so that a faithful answer mentions evening walks (September 15, 19, 24 and 27) and keeping evenings free (September 15, 21, 26 and 27). Don't write an answer by hand, and don't show the agent's product name, logo or interface. The card text from 2026-09-28 in `copy.json` was written by the agent that made the captures, from what its scripted requests returned, rather than by an agent answering the question; replace it with a real answer. Capture the agent's page after this run so Recent Activity shows the real requests.

## Capture

### iPhone and iPad simulators

- Devices: iPhone 17 Pro Max (1320 × 2868) and iPad Pro 13-inch (M5) (2064 × 2752; landscape 2752 × 2064), from Xcode 26.6. Use cloned simulators (`xcrun simctl clone`) so the everyday ones stay untouched.
- Status bar: `xcrun simctl status_bar <device> override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100`.
- Appearance: `xcrun simctl ui <device> appearance light` or `dark`.
- Capture: `xcrun simctl io <device> screenshot --type=png <file>`. Rotate the iPad to landscape before capturing. Check that the size is exactly 1320 × 2868 or 2752 × 2064; if an iPad capture comes out portrait, rotate the image by 90° so the content is upright.
- Photos: `xcrun simctl addmedia <device> <files>` puts them in the simulator's Photos library for Insert Image.

### Sync between the captures

iPhone 3 and iPad 3 come from `capture-sync.sh`: a disposable local server that the capture test sets up as "MacBook Pro" with the sample library; the iPad joins, then approves the iPhone, and the iPhone lists all three devices. The simulators share the Mac's loopback interface, so no Tailscale or HTTPS is needed. Don't connect the Mac app to a server with Connect to a Server… for captures: it registers the Mac under its real computer name.

### Mac

- A team-signed development build (`scripts/build-mac-development.sh`) with a separate data folder inside its container, so the owner's own library isn't touched.
- Window size 1280 × 800 points, on a Retina display so the capture is 2560 × 1600. Set it with a script (for example AppleScript `set bounds of front window`), not by hand.
- Capture a single window without shadow: `screencapture -o -l <window id> <file>`. Get the window ID from `CGWindowListCopyWindowInfo` (a few lines of Swift or Python with PyObjC).
- Appearance: System Settings > Appearance, or `osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true'`; restore the owner's setting afterwards.

## Composition

A script, `design/app-store/make_screenshots.py`, in the style of `design/icon/make_icon.py`:

- Inputs: `design/app-store/captures/<platform>/<nn>-<name>-<light|dark>.png` (plus `-settings`, `-sheet` and device captures for composites), `design/app-store/photos/` (only for seeding), `design/app-store/copy.json` with the headlines and sub-lines from [The story](#the-story).
- Output: `design/app-store/screenshots/iphone-6.9/01-hero.png` … `06-dark.png`, likewise `ipad-13/` and `mac/`.
- Steps per frame: background gradient and glow → accent bar or icon → headline and sub-line → shadow (Gaussian blur of the device or window alpha, tinted and offset) → device body and screen, or window → composites and callout card → flatten onto the background → convert to RGB → save PNG with an sRGB profile.
- Draw everything at 2× the final size and downscale once with Lanczos for smooth rounded corners, or draw the rounded masks with 4× supersampling.
- Check at the end: exact pixel size, mode RGB (no alpha), and that no text box crosses its margins or the device.

## Checklist before upload

- [ ] Each set has 7 frames at exactly the sizes above, RGB without alpha.
- [ ] Headline and sub-line text matches this plan and the copy in [listing.md](listing.md); nothing claims a feature the build doesn't have.
- [ ] Only seeded content is visible; no real names, addresses, computer names, server addresses or Tailscale details.
- [ ] Status bars show 9:41, full battery and Wi-Fi.
- [ ] Frame 4 on the Mac uses a real, shortened agent answer, without an agent's brand.
- [ ] Text is readable when a frame is shown at about a quarter of its size (the search results size).
- [ ] Light frames and dark frames look like one set: same margins, sizes and positions.
- [ ] Photo sources and licenses are recorded.
- [ ] The frames were reviewed by someone other than their author, as the rest of the design work is.

## The produced set

This describes the set made on 2026-09-28, which build 17 makes outdated ([Build 17 set](#build-17-set)). Made on 2026-09-28 and saved in [screenshots/](screenshots/): six frames each for `iphone/`, `ipad/` and `mac/`, flattened sRGB JPEGs at 1320 × 2868, 2752 × 2064 and 2880 × 1800. To make them again, from the repository root:

1. `python3 design/app-store/make_photos.py <folder>` crops the generated PNGs in `<folder>` (made from `design/app-store/photos/PROMPTS.md`) to 4:3 and saves them as JPEG in `design/app-store/photos/`. Skip this step to reuse the photos already there.
2. `design/app-store/capture-ios.sh <iPhone or iPad simulator> <folder>` seeds the library (`design/app-store/seed-library.sh`, which keeps its generated master password in the git-ignored `design/app-store/.seed-password`), sets the status bar and runs the opt-in `JournalScreenshotUITests` from `apps/apple/screenshots.yml` in light and dark appearance. Use simulators set to English (US), region United States (`xcrun simctl spawn <device> defaults write -g AppleLocale en_US`, then restart it); another region shows the status bar time as 09:41 and the iPad date as "Mon 28 Sep".
3. `design/app-store/capture-sync.sh <iPad> <iPhone> <iPad folder> <iPhone folder>` captures frame 3 with a disposable local server: "MacBook Pro" sets it up with the sample library, the iPad joins and then approves the iPhone.
4. `design/app-store/capture-mac.sh <folder>` runs the opt-in `JournalMacScreenshots` test hosted in a team-signed build. It opens the sample library in the app's own windows, connects "Writing Assistant" to Personal and Work through the app's agent bridge and saves what the agent read (`agent-transcript.json`).
5. Copy the captures to `design/screenshots/raw/{iphone,ipad,mac}/`, then run `JOURNAL_SCREENSHOT_FONT=<Inter variable font> python3 design/app-store/make_screenshots.py --sheet <contact-sheet.png>`. The copy, including the agent's answer, is in `design/app-store/copy.json`.

Differences from the plan above, for review:

- **Images.** The five photos are generated with Codex's image generation (prompts in `design/app-store/photos/PROMPTS.md`), not downloaded or taken; see [Photos](#photos). An image block has the same space below it as above it (see `docs/design/image-block-spacing.md`); the frames were captured with that spacing.
- **Font.** Inter (SIL Open Font License) instead of SF Pro, because SF Pro's license covers interface mock-ups and wasn't confirmed for marketing images. Tracking is left at 0.
- **Layout.** The text is centered as a block above the device, and the device keeps the same size and place on frame 1 (the icon sits above the headline instead of moving the device down).
- **iPhone 5** shows the Journals list (Personal, Work, Travel, Templates) instead of the Templates… chooser, whose search field keeps the keyboard up.
- **iPad 3** matches the plan ("Does iPhone show this code?"). iPhone 3 lists MacBook Pro, iPad and iPhone; the iPhone was added by the iPad. "MacBook Pro" is the device that set up the server, run from the capture test with JournalCore's client, since the Mac's own name must not appear.
- **Mac captures.** Without screen recording permission, the Mac test captures its own windows from inside the app: the window server's image, and the views drawn at 2x. The current set was captured on a Retina display, where the window server's 2x image has everything and is used as it is. On a 1x display, `make_screenshots.py` uses the sharp 2x views below the toolbar and right of the sidebar and the enlarged 1x image for the toolbar and sidebar, which are slightly softer. The windows were captured inactive; the frontmost window's buttons are drawn in their active colors.
- **Mac 2.** Unlock with Touch ID is off: the capture Mac had no Touch ID available.
- **Mac 3** shows Settings > Sync before a server is chosen (Use This Mac…, Connect to a Server…) rather than a running local server, with the iPhone's Personal list. Use This Mac was removed on 2026-10-05; the build 17 set shows Sync connected to a server instead.
- **Mac 4.** The agent requests went through the app's real bridge with the connector's own client code, from inside the test rather than a separate connector process. The answer on the card was written by the AI agent that made the captures, from what those requests returned; the transcript is in `design/screenshots/raw/mac/agent-transcript.json`. Recent Activity shows the capture time.
- **Mac 5** shows the template sheet (File > Use a Template…; named New Entry from Template… in versions before 1.1) attached to the window, as macOS shows a sheet, instead of a separate front element.

## App Preview storyboard (later)

Optional short videos, up to 3 per set, 15 to 30 seconds, H.264 or ProRes 422 HQ, at most 30 fps and 500 MB ([App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)). Sizes: iPhone 6.9" 886 × 1920 portrait, iPad 13" 1600 × 1200 landscape, Mac 1920 × 1080. Previews may only use screen captures of the app, with optional text overlays and narration (guideline [2.3.4](https://developer.apple.com/app-store/review/guidelines/)). They autoplay muted, so the first seconds must work without sound.

iPhone and iPad (about 24 seconds, same seeded library):

| Time | Screen | Overlay text |
| --- | --- | --- |
| 0–4 s | "Slow Sunday" in the editor. Type "- " at the start of a line; it becomes a list item. Type "Bake bread". | A calm place to write |
| 4–8 s | Insert Image, pick `loaf.jpg`; it appears in the entry. | |
| 8–12 s | Back to Journals, choose Work, then New Entry; choose use a template and pick Workday Log, which fills the entry with its headings. | Separate journals, your own templates |
| 12–15 s | Search "walk"; four results. | |
| 15–20 s | Settings > Privacy: Your Journals Are Encrypted. Lock My Journal, unlock with Face ID. | Encrypted by default |
| 20–24 s | Settings > Devices: MacBook Pro, iPad, iPhone. End on the Personal list. | Sync through your own server |

Mac (about 28 seconds): the same first 12 seconds in the three-column window using keyboard shortcuts (⌘N, typing, ⌥⌘F for Search Entries), then Settings > Agent Access with an agent's request: enter the number from its page, choose Personal and Allow, and a cut to the agent's Recent Activity after a real request (overlay: "Insights from your own writing"), ending on the dark-mode window.

Recording: `xcrun simctl io <device> recordVideo --codec=h264 <file>` for the simulators, and a window recording on the Mac (screencapture `-v`, or QuickTime). Scale and crop with ffmpeg to the exact size at 30 fps; add a silent stereo AAC track if the upload asks for audio. Overlays: same fonts and colors as the screenshots, in the bottom third, with 200 ms fades and no other motion. The poster frame is the first frame of the hero shot.
