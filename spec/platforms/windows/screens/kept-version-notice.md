---
id: kept-version-notice
title: Other version notice (Windows)
spec: screens/kept-version-notice.md
features: [kept-both-notice]
status: draft
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---

# Other version notice (Windows)

When the same entry or template changed on this PC and on another, the shared engine keeps both versions and saves the other as a separate entry or template; this page maps the notice that says so above the open entry or template, on the PC that kept both. Behaviour, states, rules and copy keys are the spec's [kept-version-notice](../../../screens/kept-version-notice.md); what the engine does and when is [resolve-conflict](../flows/resolve-conflict.md). The list of kept versions is [settings-sync](settings-sync.md). Windows never builds a review page, a review form, a marker in the entries list or a Changes to review group: nothing asks the person to decide.

## Controls

| Spec element | Windows control | Notes |
| --- | --- | --- |
| The notice above the writing | An Informational `InfoBar` in the editor's notice region ([entry-editor](entry-editor.md)), `IsOpen` while the note is unseen, `IsClosable` true, `Message` the text of the spec's table (`messages.conflict.kept.notice.entry`, `.entryNewer`, `.template` or `.templateNewer`) | Not a Warning: nothing is wrong and nothing is asked. No `Title`. The bar wraps; the engine's note decides when it opens |
| Show Other Version | The `InfoBar`'s `ActionButton`, `messages.conflict.kept.showOther` | Runs `show-other-version`: the library shows the other version wherever it is (its journal selected and the search cleared, Templates, or Recently deleted), then marks the note seen |
| Dismiss | The `InfoBar`'s close button, `AutomationProperties.Name` `common.dismiss`, with `Closed` marking the note seen | Runs `dismiss-kept-notice`. The close button is the only second control the `InfoBar` offers; the spec's "Dismiss" button is that button, named for Narrator and Voice Access |
| Held: a version only a newer My Journal can read | The same `InfoBar` with `messages.conflict.kept.noticeUpdate` and no action button; the close button is hidden (`IsClosable` false) because it settles by itself | The "Get updates" link (D51) follows the text, as for the other Update My Journal texts |

## Layout at each window width

| Width (epx) | Presentation | Apple equivalent |
| --- | --- | --- |
| Large and medium, 641 and up | The `InfoBar` spans the editor column above the writing; message left, action button and close button at the trailing end | iPad, Mac |
| Small, 640 and down | Full width above the writing; the action button wraps under the message | iPhone |
| 200% text size or more | The message wraps and the action button sits below it; nothing is truncated | accessibility sizes, where the buttons stack under the text |

It appears only when neither the title nor the text has the keyboard focus. If the cursor rests in either it waits until the entry is shown again, or until focus leaves, so the writing never moves under the cursor.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `show-other-version` | The `InfoBar`'s action button | none | Unlocked, the library not being replaced, the other version exists |
| `dismiss-kept-notice` | The `InfoBar`'s close button | none | Unlocked, the library not being replaced |

Tab reaches the action button, then the close button; Esc does not close the bar.

## Copy differences

None for the notice. `messages.conflict.kept.showOther` becomes "Show other version" in sentence case ([platform.md, 12](../platform.md#12-copy-casing-ellipses-and-vocabulary)); the proposal is in [copy-proposals](../copy-proposals.md).

## Accessibility

- The `InfoBar` is not announced when it opens: its `IsOpen` change is not given an automation peer notification, so Narrator never speaks over the typing echo. Narrator reads it in browse mode and when focus reaches its buttons.
- The action button is named by its text; the close button is named `common.dismiss`. Voice Access: "Show other version", "Dismiss".
- Four contrast themes: the Informational `InfoBar` uses theme brushes. At 225% text size nothing truncates.

## Different by design

- **An `InfoBar` instead of a callout band**, with the system close button as Dismiss: the notice is a native Windows notice and the spec's two buttons map to the control's two slots ([9](../platform.md#9-sheets-popovers-and-notices)).
- **The action button may sit beside the message** at medium and large widths, where Apple stacks it under the text only at accessibility sizes.

## Open questions

None for this page beyond [open-questions.md](../../../open-questions.md), D51 (the update link).
