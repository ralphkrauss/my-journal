---
id: image-actions
title: Act on a picture
features: [image-actions, image-descriptions]
sources:
  - apps/apple/JournalApp/Editor/ImageActionsIOS.swift
  - apps/apple/JournalApp/Editor/ImageActionsMac.swift
  - apps/apple/JournalApp/Editor/ImageItems.swift
  - apps/apple/JournalApp/Editor/NativeTextView.swift (copy, cut, writablePasteboardTypes)
  - apps/apple/JournalApp/Views/RootView.swift (imageActions)
  - apps/apple/JournalTests/ImageActionsTests.swift
  - docs/design/image-actions-ios-2026-10-03.md
  - docs/design/image-actions-mac-2026-10-03.md
---

# Act on a picture

## Purpose

Copy, share, save, describe or delete a picture in an entry, handing other apps the original file rather than the smaller copy shown.

## Start

- **Phone, tablet**: long press on a picture → a context menu with a preview of the picture.
- **Computer**: right-click (or Control-click) on a picture, or the keyboard's menu key/VoiceOver's Show Menu while one picture is selected → the picture's menu. A right-click on text keeps the standard text menu.
- **VoiceOver**: each picture is an element (after the entry's text) with the same actions as custom actions.
- **Copy and Cut** of a selection that is exactly one shown picture also act on the picture.

## The menu

What is offered depends on whether the picture is shown (its file is here) and whether the entry is editable:

| Item | Phone, tablet | Computer | Offered when |
| --- | --- | --- | --- |
| Cut | — | `editor.image.cut` (⌘X) | Editable |
| Copy | `common.copy` (first) | `common.copy` (⌘C) | Shown (computer: always listed; acts only when shown) |
| Paste | — | `editor.image.paste` (⌘V) | Editable |
| Share | `common.share` | the system Share item | Shown |
| Save to Photos | `editor.image.saveToPhotos` | — | Shown |
| Save Image As… | — | `editor.image.saveImageAs` | Shown |
| Image Descriptions… | `library.entryActions.imageDescriptions` | `library.entryActions.imageDescriptions` | Editable and descriptions can be edited (not source-only, no conflict) |
| Delete | `common.delete` (destructive, in its own section) | `common.delete` (destructive) | Editable |

Order on the computer: Cut, Copy, Paste, separator, Share…, Save Image As…, separator, Image Descriptions…, separator, Delete. The system's AutoFill and Services items are removed from this menu. On the phone and tablet, symbols: copy, share, save, text below photo, trash. With nothing to offer (a read-only entry whose picture isn't shown), the phone and tablet show no menu.

VoiceOver action names drop the ellipsis: `common.copy`, `editor.image.shareSpoken`, `editor.image.saveToPhotos` / `editor.image.saveImageAsSpoken`, `editor.image.describeSpoken`, `common.delete`.

## Steps per action

- **Copy**: reads the stored original, then puts it on the pasteboard under its own type, plus a JPEG copy for HEIC/HEIF originals, plus the entry's own Markdown for the picture (so pasting into an entry gives the same picture) and no text. VoiceOver announces `editor.announce.copied`. On the computer the original is read as soon as a single picture is selected, so ⌘C is immediate; if it's still being read, Copy waits for it without blocking. If the original can't be read: `editor.image.copyFailed` and the pasteboard keeps what it had.
- **Cut** (computer): as Copy, then removes the picture (one undo step named `editor.undo.cut`). If the original can't be read nothing changes.
- **Share**: reads the original, then shows the system share sheet (phone, tablet: anchored at the picture) with the file named `editor.image.fileName` plus its type's extension (never the description, which may be private). Failure: `editor.image.shareFailed`.
- **Save to Photos** (phone, tablet): asks for add-only photo library access (purpose `editor.permission.photosAdd`). Denied: alert `editor.image.photosOff.title`, message `editor.image.photosOff.message`, buttons `common.openSettings` and `common.cancel`. Saved: VoiceOver announces `editor.announce.savedToPhotos`. Failure: `editor.image.saveToPhotosFailed`.
- **Save Image As…** (computer): a save panel attached to the window, name `editor.image.fileName` with the type's extension, only that type allowed; writes the original. Failure: `editor.image.saveFailed`.
- **Image Descriptions…**: opens `screens/image-description.md` for the entry.
- **Delete**: writing starts (so Undo reaches the step), then the picture is removed (`flows/editing-rules.md` IM-5) as one undo step named `editor.undo.deleteImage`; VoiceOver focus moves to the text and, after a moment, announces `editor.announce.imageDeleted`.

Failures appear in the app's error alert. An action chosen for a picture that has since moved or changed does nothing. A lock or leaving the entry closes the menu, share sheet, alert or save panel and cancels the read; nothing is reported after a lock.

## Drag

- Computer: dragging a selected picture to another app hands it the original (once read); a drag that starts before the read finishes carries only the entry's content. Another app always gets a copy.

## Rules

- Copy, Cut, Share and Save always use the stored original, never the display copy (`ImageActionsTests.testMenuActionsFollowWhatIsShownAndCopyHandsOverTheOriginal`, `testCopyingASelectedPictureHandsOverTheOriginal`, `testPasteboardGetsTheOriginalUnderItsOwnType`).
- VoiceOver actions act on the picture without moving the selection (`ImageActionsTests.testVoiceOverActionsActOnThePictureWithoutSelectingIt`).
- Locking closes an open picture menu (`ImageActionsTests.testLockingClosesAnOpenPictureMenu`).
- On the computer a selected picture is tinted and outlined with the selection colour, since the text selection is drawn behind it.

## Accessibility

- Picture element label: the description, or `editor.image.accessibilityLabel`; when not shown, `editor.image.loadingAccessibility`, `editor.image.unavailableAccessibility` or `editor.image.remoteAccessibility` followed by the description. Trait: image. Activating it does nothing; its actions are the custom actions above.
- When VoiceOver focuses a picture further down, the entry scrolls to it.

## Platform notes (Apple)

- Phone and tablet: Copy, Share…, Save to Photos, Image Descriptions…, Delete.
- Computer: Cut, Copy, Paste, Share…, Save Image As…, Image Descriptions…, Delete.

## Open questions

- None.
