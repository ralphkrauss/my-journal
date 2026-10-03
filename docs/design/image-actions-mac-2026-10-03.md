# Acting on an image in an entry (Mac) — 2026-10-03

Owner request:

> “When you have the photos you should be able to right-click to copy them. Now I put the photos in my journal but I'm unable to interact with them.”

iPhone and iPad are covered by `image-actions-ios-2026-10-03.md`. This record covers the Mac editor (`JournalTextView`, an `NSTextView`), reusing the shared `ImageItem` helpers (`Editor/ImageItems.swift`).

## 1. What happens today (reproduced)

Reproduced in the real Mac editor (an `EditorHarness` window in the Mac test host, macOS 26.5) with an entry holding a picture with the description “A red square” between two paragraphs. The menu below was captured from the real popped-up menu window.

- **Right-click (or Control-click) on the picture:** AppKit selects the picture (the selection becomes that one character) and shows the standard text menu: Cut, Copy, Paste, Share…, Font ▸, Show Writing Tools, Proofread, Rewrite, Spelling and Grammar ▸, Substitutions ▸, Speech ▸, Layout Orientation ▸, AutoFill ▸, Services ▸. Nothing is about the picture.
- **Copy** (menu or ⌘C) with the picture selected writes the entry's own Markdown, RTFD and RTF with **no image in them** (the attachment has no file, only a drawing cell), and empty plain text. `NSImage` can't be read from the result: Preview's File ▸ New from Clipboard, Mail and Messages get nothing, neither the original nor the smaller display copy. Pasting into another entry works (through the Markdown).
- **Share…** shares the selection's text, which is empty.
- **Dragging** the selected picture out of the window carries the same RTFD without the image.
- **VoiceOver:** the picture is an element in the text area (an image with its description as label, through AppKit's attachment-cell proxy) with only Show Menu, which shows the menu above.

## 2. Proposal

### 2.1 The picture's menu

Right-click or Control-click on a picture in an entry shows a menu for that picture instead of the full text menu. As today, the click first selects the picture, so its highlight shows which picture the menu is for, and the Edit menu's commands and the Delete key apply to it afterwards. A selected picture is tinted lightly and outlined in the selection colour (the accent colour while the entry has focus in the active window, grey otherwise), however it was selected: the text view draws its selection behind the text, where a picture hid it. The outline also takes in the strip of the picture's line below it, where the text view's own selection still shows, so the two read as one shape. It works while reading and writing, and in a read-only entry (Recently Deleted) with only the actions that don't change the entry. Version History and the conflict sheets keep the standard text menu, as on iPhone.

Menu, in this order (as an attachment's menu in TextEdit, Notes, Pages and Mail compose starts with the standard edit items; the destructive action last and separated), with the symbols the app's other context menus use:

1. **Cut**, **Copy**, **Paste** — the standard items, with their shortcuts and the system's symbols. They act on the selected picture (2.3).
2. — separator —
3. **Share…** — the system's standard share item (`NSSharingServicePicker.standardShareMenuItem`; on macOS 26 “Share…”, which opens the share sheet beside the picture; a Share submenu on earlier versions). It lists AirDrop, Mail, Messages, Notes, **Add to Photos**, Freeform, Reminders and the person's other enabled share extensions.
4. **Save Image As…** (`square.and.arrow.down`)
5. — separator —
6. **Image Descriptions…** (`text.below.photo`) — only where the entry offers it (`canDescribeImages`, as the list's context menu and the iPhone menu); opens the same sheet.
7. — separator —
8. **Delete** (`trash`) — only in an entry that can be edited; its undo step is “Delete Image”.

Which pictures get which actions (same rules as iPhone):

- A picture on its own line and a picture inside a line of text get the same menu. Delete removes a picture on its own line with its line, and an inline picture alone. (The Delete key, by contrast, deletes the selected character as anywhere in text, leaving its empty line, as on iPhone.)
- A shown picture gets Share… and Save Image As…, and Copy puts the image itself on the pasteboard. One that is loading, unavailable or remote (never downloaded) gets neither, and Copy and Cut copy it within the journal only, as today; nothing loads a remote image.
- A read-only entry shows Copy, Share… and Save Image As… (no Cut, Paste, Image Descriptions… or Delete).

The rest of the text menu (Font, Writing Tools, Spelling and Grammar, Substitutions, Speech, Layout Orientation, AutoFill, Services) is left out: none of it is about a picture. (AppKit adds AutoFill and Services to every menu a text view shows; the picture's menu removes them as it opens. Services that take images stay reachable from the app menu's Services submenu while the picture is selected.) A right-click on text, or inside a selection of text with or without pictures, shows the standard text menu as today.

**Add to Photos vs. Save Image As….** On the Mac, adding to Photos is a standard service in the share sheet (“Add to Photos”, confirmed among the share services offered for the picture), as in Notes, so the app needs no photo-library entitlement, usage text or permission prompt of its own. Saving the file itself is the Mac counterpart: Notes and Mail offer “Save Attachment…”, Safari “Save Image As…”; the app calls these images everywhere, so it uses Safari's wording. The app's sandbox already allows saving to a place the person chooses.

The menu is built at once from what is shown. Selecting exactly one shown picture (by a click, a right-click or Shift-arrow) starts reading its original from the encrypted store in the background, so Copy, Cut, dragging and the menu's actions usually have it at hand; it is kept only while that picture stays selected and the entry stays open, and a read under way is cancelled when the selection moves on. The store is read asynchronously (it is an actor, and the main thread is never blocked on it), so:

- **Copy and Cut** chosen before the read has finished (right after selecting) wait for it without blocking, then copy (and for Cut, remove the picture).
- **A drag** that starts before the read has finished carries only the entry's own content: moving within the entry works, but another app gets no picture. A drag needs a press on the already selected picture, so in practice the read (a few milliseconds for a photo) has finished.
- If the read fails, nothing is copied, shared or saved, the pasteboard is left as it was, Cut leaves the picture in place, and the app's error alert says “The image couldn’t be copied.”, “The image couldn’t be shared.” or “The image couldn’t be saved.” If the journals lock meanwhile, nothing happens and nothing is said.

### 2.2 The actions

**Copy** (menu, Edit ▸ Copy, ⌘C) with exactly one shown picture selected: one pasteboard item with the image as it was added (the stored original, location already removed when it was added), under its own file type, together with the entry's own Markdown so another entry pastes it as before (with its description, without storing it twice). A HEIC or HEIF image also gets a JPEG copy (shared helper), made in the background. The RTF, RTFD and empty plain text are left out, so no other app takes those instead. Everything is written at once (no data promised for later), so it pastes after My Journal locks or quits. Mac apps that read pictures through AppKit's image reading (`NSImage`: Preview's File ▸ New from Clipboard, Mail, Messages, Notes, Pages) take the original type, so no TIFF copy is added: it would be about 48 MB for a 12-megapixel photo. An app that asks for TIFF still gets it: the system pasteboard offers TIFF translated from a JPEG or PNG on request (checked on macOS 26.5), made only when asked for. Copying a large HEIC photo makes its JPEG copy in the background, typically well under a second; nothing is shown meanwhile.

**Cut** with exactly one shown picture selected puts the same item on the pasteboard and removes the picture, as one undo step. **Dragging** the selected picture carries the same item: a drop within the entry still moves it (the entry reads its own Markdown first), and a drop into Mail, Pages or Notes inserts a copy of the image. A drop outside My Journal is only ever a copy, so the picture never leaves the entry because another app accepted it as a move. Dropping on Finder, which needs a file, is not part of this change (2.5).

**Share…:** the chosen service gets the original's bytes in memory with their type (an item provider), named “Image” with the type's extension (“Image.jpg”), never the description, which may be private and would travel with the file. No file is written by My Journal. If the original can't be read when the service asks for it, the service gets nothing (it may show an empty compose window), and the alert “The image couldn’t be shared.” appears, unless the journals locked meanwhile: then the request fails quietly. A service that already has the image (an open Mail window, an AirDrop under way) is outside the app's control after a lock.

**Save Image As…:** the standard save panel, as a sheet on the window, named “Image” with the original's extension and limited to its type; the original is written to the chosen place. Saving is quiet.

**Image Descriptions…:** the existing sheet, which lists every image of the entry.

**Delete:** removes the picture as described above as one undo step, **Undo Delete Image** in the Edit menu. The editor takes focus first (as a click on the picture does), so ⌘Z reaches the step at once, also when the menu was opened while reading. The stored picture is kept for undo and earlier versions, as today. No confirmation: it is undoable, like deleting text.

**Locking or leaving the entry** closes the picture's menu (its tracking is cancelled), the share picker and the save panel, and forgets the read original; the Image Descriptions sheet already closes on lock. The app locks from a task on the main actor, which runs while a menu is open, so this is checked rather than assumed.

### 2.3 Keyboard

- The arrow keys move over a picture like a character, and Shift-arrow selects it; ⌘C, ⌘X and Delete then act on it as above.
- A context menu requested from the keyboard — VoiceOver's VO-Shift-M on the text, or Full Keyboard Access — while exactly one picture is selected shows the picture's menu at the picture rather than the text menu.

### 2.4 VoiceOver

- The picture is already an element in the text area (AppKit's attachment proxy), labelled with its description, or “Image” when there is none; “Loading Image.”, “Image unavailable.” or “Remote image. Not downloaded.” when it isn't shown. That stays.
- It gains the menu's picture actions as VoiceOver actions (VO-Command-Space), named as in the menu without ellipses: **Copy**, **Share**, **Save Image As**, **Image Descriptions**, **Delete** — only those its menu offers. A spike confirmed that actions supplied by the picture's own attachment cell reach VoiceOver through AppKit's proxy. VoiceOver's cursor doesn't select the picture, so these actions don't change the selection and read the original when chosen; a failed read shows the same alerts. Copy puts the same item on the pasteboard as in 2.2. Share shows the system's share picker next to the picture. Cut and Paste are left to ⌘X and ⌘V, as for text.
- Its Show Menu (VO-Shift-M) shows the picture's menu. It has no press action, so VO-Space does nothing on it, as today.
- After Copy, VoiceOver hears “Copied”. After Delete, focus moves to the text area at the deletion point and then “Image deleted” is announced.

### 2.5 Not part of this change

- **Dropping a picture on Finder** (a file). It needs a file promise that reads the original when dropped. **Owner decision:** add it as a follow-up.
- **Copying several pictures** (or text with pictures) for other apps: a mixed selection copies as today, within the journal. Possible follow-up.
- **Quick Look** (Notes, Mail): it needs a decrypted file on disk.
- Double-click stays as it is (no action), as in TextEdit and Mail compose.

### 2.6 Privacy

As on iPhone: Copy puts the decrypted original on the general pasteboard, which Universal Clipboard can share with the person's other devices, as Notes does; the entry's Markdown that goes with it includes the picture's description, which clipboard managers can read. Share and Save Image As… hand the original only to the destination the person chooses; My Journal writes no file of its own. The read original stays in memory only while its picture is selected in an open entry.

## 3. Verification

- Unit tests on the real Mac editor: the menu's items for shown, loading and read-only pictures; Copy of a selected picture writes, on a named pasteboard, the original bytes under the original type (not the display copy) plus the Markdown and nothing else, which `NSImage` reads at the original size; Cut does the same and removes the picture as one undo step; a mixed selection copies as before (EditorClipboardTests); Delete removes exactly the picture's line (or only the inline picture) and one Undo restores it, with the editor unfocused beforehand; the VoiceOver element offers the actions; leaving the window forgets the original and closes the menu.
- Tests for the timing: Copy right after selecting (before the read finishes) still copies the picture; a drag pasteboard written before the read finishes carries only the entry's content; a failed read leaves the pasteboard and, for Cut, the picture as they were; a drop outside the app is offered only as a copy.
- A development-signed app with its own bundle ID and a scratch library: right-click each kind of picture and use each item; paste into Preview at the original size; Delete then ⌘Z; Share. Screenshots of the menu in light and dark mode, and of the selected picture's highlight with Increase Contrast. For the owner's hardware check: pasting into Word, Keynote and a Chromium-based app (to confirm leaving out TIFF), and locking during a drag.

## 4. Review

An independent design review (2026-10-03) approved the direction **with required changes**, all made above:

1. The menu followed Safari (read-only pages) rather than editable text: it now starts with the standard Cut, Copy and Paste, as TextEdit, Notes, Pages and Mail compose do for an attachment, and ends with Delete. Copy and Edit ▸ Copy are one path that keeps the entry's Markdown, so pasting back doesn't store the picture twice.
2. Cut and dragging share Copy's pasteboard path (`writeSelection`), so they now carry the picture too; only a drop on Finder is left as a follow-up. To give that synchronous path the original, it is read when a single picture is selected.
3. Share uses the system's standard share item in both the menu and VoiceOver, and the failure after a service opened is stated.
4. Locking closes the menu, the share sheet and the save panel, and this is checked (the lock runs while a menu is open).
5. The lazy TIFF is dropped: AppKit-based apps read the original type, and a promised TIFF would keep the decrypted original in memory after locking and be made at quit.
6. VoiceOver action names match the menu without ellipses; focus moves to the text before “Image deleted”; a spike confirmed that custom actions reach VoiceOver through AppKit's attachment proxy; VO-Space is stated.

Minor findings taken: the Delete key and Delete differ, and why; the description travels with the Markdown on the pasteboard (privacy); verification of the highlight with Increase Contrast. Not taken: Cut and Paste as VoiceOver actions (⌘X and ⌘V reach them, as for text; iPhone has the same set); an “Add Image to Photos” item (Add to Photos is in the share sheet); a separate alert text for an original that isn't on this Mac (the editor's display copy is made from the stored original by `DocumentImageLoader`, so a picture whose original isn't stored isn't shown and gets no Copy); copying several pictures (follow-up); “Copy Image Address” for remote pictures.

Re-review of the revision (same reviewer): **approved with required changes**, all made above:

1. Copy can't block the main thread on the store, which is an asynchronous actor: Copy and Cut wait for the read without blocking; a drag that starts before the read finishes carries only the entry's content, stated and tested. (The reviewer's alternative, a synchronous read from the text view, isn't taken: it would block the main thread on the encrypted store.)
2. A failed read leaves the pasteboard unchanged and, for Cut, the picture in place.
3. A drop outside the app is only ever a copy, so another app accepting a move can't remove the picture.
4. VoiceOver actions read the original when chosen and don't change the selection.
5. After a lock, a late share request fails quietly; the share picker closes on lock; services that already have the image are outside the app's control.

Minor points taken: a read under way is cancelled when the selection moves on; the HEIC conversion time is noted; the hardware check adds Word, Keynote, a Chromium-based app and locking during a drag; the reason a picture's original and display copy are present together is stated. Paste over a selected picture is unchanged.

## 5. Implementation and inspection

Implemented in `Editor/ImageActionsMac.swift` (the menu, reading the original, the actions, VoiceOver through the picture's own attachment cell `JournalImageCell`, which also draws the selected picture's highlight), `Editor/NativeTextView.swift` (the text view's menu, Copy, Cut, pasteboard types, drag operations, leaving the window, Show Menu) and `Views/RootView.swift` (the Mac editor gets the same `ImageActionSupport` as iPhone). Shared with iPhone: `ImageItem` (finding the picture, its type and file name, what Delete removes, the pasteboard representations).

Inspection: the screen was locked during implementation, so the real menu was captured from inside the Mac test host (the popped-up `NSMenu` window and the editor window, composited) rather than from the screen. The light-mode menu matches the design for an editable entry and a read-only entry. AppKit renders a dark menu's glass material only in the window server, so the dark capture shows the editor and the selected picture's highlight only. Deviations found and resolved: AppKit appended AutoFill and Services to the picture's menu (now removed as it opens); a selected picture had no visible highlight (now tinted and outlined). The same reviewer approved both; its required fix (a separate strip of text selection showing under the outline) is made, the tint lowered from 25% to 18% as suggested, and the captures retaken. Not taken: a contrasting inner hairline inside the outline (optional; to judge on real photos in the hardware check).

Not verified on the real screen (for the owner's hardware check): the menu in dark mode and with Increase Contrast; the highlight switching between accent and grey when the window or the editor gains and loses focus; the accent-coloured highlight in a focused window; pasting into Preview, Mail, Messages, Word, Keynote and a Chromium-based app; Share… with real services (AirDrop, Mail, Messages, Add to Photos); the save panel; a drop into Mail or Notes leaving the picture in the entry; VoiceOver's actions and VO-Shift-M with VoiceOver running; Full Keyboard Access opening the menu; locking during a drag.

