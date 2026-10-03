# Acting on an image in an entry (iPhone, iPad) — 2026-10-03

Owner request:

> “When you have the photos you should be able to right-click to copy them. Now I put the photos in my journal but I'm unable to interact with them.”

This record covers iPhone and iPad. The Mac's right-click menu is in `image-actions-mac-2026-10-03.md`; it uses the shared helper below.

## 1. What happens today (reproduced)

Reproduced on the iPhone 17 simulator (iOS 26.5) with an entry holding a 600 × 400 picture with the description “A red square” between two paragraphs:

- **Long press** on the picture, reading or writing: UIKit's own menu for a text attachment appears, with the picture lifted: **Copy Image** and **Save to Camera Roll**. Nothing in the app chose these:
  - Copy Image copies the picture as the editor draws it: the smaller display copy (at most 2,560 pixels), not the photo that was added, and without its file type.
  - Save to Camera Roll needs a photo library add usage description, which the app doesn't have; iOS refuses access to the photo library without one. (Not tried on the simulator before the fix; the description is added either way.)
  - Nothing offers sharing, the description, or removing the picture.
- **Tap**: the picture is selected (selection handles around it) and the keyboard comes up, as in Mail. Copy from the edit menu then copies the entry's own Markdown and formatted text, which other apps can't paste as a picture.
- **VoiceOver** reads the picture inside the text (“A red square” or “Image”), with no actions.

## 2. Proposal

### 2.1 Long press (and secondary click with a pointer on iPad)

The same system interaction the text view already offers for a picture — the picture lifts out of the text, the rest dims, and a menu appears below it — with My Journal's own actions instead of UIKit's defaults (`UITextViewDelegate textView(_:menuConfigurationFor:defaultMenu:)`, iOS 17 and later). It works while reading and while writing, and in a read-only entry opened in the editor (an entry in Recently Deleted) with only the actions that don't change the entry. The small previews in Version History and the conflict sheets keep the system's own menu. On iOS 16 the system's own menu stays (Copy Image, Save to Camera Roll, which now works, see 2.5); the VoiceOver actions in 2.3 give the full set there too.

Menu, in this order (copy and share first, the destructive action last and separated, as in Photos and Messages):

1. **Copy** (`doc.on.doc`)
2. **Share…** (`square.and.arrow.up`)
3. **Save to Photos** (`square.and.arrow.down`)
4. **Image Descriptions…** (`text.below.photo`) — only where the entry's ••• menu offers it (`canDescribeImages`: an editable entry without a conflict); opens the same sheet, which lists every image of the entry. Focusing this image's field from here is a possible follow-up.
5. — separator —
6. **Delete** (`trash`, destructive) — only in an entry that can be edited.

Which pictures get which actions:

- A picture on its own line and a picture inside a line of text (shown small, at most 120 × 80 points) get the same menu. Delete removes a picture on its own line with its line, and a picture inside a line alone, leaving the text around it.
- A picture whose bytes are shown (its display copy is loaded) gets Copy, Share… and Save to Photos. One that is still loading (“Loading Image…”), unavailable, or a remote image that is never downloaded (“Remote image. Not downloaded.”) gets only Delete, in an editable entry; nothing in the menu loads a remote image. With nothing to offer (a remote image in a read-only entry), the system's own menu isn't shown either.

The menu is built at once from what is shown; the original is read from the encrypted store only when an action is chosen. If that read fails, or the journals lock meanwhile, nothing is copied, shared or saved, and the app's error alert says “The image couldn’t be copied.”, “The image couldn’t be shared.” or “The image couldn’t be saved to Photos.” (no message after a lock).

Copy: the image as it was added (the stored original, after its location was removed when it was added), fully read before it is put on the pasteboard, under its own file type from its recorded media type, so it pastes into Photos, Messages, Mail or Notes at full quality, and still pastes after My Journal locks. A HEIC or HEIF image also gets a JPEG copy, made away from the main thread, for apps that don't take HEIC. Pasting it back into an entry adds it as a new image, as pasting a photo does today.

Share…: the system share sheet, given the original's bytes in memory with their type (`NSItemProvider`), so no file is written. It is offered as “Image” with the type's extension (“Image.jpg”), not the description, which may be private and would travel with the file. On iPad the sheet points at the picture. The share sheet's own Save Image works too (see 2.5).

Save to Photos: adds the original to the photo library with add-only access. The first time, iOS asks with the app's reason: “Save images from your entries to your photo library.” Saving is quiet, as in Safari and Messages. If access was turned off: an alert **Photos Access Is Off** / “Allow photo library access in Settings to save images.” with **Open Settings** and **Cancel**, as the existing **Camera Access Is Off** alert.

Delete: removes the picture as described above; one undo step, **Undo Delete Image**. The text view keeps its own undo history, which shake, the three-finger gesture and ⌘Z reach only while it has focus, so choosing Delete while reading starts writing (as a tap on the picture would) and Undo works at once; checked by a test that deletes with the editor not focused. The stored picture is kept for undo and for earlier versions, as today.

**Locking and the background.** On the simulator the system did *not* close an open picture menu when the app went to the background: it was still open on return. So the editor closes it itself when the app goes to the background, and closes the menu and any share sheet it opened when the entry leaves the screen, as when the app locks (checked: the menu is gone after going to the Home Screen and back).

**Dragging** a picture to another app on iPad is not part of this change; it keeps the system's behaviour.

### 2.2 Tap

Unchanged: a tap selects the picture, with selection handles, and writing starts, as in Mail and Pages, where a picture in text is selected by a tap. Notes instead opens a picture in a full-screen viewer, which could show the decrypted picture from memory without writing a file. Selecting keeps writing first: the caret's place is predictable, the arrow keys move before or after the picture, and Cut, Copy and Delete in the edit menu act on it. The cost is that typing after a tap replaces the picture, as with any selection (Undo brings it back). **Owner decision:** keep tap-to-select, or open a viewer on tap as in Notes (long press would keep the menu).

With exactly one picture selected, the edit menu's **Copy** (and ⌘C) puts the picture itself on the pasteboard (as in 2.1) together with only the entry's own Markdown, so other apps paste the picture and another entry pastes as before. The empty plain text and the formatted text are left out, so no other app takes those instead; with no competing text types, the pasteboard item needs no order, and its bytes are read in full before it is written, so it still pastes after My Journal locks. A selection of text and pictures copies as today.

### 2.3 VoiceOver

VoiceOver reads a picture in place while reading the text, as today. To act on one, every picture in the entry — not only those on screen — is also an element of its own. On iOS the entry's text is one element (`JournalWritingView.updateAccessibility` lists the header, the editor, then the tables), so the picture elements come after the entry's text, in document order, after the tables. Each element's frame is worked out from the laid-out text whenever VoiceOver asks, so swiping to a picture further down scrolls the entry to it.

- Label: the description; “Image” when there is none (the image trait already makes VoiceOver say “image”). A picture that is loading, unavailable or remote keeps its existing label (“Loading Image.”, “Image unavailable.”, “Remote image. Not downloaded.”) and has only Delete.
- Actions (the rotor's Actions): Copy, Share, Save to Photos, Image Descriptions, Delete — the same set as the menu for that picture.
- A double tap does nothing (`accessibilityActivate` returns true without acting), so it doesn't select the picture or bring up the keyboard; the actions are how VoiceOver acts on it.
- After Copy and Save to Photos, VoiceOver announces “Copied” or “Saved to Photos” (the app posts these; the system doesn't for custom actions). After Delete, focus moves to the entry's text first and then “Image deleted” is announced, so the announcement isn't cut off by the change. Share opens the share sheet, which VoiceOver reads.
- The elements take no touches, so the text view's own long press and tap work as described above.

While doing this, the checklist checkboxes (which are buttons placed over the text) are also listed after the entry's text, before the pictures, so VoiceOver reaches them in the same way; as before, only checkboxes on screen exist.

Checked with the accessibility hierarchy in tests; reading order and announcements with VoiceOver on a device and Full Keyboard Access on iPad are for the owner's hardware check.

### 2.4 Privacy

- Copy puts the decrypted original on the general pasteboard, which Universal Clipboard can share with the person's other devices, as Notes does; it isn't marked local-only. Orientation, capture time and other metadata go with it; location was already removed when the picture was added.
- Share and Save to Photos hand the original to the destination the person chooses; no file is written by My Journal.

### 2.5 Fixes that apply on every version

- The photo library add-only usage description is added (`NSPhotoLibraryAddUsageDescription`: “Save images from your entries to your photo library.”), so saving from the menu, the share sheet or the system's iOS 16 menu works instead of being refused.

### 2.6 Shared with the Mac

The parts that aren't iPhone-specific live in shared code (`ImageItem`), so the Mac's right-click menu can use them:

- finding the picture at a character of the entry's text, its block (attachment ID, description, media type) and whether it is inside a line;
- its file type and the shared file name;
- the pasteboard representations (original type, plus JPEG for HEIC);
- what Delete removes.

Reading the original bytes is `AppModel`'s store read, given to the editor as a closure.

## 3. Verification

- Unit tests (iOS and Mac targets, the real editor): the copied pasteboard item holds the original bytes under the original type (and JPEG for HEIC), not the display copy; Delete removes exactly the picture's line (or only the inline picture) and one Undo restores it, also when the editor isn't focused, with the document's Markdown unchanged otherwise; the menu offers only Delete for a loading or remote picture and nothing that changes a read-only entry; copying a selected picture puts the image first while a mixed selection copies as before (EditorClipboardTests).
- A UI test: long press on a picture shows Copy, Share…, Save to Photos, Image Descriptions… and Delete, and Copy puts an image on the pasteboard; read-only entries show only the first three. Added only if it runs reliably.
- Screenshots of the menu in light and dark, reading and writing.

## 4. Review

An independent design review (2026-10-03) approved the direction **with required changes**, all made above:

1. Inline and remote pictures weren't covered: they are now, with Delete removing only an inline picture and nothing loading a remote one.
2. Share wrote a plaintext file: it now hands over bytes in memory.
3. The shared file name exposed the description: it is “Image” with the extension.
4. Copy and Share had unstated failures: the menu is built from what is shown, the original is read when chosen, failures have copy, and the pasteboard gets fully read bytes.
5. Locking: the share sheet closes and the menu with the entry.
6. VoiceOver: the label, ordering, a harmless double tap and the app's own announcements are specified.
7. Undo after Delete while reading: registered with the editor's undo history and tested unfocused.
8. The reason for keeping tap-to-select was wrong (a viewer needn't write a file): the trade-off is stated and the choice is left to the owner.

Minor findings taken: Image Descriptions… only where the entry offers it; a selected picture is copied with the image first and without the empty text; types from the recorded media type; the alert copy matches the camera alert; dragging deferred explicitly; Universal Clipboard and metadata noted; iOS 16 behaviour stated. Not taken: a larger custom preview (the system's lift is kept), relabelling to “Edit Description…” with focus (kept as a follow-up, since the sheet lists every image).

Re-review of the VoiceOver section (same reviewer): **approved with required changes**, both made: every picture has an element whose frame is computed when asked, so VoiceOver can scroll to pictures off screen; and the real order is stated (after the entry's text, in document order, after the tables), with the elements added to the writing view's list. Minor points taken: the label is the description (the trait says “image”); focus moves before “Image deleted” is announced; the selected-picture copy uses item providers for order; the undo test goes through the window's undo manager with the editor unfocused; the menu's behaviour on locking is checked rather than assumed. The re-review also showed the checklist checkboxes weren't in the writing view's VoiceOver list; they are added after the entry's text.

## Owner decision (3 October 2026)

Tapping a picture selects it, as in Mail and Pages. It doesn't open a full-screen viewer.
