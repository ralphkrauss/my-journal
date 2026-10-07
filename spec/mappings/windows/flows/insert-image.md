---
id: insert-image
title: Insert an image (Windows)
spec: flows/insert-image.md
features: [insert-image, insert-image-camera, paste-and-drop, image-placeholders]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/files/using-file-folder-pickers
  - https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.ui.text.itextrange.insertimage
---

# Insert an image (Windows)

Adds pictures to an entry from files, the clipboard or a drop, without losing writing and without storing where a picture was taken. Steps, branches and copy keys are the spec's [insert-image](../../../flows/insert-image.md); the rules IM-1 to IM-9 and PA-11 to PA-15 are in [editing-rules](editing-rules.md). Windows has no photo library and the camera is not offered in version 1 ([26](../platform.md#26-camera-photos-and-images)).

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Insert Image button | `AppBarButton` in the editor header, icon Picture (E8B9), `library.toolbar.insertImage`; **opens the file picker directly**, because it would otherwise be a menu with one item | Disabled when the entry cannot be edited |
| Format ▸ Insert ▸ Image…, the formatting bar's Insert ▸ Image… | Menu items `library.menu.format.insert.image` | Nothing to close first: the bar's drop-down closes as any menu does |
| File picker | `FileOpenPicker` (with the window handle), `ViewMode` Thumbnail, start in Pictures, several files at once, image types only: the formats listed in the spec's step 3 (JPEG, PNG, GIF, HEIC, HEIF, TIFF) | The picker's multi-select order is not guaranteed to be the order chosen; the app orders by the picker's result and the spike checks it (the spec says "in the order chosen") |
| Photo Library, Take Photo | Not offered | `editor.insertImage.photoLibrary`, `editor.insertImage.takePhoto`, `editor.insertImage.cameraOff.title`, `editor.insertImage.cameraOff.message` and `editor.permission.camera` are not used on Windows |
| Choose File… menu item | Not shown | The button opens the picker directly (B30) |
| Progress notice | `InfoBar` Informational with an indeterminate `ProgressBar` and a Stop `Button`, after 0.5 s: `editor.imageImport.adding`, or `editor.imageImport.addingSeveral` ("{done} of {total}"), `editor.imageImport.stop` | [entry-editor](../screens/entry-editor.md), row 5. At 200% text size the button goes below the text |
| Failures | The general error dialog: `ContentDialog`, Close `common.ok`, no title ([8.1](../platform.md#81-rules)) | One dialog at a time |
| Placeholders | A line in secondary text at the picture's place: `editor.image.loading`, `editor.image.unavailable`, `editor.image.remote` | Replaced in place when the file arrives |

## Steps on Windows

1. Choosing the button, the menu item or Ctrl+V records the caret (or selection) as the insertion point; pictures go there even if writing continues. Cancelling the picker ends the flow without a message.
2. Chosen images are read and stored in the background, two at a time, in order. For each:
   - larger than 25 MB (25 × 1024 × 1024 − 28 bytes): refused, `messages.image.tooLarge`;
   - not readable as an image: refused, `messages.image.unreadable`;
   - cannot be provided (for example an online-only cloud file that did not download): refused, `messages.image.unavailable`;
   - otherwise its location (GPS coordinates and place names) is removed and it is stored encrypted, as the file it was where possible: orientation, capture time and other metadata kept, image data copied unchanged where the format allows (a lossless metadata-only rewrite through the imaging stack, to be confirmed per format), otherwise re-encoded without loss. HEIC and HEIF need the codecs Windows installs from the Store; an image that cannot be decoded takes the unreadable path.
3. If reading takes longer than 0.5 s the progress notice appears; Stop ends it with nothing inserted and no message.
4. When every image has been read all the stored images are inserted together, in order, at the recorded point, as one undo step, each on a line of its own with one empty line between consecutive images in the Markdown (IM-1, U-8). A single image shows at once; several are read back by the editor once inserted.
5. Narrator is told `editor.announce.imageAdded` or `editor.announce.imagesAdded`.
6. If the person moved the caret or typed elsewhere meanwhile the images still go where they were placed and the person's caret, focus and scrolling stay where they are (IM-9).

### Branches and messages

As the spec's table, with Windows presentation: one image fails, nothing inserted, error dialog with the cause; some of several fail, the others insert and one dialog says `editor.imageImport.someFailed` followed by the cause; all of several fail, `editor.imageImport.allFailed` followed by the cause; the cause when every failure shares one is `editor.imageImport.cause.tooLarge`, `editor.imageImport.cause.unreadable` or `editor.imageImport.cause.unavailable`, otherwise `editor.imageImport.cause.mixed`. Stop, starting another Insert image, and the app locking insert nothing and say nothing (a lock also closes the picker). Leaving the entry before it finished, or the entry ceasing to be editable, inserts nothing and says `editor.imageImport.left`. A failing picker shows the system's error text in the error dialog.

### Paste and drop

- **Paste (Ctrl+V, Edit ▸ Paste, the context menu).** When the clipboard holds only pictures (or pictures and nothing but a web address), each is imported like an inserted image, in order, at the caret. An image file on the clipboard is imported as the file it is. A bitmap with a registered PNG or JPEG format keeps those bytes; a bitmap offered only as a device-independent bitmap is encoded once, as JPEG (opaque, quality 0.9) or PNG (with transparency). A Snipping Tool capture (Win+Shift+S) therefore arrives as the PNG it is. When the clipboard also holds text, the text is pasted instead (PA-11).
- **Drop.** Image files dropped from File Explorer, and pictures dropped from a browser, go where they are dropped, in order. A bare web address of an image is never downloaded.
- **Pictures inside pasted formatted text** are imported first, then text and pictures arrive together (PA-12).
- Each pasted or dropped picture is placed where it was put, even if writing continues. A failure shows the single-image message; when several fail, the dialog shows the last failure.

### Placeholders while loading

A picture whose file has not been read shows `editor.image.loading`; one that cannot be found shows `editor.image.unavailable`; an image whose address is not one of the journal's attachments (a remote image from Markdown written elsewhere) shows `editor.image.remote` and is never downloaded. The placeholder is replaced in place without moving the visible text, selection or undo (IM-6). Missing images are tried again on later syncs and their references are never removed.

Images are stored only for the open entry; a picker session cannot revive after leaving, locking or a library change; location is removed before anything is stored; the stored media type is the type the bytes are, not the file name's.

## Layout at each window width

| Width | What differs | Apple equivalent |
| --- | --- | --- |
| Large and medium | The button in the editor header opens the picker; the progress notice between the title and the body ([entry-editor](../screens/entry-editor.md), row 5) | Mac toolbar button and open panel |
| Small | The button is in the entry page's header or its overflow; the picker and notice are the same | iPhone Insert Image menu |
| Text size | Notice text wraps, the Stop button goes below it | Accessibility sizes |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `insert-image`, `insert-image-choose-file` | Insert image button; Format ▸ Insert ▸ Image…; the formatting bar's Insert drop-down | none | The entry is editable |
| `insert-image-photo-library`, `insert-image-take-photo` | Not offered | none | |
| `edit-text` | Edit ▸ Paste; the context menu | Ctrl+V | Pasting a picture follows the rules above |

## Copy differences

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `editor.imageImport.cause.unavailable`, `messages.image.unavailable` | … downloading from iCloud. Try again later. | They may still be downloading. Try again later. | vocabulary (platform.md, 12.3) |
| `messages.image.tooLarge`, `editor.imageImport.cause.mixed` | Choose an image smaller than 25 MB. / … choose other images. | Select … | vocabulary (B26) |
| `editor.insertImage.chooseFile` | Choose File… | not shown | removed (B30) |

## Accessibility

- The button's name is `library.toolbar.insertImage`; the picker is the system's and fully accessible.
- The progress `InfoBar` reads as one element: label `editor.imageImport.addingAccessibility` or `editor.imageImport.addingSeveralAccessibility`, value `editor.imageImport.progressValue`; Stop is a separate button.
- Announcements as step 5. Failures are announced when the error dialog opens.

## Different by design

- **One source, so no menu:** the button opens the file picker directly.
- **Clipboard and drop replace the photo library.** A Snipping Tool capture, a copied bitmap and an Explorer drag are the Windows routes ([26](../platform.md#26-camera-photos-and-images)).
- **No camera, no permission alerts.**

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B26 (select and choose), B30 (strings never shown).
