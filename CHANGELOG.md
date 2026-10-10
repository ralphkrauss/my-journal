# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The first public version of the source code. No release has been published yet.

### Added

- Native Mac, iPhone and iPad apps built from one SwiftUI code base: several journals, templates, rich text stored as Markdown with a source view, images with descriptions, search, version history and Recently Deleted, which also keeps deleted templates.
- Optional sync through a self-hosted ASP.NET Core server, with conflicts kept as separate versions and device pairing with a check code.
- Encryption on the device by default, protected by a master password, with the option to create journals without encryption.
- App Lock with the device's own Face ID, Touch ID or Optic ID and passcode or Mac login password. There is no separate PIN; an App Lock PIN from an earlier build is replaced by the device's authentication at the first launch.
- Backup archives for export, restore and import. Before the first export the app checks that you still know your master password, and a library that isn't on a server can get a new password after the device owner authenticates (Forgot Password?).
- A standalone server for Linux and macOS, a non-root container image, and Compose examples for local, Tailscale and public HTTPS hosting.
- Agent access through the sync server on every platform: the server is a remote MCP server (Streamable HTTP, protocol revisions 2026-07-28, 2025-11-25 and 2025-06-18) with standard MCP authorization (OAuth 2.1 with PKCE, dynamic client registration and client ID metadata documents, audience-bound, rotating tokens). The agent's request appears in Settings > Agent Access; you allow it by entering the two-digit number its page shows and choosing All Journals (including ones you create later) or selected journals, and you can change its journals, name and end date afterwards. It reads a copy of those journals kept current by your devices, encrypted with a key only its tokens unlock, and you can revoke it at any time (protocol capability `agent-access-2`). The earlier Mac-only local connection was removed, and the app deletes its leftover connection files.
- Versioned protocol documentation with interoperability test vectors, including the record and archive formats.
- The server supports adding a device with a code scanned from a connected device instead of a typed pairing code (protocol capability `pairing-invite`). The scanned code carries a secret the server never sees, so no check code is needed.
- Connecting devices is simpler: a new iPhone or iPad scans a code on a device that already syncs, with no address to type or code to compare; any device can sign in with the master password; and the typed pairing code remains as an alternative. Connect to a Server lists servers announced on the local network (optional `lan` Compose profile), and setting up a new server asks for the setup code and a new master password in one step.
- The server can check a setup code without using it (protocol capability `setup-check`), so a wrong code can be reported before a password is chosen.
- Version History keeps earlier versions of ordinary edits: the version before each editing session and one every ten minutes while you write, up to 50 per entry, on the device.
- Encryption can be turned on for journals created without it: Settings > Privacy > Turn On Encryption…, with the same master password steps as a new journal. When synced, the server replaces its readable copy (protocol capability `encryption-upgrade`) and other devices sign in again. Encryption can't be turned off.
- Connect to a Server takes one step at a time: the setup code (formatted as you type), whether to encrypt, then a new master password entered twice, ending with Server Is Ready and Add Another Device. Joining a server that's set up asks for its master password on a screen of its own, and a new server can be set up without encryption.
- Export as Markdown (Settings > Backup, or File > Export Journals as Markdown… on the Mac and iPad) saves a folder per journal with one Markdown file per entry, YAML front matter and the images, for other Markdown apps. HEIC images are converted to JPEG, and App Lock asks for authentication first. The files aren't encrypted, and it isn't a backup you can import; the format is documented in `protocol/markdown-export.md`.

### Fixed

- Saving an open entry no longer overwrites changes that arrived from another device in the meantime; both versions are kept.
- A record or image the server won't accept no longer stops sync. It stays on the device with an explanation, and Sync Now tries it again.
- An image that can't be downloaded, or a record from a newer version that this one can't read, no longer stops sync. Unreadable records are kept unchanged and read-only.
- Editing no longer duplicates or merges paragraphs, drops text typed after an image, table or rule, or changes list markers and formatting when an entry is reopened.
- Copying and pasting within an entry keeps images, lists and tables, pasted photos keep their original files, and pasted text takes the entry's font.
- An entry with a table directly below a paragraph no longer makes the app quit.
- Agents can connect while the app is closed or locked, and requests no longer hang or fail after the app refreshes. Long entries are read in parts.
- A mistyped setup code or recovery code is reported as such instead of as lost access.
- Import Archive… on the iPhone and iPad welcome screen opens the file picker again.
- A device approved just before its pairing code expired still receives its approval.
- Search Entries is ⌥⌘F and Find and Replace is ⇧⌘F, as in Notes, on the Mac and on iPad.
- Backspace at the start of a list item, task or quote removes one level at a time instead of joining it with the line above.
- On iPhone and iPad, the archive save dialog suggests "Journal Archive" with the date instead of a temporary file name.
- On iPhone and iPad, the entry title's placeholder disappears as soon as you type, and the formatting bar no longer appears twice above the keyboard after moving from the title to the text.
- The Add Device pairing code is grouped as it's typed.
- App Lock is shown as on only once its settings are saved; a failed save keeps the sheet open with the error.
- Recovering a library whose device key was missing resumes syncing with its server right away.
- Quitting while another sync is running no longer waits for it beyond the three-second limit.
- Relaunching reopens the entry you had open in All Entries.
- Long and multiline titles on the Mac are shown in full.
- Zooming keeps the text selection, Add Link accepts addresses such as `HTTPS://example.com`, and Redo works after undoing a deletion.
- Image Descriptions is available from the menu of an entry that isn't open.
- An empty journal offers New Entry.

### Security

- The server sends the password-protected vault key only to a device that proves it knows the password, or to a connected device, and slows down wrong recovery attempts from all addresses together, so the password can no longer be guessed offline from what the server gives anyone.
- Images lose where they were taken (GPS coordinates and place names) when they're added; the image itself is kept unchanged where its format allows.
- After connecting to a server or importing an archive, the previous copy of the library and its keys are deleted once the new copy works.
- A new device uses a pairing only after you confirm the check code on it too (Connect), and accepts a key only from the approving device behind the code it shows.
- The Mac app runs in the App Sandbox.
- The app never sends a typed password to a server, refuses to upload encrypted journals to a server without encryption, and stops if the server's settings change during connecting.
- With App Lock on, iPhone and iPad hide journal content in the app switcher, including sheets and alerts.
- A copied recovery key stays on the device and is removed from the clipboard after two minutes. The wait after wrong PINs continues after relaunching.
- The server checks device credentials before reading a request, limits request sizes per route, rate-limits each device separately, trusts forwarded addresses only from configured proxies, and accepts only local and Tailscale host names when it listens on loopback.
- Wrong setup codes from all addresses together are slowed down after 10 an hour, up to a 15-minute wait, and the server never writes the setup code to its log.
- Server restore refuses backups that contain database objects the server doesn't create. The container runs as a non-root user, and security events are logged.
- Revoked agent access can't return from an older copy of the permissions file.
- Release and TestFlight jobs import signing credentials only after building and delete them right after use; releases are published from a checked draft with build provenance attestations.

### Changed

- The Mac app requires macOS 14 or later. Its window now uses the system's split view and toolbar, as Notes does: New Journal sits beside the sidebar button and leaves with the sidebar, the list shows the collection's name and count with a Journal Actions menu, New Entry and Templates… lead the editor's controls, and search comes last. A window too narrow for all three columns hides the sidebar, and Show Sidebar from editor only shows every column.
- Server errors are problem details with a stable `code`, and GET /v1/server reports the protocol versions, server version and capabilities.
- Setup codes are 6 characters without look-alikes, shown as `K7Q-M4X`, and can be typed in either case. The setup-code file holds the code in the same form, so it can be read directly; a server that starts with an older 8-character code writes a new one. `docker compose exec journal setup-code` (or `--setup-code`) shows the code, including the server's address when `JOURNAL_URL` is set.
- Passwords are normalized to Unicode NFC, so accented letters work however they were typed or pasted; passwords set earlier keep working.
- The server records how each device was added and which device approved a pairing, and returns both in the device list.
- The app and the server refuse data written by a newer version. The server copies its database before migrating it.
- Automatic sync waits longer after each failed attempt, up to five minutes.
- Agent access can be managed in Settings without a journal window; agents can read only while one is open.
- Image descriptions are one line.
- The Mac app is only a client, like the iPhone and iPad apps: it no longer includes a sync server, so Use This Mac… and its controls are gone, and Settings > Sync matches iPhone and iPad. Run the server as the container or the standalone server instead, on any computer, a Mac included. The app now runs fully on Intel Macs, and its download is over 100 MB smaller. A Mac that synced with the removed server stops syncing once, keeps its journals and the old server's files (Erase Journals and Settings keeps them too), and Learn More explains how to sync again. The server no longer watches a parent process (`Journal__ParentProcessId`), which it needed only inside the app, and the apps and the server each ship their own third-party notices.
- Settings > Sync, when not connected, links to How to Set Up a Server. Agent Access without a server says "To let agents read your journals, connect to a server." and offers Connect to a Server…. Add Device on a plain HTTP connection to a server on this device says other devices can't connect to it and asks for the server's HTTPS address.
- Lists start indented: bullets, numbers and checkboxes sit 18 points in from the text, at the same inset as quotes, and nested items line up with their parent's text. The stored Markdown is unchanged.
- The Mac app is distributed through the Mac App Store, with one purchase for iPhone, iPad and Mac, instead of as notarized disk images. Its library moves into the app's container the first time it opens. iPhone, iPad and Mac builds are uploaded to TestFlight by a manually started workflow, GitHub releases hold the standalone Linux server, and development packages are built only on request.
- Large libraries unlock, open entries and search much faster, and typing no longer slows down with library size. Automatic sync sends an entry once writing pauses, and a new device shows its entries before all images have downloaded.
- The Devices list says how each device was added and which device approved it.
- A journal's default template is gone; use a template from inside a new entry. New Entry always starts an empty entry, so New Blank Entry and New Entry In are gone, and File > Use a Template… replaces File > New Entry from Template…. A default template set in an earlier version is ignored, not erased.
- Merge Into… and a journal's Version History are gone. If sync, an import or Merge Journals numbers a duplicate journal (“Work 2”), rename it, or move its entries one at a time and delete the journal. A name changed by mistake is changed back with Rename; the earlier name is not offered back.
- Restore acts at once, with no sheet. When an entry's journal is deleted or missing, the button is Restore to followed by the name of your Default Journal, and Restore Journal brings back a deleted journal with its entries.
- Conflicts settle themselves, keeping both versions, and are listed in Settings > Sync > Changed on Two Devices, with no review form. The Review Changes sheet, its notice and the marker on a list row are gone. When an entry or template changed on two devices, the version that reached the server last stays where it is and the other version is saved as a separate entry or template titled “… (other version)”. The open entry shows a notice with Show Other Version and Dismiss, and the list row opens the other version. If the other device keeps typing, its later text replaces the saved copy as long as you haven’t changed that copy. A journal renamed on two devices keeps the name the server received last. An item deleted permanently on one device and changed on another stays deleted, and the changed version is saved as a separate entry or template in Recently Deleted. A change only a newer version can read stays held, with the line “Update My Journal to combine them”. Until the next sync finishes combining a change from another device, moving that entry, restoring an earlier version of it or deleting it permanently says the changes will finish combining when My Journal next syncs. When 1.1 first opens a library in which an earlier version left such conflicts pending, entries and templates included, it settles them once, keeping both versions, and lists each outcome; a deletion you had meant to confirm is made final and the edit is saved separately in Recently Deleted.
- Every new library is encrypted: Start a Journal is one step, Choose a Master Password, and Connect to a Server no longer offers Don’t Encrypt. 1.1 opens only encrypted journals. A library that 1.0 created without encryption can’t be opened by 1.1: it shows Your Journals Can’t Be Opened and says the journals aren’t encrypted. Nothing is changed or removed, so version 1.0 can still read them, and Erase Journals and Settings… starts over. Encrypt Your Journals, Turn On Encryption… and Continue Without Encryption are gone, and Settings > Privacy shows only the encrypted state. Every device refuses a server that doesn’t use encryption, and an archive that 1.0 saved for journals without encryption can’t be restored.
- An archive is one file. Export Archive saves a single `.journalbackup` file that you can attach to a message or send by AirDrop as it is, and Import Archive opens it. The file is encrypted and opens only with your master password, and Export Archive asks for no device authentication. 1.1 still opens the encrypted `.journalarchive` folders that 1.0 saved, but 1.0 can't open the new file: update every device before you move an archive between them. The format is documented in `protocol/archive.md`, with fixtures, so that Windows and Android can read and write it too.
- Check Your Password is gone. Forgot Password? is in Change Password, Export Archive points to Change Password, and a saved archive says to keep your master password with it.
- The server reports a protocol revision (`protocolRevision`, 1) next to its 13 capability names in `/v1/status` and `/v1/server`, and My Journal reads the revision instead of the individual names. The names stay on the wire for My Journal 1.0 apps and are never extended. My Journal 1.1 syncs with every server since the first 1.0 releases; owners of a server from before them should update the server before the app, which otherwise says “This server needs an update before this device can connect” and changes nothing on the device. Nothing is removed from the server’s API. [protocol/README.md](protocol/README.md#protocol-revision) has the rule and the new fixtures.
- The self-hosting guide has one first deployment route: the local container, then Tailscale or public HTTPS as variations of where it runs, with the address and setup code copied from the same `setup-code` output.
