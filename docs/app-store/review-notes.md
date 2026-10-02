# App Review notes

The text for App Store Connect > App Review Information, for the iOS and macOS versions, plus the background behind it. The Notes field takes at most 4000 bytes ([Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)).

## Fields

| Field | Value |
| --- | --- |
| Sign-in required | No. Leave the user name and password empty. |
| Contact | Ralph Krauss, ralph@krauss.be, phone: owner to fill in |
| Attachment | Optional: a short screen recording of Settings > Agent Access with an agent reading a journal (see [owner to-dos](#owner-to-dos)). |

## Notes for iPhone and iPad

Paste this into the Notes field of the iOS version. Replace the demo server lines, or delete them if no demo server is ready. (2385 bytes with the placeholders.)

```text
My Journal is a private, end-to-end encrypted journal for iPhone, iPad and Mac (universal purchase). There is no account and no sign-in, and the app works fully offline without any server.

TRY EVERYTHING WITHOUT A SERVER
1. Open the app and choose Start a Journal > Use Encryption. Enter any password of at least 12 characters and choose Create. A journal named Default opens.
2. Choose New Entry. Use the Formatting button for headings, lists and checklists, the photo button to insert an image, and the … menu for Change Date, Version History and Save as Template.
3. Templates… starts an entry from a template. The Journals list has New Journal and Recently Deleted. The search field searches entries.
4. Settings (gear in Journals): Privacy > Turn On App Lock (PIN, then Face ID or Touch ID); Backup > Export Archive and Import Archive.

SYNC IS OPTIONAL
Sync goes only through a server the person runs themselves (their Mac, a home server or a host they choose). We don't operate a server for customers and have no access to theirs. Connecting needs the server's address plus either a one-time setup code from that server, the master password, or approval on a device that is already connected.

For review we run a demo server with sample journals:
- On the first screen of a fresh install, choose Connect to a Server… (or use Settings > Sync > Connect to a Server… and keep Upload Local Journals on).
- Address: [DEMO SERVER ADDRESS]
- Choose Recover Journals and enter the demo master password: [DEMO MASTER PASSWORD]
The sample journals then download. To pair a second device, choose Settings > Devices > Add Device… on the first device and enter the pairing code shown on the second one; both show the same six-digit code.

AGENT ACCESS
Settings > Agent Access shows the sync server's MCP address. Agents connect to the person's own server, not to the app; their access requests appear in Agent Access, where the person enters the number the agent's page shows and chooses the journals it may read. Without a server it explains that agent access needs one.

PERMISSIONS
Camera: only when the person chooses Take Photo. Face ID: only for App Lock. Local network: only to reach the person's own server on their network. Photos are read through the system picker without library access.

ENCRYPTION
ITSAppUsesNonExemptEncryption is NO. The app uses only encryption provided by the operating system (CryptoKit, CommonCrypto, Security framework, HTTPS through URLSession).

PRIVACY
No analytics, advertising or tracking; the app sends nothing to us.
```

## Notes for the Mac

Paste this into the Notes field of the macOS version. (2879 bytes with the placeholders.)

```text
My Journal is a private, end-to-end encrypted journal for Mac, iPhone and iPad (universal purchase). There is no account and no sign-in, and the app works fully offline without any server.

TRY EVERYTHING WITHOUT A SERVER
1. Choose Start a Journal > Use Encryption, enter any password of at least 12 characters, and choose Create.
2. File > New Entry (Cmd-N). The Format menu and the Formatting toolbar button format text; Format > Insert > Image… or the Insert Image toolbar button adds an image. The entry's … menu has Change Date, Version History and Save as Template. File > New Entry from Template… starts an entry from a template.
3. My Journal > Settings: Privacy (App Lock with PIN and Touch ID), Backup (Export and Import Archive), Sync, Devices, Agent Access.

OPTIONAL: USE THIS MAC AS THE SERVER
Settings > Sync > Use This Mac… > enter the master password > Start Server. This runs the bundled server, Contents/Helpers/JournalServer.app, so the person's own iPhone and iPad can sync through their Mac. It is sandboxed and inherits the app's sandbox, listens only on 127.0.0.1, uses only the app's container, starts only after the person chooses Use This Mac, stops when the app quits, and never runs at login. To reach it, other devices need a private HTTPS connection such as Tailscale, which the person sets up themselves; the Mac itself syncs with it right away.

We also run a demo server for review: on the first screen of a fresh install choose Connect to a Server… (or Settings > Sync > Connect to a Server… with Upload Local Journals on), address [DEMO SERVER ADDRESS], Recover Journals, demo master password [DEMO MASTER PASSWORD].

OPTIONAL: AGENT ACCESS
On the Mac, choose Settings > Sync > Use This Mac…, then Settings > Agent Access shows an MCP address on this Mac. Add it to an MCP client on the same Mac (for example Claude Code: claude mcp add --transport http my-journal <address>) and authenticate; the client's browser page shows a number, and the request appears in Agent Access. Enter the number, choose the journals and choose Allow. Before access is allowed, the sheet explains that the agent can only read, and may send what it reads to its AI provider. Revoke Access stops it.

Both helpers are in the reviewed bundle. Nothing is downloaded, installed outside the bundle, or added to login items, and there is no updater.

ENCRYPTION
ITSAppUsesNonExemptEncryption is NO. The app and its server use only encryption provided by the operating system (CryptoKit, CommonCrypto, Security framework); the server serves plain HTTP on loopback.

PRIVACY
No analytics, advertising or tracking; the app sends nothing to us.
```

## Background

### Why these notes

- **No sign-in.** Guideline [2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness) asks for demo account details only if the app has a login. My Journal has none, and everything but sync works offline, so the notes lead with the offline path.
- **Hidden features.** Guideline [2.3.1](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) requires every feature to be discoverable and described. Use This Mac and Agent Access are optional and need setup, so the notes give exact steps.
- **Mac helper.** The bundled server is the part most likely to draw questions. The [Mac App Store sandbox record](https://github.com/ralphkrauss/my-journal/blob/main/docs/design/mac-app-store-sandbox.md) maps them to guidelines 2.4.5(i) to (iv), (vii), 2.5.1 and 2.5.2. In short: every executable is sandboxed with no temporary exceptions; the server inherits the app's sandbox and stays inside the bundle; the server starts only on the person's choice and ends with the app; no code is downloaded. (At the time of writing that record is on the sandbox integration branch, not yet in `main`.)
- **Third-party AI.** Guideline [5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing) requires disclosure and explicit permission before sharing personal data with third-party AI. The Allow Access sheet does both, per journal. Naming Claude Code in the notes (which aren't public) only helps the reviewer find a client.

### Export compliance

Both apps set `ITSAppUsesNonExemptEncryption` to `NO` (`apps/apple/project.yml`), so App Store Connect doesn't ask per build. This relies on all cryptography coming from the operating system: CryptoKit (AES-GCM, HKDF, SHA-256, Curve25519), CommonCrypto (PBKDF2), `SecRandomCopyBytes` and HTTPS through URLSession ([release operations](../release-operations.md#export-compliance)). If App Store Connect shows the encryption questions anyway, answer that the app uses encryption, and for the algorithm type choose the option that it uses none of the listed kinds (neither proprietary nor standard algorithms in addition to or instead of the operating system's encryption).

Owner check before the first Mac upload: the Mac build contains the bundled .NET server. Its imports are only system frameworks (Security, CommonCrypto, CryptoKit and others), and it serves plain HTTP on loopback, but the .NET runtime's cryptography hasn't been formally assessed for export compliance. Confirm the answer for the Mac build, as release operations already notes.

### Demo server

The notes offer a demo server because a reviewer can't create one. Without it, iPhone and iPad reviewers can only see the Connect to a Server screen. (An iOS simulator can reach a Mac's loopback server, but a reviewer's device can't.)

Recommended setup:

1. Run the server from [self-hosting](../self-hosting/README.md) behind public HTTPS ([HTTPS example](../self-hosting/https.md)) at an address used only for review, such as `review.<your domain>`.
2. Set it up from a Mac or simulator with an encrypted library, a long generated demo master password (not one you use anywhere else), and the sample journals from [screenshots-plan.md](screenshots-plan.md#sample-content). Never put real journal content on it.
3. Put the address and demo password into both Notes fields. They are test credentials for review, not a customer account. Don't commit them to the repository.
4. Keep it running through review and each update's review. Afterwards, stop it or rotate the password, and revoke the reviewer's devices in Settings > Devices.

"Recover Journals" with the master password lets any number of reviewer devices join without a one-time setup code. The server limits wrong password guesses (SECURITY.md, "Password guessing"), so a mistyped password slows later attempts.

## Owner to-dos

- [ ] Fill in the contact phone number.
- [ ] Set up the demo server and fill in `[DEMO SERVER ADDRESS]` and `[DEMO MASTER PASSWORD]` in both notes, or delete those lines.
- [ ] Confirm export compliance for the Mac build with the bundled server.
- [ ] Check every step in the notes against the submitted build (button names, menu paths, the Formatting and Insert Image buttons).
- [ ] Optional: record a 1 to 2 minute screen recording of Agent Access with a real MCP client and attach it, since a reviewer may not have one installed.
- [ ] Check both notes stay under 4000 bytes after editing.
