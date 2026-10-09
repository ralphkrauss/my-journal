---
id: image-description
title: Image descriptions (Windows)
spec: screens/image-description.md
features: [image-descriptions]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/text-box
---

# Image descriptions (Windows)

Write a short description of every image in an entry or template, so Narrator can read it; the description is the image's Markdown alt text. Behaviour, rules and copy keys are the spec's [image-description](../../../screens/image-description.md). On Windows it is a page, because it shows a list of pictures with text fields ([9](../platform.md#9-sheets-popovers-and-notices)).

## Controls

A page in the window's content area, replacing the library panes and returning to them exactly as they were. Opening it first saves the open entry. Offered (enabled) only when the entry is editable, not shown as source only, and has no changes to review.

| Spec element | Control | Notes |
| --- | --- | --- |
| Header | A back button and a `BreadcrumbBar`: the entry or template title, then `editor.imageDescriptions.title` | Back (the back button, Alt+Left, the breadcrumb's earlier item) goes back at once when nothing is unsaved; with unsaved descriptions it asks first with the Save changes dialog below ([D39](../../../open-questions.md)). Nothing is disabled and nothing typed is lost silently |
| Introduction | `TextBlock`, secondary, `editor.imageDescriptions.intro` | |
| Each image | A `StackPanel`: heading, preview, field | Images on lines of their own first, in document order; then, block by block, images inside lines and table cells (remote images show as unavailable) |
| Heading | `TextBlock`, `BodyStrong`, heading level 2: `editor.imageDescriptions.image` for one image, otherwise `editor.imageDescriptions.imageNumber` | |
| Preview | `Image` fitted in 280 × 160 epx; while it loads a small indeterminate `ProgressBar` along its bottom edge with `editor.image.loading` (the page stays usable, so not a ring); when it cannot be shown, an icon (Picture E8B9) with `editor.imageDescriptions.imageUnavailable` in secondary text | |
| Description field | `TextBox`, `PlaceholderText` `editor.imageDescriptions.placeholder`, `TextWrapping` Wrap, growing from 1 to 3 lines (`MinHeight` one line, `MaxHeight` three, then scrolling), `AutomationProperties.Name` `editor.imageDescriptions.fieldLabel`, `IsSpellCheckEnabled` true | Stored as one line: Enter moves to the next description (or ends editing after the last); typed or pasted line breaks become spaces |
| Error or status text | An `InfoBar`, Severity Error (or Informational for status), not closable, selectable text | Announced when it opens |
| Progress | An indeterminate `ProgressBar` along the top of the page with `editor.imageDescriptions.loadingImages` or `editor.imageDescriptions.saving` | |
| Command row (bottom, pinned) | `Button` `editor.imageDescriptions.copy` (shown until saved), then `editor.imageDescriptions.reload` and `common.tryAgain` after an error or when the entry changed (as the spec's rules), at the leading end; `common.cancel` and `common.done` (accent) at the trailing end | Done is not the default button, because Enter belongs to the fields |

### States, as in the spec

Loading a preview: `editor.image.loading`. Image missing: `editor.imageDescriptions.imageUnavailable`. Saving: `editor.imageDescriptions.saving`. Reloading: `editor.imageDescriptions.loadingImages`. The entry is no longer describable (deleted, moved out, conflict, read-only): fields stay and Done is disabled, `editor.imageDescriptions.noLongerAvailable`. The entry changed: `messages.entry.imagesChanged`. Unavailable: `messages.entry.unavailableForEditing`. The entry's own writing is not saved: `messages.save.before.goBack` (Reload and Try again hidden; Copy stays). Saved but not shown: `editor.imageDescriptions.savedNotShown`. Images editable only as Markdown source: `messages.image.descriptionsNeedSource`.

### Actions

- **Done.** Unchanged: goes back. Changed: saves every description in one change to the entry, then goes back; if saved but the view could not refresh, it stays with `editor.imageDescriptions.savedNotShown`.
- **Cancel.** The button goes back and discards the changes, as on Apple; not while busy. Esc does not go back and does not discard anything (Esc is for transient surfaces only, [7.2](../platform.md#72-additions)).
- **Back with unsaved descriptions.** The back button, Alt+Left, the breadcrumb's earlier item and the window's Close button ask first, with the standard unsaved-changes prompt of Windows apps (Notepad's): a `ContentDialog` titled "Save description changes?" (new, B41), with Primary `common.save` (the default button; it saves as Done does, then goes back or closes), Secondary "Don’t save" (new; goes back or closes and discards, as Cancel does) and Close `common.cancel` (stays on the page, keeping what was typed). A greyed back button looks like a bug on Windows, and a silent discard breaks "nothing is silently discarded"; the disabled back of the Mac sheet is not copied (D39). Saving changes only the descriptions of the images the page showed and only if the entry still has exactly those images; otherwise it fails with "changed" and nothing is written, and the dialog's Save leaves the page open with that message.
- **Copy descriptions.** Copies all descriptions as plain text: "Image 1", a new line, the description, a blank line, and so on.
- **Reload images** with unsaved changes asks first: a `ContentDialog` titled `editor.imageDescriptions.discardTitle`, Primary `editor.imageDescriptions.reload`, Close `editor.imageDescriptions.keepEditing`, no default button. Then it waits for the entry's save, reloads and shows the current images.
- **Locking** saves typed descriptions (with the open entry, at most 2 seconds); if they cannot be saved in time they are kept in memory and saved after the next unlock while that entry is open, or shown again the next time the page opens for the same entry with the same images. The page closes when locking.

## Layout at each window width

| Width | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium | Content column at most 600 epx wide, left-aligned with 24 epx margins; the command row pinned at the bottom | Mac sheet 360–460 × 400–540 pt |
| Small | Full-width page with 12 epx margins; previews scale down to the width; the command row wraps to two rows | iPhone sheet |
| 200% text size or more | Fields grow; the command row stacks with Done first; the page scrolls | |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `image-descriptions` | Entry actions; entry row context menu; a picture's context menu | none | The entry is editable, not source only, no changes to review; shown only when the entry has pictures |

- Enter in a description field moves to the next one (Done on the last).
- Alt+Left, the back button and the breadcrumb go back, asking first while descriptions are unsaved; Esc does nothing on the page. Focusing a field scrolls it to the top of the page.

## Copy differences

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `editor.imageDescriptions.intro` | Describe what matters in each image. Descriptions help people using VoiceOver. | … Descriptions help people using Narrator. | vocabulary (B28) |
| `editor.imageDescriptions.copy`, `editor.imageDescriptions.reload`, `editor.imageDescriptions.title` | Copy Descriptions, Reload Images, Image Descriptions | Copy descriptions, Reload images, Image descriptions | casing |
| A new dialog title and a new button for Back with unsaved descriptions: "Save description changes?" and "Don’t save" (Save is `common.save`, Cancel is `common.cancel`) | none | In [copy-proposals.md](../copy-proposals.md) | new, B41, D39 |

## Accessibility

- Each field is named by `editor.imageDescriptions.fieldLabel`; each preview by `editor.imageDescriptions.previewLabel`, a loading one by `editor.imageDescriptions.previewLoading`, an unavailable one by `editor.imageDescriptions.previewUnavailable`.
- The Save changes dialog reads its title and message; focus starts on Save, and closing it with Cancel returns focus to the field that had it. Errors are `InfoBar`s and are announced when they appear. Focus goes to the first field when the page opens and returns to the Entry actions button or the picture's menu's origin on leaving.
- The page works in contrast themes with system colours and scales with text size.

## Different by design

- **A page, not a sheet**, with a back button and breadcrumb ([9](../platform.md#9-sheets-popovers-and-notices)).
- **Back asks before leaving with unsaved descriptions.** On Apple, swipe-to-dismiss is blocked while there are unsaved changes. On Windows a greyed back button looks like a bug, so Back, Alt+Left, the breadcrumb and the window's Close button ask Save, Don’t save or Cancel, as Notepad does; only the Cancel button of the page discards without asking (D39).
- **Esc is not Back.** It never discards typed text.
- **Fields have names, not only placeholders**, and the intro says Narrator.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B28 (Apple names in sentences), D39 (Back with unsaved descriptions), B41 (the Save changes strings).
