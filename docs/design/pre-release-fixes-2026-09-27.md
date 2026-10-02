# Pre-release fixes — 2026-09-27

Scope: interface and behavior changes made while fixing bugs found in the pre-release review, the independent design review of them, and what still needs the owner's decision.

These changes were made as bug fixes, several of them to prevent lost writing or leaked content, and were reviewed afterwards. An independent design agent reviewed the requirements, the code and every new or changed string against the platform conventions and the copy rules in AGENTS.md; it didn't run the app. Its required changes were then applied. The editor changes listed at the end weren't part of that review.

## Reviewed changes

| Item | Change | Review | Outcome |
| --- | --- | --- | --- |
| a | After a failed pairing install, the library is read-only until Try Again succeeds or the connection sheet is cancelled, so a retry can't lose writing. | Approved with changes: the pause was silent. | The sheet now says "Couldn’t finish connecting. Your local journals remain on this device. Try again, or cancel to keep writing." when a copy is kept. Owner: a notice in the Mac main window. |
| b | Mac Settings panes fit their content up to the screen's height and scroll beyond it. | Approved. | Unchanged. |
| c | Create and Save are disabled for blank journal and template names. | Approved; rename should also trim. | Renaming a journal now trims the name and ignores a blank one. |
| d | On iPhone and iPad, while App Lock is on, a cover hides every window, including sheets and alerts, whenever the app isn't active. | Approved with changes: it said "My Journal Is Locked" when the app was only inactive. | The label appears only while locked; otherwise the cover is plain. |
| e | ⇧⌘F opens entry search on iPad (iOS 17 and later; not offered on iOS 16), and Zoom In, Zoom Out and Actual Size scale the editor relative to Dynamic Type. | Approved; the command did nothing in stacked layouts. | Search now works in stacked layouts too: from the Journals list it opens Search All Entries, and from an open entry it goes back to the list and opens its search. |
| f | Automatic sync waits longer after each failed pass, up to 5 minutes. A record or image the server refuses stays on the device with a message, without stopping the rest. | Approved with changes: message wording, long titles, a Try Again that didn't retry, and contradictory Mac text. | Messages rewritten (below), titles cut to 40 characters, Sync Now and Try Again retry refused items, and the Mac's "Choose Sync Now to try again." appears only when the whole sync failed. |
| g | Move Entry disables journals whose names are shared by another journal and explains why. | Approved with changes. | New explanation copy; disabled rows are dimmed. |
| h | With no journal window open, Settings still lists, adds and revokes agent access; reads stay paused. | Approved with changes: "while My Journal is open" became ambiguous. | Footer, Add Access and connection instructions now say "while a My Journal window is open and unlocked". |
| i | Image descriptions are stored as one line. | Approved with changes: keep the wrapping field. | Return moves to the next description (Next, or Done on the last), and pasted line breaks become spaces. |
| j | Local network purpose string, needed for servers on the local network. | Approved with changes. | "Sync with your server on your local network." The first connection to a server waits up to 20 seconds for network access, so the permission alert doesn't cause an error. |
| k | Encrypted journals on this device are never uploaded to a server without encryption; the refusal appears right after the server check. | Approved with changes: wording, and after a changed server in the pairing path only a failing Try Again was offered. | New copy, and a changed server now returns to Continue. Owner: how someone with an encrypted library can join their own server without encryption. |

Also approved: Quit is never refused because of the bundled server (the message "The server is still stopping. Try quitting again in a moment." was removed), and the wait after wrong PINs survives relaunching.

## Copy

New or changed strings, as shipped:

- "This server has changed since you checked it. Choose Continue to check it again."
- "Encryption is off for this server, so it can’t store your encrypted journals. Connect to a server that uses encryption."
- "That recovery code isn’t valid. Check it and try again."
- "That setup code isn’t valid. Check it and try again."
- "Couldn’t finish connecting. Your local journals remain on this device. Try again, or cancel to keep writing."
- "These journals were saved by a newer version of My Journal. Update My Journal to open them." (archive import keeps "Update My Journal to open this archive.")
- "Couldn’t save your changes. Unlock My Journal to try again."
- "“Title” is too large to sync. It’s saved on this device. Shorten it or split it into separate entries."
- "Your server didn’t accept “Title”. It’s saved on this device. Edit it to try again."
- "An image is too large for your server. Entries that include it are saved on this device."
- "Your server didn’t accept an image. Entries that include it are saved on this device."
- "The server sent more data than expected."
- Move Entry row: "Same name as another journal". Explanation on the Mac: "Journals with the same name can’t be chosen. To move this entry to one of them, rename it in the sidebar first." On iPhone and iPad the last words are "in the Journals list first."
- Agent Access: "Choose which journals an agent can read while a My Journal window is open and unlocked."; "Keep a My Journal window open and unlocked on this Mac. Closing the last window or quitting stops access."
- "Use at least 12 characters." now also applies when the password is changed from anywhere in the app.

## Waiting for the owner

- (a) A notice in the Mac main window while writing is paused, for example "Writing is paused while this Mac finishes connecting to your server." with "Show Connection". Done in [pre-release-ui-2026-09-27.md](pre-release-ui-2026-09-27.md) §3.
- (e) ⌥⌘F, as in Notes and Mail, instead of ⇧⌘F for Search Entries on both platforms. Approved and done in [pre-release-ui-2026-09-27.md](pre-release-ui-2026-09-27.md) §6; Find and Replace… moves to ⇧⌘F.
- (f) A notice in the entry itself when one entry can't sync, and "Unknown device" instead of an all-zero identifier in conflict details. Suggested engineering follow-up: return to the usual sync pace when the network comes back.
- (h) Whether Settings should say that agents can't read while no window is open.
- (j) Approval of the final local network string.
- (k) Allowing an encrypted library to join a server without encryption: an explicit confirmation, only when there are no local entries, or pointing to Export Archive.
- The recovery key copied to the clipboard is removed after two minutes and stays off other devices; the reviewer recommends the footnote "The copied key is removed from the clipboard after 2 minutes."
- Showing the remaining wait after wrong PINs ("Try again in <n> seconds.").
- The new device doesn't ask the person to confirm the pairing check code before it accepts the key. This needs its own design proposal and review ([SECURITY.md](../../SECURITY.md#what-a-malicious-server-can-do)).

## Editor changes not yet reviewed

These came from fixes that stop the editor from losing or duplicating text, and need a design review:

- The caret no longer stops inside the hidden markers of lists, tasks and quotes.
- Typing in a table cell is one undo step until anything else changes, and undo keeps the last 100 steps.
- When the pasteboard has rich or plain text as well as a picture, the text is pasted.
- Text copied from within one paragraph is pasted into the paragraph it lands in.

Owner: whether one Backspace at the start of a list item, task or quote removes its formatting, as in Notes and Pages. Today it deletes the hidden separator first, and a second Backspace removes the marker.

## Inspection

Checked in the iPhone simulator: ⇧⌘F from an open entry and from the Journals list, Move Entry with duplicate names, and Return in Image Descriptions. Not yet inspected in the running app: the privacy cover in the app switcher and behind system alerts, the Mac Settings copy and pane heights, and the connection sheet after a failed pairing or a changed server, which were checked through code and tests.
