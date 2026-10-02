# Effortless connection review

Date: 2026-09-28  
Reviewer: independent design agent  
Reviewed: `effortless-connection.md` against `AGENTS.md`, the owner's request, approved `devices.md` / `devices-review.md`, and current `ConnectionView.swift`, `DevicesView.swift` (ApproveDeviceView), `CreateJournalView.swift` and the welcome screen in `RootView.swift`. Proposal review only; no UI inspected or implementation edited.

## Outcome

The direction is right and mostly restrained. A QR code shown by a connected device and scanned by the new one is the familiar 1Password/Signal pattern, and carrying the server address inside the code is the biggest real "magic" win: a new iPhone never types an address, even away from home. Local discovery as a suggestion with the typed address always available, an 8-character setup code, and choosing the master password while setting up the server all answer the owner's request directly without adding navigation or a custom visual system. Keeping the welcome screen unchanged is correct; the approving device's instruction tells people exactly where Scan Code is. The protocol keeps the existing commitment/challenge/grant checks and the approver names the device before granting access.

**Revise before implementation.** Findings 1–4 are gaps that would make the "magic" path fail in common setups or leave people without a clear next step; 5–6 are copy and state decisions the proposal leaves open. Re-review the revision before implementing.

## Must fix before implementation

1. **Define the address the QR code carries when the approver's own address isn't reachable by others.** The QR embeds the approving device's server URL. A Mac using the bundled server (Use This Mac) is connected to `http://127.0.0.1:<port>`; other devices need the Tailscale Serve HTTPS address, which the app may not know. The same applies to any approver connected through a loopback or LAN-only address. As written, the owner's likely first setup (server on the Mac, then add an iPhone) produces a code that points the iPhone at its own loopback. Specify where the reachable HTTPS address comes from (for example the Connection Details address other devices use) and what Add Device shows when there is none, e.g. "To add another device, make this Mac reachable from your other devices first." with **Show Connection Details**. Only put an `https` URL (or loopback for development builds) in the code, and have the scanner reject a loopback address from another device with "This code points to a server your other device can’t reach." rather than failing with a generic network error.

2. **Make which device shows and which device scans unambiguous, and finish the Mac path.** The QR flows from the connected device to the new one, while the typed fallback flows the other way (the new device shows the 9-digit code). People will not know which screen to look at unless every instruction says it. Concretely:
   - Scan Code footer: "On a connected device, open Settings > Devices > Add Device, then scan the code it shows." (use "connected device" everywhere; the proposal mixes "a device that already syncs", "your other device" and the shipped "a connected device").
   - Add Device sheet: keep "On your new iPhone or iPad, open My Journal, choose Connect to a Server, then Scan Code." Under **Enter Code Instead…** add the footer "For a Mac or a device without a camera." Adding a Mac is a common case and it is currently invisible on this sheet.
   - Add This Device (new device): *replace* the existing line rather than adding a second one, and match the real button label: "On a connected device, open Settings > Devices > Add Device, then choose Enter Code Instead."
   - The Enter Code step on the approver shows the server address with **Copy Address**, so a Mac that can't discover the server (away from the LAN, or no `lan` profile) can find out what to type. Today the fallback silently assumes the person knows the address.
   - State explicitly that a new Mac keeps the typed code plus check-code comparison in this version. A reverse direction (new Mac shows a QR code, iPhone scans it from Add Device) is a reasonable later addition but not required; record it as a deliberate deferral so the owner can decide.

3. **Complete the error and interruption states for invite pairing on both devices.** The new-device side lists declined, expired and security failure only; the approver side lists expiry only. Add:
   - New device, server unreachable after scanning (typical for a Tailscale address when Tailscale is off): "Couldn’t connect to the server. If it uses Tailscale, turn on Tailscale on this device and try again." / **Try Again** (retries with the same scanned code while it is valid).
   - New device, `invite_used`: "This code was already used. Show a new code on your other device." Do not reuse the expiry message; the residual-risk paragraph says the real device sees "This code has expired…", which hides the one signal that someone else scanned the code.
   - Approver, the new device cancels after scanning: return from "Add “name”?" to a new code with "“name” stopped connecting." rather than leaving a live Add Device button.
   - Approver, proof verification fails: never show a name; show "Couldn’t verify the new device. Show a new code and try again." / **Show New Code**.
   - Approver, network loss while polling: keep the QR code, retry quietly, and after repeated failures show "Couldn’t reach the server. Check your connection." without discarding the code.
   - Approver sheet closed or app locked while a request is pending: the request is declined (state it, as devices.md revision 2 does for the requesting side).
   - While the QR code is on screen, keep the display awake (idle timer) for the code's 10-minute lifetime, and redact the code in the app-switcher snapshot when App Lock is off; the code contains the secret.

4. **Treat discovered and scanned servers as unverified until the person can see where they are connecting, and name the server where data leaves the device.** A Bonjour instance name is spoofable by anything on the network; a QR code can be shown by someone else. Neither is dangerous by itself, but the next steps (setup code, master password, Upload Local Journals) are.
   - After a discovered row is chosen, subsequent screens keep the address visible read-only with **Change Address**, as the current sheet does. Say so in the proposal.
   - In discovered rows, consider the host (the TLS-verified identity) as the primary text and the advertised name as secondary. At minimum, never show the advertised name alone.
   - Upload Local Journals consent names the server: "Your local journals will be added to journal.example.ts.net. Existing journals will be kept." This matters more once a scanned code can choose the server.
   - AGENTS.md requires documenting metadata exposure: note in SECURITY.md/self-hosting that the optional `lan` profile advertises the server's existence, host name and HTTPS address (including a tailnet name) to everyone on the local network.

5. **Decide the setup-code instructions and make them match the real command.** The proposal leaves two copy options and quotes a command (“setup-code”) that doesn't exist; the actual command is `docker compose exec journal dotnet Journal.Api.dll --setup-code`. Recommended:
   - Ship a small `setup-code` executable in the image so the command is `docker compose exec journal setup-code`, and use that in the guide, self-hosting pages and startup log: "This server isn’t set up yet. To see its setup code, run setup-code." (still never the code itself).
   - In-app footer: "To see the setup code, run setup-code on your server." followed by a link **How to Set Up a Server** to the guide page. One command name, no flags, no Docker detail in the app.
   - Setup Code field: placeholder "XXXX-XXXX", accept any case, spaces or hyphen; the plain (not secure) field is the right call.

6. **Fix the combined setup-and-password screen's partial failure and define its structure.** Asking "the password just chosen" again after the server step fails is confusing: the person typed it seconds ago and the field would change meaning under them. While the sheet is open, keep the chosen password in memory and offer **Try Again** with "Your journal is saved on this device, but the server couldn’t be set up." plus the specific error. If the sheet is closed, the existing path applies and nothing is lost; say that in the proposal. Also specify: sections **Setup Code** and **Master Password** (header), the master password footer combining the existing copy ("Use at least 12 characters." then the save/backup paragraph), focus on Setup Code on appear, Return moving to Master Password, and **Set Up** enabled only when the code has 8 valid characters and the password has at least 12.

## Polish (nonblocking)

- **Native sheet structure.** The current sheet is a custom VStack with inline Cancel/Continue; since the proposal moves to a Form, put Cancel and Continue/Set Up in the toolbar as `CreateJournalView` does, and use `.formStyle(.grouped)` on the Mac. When a discovered row is tapped, show progress in that row and disable the others.
- **Discovery copy and states.** "No servers found. Enter your server’s address below." → "No servers found on this network." (the field is right there; avoid spatial "below"). Local network denied is platform-specific: iOS "To find servers automatically, turn on Local Network for My Journal in Settings."; Mac "…in System Settings > Privacy & Security > Local Network." Deduplicate rows by URL (IPv4/IPv6 and multiple interfaces). Expect the local network alert to appear as soon as the sheet opens; that's acceptable.
- **Discovery is opt-in on the server.** With an optional `lan` compose profile, most self-hosters will only ever see "No servers found". Either make the guide's default setup include it or say plainly in the guide that it is what makes servers appear automatically. Keep the Avahi container's privileges minimal and documented alongside the non-root requirement.
- **Scan Code.** iOS 16.4 is the minimum, so VisionKit's `DataScannerViewController` (with its built-in guidance) is worth using where supported, with the AVFoundation scanner as fallback. Announce "Code found" to VoiceOver, keep the instruction text at Dynamic Type sizes on a solid background when Reduce Transparency or Increase Contrast is on, and label the preview. Consider "Point your camera at the code on your connected device." for terminology consistency.
- **Camera app trap.** People will try the Camera app first. Since the scheme is deliberately unregistered, verify on device that Camera offers nothing (in particular no web search of the code text, which contains the secret).
- **Waiting copy on the new device.** "Approve on Your Other Device" names an action ("Approve") that no longer exists on the approver. Use "Finish on Your Other Device" with "Choose Add Device on your other device." and the existing "Waiting for approval…".
- **Approval prompt.** On iOS 16+ `UIDevice.current.name` returns "iPhone" without the user-assigned-name entitlement, so the prompt will usually read "Add “iPhone”?". Acceptable given the QR secret, but consider the entitlement. Label the decline button "Don’t Add" rather than Cancel, so it is clear it declines rather than just closing the sheet.
- **Empty libraries.** A new iPhone where someone tapped Start a Journal before scanning should not have to consent to upload an empty library; skip the Upload Local Journals toggle when there are no entries.
- **Setup code rotation.** After 10 wrong guesses the code changes, so someone may type a code that was valid a minute ago. Make the error "That setup code isn’t valid. Check it, or run setup-code again to see the current code."
- **Stale copy elsewhere.** `CreateJournalView` says the master password is used to "connect another device"; with QR pairing that is no longer the normal path. Suggest "Use your master password to restore a backup or recover your journals."
- **Layout.** Keep the QR code at a fixed size (it should not grow with Dynamic Type) inside a scrolling sheet; verify at accessibility sizes on iPhone SE width and at the Mac minimum sheet size.
- **Considered and agreed:** no Home Assistant–style "first visitor claims the server" without a code; the short setup code is the right trade for a headless server. No PAKE; the QR secret plus the typed code's check-code comparison is sufficient.

## Verification after implementation

Inspect actual UI for: discovery found / none / denied; discovered Tailscale server with Tailscale off; combined setup screen including the partial-failure retry; Scan Code with camera denied, unknown code and newer-version code; approver QR, approval prompt, expiry, decline, cancel-after-scan and `invite_used`; bundled-server Mac showing Add Device; Mac-as-new-device typed path end to end; VoiceOver on every new screen; large text, dark mode, Reduce Motion and Reduce Transparency.

## Verdict

Revise findings 1–6 and re-review before implementation. The overall approach needs no rethink; the revisions stay within native controls and the existing pairing screens.

## Revision 2 re-review — 2026-09-28

Reviewed revision 2 of `effortless-connection.md` against the same requirements. Proposal review only; no UI inspected.

**Resolved.** All six original findings are addressed:

1. The QR code appears only for an `https` server address, and a Mac using its own bundled server opens directly on the Pairing Code step. The scanner rejects non-`https` codes.
2. Terminology is defined. Scan Code tells people to scan "the code it shows". **Enter Code Instead…** covers Macs, and its step shows the server address with **Copy Address**. The line on Add This Device replaces the old one and matches the button label, and the reverse QR is recorded as an owner decision.
3. Both devices have complete error and interruption states. `invite_used` has its own message, and the design specifies a quiet retry after network loss, decline on close or lock, keeping the display awake and screen-sharing exclusion.
4. The host is the primary row text and stays visible read-only on later steps. Consent names the server, and the metadata exposure is documented.
5. The command is one real `setup-code` command, used the same way in the app, log and guide.
6. The combined screen keeps the chosen password for **Try Again** and defines its sections, focus order and when Set Up is enabled.

The security changes fit well without adding clutter. The code is opaque text with no URL scheme, so no other app can receive it. The proof now binds the approver key and the server origin, and the name is cleaned before display. Rotating the code without showing a countdown keeps the screen calm. Asking for Face ID, Touch ID or the passcode before granting full read access is justified, not an extra confirmation, and it applies to the typed Approve too. The layout moves to a Form with toolbar actions and uses the native scanner and system prompts.

### Remaining must-fix items (small and precisely scoped)

1. **Code rotation needs a grace period.** If a new device scans a code just before it changes every 2 minutes, the connected device has already stopped looking up that code. The new device would then sit on "Waiting for approval…" until the server request expires, and the person has no idea why. After each rotation, keep looking up the previous code for about 30 seconds and accept one candidate from it. Alternatively, have the new device report an expired code at once. The first option is invisible to people and preferred.
2. **Define "leaves the foreground" per platform.** It should mean the scene moves to the background on iOS and iPadOS. On Mac it should mean hide, minimize, screen lock or sleep, not app deactivation.
   - **iOS inactive state:** a literal inactive check would discard the code whenever Control Center or a notification is pulled down.
   - **Mac deactivation:** it would also discard the code on the Mac when someone clicks another window while holding an iPhone to the screen.
   - **Pending request:** the Face ID, Touch ID or passcode prompt for **Add Device** makes the app inactive. That prompt must not discard or decline the request.
3. **Scan Code is gated on `model.store == nil`, but the connected device tells every new iPhone to choose Scan Code.** A new iPhone where someone tapped Start a Journal first, which is the prominent welcome button, has no Scan Code and no explanation.
   - Treat a library with no entries and no templates as having no journals. Offer Scan Code there and replace that empty library on success.
   - Change the **Enter Code Instead…** footer to "For a Mac or a device that can’t scan the code." That covers Macs, devices without a camera and devices with journals in one phrase.
   - Also correct the rationale in 1a. The check code protects against a malicious server, not against a person who controls both the server and the "connected" device. The real protections for a device with journals are typing the address and seeing the host named in the upload consent. The gate is still worth keeping.

### Polish (nonblocking)

- **Wording consistency:** Several strings still say "other device" despite the terminology rule: **Finish on Your Other Device**, "Your other device didn’t add this device." and "Show a new code on your other device." Either allow "other device" in the new device's post-scan screens, which reads naturally, or change them all. Reword the decline message to avoid "device … device": "Your connected device didn’t add this one." / **Scan Again**.
- **Tailscale hint for discovered servers:** A discovered row for a tailnet address, tapped while Tailscale is off on this device, will fail. Use the same Tailscale-aware unreachable copy as the scan path, not the generic check error.
- **Bundled-server copy:** "Other devices connect to this Mac using the HTTPS address from Connection Details." promises an HTTPS address, but per `local-server.md` Connection Details shows the local address and Tailscale instructions. Say "…using a Tailscale HTTPS address. See Connection Details in Settings > Sync." Letting the person save that address once in Connection Details would enable the QR code for Use This Mac. That is worth offering the owner alongside the deferred reverse QR, because together they leave the bundled-server case on the typed path.
- **Authentication reason:** Use lower case, "add a device to your journals", so the Mac prompt reads naturally as "My Journal is trying to add a device to your journals."
- **Setup-code backoff:** The global backoff lets anyone who can reach an unclaimed server keep the owner waiting. Let `setup-code` on the server also clear the wait, since whoever runs it has server access. Then the 429 message can be "Too many attempts. Try again in a few minutes, or run setup-code on your server to reset." The client already keeps Set Up disabled until the code has 8 valid characters. Consider an inline hint when a character outside the alphabet is typed, so a disabled button isn't the only feedback.
- **Mac sheet title:** Inside a `NavigationStack` in a Mac sheet the navigation title doesn't show. Make sure **Connect to a Server** and **Add Device** are visible as headings on the Mac.
- **Verification:** `sharingType = .none` also blanks the Add Device window in Mac screenshots. Plan UI verification of that sheet with the iOS approver, or with a debug-only override, and note which was used. On iOS, check that the app-switcher snapshot doesn't capture a live code.

### Verdict

**Approved for implementation once must-fix items 1–3 are incorporated as specified above.** They are scoped changes to timing, lifecycle and gating rather than a new design, so no further design review is needed if they are applied as written. Record in the proposal how they were resolved. Actual-UI verification after implementation remains required for the states listed under "Verification after implementation", plus the rotation boundary, a Face ID prompt while a request is pending, and a new iPhone that has an empty library.

## Revision 3 review — 2026-09-28

Reviewed "Revision 3 — lighter pairing" in `effortless-connection.md` against the same requirements and the owner's test feedback ("still a bit cumbersome"). I also checked `SECURITY.md` ("Password guessing") and `protocol/README.md` ("Setup and recovery", POST /recovery). Proposal review only; no UI inspected.

**Change 2 (sign in with the master password first) is the right answer to the owner's feedback.** The heaviest remaining step was the Mac joining with the typed code and check-code comparison. A password field that a password manager can fill, then **Connect**, is the familiar sign-in pattern on every platform. It works without the other device at hand and uses the same route as recovery, so there is one concept instead of a picker. Replacing the Connection Method picker removes a decision people shouldn't have to make. Libraries without a password keep their current defaults, which is correct.

**Change 1 (automatic Face ID prompt) saves one tap but removes the only deliberate act in the approval.** It needs changing before implementation.

### Must fix before implementation

1. **Don't treat Face ID as confirmation. Keep the Add Device tap on Face ID devices.**
   - **Why the tap matters:** Face ID proves the owner is present, not that they intend to approve. Someone watching the screen for the new device to connect will be authenticated the moment the request arrives, before they have read the name. The name check is the stated defence against a photographed code (revision 2 residual risk; `SECURITY.md`: "Only add a device whose name you expect"), and an instant prompt removes it.
   - **Apple precedent:** Apple Pay requires a double-click before Face ID, and password autofill requires a tap first, for this reason.
   - **The reason text doesn't help:** on iPhone and iPad, Face ID doesn't show the reason string at all, so "Add “name” to your journals" is only shown for Touch ID and the passcode.
   - **VoiceOver:** an automatic system prompt interrupts VoiceOver before it has spoken the name.
   - **Resolution:**
     - **Face ID devices:** **Add Device** then Face ID, as in revision 2.
     - **Automatic prompt allowed:** where authentication itself is a deliberate act. That means Touch ID (placing a finger), a passcode or Mac password, and Apple Watch approval on the Mac (double-click).
     - **VoiceOver running:** never prompt automatically; the name is announced and **Add Device** is the next element.
   - **Labels and reason text:**
     - Keep the button label **Add Device** everywhere; the revision says "Add" after a cancelled prompt.
     - Make the reason string lower case, "add “name” to your journals", so the Mac prompt reads "My Journal is trying to add “name” to your journals."
   - **Tap count:** on Face ID devices this costs one tap more than the revision proposes. Change 2 removes the owner's actual pain point, the Mac's typed code, so the flow still gets clearly lighter.

2. **Correct "Security is unchanged" for password-first sign-in, and decide the mitigation.** Recover Journals was a secondary route. Revision 2's discovery trust section relies on "for joining, the check code" against a rogue advertisement or typed look-alike address. With revision 3 the default route on any discovered or typed server is the password.
   - **What a rogue server receives:** `recoverySecret` (HKDF of the password-derived wrapping key, per the protocol README).
   - **Replay against the real server:** a rogue server can replay that value to the real server's POST /recovery. That returns a device credential and the whole envelope: sync access to all ciphertext, the ability to write or delete as an authorized device, and offline password guessing. The server-wide attempt budget doesn't slow any of this.
   - **What the proposal must do:** state this accurately in the proposal, `SECURITY.md` and the discovery trust section, and decide with the security reviewer whether password-first ships as the default with only documentation.
   - **Recommended protocol mitigation:** an origin-bound challenge-response for POST /recovery, where the client proves knowledge of the secret with an HMAC over a server nonce and the server's origin instead of sending it. Then a relayed or replayed value fails at the real server. A proper PAKE remains out of scope.
   - **Interim UI mitigation:** keep the host prominent in the sign-in form itself: the section header "Sign In to journal.example.ts.net" above **Master Password**, not only the read-only address row. Don't put the sign-in behind discovery alone; the host stays the primary row text.

3. **Define the sign-in failure states, including the shared lockout.** The wrong-password budget is server-wide (20 an hour, then waits up to 15 minutes). Anyone who can reach the server can keep the owner's normal sign-in route refused, while the code route isn't limited. Copy:
   - wrong password: "That password isn’t correct." Keep focus in the field and the text selected.
   - 429: "Too many password attempts on this server. Try again in a few minutes, or use a code from a connected device." The alternative route is right there.
   - unreachable: the existing Tailscale-aware message from revision 2.
   - envelope parameters changed since shown: the existing "This server has changed since you checked it…" with Continue.

### Polish (nonblocking)

- **Password autofill:** it will be less automatic than the revision implies. The app has no associated domains, so iOS doesn't suggest a saved password automatically in the keyboard's suggestion bar and doesn't offer strong passwords when one is created; people open the key icon and search. Add a username-type field showing the server host, read-only and visible or as the standard hidden technique, so saved password items are identifiable. Offer the owner a `webcredentials` associated domain once there is a domain to host it. Verify on a device with iCloud Keychain and one third-party password manager before telling the owner it "fills".
- **Label for the code route:** "Use a Code from Another Device Instead…" is long and mixes the terminology. Suggest **Use a Connected Device Instead…**, with the footer "If you don’t have your password, a connected device can add this one."
- **Field label follows the library:** use the credential name the library actually has, as today (Recovery Key for version 1, the access password for version 3), rather than always "Master Password".
- **Footer copy:** "Your journals will download to this device." is good. With a very large library, show download progress after Connect rather than a silent sheet.
- **Password sign-in awareness:** since it is now normal, consider a quiet line on connected devices' Devices list for recently added devices. The existing "Added with your master password on [date]" is sufficient for now.

### Verdict

**Change 2 is approved subject to must-fix items 2 and 3. Change 1 is not approved as written; implement it as described in must-fix item 1.** Item 2 needs a recorded security decision, and a protocol change if the recommended mitigation is adopted. Re-review only if that decision changes the sign-in UI beyond the header and copy given here. Actual-UI verification must cover:
- Face ID versus Touch ID/Mac approval
- VoiceOver on the approval screen
- password autofill with iCloud Keychain and one third-party password manager
- wrong password, 429 and unreachable sign-in
- the Mac joining by discovery plus password.
