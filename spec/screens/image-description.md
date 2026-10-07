---
id: image-description
title: Image Descriptions
features: [image-descriptions]
sources:
  - apps/apple/JournalApp/Views/ImageDescriptionsView.swift
  - apps/apple/JournalApp/Model/ImageDescriptionOperations.swift
  - apps/apple/JournalApp/Model/LockSaving.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/ImageDescriptions.swift
  - apps/apple/JournalTests/ImageDescriptionLifecycleTests.swift
  - apps/apple/JournalTests/LockSavingTests.swift
  - docs/design/image-descriptions.md
  - docs/design/image-description-native-form.md
  - docs/design/pre-release-fixes-2026-09-27.md (item i)
---

# Image Descriptions

## Purpose

Write a short description of every image in an entry or template, so VoiceOver can read it. The description is the image's Markdown alt text.

## Entry points

- Entry Actions ▸ Image Descriptions… (and the entry row's context menu), shown when the entry has images (`image-descriptions`).
- A picture's menu ▸ Image Descriptions… (`image-descriptions`), and the VoiceOver action “Image Descriptions”.

Offered (enabled) only when the entry is editable, isn't shown as Markdown source only, and has no changes to review.

## Content

Sheet. Phone and tablet: navigation bar with title `editor.imageDescriptions.title`, `common.cancel` (leading) and `common.done` (trailing). Computer: title at the top, scrolling content, a divider, then Cancel (leading) and Done (trailing); 360–460 pt wide, 400–540 pt tall.

Scrolling content:

1. Introduction, secondary text: `editor.imageDescriptions.intro`.
2. For each image of the entry: first the images on lines of their own, in document order; then, block by block, the images inside lines and inside table cells (including remote images, which show as unavailable):
   - Heading: `editor.imageDescriptions.image` when there is one image, otherwise `editor.imageDescriptions.imageNumber`.
   - Preview: the image fitted in 280 × 160 pt; while it loads, a progress indicator with `editor.image.loading`; when it can't be shown, a photo symbol with `editor.imageDescriptions.imageUnavailable` in secondary text.
   - A rounded text field with placeholder `editor.imageDescriptions.placeholder`, growing from 1 to 3 lines; its Return key is Next, or Done on the last image.
3. Error or status text (secondary, selectable), when there is one.
4. While working: a progress indicator with `editor.imageDescriptions.loadingImages` or `editor.imageDescriptions.saving`.
5. Until saved: `editor.imageDescriptions.copy` button; and, after an error or when the entry changed, `editor.imageDescriptions.reload` and (when it can still be saved) `common.tryAgain`.

## Actions

| Action | Enabled | Result |
| --- | --- | --- |
| Type a description | Not busy, not saved | Stored as one line: Return moves to the next description (or ends editing after the last); line breaks typed or pasted become spaces (`ImageDescription.singleLine`). |
| Done | Unchanged, or saved, or (changed and still describable, not invalidated, entry saved) | Unchanged: closes. Changed: saves every description in one change to the entry, then closes. If saved but the view couldn't refresh: stays with `editor.imageDescriptions.savedNotShown`. |
| Cancel, Escape | Not busy and not saved | Closes; changes are discarded. Swipe-to-dismiss is blocked while there are unsaved changes or work in progress. |
| Copy Descriptions | Not busy | Copies all descriptions as plain text: “Image 1”, a new line, the description, a blank line, and so on. |
| Reload Images | After an error or invalidation, entry describable, not busy | With unsaved changes, asks first: dialog `editor.imageDescriptions.discardTitle` with `editor.imageDescriptions.keepEditing` (cancel) and `editor.imageDescriptions.reload` (destructive). Then waits for the entry's save, reloads the entry and shows its current images and descriptions. |
| Try Again | After an error, not invalidated, describable | Saves again. |

## States

| State | Copy |
| --- | --- |
| Loading a preview | `editor.image.loading` |
| Image missing | `editor.imageDescriptions.imageUnavailable` |
| Saving | `editor.imageDescriptions.saving` |
| Reloading | `editor.imageDescriptions.loadingImages` |
| Entry no longer describable while the sheet is open (deleted, moved out, conflict, read-only): fields stay, Done disabled | `editor.imageDescriptions.noLongerAvailable` |
| The entry changed (images added or removed elsewhere) | `messages.entry.imagesChanged` |
| Unavailable | `messages.entry.unavailableForEditing` |
| The entry's own writing isn't saved | `messages.save.before.imageDescriptions` (Reload and Try Again hidden; Copy stays) |
| Saved but not shown | `editor.imageDescriptions.savedNotShown` |
| The entry’s images can only be edited as Markdown source (refused when saving) | `messages.image.descriptionsNeedSource` |
| Locked | See Rules. |

Errors are announced to VoiceOver when they appear.

## Rules

- Saving changes only the descriptions of the images the sheet showed, and only if the entry still has exactly those images; otherwise it fails with “changed” and nothing is written. It first waits for the entry's own pending save.
- The description of an image is written as its alt text in the Markdown; inline images and images in table cells are described the same way. Nothing else in the Markdown changes.
- **Locking**: before the journals lock, typed descriptions are saved (with the open entry), waiting at most 2 seconds. If they can't be saved in time, they're kept in memory: saved after the next unlock while that entry is open, or shown again in this sheet the next time it opens for the same entry with the same images. The sheet closes when locking.
- One description per image; no length limit.

## Accessibility

- Each field: label `editor.imageDescriptions.fieldLabel`. Each preview: label `editor.imageDescriptions.previewLabel`; a loading preview `editor.imageDescriptions.previewLoading`, an unavailable one `editor.imageDescriptions.previewUnavailable`.
- Focusing a field scrolls it to the top of the sheet.
- Errors are announced.

## Platform notes (Apple)

- Same content on every platform; navigation-bar buttons on the phone and tablet, a bottom button row on the computer.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
