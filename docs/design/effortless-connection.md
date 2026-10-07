# Effortless server setup and device pairing

Date: 2026-09-28, revision 2 (addresses [effortless-connection-review.md](effortless-connection-review.md) and the security review recorded there). Extends [devices.md](devices.md) and the approved connection screens.

Owner request: setting up a server and connecting devices should feel as easy as Apple's own setup ("magic") without weakening security; find nearby servers automatically; replace the 64-character setup code; choose the master password as part of setting up a server.

Research summary: self-hosted products converge on (1) claiming a server once with something only its owner can read (Plex claim token, Home Assistant onboarding), (2) adding later devices from a device that is already signed in, usually with a QR code (1Password "Set Up Another Device", Signal and WhatsApp linked devices), and (3) local discovery as a convenience with a typed address as fallback (Home Assistant companion app, `_home-assistant._tcp` with URL TXT keys). A QR code carries enough entropy to authenticate both devices, so the scan path needs no code comparison and no PAKE; a typed short code keeps today's check-code comparison. The device that grants access must name what it is about to approve (attacks on Signal device linking relied on people scanning codes blindly).

## What changes for people

| Today | After |
| --- | --- |
| Type the server's HTTPS address on every device | The first device picks the server from **Servers on This Network** or types it once. New iPhones and iPads get it from the QR code. |
| Read a 64-character setup code from a file | Run `setup-code` on the server: `Setup code: K7QM-4XPD` |
| Connect to a Server with no journal ends at "Create a journal on this device first" | Setting up a new server asks for the setup code and a new master password in one step |
| Adding a device: type the address, copy 9 digits from one screen to another, compare two 6-digit codes, confirm on both | New iPhone or iPad: Scan Code, point at the connected device, tap **Add Device** there (Face ID/Touch ID). Macs and devices without a camera keep today's code with check-code comparison. |

Terminology in all copy: **connected device** (already syncs with the server) and **new device**.

## 1. Connect to a Server (new device)

Opened from the welcome screen, the Mac Server section in Settings, and Devices. A `Form` (`.formStyle(.grouped)` on Mac) inside a `NavigationStack`, title **Connect to a Server**, **Cancel** in the cancellation toolbar position and the step's primary action (**Continue**, **Set Up**, **Add This Device**) in the confirmation position, as `CreateJournalView` does. Scrolls at all text sizes.

### 1a. Choose a server

1. **Scan Code** section — iOS and iPadOS only, only when this device has no journals yet (`model.store == nil`) and has a camera. A device that already has journals uses the typed route (1c/1d), where the check code protects against being tricked into uploading them to someone else's server.
   - Button with `qrcode.viewfinder`: **Scan Code**
   - Footer: "On a connected device, open Settings > Devices > Add Device, then scan the code it shows."
2. **Servers on This Network** section.
   - Each discovered server is a row button: primary text the host of its address ("journal.example.ts.net" — the part TLS verifies), secondary text the advertised name ("My Journal on server"). VoiceOver: "journal.example.ts.net, My Journal on server". Rows are deduplicated by address. Tapping a row shows a small progress indicator in it, disables the other rows, and continues exactly as Continue does with that address.
   - Before anything is found: `ProgressView` "Looking for servers…"; after 5 seconds with nothing found: "No servers found on this network." Browsing continues; rows appear when found.
   - Local network access denied: iOS "To find servers automatically, turn on Local Network for My Journal in Settings."; Mac "To find servers automatically, allow My Journal in System Settings > Privacy & Security > Local Network."
   - Only `https` addresses are listed.
3. **Server Address** section: text field, placeholder "https://journal.example.ts.net", footer (existing) "For Tailscale, use your server’s HTTPS address while connected to your tailnet." **Continue** is enabled when the field isn't empty; Return submits.

Browsing runs only while this sheet shows step 1a. After a server is chosen, every later step shows its address read-only at the top of the form with **Change Address** (existing behavior).

### 1b. Server not set up yet

- **Setup Code** section: plain text field (not secure: short, single use, copied from another screen), placeholder "XXXX-XXXX", no autocorrection, characters autocapitalization; accepts any case with or without the hyphen or spaces. Focused on appear. Footer: "To see the setup code, run setup-code on your server." followed by the link **How to Set Up a Server** (the guide page on GitHub).
- With no journal on this device: **Master Password** section — secure field with new-password autofill (Return in Setup Code moves here), **Show Password** toggle, footer "Use at least 12 characters. Save this password in your password manager. If you lose it and access to your devices, you won’t be able to restore your journals. Keep a backup, too."
- With a journal on this device: the existing password or recovery key field, and **Upload Local Journals** with "Your local journals will be added to journal.example.ts.net. Existing journals will be kept." (server host named).
- **Set Up** is enabled when the setup code has 8 valid characters and, where asked, the password has at least 12 characters (new) or isn't empty (existing journal), and Upload Local Journals is on where shown. Progress "Setting Up…".
- Set Up with no journal first creates the encrypted library with that password, then sets up the server. If the server step fails, the sheet keeps the chosen password in memory, shows "Your journal is saved on this device, but the server couldn’t be set up." and the specific error, and offers **Try Again** (same setup code field, editable). Closing the sheet keeps the journal; connecting later uses the existing path with its password field. A library without encryption stays available through Start a Journal.
- Errors: wrong or malformed code "That setup code isn’t valid. Check it and try again."; too many attempts (429) "Too many attempts. Try again in a few minutes."; unreachable server (existing) "Couldn’t connect to the server. Check your connection and try again."

### 1c. Server already set up (typed or discovered address)

Unchanged apart from copy: Add This Device (default) shows the 9-digit code and waits, or Recover Journals. The line under the code becomes "On a connected device, open Settings > Devices > Add Device, then choose Enter Code Instead." The Upload Local Journals consent names the server as in 1b.

### 1d. Mac as a new device

Macs have no scanner in this version: they use discovery or the address, then 1c. A reverse QR (the new Mac shows a code that a connected iPhone scans) is deferred for an owner decision.

## 2. Scan Code (iOS and iPadOS)

Full-screen cover with a live camera preview (`AVCaptureMetadataOutput`, QR only; works on every supported device), accessibility label "Camera preview", a static rounded viewfinder guide (no animation), Cancel at the top leading edge, and at the bottom, on a solid material that becomes opaque with Reduce Transparency: "Point your camera at the code on your connected device." A recognized code gives success haptics and announces "Code found".

- Camera permission not decided: system prompt; `NSCameraUsageDescription` becomes "Take photos for your entries and scan codes to connect your devices."
- Denied: "Allow camera access in Settings to scan the code." with **Open Settings**; Cancel returns to step 1a.
- A QR code that isn't a My Journal code: ignored, scanning continues. A My Journal code of a newer version: "Update My Journal to use this code."
- A code whose server isn't an `https` address (for example a Mac serving only itself): "This code points to a server this device can’t reach."

After a recognized code the sheet shows the server's address read-only, then:

- **Finish on Your Other Device** / "Choose Add Device on your connected device." with `ProgressView` "Waiting for approval…".
- Approved: installs, closes the sheet, sync starts (existing).
- Errors, each with the next step:
  - unreachable: "Couldn’t connect to the server. If it uses Tailscale, turn on Tailscale on this device and try again." / **Try Again** (same code while valid)
  - declined: "Your other device didn’t add this device." / **Scan Again**
  - already used (`invite_used`): "This code was already used. Show a new code on your other device." / **Scan Again**
  - expired: "This code has expired. Show a new code on your other device." / **Scan Again**
  - server without `pairing-invite`: "This server needs an update before you can add devices this way." (never falls back to the typed code for a scanned code)
  - verification failure: "Couldn’t add this device securely. Show a new code on your other device and try again." / **Scan Again**
- Cancel withdraws the request (existing cancellation revokes anything created for it).

## 3. Add Device (connected device)

Settings > Devices > **Add Device…** opens a sheet (Form, toolbar Cancel):

- **QR code** section, centered: the code at a fixed 220 points on a white rounded rectangle with a quiet margin (scans in Dark Mode; doesn't grow with Dynamic Type). Accessibility label "Code for adding a new device". Under it: "On your new iPhone or iPad, open My Journal, choose Connect to a Server, then Scan Code." and a small `ProgressView` "Waiting for your new device…".
- Button **Enter Code Instead…** with footer "For a Mac or a device without a camera." It switches to today's Pairing Code step (check code and Approve unchanged), which also shows "Server address" with the connected address and **Copy Address**.
- Shown only when this device's server address is `https`. A Mac connected to its own bundled server (`http://127.0.0.1`) opens directly on the Pairing Code step with "Other devices connect to this Mac using the HTTPS address from Connection Details." (no Copy Address for loopback).
- When a new device scans the code and its request verifies, the QR section is replaced by:
  - **Add “Alex’s iPhone”?** (name shown with control and bidirectional characters removed, at most 60 characters)
  - "It will be able to read and sync all your journals."
  - **Don’t Add** and **Add Device** (prominent; ⌘Return on Mac, not the plain Return default). Add Device asks for Face ID, Touch ID or the device passcode ("Add a device to your journals") when the device has one; the typed Approve asks too.
  - Progress "Adding Device…"; success dismisses the sheet and refreshes the list (existing).
- States:
  - The code changes every 2 minutes while no device has scanned it, and is discarded when the app leaves the foreground (a new one appears on return). On the Mac the code is kept, and its image stays visible, while another window is in front, because the person may be holding a phone to the screen; it is hidden and discarded only when the app goes to the background (build 18, docs/design/build-18-fixes-2026-10-06.md §3.3). iPhone and iPad hide the image whenever the app isn't active, because the app switcher's snapshot shows the inactive state. The sheet keeps the display awake while a code shows. On Mac the sheet's window is excluded from screen sharing and recording (`sharingType = .none`).
  - After 10 minutes: "This code has expired." with **Show New Code**.
  - Verification fails: never shows a name; "Couldn’t verify the new device. Show a new code and try again." / **Show New Code**. The request is declined.
  - The new device cancels or its request expires while "Add …?" shows: "“Alex’s iPhone” stopped connecting." and a new code.
  - Server unreachable while waiting: keep the code and retry quietly; after three failures in a row show "Couldn’t reach the server. Check your connection." until a retry succeeds.
  - Sheet closed, Don’t Add, or App Lock while a request is pending: the request is declined (best effort; otherwise it expires).
- A server without `pairing-invite` opens directly on the Pairing Code step (today's behavior).

## 4. Setup code on the server

- Format: 8 characters from `23456789ABCDEFGHJKLMNPQRSTUVWXYZ` (no 0/O, 1/I), shown `XXXX-XXXX`; 40 bits, uniform (`RandomNumberGenerator.GetString`).
- `setup-code` in the server image (`docker compose exec journal setup-code`; elsewhere `Journal.Api --setup-code`) prints `Setup code: K7QM-4XPD`, or with `JOURNAL_URL` configured `Setup code for https://journal.example.ts.net: K7QM-4XPD`. The startup log says "This server isn't set up yet. To see its setup code, run setup-code." and never contains the code (AGENTS.md).
- Checking: the server normalizes ASCII (upper case, hyphens and whitespace removed), rejects anything not 8 alphabet characters with 400 `invalid_setup_code` without counting it, then compares hashes in constant time. Wrong codes from all addresses together share one budget, like recovery: after 10 within an hour each attempt waits 30 seconds, doubling up to 15 minutes (429 `rate_limited` with Retry-After). That caps guessing at about a hundred tries a day. The per-address limit (30/minute) still applies. The code stays the same until setup succeeds, when it's deleted (existing).
- Residual risk, documented: someone who can reach an unclaimed server could try codes, so set it up before exposing it beyond your tailnet or network.
- The Mac's bundled server: unchanged; the app reads the code itself.

## 5. Discovery

- Service type `_myjournal._tcp`, TXT `v=1` and `url=<https address>`, instance name "My Journal on <host name>".
- Apple clients browse with `NWBrowser` only while step 1a shows. Info.plist: `NSBonjourServices = [_myjournal._tcp]`; `NSLocalNetworkUsageDescription` becomes "Find and sync with your server on your local network."
- Docker: an Avahi container on the host network (non-root, all capabilities dropped, read-only root filesystem, no D-Bus) publishes the service from `JOURNAL_URL`. It's a Compose profile, `lan`, used by the guide's standard setup; the guide states that it is what makes the server appear automatically and what it reveals.
- Metadata exposure (SECURITY.md and self-hosting): the profile tells everyone on the local network that a My Journal server exists, the host's name and its HTTPS address (including a tailnet name). mDNS doesn't cross Tailscale.
- Trust: a discovered entry is only a suggestion. The host is the primary text, and it stays visible read-only on every later step. A rogue advertisement on the local network could point to an attacker's HTTPS server; the defences are the visible host, the setup code (which a rogue server can't make valid on the real server once used), and for joining, the check code. This is documented; a PAKE-authenticated setup is out of scope.
- Not in scope: advertising the Mac's bundled server (it listens on 127.0.0.1 only).

## 6. Protocol: invite pairing (capability `pairing-invite`)

Reuses check-code pairing (commitment, challenge, reveal, sealed grant); only the authentication changes.

1. The connected device creates, in memory only: invite handle `t` (16 random bytes), secret `s` (32 random bytes, never sent to the server) and its one-time Curve25519 key `A`. It shows a QR code whose text is `MYJOURNAL1.` followed by base64url (no padding) of `t ‖ A (32) ‖ s ‖ UTF-8 server address`. The text contains no colon, so no app can register it as a URL scheme and receive it; only the in-app scanner reads it.
2. The new device creates key `N` and commitment `C` (existing), and `proof = HMAC-SHA256(key: s, message: "journal:v2:pairing-invite" ‖ 0x00 ‖ t ‖ A ‖ C ‖ u16be(len(origin)) ‖ origin ‖ u16be(len(name)) ‖ name)`, where origin is the server's lower-case `https://host` with `:port` only when it isn't 443, and name the exact UTF-8 bytes of the device name it sends. POST /pairing with deviceName, keyCommitment, `invite` (t as 32 lower-case hex) and `inviteProof` (base64). The server requires both or neither, stores the request with code hash `Hash(t)` and returns code = t; a second request for the same invite returns 409 `invite_used`.
3. The connected device polls POST /pairing/lookup with its own `t` (every 3 s, within the 30-per-minute lookup limit). It verifies the proof over its own `t`, `A`, origin and the candidate's commitment and name, with constant-time comparison, before showing anything. It accepts exactly one candidate per code; a bad proof declines the request and ends the code. It then challenges with `A` (existing).
4. The new device accepts the challenge only if approverKey equals `A` from the code, then reveals `N` (existing). The connected device checks the reveal against `C` (existing), asks "Add “name”?" plus device authentication, and seals the grant with `A` (existing). The new device opens only a grant whose first 32 bytes are `A` and installs it without a check code.

Security properties: the server never sees `s`, so it can't forge a request the connected device accepts or change the name it shows; it can't substitute the approver key because the new device knows `A` from the code; nothing short is involved, so nothing can be brute-forced offline. The proof binds the server origin, so a request relayed to another server fails. Residual risk: someone who photographs the code during its 2-minute window and can reach the server could scan it first; they still need the person to choose Add Device on a request carrying their device's name, and the real device then reports that the code was already used. Scan Code is offered only to devices without journals, so a code shown by someone else can't make a device upload existing journals to a server they control.

Server changes: BeginPairing gains optional `invite` and `inviteProof`; `PairRequest.InviteProof` column (migration); lookup and GET /pairing/{id} return `inviteProof`; capability `pairing-invite`; setup-code format, budget, `--setup-code` and the `setup-code` command. Protocol README, self-hosting, SECURITY.md and guide pages are updated, including removing the stale paragraph that says the new device doesn't confirm check codes (the current app does).

## Accessibility and platform notes

- The QR image has a label and the sheet always offers Enter Code Instead, so VoiceOver and Switch Control users and devices without cameras have the typed route. Status changes are announced (existing `announceForAccessibility`); "Code found" on scan.
- Discovered rows wrap at large sizes. The camera cover uses no animation (Reduce Motion) and an opaque instruction background with Reduce Transparency or Increase Contrast.
- `CreateJournalView` copy "Use your master password to restore a backup or connect another device." becomes "Use your master password to restore a backup or recover your journals."
- Lock during any step cancels it (existing lifecycle rules).
- iOS reports the device name as "iPhone" or "iPad" without the user-assigned-name entitlement; the prompt shows what the new device reports.

## Revision 3 — lighter pairing (owner feedback after testing: "still a bit cumbersome")

Tested end to end on the local network (iPhone sets up the server, iPad joins by scanning, Mac joins with the typed code). Two steps remained heavier than they need to be:

1. **Scanned device, connected side: authentication is the confirmation.** When a scanned request verifies, the sheet shows "Add “name”?" / "It will be able to read and sync all your journals." and immediately asks for Face ID, Touch ID or the passcode (reason "Add “name” to your journals"). Success adds the device; the sheet closes. Cancelling the system prompt leaves **Don’t Add** and **Add** visible, and Add asks again. Devices without a passcode keep the explicit Add button. One glance instead of a tap plus a glance; the name stays on screen behind the prompt, so the person still sees what they approve.
2. **Joining a server that's already set up, on any device without a scanned code: master password first.** Step 1c becomes a sign-in: section **Master Password** (secure field with password autofill, so a password manager fills it), footer "Your journals will download to this device." (with journals on this device: the existing Upload Local Journals toggle naming the server), primary **Connect**. Below, a plain button **Use a Code from Another Device Instead…** switches to today's 9-digit code and check-code comparison. Libraries without a password (recovery code, version 4) keep Add This Device as the default and the recovery code as the alternative, as today. This replaces the Connection Method picker. Security is unchanged: this is the existing Recover Journals route (only the password-derived recovery secret is sent, with the server-wide attempt budget), now presented as the normal way to sign in; the Devices list says "Added with your master password".

Copy: the connected device's Add Device footer "For a Mac or a device that can’t scan the code." stays under Enter Code Instead…; the new device's code screen keeps "…then choose Enter Code Instead.".

### Revision 3, after review

- Authentication follows a verified scanned request without a tap only where authenticating is itself deliberate: Touch ID, a passcode or password, or Apple Watch. With Face ID, or while VoiceOver is running, **Add Device** stays the explicit step (then Face ID). The button keeps the label Add Device; the Mac prompt reason is lower case ("add “name” to your journals").
- The sign-in section header names the server: "Sign In to journal.example.ts.net". The field label follows the library's credential (Master Password, or Recovery Key / Access Password for older formats). The alternative route is **Use a Connected Device Instead…**; the code screen offers **Use Master Password Instead**.
- Failures: wrong password "That password isn’t correct."; too many attempts "Too many password attempts on this server. Try again in a few minutes, or use a connected device."; others unchanged.
- Security note (recorded in SECURITY.md): signing in with the password sends the password-derived recovery secret to the chosen server, as Recover Journals always did. A rogue server that the person picks by mistake and that can reach the real server could relay it. The header naming the server, the Devices list ("Added with your master password") and the attempt budget are the current defences; a challenge-response bound to the server's address is proposed as a later protocol change for owner decision.
