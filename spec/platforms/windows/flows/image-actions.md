---
id: image-actions
title: Act on a picture (Windows)
spec: flows/image-actions.md
features: [image-actions, image-descriptions]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/command-bar-flyout
  - https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/integrate-sharesheet-send
---

# Act on a picture (Windows)

Copy, share, save, describe or delete a picture in an entry, handing other apps the original file rather than the smaller copy shown. Steps, rules and copy keys are the spec's [image-actions](../../../flows/image-actions.md); IM-5 and PA-1 of [editing-rules](editing-rules.md) apply.

## Controls

A picture's context menu is a `CommandBarFlyout`, opened by right-click, by Shift+F10 or the Menu key while one picture is selected, and by touch or pen press-and-hold. A right-click on text keeps the text's own menu ([5](../platform.md#5-context-menus)).

| Position | Item | Copy | Offered when |
| --- | --- | --- | --- |
| Primary | Cut (icon Cut E8C6) | `editor.image.cut` | Editable |
| Primary | Copy (Copy E8C8) | `common.copy` | Shown (always listed; acts only when shown) |
| Primary | Paste (Paste E77F) | `editor.image.paste` | Editable |
| Primary | Share (Share E72D) | `common.share` | Shown |
| Secondary | Save image as… | `editor.image.saveImageAs` | Shown |
| Secondary, after a separator | Image descriptions… | `library.entryActions.imageDescriptions` | Editable and descriptions can be edited (not source only, no conflict) |
| Secondary, after a separator | Delete (icon Delete E74D) | `common.delete` | Editable |

With nothing to offer (a read-only entry whose picture is not shown) no menu opens. Windows adds no AutoFill or Services items, so none are removed. The accelerators of `edit-text` (Ctrl+X, Ctrl+C, Ctrl+V) work on a selected picture. A selected picture is drawn with the selection colour tint and outline.

## Steps per action

- **Copy** reads the stored original, then puts it on the clipboard under its own format, a JPEG copy for HEIC and HEIF originals, and the entry's own Markdown for the picture (so pasting into an entry gives the same picture), with no text. Narrator hears `editor.announce.copied`. The original is read as soon as a single picture is selected, so Ctrl+C is immediate; if still being read, Copy waits for it without blocking. If it cannot be read: `editor.image.copyFailed`, and the clipboard keeps what it had.
- **Cut** does Copy, then removes the picture as one undo step named `editor.undo.cut`; nothing changes if the original cannot be read.
- **Share** reads the original, writes it to a temporary file named `editor.image.fileName` plus the type's extension (never the description, which may be private), and opens the Windows Share UI for the window ([27](../platform.md#27-sharing)). Failure: `editor.image.shareFailed`. The temporary file is deleted afterwards.
- **Save image as…** opens a `FileSavePicker` with the name `editor.image.fileName` and the type's extension, only that type allowed, and writes the original. Failure: `editor.image.saveFailed`.
- **Image descriptions…** opens [image-description](../screens/image-description.md) for the entry.
- **Delete** starts writing (so Undo reaches the step), removes the picture by rule IM-5 as one undo step named `editor.undo.deleteImage`, moves focus to the text and, after a moment, Narrator hears `editor.announce.imageDeleted`.

Failures show in the general error dialog. An action chosen for a picture that has since moved or changed does nothing. A lock or leaving the entry closes the menu, the Share UI, the dialog and the save picker, and cancels the read; nothing is reported after a lock.

Not offered: Save to Photos. Its keys (`editor.image.saveToPhotos`, `editor.image.photosOff.title`, `editor.image.photosOff.message`, `editor.image.saveToPhotosFailed`, `editor.announce.savedToPhotos`) are not used. The spoken action names (`editor.image.shareSpoken`, `editor.image.saveImageAsSpoken`, `editor.image.describeSpoken`) are VoiceOver action names; Windows uses the menu items' own names.

### Drag

Dragging a selected picture to another app hands it the original once read, as a file (a temporary file offered with delayed rendering, so Explorer and other apps accept it); a drag that starts before the read finishes carries only the entry's content. Another app always gets a copy; only a drop within the entry moves it (PA-14).

## Layout at each window width

| Width | What differs | Apple equivalent |
| --- | --- | --- |
| Large and medium | The `CommandBarFlyout` opens at the pointer or the picture | Mac context menu |
| Small | The same flyout, full width when opened by touch | iPhone menu with a picture preview |
| Text size | Menu text scales; no truncation | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `image-cut`, `image-copy`, `image-paste` | Primary commands of the picture flyout | Ctrl+X, Ctrl+C, Ctrl+V | As the table above |
| `image-share` | Primary command | none | Shown |
| `image-save-as` | Secondary command | none | Shown |
| `image-save-to-photos` | Not offered | none | |
| `image-delete` | Secondary command | Delete or Backspace with the picture selected is the editor's ordinary deletion, which follows IM-5; no chord of its own | Editable |
| `image-descriptions` | Secondary command | none | Editable, descriptions can be edited |

## Copy differences

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `common.share`, `editor.image.saveImageAs` | Share…, Save Image As… | Share (icon button with a tooltip), Save image as… | ellipsis and casing (platform.md, 12.2) |

Sentence case on the other labels ("Image descriptions…", "Delete").

## Accessibility

- A picture is one element: its name is the description, or `editor.image.accessibilityLabel`; when not shown, `editor.image.loadingAccessibility`, `editor.image.unavailableAccessibility` or `editor.image.remoteAccessibility` followed by the description. Activating it does nothing; its actions are in the context menu, which Narrator opens with its context-menu command (Shift+F10 on a focused picture). No separate spoken action names are needed: the menu's items are named.
- Acting on a picture from the menu does not move the selection (VoiceOver rule); Delete moves focus to the text.
- When Narrator focuses a picture further down, the entry scrolls to it.
- Menus and selection use system colours and are visible in contrast themes.

## Different by design

- **A `CommandBarFlyout`** with Cut, Copy, Paste and Share on top, replacing the Mac's flat menu; every action is still reachable by keyboard and the menu key.
- **No Save to Photos,** and Share is the Windows Share UI.
- **Windows file drag** carries a file, not a pasteboard item.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D36 (clipboard format).
