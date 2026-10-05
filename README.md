<p align="center">
  <img src="design/icon/AppIcon-AppStore-1024.png" width="128" height="128" alt="My Journal app icon: a handwritten “My” in navy ink on paper">
</p>

<h1 align="center">My Journal</h1>

<p align="center">
  An end-to-end encrypted, open-source journal for Mac, iPhone and iPad.<br>
  No account, no subscription, no company server: sync through a server you run, or not at all.
</p>

My Journal is for people who want to own their writing. Your journals stay on your devices, encrypted on the device by default, and sync only through a server you run: on a home server, a Mac or PC, or a host you choose, privately with Tailscale or over HTTPS. Entries are Markdown, the sync, encryption and archive formats are documented, and the native SwiftUI apps and the server are open source under Apache 2.0.

<p align="center">
  <img src="docs/app-store/screenshots/mac/01-hero.jpg" width="860" alt="My Journal on the Mac: journals in the sidebar, a list of dated entries, and the entry Slow Sunday with text and a photo of coffee on a wooden table">
</p>
<p align="center">
  <img src="docs/app-store/screenshots/iphone/01-hero.jpg" width="250" alt="My Journal on iPhone: the entry Slow Sunday with text, a photo, a bulleted list and a checklist">
  <img src="docs/app-store/screenshots/iphone/02-privacy.jpg" width="250" alt="Privacy settings on iPhone: Your Journals Are Encrypted, Change Password, and App Lock with Require Face ID turned on">
  <img src="docs/app-store/screenshots/iphone/06-dark.jpg" width="250" alt="My Journal on iPhone in dark appearance: the entry Porto, day two with a photo of the river at sunset and a checklist">
</p>

**Status: coming to the App Store.** Version 1.0 for iPhone, iPad and Mac is ready for App Review; this page will link to the App Store once it’s available. You can also [build it from source](docs/development.md) for free. Keep an [archive](docs/guide/backups.md) of anything you can’t afford to lose.

## Why My Journal

- **Your data stays yours.** No account, no company server, no analytics or tracking. Encryption happens on your device with a key protected by your master password; your server stores only what it can’t read ([security model](SECURITY.md)).
- **Your server, or none.** Run the non-root container on a home server, a NAS, a VPS or a Mac or PC you keep on, reach it over Tailscale or HTTPS, or keep everything on one device.
- **Open source and open formats.** The apps, the server and the protocol are Apache 2.0. Entries are Markdown, and the sync, encryption and archive formats are documented with test vectors, so other clients can read your data.
- **Your writing is portable.** Export as Markdown gives you plain files, with their images, that any Markdown app opens, such as Obsidian or iA Writer. For a full backup, the encrypted archive keeps everything, including earlier versions.
- **Native and simple.** Native SwiftUI apps with each platform’s controls, menus and keyboard shortcuts, not a web page in a wrapper. The basics, done well: write, format, add photos, find things again. No feeds, streaks or prompts.
- **No subscription, no account.** One purchase covers iPhone, iPad and Mac, with no in-app purchases. Building from source is free.
- **AI on your terms.** No AI service is built in. If you want one, let the agent you already use, such as Claude Code or another MCP client on your own computer, read the journals you choose through your own server. Access is read-only, per journal and revocable.

## Who it’s for

My Journal is for people who want to own their writing: who would rather run their own server than trust someone else’s cloud, want end-to-end encryption without an account or a subscription, prefer open source and plain Markdown, and like native apps that stay simple.

Your writing isn’t locked in: Export as Markdown saves plain files that Obsidian, iA Writer and other Markdown apps open, and Export Archive keeps an encrypted full backup.

It isn’t for everyone. It has no mood tracking, maps, writing prompts, sharing of entries or web app, and syncing between devices needs a server you set up and keep running, such as the container on a home server or a computer you leave on. If you want sync that works with no setup at all, or a large all-in-one notes app, another app will suit you better.

## How it compares

Many journaling apps are good at what they do. Most are built around an account and the developer’s cloud, often with a subscription. My Journal makes different choices:

| | Typical journaling apps | My Journal |
| --- | --- | --- |
| Account | Usually required for sync | None |
| Where your journals sync | The developer’s or the platform’s cloud | A server you run, or nowhere |
| Encryption | Varies; end-to-end encryption is sometimes optional or paid | End-to-end, on by default |
| Data format | Often undocumented | Markdown entries; documented archive, sync and encryption formats |
| AI | Built in, with a provider the app chooses, or none | None built in; your own agent, read-only, for the journals you choose |
| Price | Often a subscription | One purchase for iPhone, iPad and Mac, or build it free |
| Source code | Usually closed | Open source under Apache 2.0 |

## Features

### Writing

- Rich text with headings, bold, italic, underline, strikethrough, lists, checklists, quotes, code, tables and links. Your system’s spelling and correction settings apply.
- Lists with Increase and Decrease Indent; new items start with a capital letter, as anywhere else on your device.
- Markdown shortcuts as you type, and a source view for the Markdown itself.
- Photos and images: add several at once, describe them for VoiceOver, and copy, share or save them again. Location data (GPS coordinates and place names) is removed when you add a photo.
- Templates you create, with a default template for each journal. New libraries start without templates, so there’s nothing to clear away.
- Dated entries: the date is shown in the list and changed with Change Date.
- On the Mac, View > Show Editor Only hides the sidebar and entry list for focused writing.

### Organizing

- Separate journals, for example for personal and work notes, in the order you choose: drag them in the Mac sidebar, or use Edit on iPhone and iPad.
- Pin entries to keep them at the top of their journal and of All Entries.
- Search all entries, and Find and Replace within an entry.
- Version History keeps earlier versions of each entry on the device, so you can restore one.
- Recently Deleted brings back deleted entries, journals and templates, and Delete All empties it.

### Privacy and encryption

- End-to-end encryption, on by default. Entries, journal names, templates, images and image descriptions are encrypted on your device with AES-256-GCM, using a key protected by your master password. The server never receives your password or the key.
- Or choose Continue Without Encryption when you start, if you prefer readable files, and turn encryption on later.
- App Lock with Face ID, Touch ID or your device passcode. On iPhone and iPad, journal content is hidden in the app switcher. On the Mac, My Journal also locks after a period without use (30 minutes unless you choose otherwise), and when your Mac sleeps or you switch users.
- Erase Journals and Settings returns a device to a fresh start, after warning you about anything that isn’t on your server yet.
- Works offline. Everything is stored on your device, and nothing leaves it unless you set up sync.
- The [security model](SECURITY.md) lists exactly what a server can and can’t see.

### Self-hosted sync

- A small ASP.NET Core server with SQLite. Run it as a non-root container, for example on a home server, a NAS, a VPS or a Mac, or as a standalone server on Linux or macOS. The apps are only clients.
- Compose examples for a local container, [Tailscale](docs/self-hosting/README.md#tailscale) and [public HTTPS with Caddy](docs/self-hosting/https.md).
- Add a device by scanning a QR code on a device you already use, by signing in with your master password, or with a pairing code and a check code.
- Servers on your local network can be found with Bonjour, if you turn on the optional announcer.
- Quiet by design: sync runs in the background and only shows a status when you need to act. Changes wait on the device while you’re offline.
- If an entry changes on two devices at once, both versions are kept for you to review. Nothing is overwritten silently.
- Server backups and restores with integrity checks.

### Backups and portability

- Export all your journals, with images and earlier versions, to one archive, encrypted with your master password, and restore or import it later on any device.
- Export as Markdown: a folder per journal, one file per entry with front matter, and the images beside them, for any Markdown app. The [format](protocol/markdown-export.md) is documented.
- Entries are CommonMark Markdown with GitHub-style tables and task lists, and the [archive format](protocol/archive.md) is documented, so other clients can read it.

### Agent access

- Let an AI agent read the journals you choose through your sync server’s MCP address, and ask it about a month, a habit or a pattern. Agents that support the Model Context Protocol with authorization work, such as Claude Code, the Claude apps, ChatGPT, VS Code or Cursor.
- Read-only, per journal and revocable, with a list of recent activity. No AI service is built in.
- See [agent access](docs/guide/agent-access.md) for what agents can read and what to consider before sharing.

### Native and accessible

- Native SwiftUI apps: three columns on the Mac and iPad, familiar stacked navigation on iPhone, with the menus and keyboard shortcuts of each platform.
- Follows your appearance, text size and accessibility settings, and works with VoiceOver and the keyboard.

## Get My Journal

| Platform | Status |
| --- | --- |
| iPhone and iPad (iOS and iPadOS 16 or later) | Version 1.0 coming to the App Store. |
| Mac (macOS 14 or later, Apple silicon or Intel) | Version 1.0 coming to the Mac App Store. |
| Sync server (Linux, macOS or a container) | Run it yourself; see [self-hosting](docs/self-hosting/README.md). |
| Windows, Android and Linux | Planned, after the Apple apps. |

- **App Store:** one purchase covers iPhone, iPad and Mac, and supports development.
- **Build from source:** free. You need a Mac with Xcode; see [development](docs/development.md).

The Apple apps are the first clients. Apps for other platforms will each follow their own platform’s conventions and use the same open protocol, encryption and data format, so your journals can move with you.

## Run your own sync server

Sync is optional. To sync, run the server on a computer you control that stays on, such as a home server, a NAS, a VPS, or a Mac or PC with Docker, and connect your devices to it (see [Sync](docs/guide/sync.md)):

```sh
git clone https://github.com/ralphkrauss/my-journal.git
cd my-journal
docker compose -f deploy/compose.yaml up -d --build
docker compose -f deploy/compose.yaml exec journal setup-code
```

Enter the setup code in the app with Connect to a Server…. This container listens on `127.0.0.1:8080` only. To reach it from your other devices, use the [Tailscale](docs/self-hosting/README.md#tailscale) or [public HTTPS](docs/self-hosting/https.md) setup. [Self-hosting](docs/self-hosting/README.md) covers [running the server on a Mac](docs/self-hosting/README.md#running-the-server-on-a-mac), backups, updates and reverse proxies.

## Questions

- **Do I need a server?** No. Without one, your journals stay on the device you write on. A server is only needed to sync between devices or to let an agent read your journals.
- **Can the person running the server read my journals?** Not with encryption on. They can see things like how many entries you have, their sizes and when your devices sync; the [security model](SECURITY.md#what-the-server-can-see) lists everything.
- **What if I forget my master password?** Nobody can reset it, and your server never receives it. A device that has your journals keeps opening without it, and you can add devices by pairing; see [troubleshooting](docs/guide/troubleshooting.md#i-forgot-my-master-password).
- **Can I get my entries out?** Yes. Export as Markdown saves plain [Markdown files](protocol/markdown-export.md) with their images, which other Markdown apps open. Export Archive saves all your journals, images and earlier versions in a [documented format](protocol/archive.md) that other clients can read.
- **Is there a subscription?** No. One purchase covers iPhone, iPad and Mac, and there are no in-app purchases.

## Using My Journal

The [user guide](docs/guide/README.md) covers:

- [Getting started](docs/guide/getting-started.md): create your journal, choose a master password, write and organize
- [Sync](docs/guide/sync.md): connect to your own server, and [self-hosting](docs/self-hosting/README.md) for running the server
- [Devices](docs/guide/devices.md): add and remove devices
- [Backups](docs/guide/backups.md): export and restore archives, and export as Markdown
- [App Lock](docs/guide/app-lock.md) and [agent access](docs/guide/agent-access.md)
- [Updating](docs/guide/getting-started.md#update-my-journal) and [deleting your data](docs/guide/troubleshooting.md#delete-your-data)
- [Troubleshooting](docs/guide/troubleshooting.md)

## Help and feedback

Questions, problems and ideas are welcome. [Open an issue](https://github.com/ralphkrauss/my-journal/issues/new/choose); [SUPPORT.md](SUPPORT.md) says what to include. Issues are public, so never post journal text, passwords, recovery keys or setup codes.

Report security problems privately through the repository’s Security tab, as described in [SECURITY.md](SECURITY.md).

## For developers

- [Development](docs/development.md): build the apps and the server, and run the checks and tests
- [Architecture](docs/architecture.md): components, data flow, storage, sync, encryption and agent access
- [Protocol](protocol/README.md): versioned contracts for encryption, sync, pairing, archives and agent access, with test vectors
- [Contributing](CONTRIBUTING.md), [changelog](CHANGELOG.md) and [all documentation](docs/README.md)

| Path | Contents |
| --- | --- |
| `apps/apple/` | iPhone, iPad and Mac apps (SwiftUI) and the shared JournalCore Swift package |
| `server/` | Sync server (ASP.NET Core, EF Core, SQLite) and its tests |
| `protocol/` | Versioned contracts and test vectors |
| `deploy/` and `packaging/` | Compose files for local, Tailscale and public HTTPS hosting, and package contents |
| `scripts/` | Build, check, packaging and end-to-end test scripts |
| `docs/` | User guide, developer documentation and design records |

## License

© 2026 Ralph Krauss. Licensed under the [Apache License 2.0](LICENSE); see also [NOTICE](NOTICE). Third-party components are listed for the apps in [ThirdPartyNotices.txt](apps/apple/JournalApp/Resources/ThirdPartyNotices.txt) and for the server in [server-THIRD-PARTY-NOTICES.txt](packaging/server-THIRD-PARTY-NOTICES.txt). See the [Privacy Policy](PRIVACY.md) for how My Journal handles your data.

Apple, iPhone, iPad, Mac, App Store, Face ID and Touch ID are trademarks of Apple Inc., registered in the U.S. and other countries and regions.
