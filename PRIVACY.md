# Privacy Policy

Effective September 29, 2026

I’m Ralph Krauss, and I make My Journal. This policy explains what happens to your information when you use the My Journal apps for iPhone, iPad and Mac, and this project on GitHub, which is the app’s website.

## In short

- The app doesn’t collect any personal data or send anything to me, and I don’t run servers for it.
- There are no analytics, ads or tracking.
- Your journals are stored on your devices and are encrypted by default.
- If you turn on sync, your journals go only to a server you run, encrypted unless you turned encryption off.

## On this page

- [On your devices](#on-your-devices)
- [Sync with your own server](#sync-with-your-own-server)
- [Adding a device](#adding-a-device)
- [Images and camera](#images-and-camera)
- [Archives](#archives)
- [Agent access through your server](#agent-access-through-your-server)
- [Apple](#apple)
- [This project on GitHub](#this-project-on-github)
- [Support requests](#support-requests)
- [Keeping and deleting your data](#keeping-and-deleting-your-data)
- [Children](#children)
- [Changes to this policy](#changes-to-this-policy)
- [Contact](#contact)

## On your devices

Your journals, entries, templates and images are stored in the app on each device. With encryption on, which is the default, they’re encrypted on the device with a key protected by your master password. The key is kept in your device’s keychain.

If you choose Continue Without Encryption when you set up My Journal, your journals are stored unencrypted on your devices, on your server and in archives.

App Lock hides your journals until you authenticate with Face ID, Touch ID or your device passcode or Mac login password. It doesn’t change how they’re encrypted. Face ID and Touch ID are handled by your device, and the app never receives biometric data.

Backups of your device, such as iCloud Backup or Time Machine, can include the app’s data. With encryption on, journal content in them stays encrypted.

The app connects to the internet only to reach a server you set up. Images linked from the web aren’t downloaded, and a link in an entry opens only when you choose it. System features you use while writing, such as Dictation, Writing Tools or a third-party keyboard, are provided by Apple or the keyboard’s developer under their own privacy policies.

## Sync with your own server

Sync is off until you connect to a server. The server is one you run: on your Mac, on a home server or with a hosting provider you choose. I don’t operate a server for My Journal and have no access to yours.

Your master password never leaves your device. The server stores a copy of your journals’ key, locked with your master password, so your other devices can use it. Anyone with the server’s data could try to guess your password, so use a long one from a password manager.

With encryption on, the server stores content it can’t read. It, and anyone with its data or backups, can see:

- how many journals, entries and templates you have
- every version of each, kept permanently, with its size, when it was received and which device sent it, which shows roughly how long your entries are and when you write and edit them
- which items were probably deleted permanently
- each image’s size and when it was uploaded
- each device’s name (on a Mac, the computer name, which often includes your name; on iPhone and iPad, usually the model name), how and when it was added, and whether it was revoked
- network addresses, and when your devices connect; devices sync every few seconds while the app is open, so this shows when you use it

It can’t see journal names, entry titles, entry dates or text, images, image descriptions or templates. Without encryption, anyone with access to the server or its backups can read everything.

If a hosting provider or a network service such as Tailscale is involved, its own privacy policy applies to what it handles. The [security model](SECURITY.md#what-the-server-can-see) has the details.

## Adding a device

To add a device, approve it on a device you already use, or enter your master password on the new device. When you approve, both devices show a six-digit code; check that they match. Your journals’ key is then sent, encrypted, only to that device.

## Images and camera

Images you add are stored with your entries and, with encryption on, encrypted with them. When you add an image, the app removes where it was taken: GPS coordinates and place names. Other details, such as when it was taken and the camera model, are kept.

On iPhone and iPad, the app uses the camera only when you choose Take Photo. The app reads only the photos and files you choose.

## Archives

Export Archive creates a copy of your journals, including images and earlier versions. With encryption on, it’s encrypted and opens only with your master password; without encryption, anyone with the file can read it. You choose where it’s saved.

## Agent access through your server

Agent access is off until you allow an agent in Settings > Agent Access. An AI agent you allow reads only the journals you choose (with **All Journals**, also ones you create later), through your own server, and can’t change anything. To make that possible, your devices keep a copy of those journals on your server for that agent. With encryption on, the copy is encrypted with a key that only the agent’s access unlocks, so your server can read the shared journals while it answers the agent; your other journals stay end-to-end encrypted.

What the agent reads is sent to it. If the agent uses an online service, such as a cloud AI model or a connector in its provider’s app, that service receives what it reads and keeps its access until you revoke it, under its own privacy policy. Your server records which tools each agent used and when, not what it searched for or read. Revoking access deletes the agent’s copy and access on your server; it doesn’t remove what the agent already read. The [security model](SECURITY.md#agent-access-through-mcp) has the details.

## Apple

Apple handles purchases and downloads from the App Store, as described in [Apple’s Privacy Policy](https://www.apple.com/legal/privacy/). I receive sales reports from Apple that don’t identify you.

If you turn on Share With App Developers in your device’s Analytics & Improvements settings, Apple may share crash reports and usage statistics with me. I use them only to fix problems and improve the app.

If you join a TestFlight beta, TestFlight shares crash reports and usage data, including details about your device, with me, along with any feedback and screenshots you send, as described in the [TestFlight terms](https://www.apple.com/legal/internet-services/itunes/testflight/sren/terms.html). Screenshots can show your journals.

## This project on GitHub

My Journal’s website is its repository on GitHub, where this policy is published. I don’t add cookies, analytics or tracking to it. GitHub hosts it, and the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) applies when you visit it. GitHub shows me only aggregate traffic statistics, such as the number of visitors, not who they are.

## Support requests

Issues on GitHub are public, and the [GitHub Privacy Statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement) applies to them. If you email me, I use your message only to reply, keep it no longer than needed and delete it on request.

## Keeping and deleting your data

Nothing is deleted automatically. Deleted items stay in Recently Deleted until you delete them permanently, and your server keeps every version it receives until you delete its data.

I don’t hold your journals or any account for you. If you emailed me or opened an issue, you can ask me to delete your messages or the issue. Your journals are on your devices and, if you sync, on your server:

- Delete entries or journals in the app. They move to Recently Deleted. Choose Delete Permanently to remove them and their version history from this device, and from your other devices when they sync. This doesn’t erase every copy: their images stay in the app’s storage, and your server, its backups and any archives you exported keep earlier versions.
- To remove everything from a device, delete the app. If you sync, first go to Settings > Devices on another device and choose Revoke Access for this one. On a Mac, also delete the PrivateJournal folder inside your user Library folder. If that Mac is your sync server, the folder also holds the server’s data.
- To remove your data from your server, delete the server’s data and its backups. Delete any archives you exported.
- To stop an agent’s access, revoke it in Settings > Agent Access. Ask the agent’s provider about data it already received.

## Children

My Journal doesn’t collect personal data from anyone, including children.

## Changes to this policy

When this policy changes, I’ll publish the new version here with a new effective date. Earlier versions stay in the project’s [public history on GitHub](https://github.com/ralphkrauss/my-journal/commits/main/PRIVACY.md).

## Contact

Ralph Krauss<br>
[ralph@krauss.be](mailto:ralph@krauss.be)

If you have a concern about how I handle your data, you can also contact your data protection authority.
