# App Review notes

The text for App Store Connect > App Review Information, for the iOS and macOS versions of build 16 (version 1.0), plus the background behind it. Written on 2026-10-05 and checked against the code. The Notes field takes at most 4000 bytes ([Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)).

Nothing private belongs here: no tailnet names, host names, personal paths or real journal content. The demo server address and password, if you use one, go only into App Store Connect, never into this repository.

## Fields

| App Store Connect label | Value |
| --- | --- |
| Sign-in required | Off. Leave User name and Password empty: the app has no account, sign-in or login. |
| First name, Last name | Ralph, Krauss |
| Phone number | Owner to enter, in international format (for example +32 …). |
| Email | ralph@krauss.be |
| Notes | The text below, per platform. |
| Attachment | Optional: a 1 to 2 minute screen recording of Agent Access with a real MCP client (see [owner to-dos](#owner-to-dos)). |

## Notes for iPhone and iPad

Paste into the Notes field of the iOS version. Edit or delete the bracketed demo server block first. (about 3510 bytes with the placeholders.)

```text
My Journal is a private journal for iPhone, iPad and Mac (one universal app). There is no account, sign-in or login, and everything except sync works offline without a server.

TRY IT WITHOUT A SERVER
1. Choose Start a Journal > Use Encryption. Enter any master password in Master Password and Verify, and choose Create. A journal named Default opens.
2. Tap New Entry. The Formatting button (Aa) has headings, lists, checklists, quotes and indentation; Insert Image adds several photos at once (Photo Library, Take Photo or Choose File…). Touch and hold an image for Copy, Share…, Save to Photos and Delete.
3. The entry's … menu has Pin Entry, Change Date…, Move Entry…, Save as Template… and Version History…. New libraries have no templates: save one with Save as Template…, then a new empty entry offers "use a template".
4. In Journals: New Journal, Edit to reorder journals, Recently Deleted (Restore, Delete All) and the search field.
5. Settings (gear at the top of Journals):
- Privacy: "Your Journals Are Encrypted", Change Password…, and App Lock (Require Face ID, then Lock My Journal).
- Backup: Export Archive… and Import Archive….
- Erase Journals and Settings… at the end returns the app to its first screen.

MASTER PASSWORD
It protects the encryption key on the device and never leaves it. Nobody can reset it, so no recovery key or account is involved. App Lock uses only Face ID, Touch ID or the passcode.

SYNC IS OPTIONAL
Sync goes only through a server the customer runs themselves: the open-source server, on a home server, a computer of their own or a host they choose. The app only connects to it. We don't operate a server for customers and have no access to theirs. Without a server, Settings > Sync, Devices and Agent Access explain what they need, and everything else works.
[DEMO SERVER: delete this block if no demo server is ready]
To try sync with our review server: on the first screen of a fresh install choose Connect to a Server…, enter [DEMO SERVER ADDRESS], choose Continue, then enter the master password [DEMO MASTER PASSWORD] and choose Connect. Sample journals download. Settings > Devices > Add Device… shows a code that a second iPhone or iPad can scan.

AGENT ACCESS (OPTIONAL, NEEDS A SERVER)
Settings > Agent Access shows the server's MCP address. A person adds it to an AI agent they already use; the agent's request then appears in Agent Access, where they enter the number shown on the agent's page and choose the journals it may read. Access is read-only and can be revoked. Before allowing, the sheet explains that the agent may send what it reads to its AI provider. No AI service is built in.

PERMISSIONS
Camera: Take Photo and scanning a code from another device. Face ID: App Lock and confirming a new device. Photos: only saving an image the person chooses; picking uses the system picker. Local network: finding the person's own server on their network.

NO VPN
The app has no VPN functionality: no NetworkExtension, VPN configuration or tunnel, and it doesn't route or inspect traffic. Some people reach their own server through Tailscale, a separate app they manage themselves; My Journal only mentions it in connection hints and connects to the server's address over HTTPS.

ENCRYPTION
Only the operating system's encryption (CryptoKit, CommonCrypto, Security framework, HTTPS through URLSession), so ITSAppUsesNonExemptEncryption is NO.

PRIVACY
No analytics, advertising or tracking. The app sends nothing to us.
```

## Notes for the Mac

Paste into the Notes field of the macOS version. (about 3270 bytes with the placeholders.)

```text
My Journal is a private journal for Mac, iPhone and iPad (one universal app). There is no account, sign-in or login, and everything except sync works offline without a server.

TRY IT WITHOUT A SERVER
1. Choose Start a Journal > Use Encryption, enter any master password in Master Password and Verify, and choose Create.
2. File > New Entry (Cmd-N). The Format menu and the Formatting toolbar button format text, including checklists and Increase/Decrease Indent; Format > Insert > Image… or dragging adds images. Control-click an image for Copy, Share, Save Image As… and Delete.
3. The entry's … menu has Pin Entry, Change Date…, Move Entry…, Save as Template… and Version History…. New libraries have no templates: save one, then File > New Entry (Cmd-N) and, in the empty entry, "use a template" or File > Use a Template…. Drag journals in the sidebar to reorder them. Recently Deleted has Restore and Delete All….
4. My Journal > Settings: General (Erase Journals and Settings… at the end), Sync, Devices, Privacy (App Lock with Touch ID or the login password, and Lock when inactive), Backup (Export Archive…, Import Archive…), Agent Access.

MASTER PASSWORD
It protects the encryption key on the device and never leaves it. Nobody can reset it, so no recovery key or account is involved.

SYNC IS OPTIONAL
Sync goes only through a server the customer runs themselves: the open-source server, as a container or standalone program on a home server, a computer of their own or a host they choose. The app doesn't include or start a server; it only connects to one with Settings > Sync > Connect to a Server…. We don't operate a server for customers and have no access to theirs. Without a server, Settings > Sync, Devices and Agent Access explain what they need, and everything else works.
[DEMO SERVER: delete this block if no demo server is ready]
To try sync with our review server: on the first screen of a fresh install choose Connect to a Server…, enter [DEMO SERVER ADDRESS], choose Continue, then enter the master password [DEMO MASTER PASSWORD] and choose Connect. Sample journals download.

AGENT ACCESS (OPTIONAL, NEEDS A SERVER)
Settings > Agent Access shows the server's MCP address. A person adds it to an AI agent they already use (for example Claude Code: claude mcp add --transport http my-journal <address>); the agent's request then appears in Agent Access, where they enter the number shown on the agent's page and choose the journals it may read. Access is read-only and can be revoked. Before allowing, the sheet explains that the agent may send what it reads to its AI provider. No AI service is built in.

APP SANDBOX
The app is sandboxed. It has no helper, login item or updater, and downloads no code.

NO VPN
The app has no VPN functionality: no NetworkExtension, VPN configuration or tunnel, and it doesn't route or inspect traffic. Some people reach their own server through Tailscale, a separate app they manage themselves; My Journal only mentions it in connection hints and connects to the server's address over HTTPS.

ENCRYPTION
Only the operating system's encryption (CryptoKit, CommonCrypto, Security framework, HTTPS through URLSession), so ITSAppUsesNonExemptEncryption is NO.

PRIVACY
No analytics, advertising or tracking. The app sends nothing to us.
```

## Background

### How App Review can test everything

- **No account.** Guideline [2.1](https://developer.apple.com/app-store/review/guidelines/#app-completeness) asks for demo account details only if the app has a login. My Journal has none, and everything except sync and agent access works offline on one device, so the notes lead with that path. Any master password works; the minimum length is one character, and it's never sent anywhere.
- **No recovery key.** New libraries are protected by the master password alone; "Recovery Key" appears only for libraries from early test builds. Forgot Password? appears only in the one-time password check before the first archive export, for a library that isn't on a server, after the device owner authenticates. The notes don't send the reviewer there.
- **App Lock** has no PIN: it uses Face ID, Touch ID, Optic ID or the device passcode (Mac: Touch ID or the login password). On a review device without enrolled biometrics, the passcode works.
- **Erase Journals and Settings…** returns to the first screen, which is a quick way for a reviewer to start over or to try Connect to a Server… on a fresh install.
- **Hidden features.** Guideline [2.3.1](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) requires every feature to be discoverable and described. Sync and Agent Access are optional and need a server, so the notes give exact steps.

### Sync without a demo server

Sync needs a server the person runs, and the apps only connect to one. Without a demo server, reviewers on every platform see only the Connect to a Server… screen and the explanations in Sync, Devices and Agent Access. A reviewer could run the open-source server themselves, for example the container on a Mac, but the notes can't ask for that.

**Demo server (recommended, owner decision).** It lowers the risk of a "couldn't review the feature" rejection under guideline 2.1. Setup:

1. Run the server from [self-hosting](../self-hosting/README.md) behind public HTTPS ([HTTPS example](../self-hosting/https.md)) at an address used only for review.
2. Set it up from a test device or simulator with an encrypted library, a long generated demo master password (not one you use anywhere else), and the sample journals from [screenshots-plan.md](screenshots-plan.md#sample-content). Never put real journal content on it.
3. Put the address and the demo password into both Notes fields. They're test credentials for review, not a customer account. Don't commit them.
4. Keep it running through review and each update's review. Afterwards, stop it or rotate the password, and revoke the reviewer's devices in Settings > Sync > Devices.

Signing in with the master password lets any number of reviewer devices join without a one-time setup code. The server slows down repeated wrong passwords (SECURITY.md, "Password guessing").

If you don't run one, delete the bracketed block from both notes. The "Sync is optional" paragraphs then explain why sync can't be tried.

### The Mac app's sandbox

The Mac app is a plain sandboxed client, like the iPhone and iPad app: no helpers, login items or updater, and no downloaded code (guidelines [2.4.5](https://developer.apple.com/app-store/review/guidelines/#mac-app-store) and [2.5.2](https://developer.apple.com/app-store/review/guidelines/#software-requirements)). It uses the outgoing network entitlement to reach the person's own server.

### Third-party AI

Guideline [5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing) requires disclosure and explicit permission before sharing personal data with third-party AI. The Allow Access sheet does both, per journal, and PRIVACY.md describes it. Naming Claude Code in the notes, which aren't public, only helps the reviewer find a client.

### Build 18 rejection (2026-10-08)

Two automated findings, no human review yet:

- **VPN functionality (iOS and macOS, guideline 2.1).** The scan most likely matched the Tailscale hints in the connection screens. The app has no VPN code. Answered in a reply to App Review and the NO VPN section in both Notes fields; keep that section in future submissions.
- **`com.apple.security.network.server` without matching functionality (macOS, 2.4.5).** Left from when the Mac app ran a server. Removed in build 19; the Mac app only makes outgoing connections. Don't add entitlements the app doesn't use.

### Export compliance

See [export-compliance.md](export-compliance.md): keep `ITSAppUsesNonExemptEncryption` as NO, and if asked, answer "None of the algorithms mentioned above".

## Owner to-dos

- [ ] Enter the contact phone number in international format.
- [ ] Decide on the demo server. If yes, set it up and fill in `[DEMO SERVER ADDRESS]` and `[DEMO MASTER PASSWORD]` in both notes; if no, delete the bracketed blocks.
- [ ] Check every step in the notes against the submitted build (button names, menu paths).
- [ ] Optional: record a 1 to 2 minute screen recording of Agent Access with a real MCP client and attach it, since a reviewer may not have one installed.
- [ ] Recount both notes after editing; each must stay under 4000 bytes.
