---
id: entry-conflict
title: Review changes, entry or template (Windows)
spec: screens/entry-conflict.md
features: [conflict-review-entry]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/selector-bar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---

# Review changes, entry or template (Windows)

When this device and another both changed the same entry or template, show both versions and let the person keep both or keep one. Nothing is merged and nothing is lost: the other versions remain in Version history. Behaviour, rules and copy keys are the spec's [entry-conflict](../../../screens/entry-conflict.md); the page around it, the routing to the other forms and the signals are [conflict-review](conflict-review.md); what each choice does is [resolve-conflict](../flows/resolve-conflict.md).

## Controls

The form fills the content region of the Review changes page (a page, not a dialog: [conflict-review](conflict-review.md)). The preview is the editor control in read-only mode ([entry-editor](entry-editor.md)), so formatting and images look as they do in the entry.

| Spec element | Windows control | Notes |
| --- | --- | --- |
| Status | An `InfoBar` at the top, not closable: Informational for `messages.conflict.status.updated`; Error for `messages.conflict.status.refreshFailed` (with `ActionButton` `common.tryAgain`), `messages.conflict.committedNotReloaded` (with `common.tryAgain`, and `common.done` next to it) and any other error text | A changed state closes and reopens the bar so Narrator reads it ([9.1](../platform.md#91-notices)); the bar is not focusable, so after a refresh focus moves to the version selector and the notification carries the text |
| Version choice | A `SelectorBar` with `common.thisDevice` and `messages.conflict.version.otherDevice`, `AutomationProperties.Name` `common.version`, at every width: one version is shown at a time, as in the spec (D50) | Selection is the spec's "switch version"; images load for the version shown |
| Version card | One card, the selected version: heading (`TextBlock`, `BodyStrong`, level 2: `common.thisDevice` or `messages.conflict.version.otherDevice`); the version's title (`Subtitle` style); its last change time (secondary, date and time in the user's regional format, [31](../platform.md#31-dates-time-zones-and-formats)); the placement line (secondary) from the spec's list: `messages.conflict.placement.inJournal`, `messages.conflict.placement.inJournalDated`, `messages.conflict.placement.inRecentlyDeleted`, `messages.conflict.placement.inRecentlyDeletedDated`, `messages.conflict.placement.inTemplates`, `messages.conflict.placement.inTemplatesDated`, `messages.conflict.placement.archivedIn`, `messages.conflict.placement.archivedInDated`, `messages.conflict.placement.dated`; only when the two versions differ in place or date | |
| Preview | The read-only editor surface, at least 300 epx tall; `AutomationProperties.HelpText` `messages.conflict.version.hintThisDevice` or `messages.conflict.version.hintOtherDevice` | Selectable and copyable so a person can take text from either version; the preview never changes the record |
| Keep both note | `TextBlock`, `Caption`, secondary, under the cards: `messages.conflict.keepBothNote.entries` or `messages.conflict.keepBothNote.templates`, followed when relevant by `messages.conflict.keepBothOutcome.placeAndDate`, `messages.conflict.keepBothOutcome.place` or `messages.conflict.keepBothOutcome.date` | |
| Keep both | `Button` (accent) `messages.conflict.keepBoth` | The one primary action of the page |
| Keep one version | A `DropDownButton` `messages.conflict.keepOne` with a `MenuFlyout` of two items, `messages.conflict.keepThisDevice` and `messages.conflict.keepOtherDevice` | Each opens the confirmation below |
| Confirmation | `ContentDialog`, title `messages.conflict.keepOne.title`; content: for this device's version `messages.conflict.keepOne.history` only; for the other device's version first the outcome (`messages.conflict.outcome.entry.moveToRecentlyDeleted`, `messages.conflict.outcome.entry.moveTo`, `messages.conflict.outcome.entry.archiveIn`, `messages.conflict.outcome.entry.dateChange`, `messages.conflict.outcome.entry.moveToRecentlyDeletedAndDate`, `messages.conflict.outcome.entry.moveToAndDate`, `messages.conflict.outcome.entry.archiveInAndDate`, or the `messages.conflict.outcome.template.*` equivalents) then `messages.conflict.keepOne.history`; Primary `messages.conflict.keepVersion`, Close `common.cancel`, no default button | The date in the outcome sentences is the abbreviated date in the user's format. It closes by itself if the conflict changes while it is open |
| Progress | An indeterminate `ProgressBar` along the top with `messages.conflict.savingChanges` or `messages.conflict.updatingChanges`; the choices dim and the back button is disabled | |
| Resolved | `messages.conflict.resolved` as an Informational bar; the page's button becomes `common.done` | |

## Layout at each window width

| Width (epx) | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium, 641 and up | One card at most 600 epx wide under the `SelectorBar`, left-aligned with 24 epx margins; preview 300 epx tall or more; the Keep both note, Keep both and Keep one version below | Mac sheet; iPad sheet, 360–480 pt |
| Small, 640 and down | One card full width with 12 epx margins; the `SelectorBar` fills the width; the actions fill the width and stack with Keep both first | iPhone sheet |
| 200% text size or more | One layout narrower; the preview follows the text size; the page scrolls | Apple's version menu at accessibility sizes: the `SelectorBar` stays, because it is one row of two items and wraps |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `review-changes` | The entry notice, the Changes to review list and the other signals ([conflict-review](conflict-review.md)) | none | Unlocked |

Keyboard: the selector and the cards are in reading order; Left and Right move in the `SelectorBar`; Ctrl+C copies the selected text of the preview; Enter on Keep both runs it; Alt+Left and the back button go back unless busy; Esc closes the dropdown or the confirmation and never leaves the page. Keep both and Keep one version never have an accelerator: a resolution is deliberate.

## Copy differences

Sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)): "This device", "Other device", "Keep both", "Keep one version", "Keep this version?", "Keep version". Ellipses ([12.2](../platform.md#122-ellipsis)):

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `messages.conflict.keepThisDevice` | Keep Version from This Device… | Keep version from this device | ellipsis (it only asks for confirmation) and casing |
| `messages.conflict.keepOtherDevice` | Keep Version from Other Device… | Keep version from other device | ellipsis and casing |

Nothing else differs. The placement and outcome lines use "Recently Deleted" and "Templates" as names of collections: "Recently deleted" by the casing rule, "Templates" unchanged.

## Accessibility

- The `SelectorBar` is named `common.version` and reads its selected value; the selected card is one group labelled by its heading.
- The preview's help text names the version. After a refresh the notification carries `messages.conflict.status.updated`, the bar is reopened, and focus goes to the version selector.
- No success announcement; the page leaves and the entry opens, so Narrator reads the entry's focus.
- Text wraps at every size; the `SelectorBar` wraps rather than truncates at 225% text size.
- Confirmation dialogs: Narrator reads the title and content; focus starts on Cancel; the destructive effect is described in words (the outcome sentence), not in colour.
- Four contrast themes: the cards, the preview decorations and the bars use theme resources.

## Different by design

- **One version at a time at every width, as in the spec** (D50, the review's recommendation: ship the spec's control first and add side by side only if testing shows people need it). The page is wide enough to compare directly, so side by side stays a later option.
- **A page with a status bar** instead of a sheet with a status line and VoiceOver focus on it.
- **The confirmation has no default button and focus starts on Cancel**: it is the only dialog in the flow, and choosing one version moves the other to history.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D50 (side by side reviews, deferred).
