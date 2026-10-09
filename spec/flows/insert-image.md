---
id: insert-image
title: Insert an image
features: [insert-image, insert-image-camera, paste-and-drop, image-placeholders]
sources:
  - apps/apple/JournalApp/Editor/WritingAccessory.swift (InsertImageMenu)
  - apps/apple/JournalApp/Views/ImagePickerPresenter.swift
  - apps/apple/JournalApp/Editor/ImageInsertionSession.swift
  - apps/apple/JournalApp/Views/ImageImportNotice.swift
  - apps/apple/JournalApp/Model/ImportedImage.swift
  - apps/apple/JournalApp/Editor/PastedImages.swift
  - apps/apple/JournalApp/Editor/EditorSession.swift (receiveImages)
  - apps/apple/JournalApp/Editor/InsertedText.swift (importForeignImages)
  - apps/apple/JournalApp/Editor/FormattingSessions.swift
  - apps/apple/JournalApp/Views/RootView.swift (importImageResult, cancelImageImport)
  - apps/apple/JournalTests/SeveralImagesTests.swift
  - apps/apple/JournalTests/ImageImportTests.swift
  - apps/apple/JournalTests/EditorClipboardTests.swift
  - docs/design/owner-decisions-2026-09-25.md (§3)
  - docs/design/several-photos-2026-10-03.md
  - docs/design/image-insertion-ownership.md
  - docs/design/imported-image-type.md
  - protocol/records.md (Images)
---

# Insert an image

## Purpose

Add pictures to an entry from the photo library, the camera, files, the pasteboard or a drop, without losing writing and without storing where a photo was taken.

## Start

| Platform | Control | Sources |
| --- | --- | --- |
| Computer | Toolbar Insert Image (`library.toolbar.insertImage`), Format ▸ Insert ▸ Image…, Formatting ▸ Insert ▸ Image… | The standard open panel, image files only, several at once. |
| Phone, tablet | Insert Image (photo symbol, label `library.toolbar.insertImage`) in the writing controls: a menu | `editor.insertImage.photoLibrary` (the system photo picker, several at once, in the order chosen, no permission prompt); `editor.insertImage.takePhoto` (camera; only on devices with a camera that isn't restricted); `editor.insertImage.chooseFile` (Files, image files, several at once). |
| Phone, tablet: Formatting and the Format menu | Formatting ▸ Insert ▸ Image…; tablet menu bar Format ▸ Insert ▸ Image… | Always the photo picker, not the source last used. |
| All | Paste or drop pictures | See Paste and drop below. |

Insert Image is disabled when the entry can't be edited. Choosing it records the caret (or selection) as the insertion point; the pictures go there even if writing continues meanwhile.

## Steps

1. The person chooses the source and picks one or more images. Cancelling the picker ends the flow without a message.
2. **Camera only, access denied**: an alert `editor.insertImage.cameraOff.title`, message `editor.insertImage.cameraOff.message`, buttons `common.openSettings` (opens the app's system settings) and `common.cancel`. First use asks the system permission with the purpose `editor.permission.camera`. A photo taken is stored as JPEG (quality 0.9).
3. The chosen images are read and stored in the background, two at a time, in the order chosen. For each:
   - Larger than 25 MB (25 × 1024 × 1024 − 28 bytes): refused, `messages.image.tooLarge`.
   - Not readable as an image: refused, `messages.image.unreadable`.
   - The photo library can't provide it (for example an iCloud original not downloaded): refused, `messages.image.unavailable`.
   - Otherwise its location (GPS coordinates and place names) is removed and it's stored encrypted, as the file it was where possible (orientation, capture time and other metadata kept; image data copied unchanged where the format allows, otherwise re-encoded without loss).
4. **Progress**: if reading takes longer than 0.5 s, a notice appears above the writing (laid out like the other-version notice): a small progress indicator and `editor.imageImport.adding` (one image) or `editor.imageImport.addingSeveral` (“Adding Images… 2 of 5”), and an `editor.imageImport.stop` button. At accessibility text sizes the button goes below the text. It appears and leaves with a slide unless Reduce Motion is on.
5. When every image has been read, all the stored images are inserted together, in the order chosen, at the recorded insertion point, as **one undo step**. Each goes on a line of its own (`flows/editing-rules.md` IM-1), with one empty line between consecutive images in the Markdown. A single image is shown at once; several are read back by the editor once inserted.
6. VoiceOver announces `editor.announce.imageAdded` or `editor.announce.imagesAdded`.
7. If the person moved the caret or typed elsewhere meanwhile, the images still go where they were placed and the person's caret, focus and scrolling stay where they are (IM-9).

## Branches and messages

| Situation | Result | Message |
| --- | --- | --- |
| One image fails | Nothing inserted | The app's error alert with the cause (`messages.image.tooLarge`, `messages.image.unreadable` or `messages.image.unavailable`). |
| Some of several fail | The others are inserted | One alert: `editor.imageImport.someFailed` followed by the cause. |
| All of several fail | Nothing inserted | `editor.imageImport.allFailed` followed by the cause. |
| Cause when every failure has the same cause | | `editor.imageImport.cause.tooLarge`, `editor.imageImport.cause.unreadable`, `editor.imageImport.cause.unavailable` |
| Causes differ | | `editor.imageImport.cause.mixed` |
| Stop | Nothing inserted; no message | — |
| Another Insert Image started | The first ends; nothing of it is inserted; no message | — |
| The app locks | Nothing inserted; no message; the picker closes | — |
| The person leaves the entry (opens another, goes back) before it finished | Nothing inserted | `editor.imageImport.left` (one or several) |
| The entry stays open but stops being editable (for example it became read-only), or the library is replaced, before the images were read | Nothing inserted | `editor.imageImport.unchangeable` (one or several); see [open-questions.md](../open-questions.md), B25 |
| The file picker fails (other than cancelling) | Nothing inserted | The system's error text in the app's error alert. |

## Paste and drop

- **Paste** (⌘V, Edit ▸ Paste, the edit menu): when the pasteboard holds only pictures (or pictures and nothing but a web address), each picture is imported like an inserted image, in order, at the caret. A photo keeps its own bytes (HEIC, HEIF, JPEG, PNG, GIF, most compact first); a bitmap without a file (TIFF) is encoded once as JPEG (opaque, quality 0.9) or PNG (with transparency). Image files on the pasteboard are imported as the files they are. When the pasteboard also holds text, the text is pasted instead (`flows/editing-rules.md` PA-11).
- **Drop** (computer): pictures and image files dropped on the text go where they are dropped, in order.
- **Pictures inside pasted formatted text**: imported first, then the text and pictures arrive together (PA-12).
- Each pasted or dropped picture is placed where it was put, even if writing continues meanwhile. A failure shows the single-image message in the app's error alert; when several pictures fail, the alert shows the last failure.

## Placeholders while loading

- A picture whose file hasn't been read yet shows `editor.image.loading` (secondary text, the body size, the text width) in its place; one that can't be found shows `editor.image.unavailable`; an image whose address isn't one of the journal's attachments (a remote image from Markdown written elsewhere) shows `editor.image.remote` and is never downloaded.
- When the file arrives the placeholder is replaced in place; the visible text, selection and undo stay (IM-6).
- Missing images are tried again on later syncs; their references are never removed.

## Rules

- Images are stored only for the open entry; an image stored while writing continued in the same entry is still inserted, never left unused (`ImageImportTests.testAnImageStoredWhileTheEntryChangesIsKept`).
- The picker session can't come back after leaving, locking or a library change (`ImageImportTests.testPickerSessionCannotReviveAfterNavigationLockOrStoreReplacement`).
- Location is removed before anything is stored; pixels and orientation stay (`ImageImportTests.testAddedImagesLoseTheirLocationButKeepTheirPixelsAndOrientation`).
- The stored media type is the type the bytes are, not the file name's (`ImageImportTests.testImageImportUsesEncodedTypeAndPreservesBytesBeforeRejectingInvalidData`).

## Accessibility

- The progress notice reads as one element: label `editor.imageImport.addingAccessibility` or `editor.imageImport.addingSeveralAccessibility`, value `editor.imageImport.progressValue`; Stop is a separate button.
- Announcements as in step 6. The Insert Image menu items have symbols (photo on rectangle, camera, folder) and text labels.

## Platform notes (Apple)

- Computer: no camera or photo library choice; the open panel only.
- Phone, tablet: the same menu in the bottom bar and the keyboard accessory.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
