# App Privacy answers

The answers for App Store Connect > App Privacy, for both the iOS and macOS versions of My Journal. Checked on 2026-10-05 against build 17's code (the Swift app and the JournalCore package; since 2026-10-05 the Mac app no longer includes the .NET server), [PRIVACY.md](../../PRIVACY.md), [SECURITY.md](../../SECURITY.md) and the privacy manifest (`apps/apple/JournalApp/Resources/PrivacyInfo.xcprivacy`).

## Answers

| Question | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app.** Then Save. No further questions follow. |
| Privacy Policy URL | `https://github.com/ralphkrauss/my-journal/blob/main/PRIVACY.md` |
| Privacy Choices URL (optional) | Leave empty. There is nothing to opt out of. |

The product page then shows **Data Not Collected**. Answers are made at the app level and must cover every platform ([Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)). The iPhone, iPad and Mac apps are all clients built from the same code; none of them includes a server.

The privacy manifest agrees on tracking and collection: `NSPrivacyTracking` is false, and `NSPrivacyTrackingDomains` and `NSPrivacyCollectedDataTypes` are empty. Its required-reason APIs are listed in [Privacy manifest](#privacy-manifest).

## Apple's definition

Apple defines collection as follows ([App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)):

> "Collect" refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time.

The same page says that data processed only on the device isn't collected, and "You are not responsible for disclosing data collected by Apple."

## What the code does

Every network connection, from a search of the Swift app, the JournalCore package and the server (2026-10-05):

| Where | What it reaches |
| --- | --- |
| `ServerClient.swift`, `SyncWaiting.swift` (URLSession) | Only the server the person connected to. HTTPS, or plain HTTP to `localhost`, `127.0.0.1` or `::1` only; redirects are refused. |
| `ServerBrowser.swift` (Bonjour browse for `_myjournal._tcp`) | Looks for the person's own server on the local network. The app never announces itself. |
| `SyncHealthOperations.swift` (NWPathMonitor) | Watches network status; sends nothing. |
| Settings ▸ About on iPhone and iPad, the Help menu on the Mac (Privacy Policy, Support, Source Code, the user guide, Rate My Journal) | Open the project's pages on GitHub in the person's browser, or the App Store's review page, only when chosen. |
| `ReviewRequest.swift` (StoreKit's `requestReview`) | Asks the system to show its rating prompt after enough use ([about-and-ratings-2026-10-05.md](../design/about-and-ratings-2026-10-05.md)). The counters it decides with stay in the app's own preferences on the device; the app sends nothing. Ratings are submitted by the system to Apple, which the developer doesn't collect. |
| The person's own server, `OAuthClients.cs` (not part of the apps) | When an MCP agent that identifies itself with an `https://` address asks for access, the person's server downloads that public client description (at most 16 KiB, public addresses only, no redirects). Nothing about the person or their journals is sent. |

Not present anywhere: analytics, crash reporting, advertising or attribution SDKs, MetricKit, CloudKit or iCloud, StoreKit purchases (StoreKit is used only for the system's rating prompt), web views (WKWebView, SFSafariViewController), link previews, remote image loading (remote images show as "Remote image. Not downloaded."), AdSupport or App Tracking Transparency. The Swift dependencies are GRDB, swift-markdown and swift-cmark; the server's are Entity Framework Core and SQLite. None of them uses the network. The server has no telemetry exporter.

## Why each flow isn't collection

### On the device

Journals, entries, templates, images, image descriptions, the master password, keys and settings stay on the device. Encryption keys are in the Keychain. Nothing is sent to the developer. Processing only on the device isn't collection.

Photos and the camera: the app reads only the photos and files the person picks (through the system picker, without Photos library access), uses the camera only for Take Photo and for scanning another device's code, writes to Photos only for Save to Photos, and removes the location from images it adds.

Face ID and Touch ID are handled by the system; the app receives only success or failure. App Lock has no PIN or other secret of its own.

Erase Journals and Settings removes the device's data and asks the person's own server to sign the device out.

### Sync with the person's own server

Sync is off until the person connects to a server they run, separately from the app: on a home server, a computer of their own, or a host they choose. The developer doesn't operate a server for My Journal, has no access to the person's server, and has no partner that does.

- The server's operator is the person, not the developer or a "third-party partner" of the developer. Hosting providers and Tailscale are services the person chooses and contracts with; the app includes no SDK or code from them.
- With encryption on (the default), the server stores content it can't read. It still sees metadata such as device names, sizes and times (SECURITY.md, "What the server can see"). This is disclosed in PRIVACY.md, but it's the person's own server, so it isn't collection by the developer.

### Adding a device

Pairing runs between the person's devices through the person's server. The check code is compared on the devices, and a scanned code carries a secret the server never sees. Nothing reaches the developer.

### Agent access

Off until the person allows an agent in Settings > Agent Access, on any device that syncs. The agent is one the person already uses and chose; it connects to the person's own server's MCP address, and reads only the journals the person selected. Access is read-only and revocable.

- The developer receives nothing and has no agreement with any agent provider, so the agent isn't the developer's third-party partner.
- If the agent uses an online AI service, that service receives what it reads under its own privacy policy. PRIVACY.md and the Allow Access sheet say so before access is allowed, which also meets guideline [5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing) (disclosure and explicit permission before sharing personal data with third-party AI).
- The client-description download described above goes from the person's server to the agent's developer, at the agent's request, and carries no personal data.

### Archives

Export Archive writes a file to a place the person chooses. Nothing is sent anywhere.

### Crash reports and analytics

- No analytics, crash reporting or advertising code, and no MetricKit.
- Crash reports and usage statistics from people who turn on Share With App Developers, and TestFlight feedback, are collected by Apple and shared through App Store Connect and Xcode. Apple's definition excludes data collected by Apple. PRIVACY.md ("Apple") describes this anyway.
- App Store sales reports come from Apple and don't identify people.

### Support

GitHub issues and email happen outside the app, so they aren't data collected from the app. PRIVACY.md covers them.

### Tracking

No. The app doesn't link data with third-party data for advertising or share it with data brokers, and it has no tracking domains.

## Privacy manifest

Apple asks every bundle whose executable uses an API from its [required reason list](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) to declare it in that bundle's `PrivacyInfo.xcprivacy`, with approved reasons ([NSPrivacyAccessedAPITypeReasons](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons)). App Store Connect refuses iOS uploads that miss one (ITMS-91053); macOS isn't checked at upload, but the Mac app declares its uses too. Audited for build 17 on 2026-10-05 from the sources and from the symbols the built binaries import (`nm -u`, plus the Objective-C selectors in the app binary), for all five categories: file timestamp, system boot time, disk space, active keyboards and user defaults.

**The app** (`apps/apple/JournalApp/Resources/PrivacyInfo.xcprivacy`, the same file for iPhone, iPad and Mac):

| Category and reasons | API and where | Why these reasons |
| --- | --- | --- |
| `NSPrivacyAccessedAPICategoryUserDefaults`: `CA92.1` | `UserDefaults.standard` and `@AppStorage`: Format Markdown as You Type, Last Synced (`SyncSchedule.swift`), the rating request's counters (`ReviewRequest.swift`) | Only the app's own defaults; no app group suite, nothing read from other apps or the system. |
| `NSPrivacyAccessedAPICategoryFileTimestamp`: `C617.1` | `URLResourceValues.contentModificationDate` in `ServerJoining.swift` (`removeAbandonedCopies`) | Reads the modification date of the app's own `vault-` folders in its data folder (the app container, or the app group container), to leave a connection in progress alone. Nothing is shown or sent. |
| `NSPrivacyAccessedAPICategoryDiskSpace`: `E174.1`, `85F4.1` | `volumeAvailableCapacityForImportantUsage` in `EncryptionOperations.swift` (`requireSpace`) | Before Turn On Encryption copies the library, it checks there is room to write the copy and stops if not (`E174.1`); the message shows how much space to free up, derived from the available capacity (`85F4.1`). Nothing is sent. |

Not used by the app: system boot time (`systemUptime` appears only in the `JournalMeasure` tool, which isn't shipped; no `mach_absolute_time`), active keyboards (`activeInputModes`), `stat`-family calls, `getattrlist`, `creationDate` or file attribute dictionaries. `fileSizeKey`, used for archives and attachments, isn't on Apple's list. GRDB, swift-markdown and swift-cmark are linked statically into the app binary, so the audit of that binary covers them; GRDB's own (empty) manifest is bundled as `GRDB_GRDB.bundle`. SQLite is the system's library.

Until 2026-10-05 the Mac app also bundled the server, with a privacy manifest of its own. Both were removed, so the app's manifest above is the only one.

To check a build: `nm -u <binary> | grep -E '_(f?stat(at|fs|vfs)?|lstat|statv?fs|getattrlist\w*|mach_absolute_time)$'`, and for the Swift binary `nm -u` for `NSURL…Key`, `systemUptime` and `activeInputModes`. Update the manifest whenever a new use appears.

## When the answer must change

Answer again, and update PRIVACY.md and the privacy manifest, before shipping any of these:

- analytics, crash reporting or feedback that sends data to the developer or a service the developer chooses, including MetricKit payloads uploaded anywhere;
- a sync, relay, backup or demo service run by the developer for customers (a demo server used only by App Review doesn't count, because it's not offered to customers);
- a built-in AI feature, or any integration where the developer picks the provider;
- web content loaded by the app, such as remote images or link previews.
