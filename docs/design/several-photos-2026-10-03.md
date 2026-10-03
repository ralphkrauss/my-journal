# Insert several photos at once — 2026-10-03

Owner request:

> “When inserting photos in My Journal, if you take photos from the photo library you should be able to choose if you want one or more photos, how it works on apps like WhatsApp that use the photo library.”

Today Insert Image ▸ Photo Library (iPhone, iPad) opens the system photo picker with a single `PhotosPickerItem`: tapping a photo adds it and closes the picker. Choose File… (iPhone, iPad) and Insert ▸ Image… (Mac, an open panel through the same SwiftUI `fileImporter`) also take one file. The camera takes one photo.

## Proposal

### Choosing

- **Photo Library:** the system picker in multiple selection with ordered selection (`PhotosPicker` `selection: [PhotosPickerItem]`, `selectionBehavior: .ordered`, images only). It shows numbered selection circles and the system's own **Add** button, as Messages and WhatsApp do. Tapping one photo and Add inserts one photo, as today. The picker's UI, copy and privacy (no photo library permission needed) are the system's.
- **No limit** (`maxSelectionCount: nil`), as in Notes. Images are read two at a time and each is stored as soon as it is read, so a long selection doesn't use more memory than a short one, and writing stays responsive (below). Each image still has the existing 25 MB limit.
- **Files** (iPhone, iPad) and **Image…** on the Mac: the same document picker / open panel with multiple selection allowed. The panel decides the order of the chosen files (the order it lists them in); the Photo Library keeps the order the photos were tapped in.
- **Camera:** one photo, unchanged.

### Reading, progress and inserting

- The chosen images are read and stored in the background, two at a time and in the chosen order, so a long selection uses no more memory than a short one and the interface stays responsive. Location is removed before each is stored, as today (ImportedImage); images are stored at the quality the picker gives, as today (the picker's automatic encoding is kept, so other clients can read them).
- **Progress.** While images are being read, a one-line notice sits above the writing, where the conflict notice goes on both platforms, so it stays in view however far the entry is scrolled: a small determinate progress indicator, **Adding Images… 3 of 12**, and a **Stop** button. It appears only once reading has taken more than half a second, so a quick single photo shows nothing new. For one image it reads **Adding Image…** without a count. VoiceOver reads it as “Adding Images, 3 of 12” and the Stop button; when the images are in the entry it announces “Images added” (“Image added” for one). Like the conflict notice, it takes a line above the editor, so the writing moves down by that line while it shows and back when it goes; the change is animated unless Reduce Motion is on.
- **Inserting.** When every chosen image has been read, they are inserted together, in the chosen order, where the caret was when Insert Image was chosen: each its own image block with the one empty line after it that a single photo gets today, so consecutive images are separated by exactly one empty line. Nothing is put in the entry before then. A placeholder would be saved and synced as a reference to a picture that may never arrive (the app closed, a download failed), leaving “Image unavailable” in the entry for good; the progress notice shows the wait instead. The existing “Loading Image…” presentation stays for pictures whose bytes are stored but still loading.
- **Writing meanwhile.** The person can keep writing. If the caret is still where Insert Image left it, the images go there and the caret ends after the last one, kept clear of the keyboard and writing controls (`revealCaretAfterImage`), as today. If the person has moved the caret or typed elsewhere, the images still go where they were placed, but the caret, the keyboard and the scroll position stay where the person is.
- **Stop** ends the import: nothing is inserted and nothing is said. Images already stored for it stay on this device unused, as an image removed from an entry does: they are never synced, and a backup archive, which copies the library's image folder, includes them encrypted. Removing unused images from the device is a separate, existing gap and not changed here.
- **Leaving the entry or switching libraries** during the import ends it the same way, and the app's error alert then says: “The images weren’t added because you left the entry before they finished.” (one image: “The image wasn’t added because you left the entry before it finished.”). This is new for a single photo too, which today stops silently. Locking ends it quietly, so nothing about the entry shows over the lock screen.
- **Memory.** An image is not kept for display while the others are read; once all are inserted, the editor reads its display copies as for any entry, showing the existing “Loading Image…” state for a moment. A single image is shown at once, as today.

### Undo

All images from one choice are inserted in one edit, so they are **one undo step** (Edit ▸ Undo, shake, three-finger swipe): Undo removes all of them. Undo during the import affects only what is already in the entry; the images arrive afterwards as one new step.

### When some can't be added

Images that can't be read or stored are skipped; the others are inserted in order. Errors are collected for the whole import, and one message follows in the app's existing error alert (the single-image and paste paths no longer each raise their own):

- One image chosen: the existing message for it (for example “Choose an image smaller than 25 MB.”), except that a photo the Photo Library couldn't provide says “The image couldn’t be added. It may still be downloading from iCloud. Try again later.” instead of today's misleading “isn’t in the correct format”.
- Several chosen, some skipped: “2 of 5 images couldn’t be added.” followed by the cause when every skipped image has the same one:
  - larger than 25 MB: “They’re larger than 25 MB.”;
  - unreadable or an unsupported format: “They couldn’t be read.”;
  - the Photo Library couldn't provide the image (only for the Photo Library, never for Files or the Mac): “They may still be downloading from iCloud. Try again later.”;
  - mixed causes: “Try again, or choose other images.”
  One cause sentence only; a size or format cause has no “Try again later.”
- Several chosen, none added: “None of the 5 images could be added.” followed by the same cause sentence.

“Images” rather than “photos”, because Files and the Mac add any image, and the app's commands say Insert Image.

### Mac

The Mac has no Photo Library choice, on purpose, as today (Insert ▸ Image… opens the open panel, now with multiple selection). A Photos picker on the Mac is a possible follow-up.

### Accessibility

The picker's accessibility is the system's. The progress notice is described above. Each inserted image is an image block with its usual VoiceOver label (“Image”, or its description).

## Verification

- Unit tests with a fake loader (iOS and Mac test targets): images read with different delays are inserted in the chosen order, one empty line apart; a failing image is skipped and the summary names the count and cause; one Undo removes all images of one choice; Stop, a lock or leaving the entry inserts nothing (with the message only for leaving); typing elsewhere during the import keeps the person's caret.
- Existing image tests (ImageViewportTests, ImageImportTests, EditorClipboardTests, ImageArrivalTests) keep passing.
- The system picker runs in another process, so a UI test of choosing several photos is left out unless it proves reliable; screenshots of the picker with ordered selection on the iPhone simulator.

## Review

First review (independent design agent, 2026-10-03): **approved with required changes**. Material findings and how they were resolved:

1. No visible progress, and no way to stop: added the progress notice with a count and Stop, with VoiceOver label, value and a completion announcement.
2. Each arriving photo moved the caret, scrolled and brought back the keyboard: images are now inserted together at the end, and when the person has moved the caret meanwhile, their caret, keyboard and scroll position stay.
3. Undo during an import: with one insertion at the end, Undo affects only what is already in the entry; the images arrive as one later step.
4. Leaving the entry discarded the rest silently: leaving now ends the import with a message; locking stays quiet. Stored but unused images are never synced (`attachmentsToUpload` uploads only images something uses).
5. Each failure raised its own alert: errors are collected and summarised once, by cause.

Minor findings taken: the cause-specific copy; exactly one empty line between images, with a test; the encoding decision made explicit (automatic, unchanged); two reads at a time instead of three, each stored as soon as read; the Mac's missing Photo Library stated; tests for Stop, leaving, typing meanwhile and one undo step; screenshots of the progress notice.

Re-review of the revision (same agent): **approved**. Its minor points are folded in above: the notice does move the writing, so the doc says so and the change is animated unless Reduce Motion is on; singular copy for the notice and the leaving message, which is new for a single photo; the iCloud cause only for the Photo Library, including the single-photo case; images aren't kept for display while the rest are read; unused stored images after Stop stay on the device (not synced, included encrypted in archives); one cause sentence per message.
