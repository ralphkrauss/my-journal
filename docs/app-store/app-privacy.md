# App Privacy answers

The answers for App Store Connect > App Privacy, for both the iOS and macOS versions of My Journal. Checked 2026-09-28 against the app code, [PRIVACY.md](../../PRIVACY.md), [SECURITY.md](../../SECURITY.md) and the privacy manifest (`apps/apple/JournalApp/Resources/PrivacyInfo.xcprivacy`).

## Answers

| Question | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | **No, we do not collect data from this app.** Then Save. No further questions follow. |
| Privacy Policy URL | `https://github.com/ralphkrauss/my-journal/blob/main/PRIVACY.md` |
| Privacy Choices URL (optional) | Leave empty. There is nothing to opt out of. |

The product page then shows **Data Not Collected**. Answers are made at the app level and must cover every platform, so they include the Mac-only features ([Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)).

The privacy manifest agrees: `NSPrivacyTracking` is false, `NSPrivacyTrackingDomains` and `NSPrivacyCollectedDataTypes` are empty, and the only required-reason API is UserDefaults (`CA92.1`, the app's own settings).

## Apple's definition

Apple defines collection as follows ([App privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)):

> "Collect" refers to transmitting data off the device in a way that allows you and/or your third-party partners to access it for a period longer than what is necessary to service the transmitted request in real time.

The same page says that data processed only on the device isn't collected, and "You are not responsible for disclosing data collected by Apple."

## Why each flow isn't collection

### On the device

Journals, entries, templates, images, image descriptions, the master password, keys, the App Lock PIN, and settings stay on the device. Encryption keys are in the Keychain. Nothing is sent to the developer. Processing only on the device isn't collection.

Photos and the camera: the app reads only the photos and files the person picks, uses the camera only for Take Photo, and removes the location from images it adds. The images stay with the entries on the device.

Face ID and Touch ID are handled by the system; the app receives only success or failure.

### Sync with the person's own server

Sync is off until the person connects to a server they run: this Mac, a home server, or a host they choose. The app connects to the internet only to reach that server (PRIVACY.md, "On your devices"). The developer doesn't operate a server for My Journal, has no access to the person's server, and has no partner that does.

- The server's operator is the person, not the developer or a "third-party partner" of the developer. Hosting providers and Tailscale are services the person chooses and contracts with; the app includes no SDK or code from them.
- With encryption on (the default), the server stores content it can't read. It still sees metadata such as device names, sizes and times (SECURITY.md, "What the server can see"). This is disclosed in PRIVACY.md and the in-app choices, but it's the person's own server, so it isn't collection by the developer.
- Network addresses reach only the person's server and any network service they chose.

### Adding a device

Pairing and recovery run between the person's devices through the person's server. The check code is compared on the devices. Nothing reaches the developer.

### Agent access on the Mac

Off until the person adds it in Settings > Agent Access. An AI agent that the person installed and chose reads the journals the person selected, through the connector included in the app, over the Mac's loopback interface.

- The developer receives nothing and has no agreement with any agent provider, so the agent isn't the developer's third-party partner. The person decides which agent reads which journals, and can revoke access.
- If the agent uses an online AI service, that service receives what it reads under its own privacy policy. PRIVACY.md and the Add Agent Access sheet say so before access is allowed, which also meets guideline [5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing) (disclosure and explicit permission before sharing with third-party AI).

### Archives

Export Archive writes a file to a place the person chooses. Nothing is sent anywhere.

### Crash reports and analytics

- The app contains no analytics, crash reporting or advertising SDK, and doesn't use MetricKit. Its dependencies are GRDB and swift-markdown (with swift-cmark), which don't use the network.
- Crash reports and usage statistics from people who turn on Share With App Developers, and TestFlight feedback, are collected by Apple and shared through App Store Connect and Xcode. Apple's definition excludes data collected by Apple. PRIVACY.md ("Apple") describes this anyway.
- App Store sales reports come from Apple and don't identify people.

### Support

GitHub issues and email happen outside the app, so they aren't data collected from the app. PRIVACY.md covers them.

### Tracking

No. The app doesn't link data with third-party data for advertising or share it with data brokers, and it has no tracking domains.

## When the answer must change

Answer again, and update PRIVACY.md and the privacy manifest, before shipping any of these:

- analytics, crash reporting or feedback that sends data to the developer or a service the developer chooses, including MetricKit payloads uploaded anywhere;
- a sync, relay, backup or demo service run by the developer for customers (a demo server used only by App Review doesn't count, because it's not offered to customers);
- a built-in AI feature, or any integration where the developer picks the provider;
- web content loaded by the app, such as remote images or link previews.
