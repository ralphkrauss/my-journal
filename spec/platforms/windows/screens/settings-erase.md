---
id: settings-erase
title: Erase journals and settings, section and dialogs (Windows)
spec: screens/settings-erase.md
features: [erase-device]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Erase journals and settings, section and dialogs (Windows)

The last group of General and the dialogs it opens. Behaviour and copy keys are the spec's [Erase](../../../screens/settings-erase.md); what is removed on Windows, in order, is the [erase flow mapping](../flows/erase.md). The shell and patterns are in [settings](settings.md#card-patterns).

## Controls

### The group

The group sits last on [General](settings-general.md), 24 epx below the other cards, with no header. An [action card](settings.md#card-patterns): `Header` `settings.erase.button` (icon Delete E74D, no red) with a real standard `Button` `settings.erase.button` in its content (the card is not clickable on its own, so it cannot be hit by accident), `Description` the footer: `settings.erase.footerConnected` or `settings.erase.footerLocal`. The Mac-only sentence `settings.erase.footerFormerServer` is never shown. The card is disabled with the spec's rules: no library, or the library is being changed (connecting, importing, encrypting, Delete all running, a failed save, another erase), and while the count is being made (the "checking" state).

### Warning dialog

A `ContentDialog`. `Title` `settings.erase.alert.title` (a question). Content: one message by case, from the spec's table: `settings.erase.alert.onServer`, `settings.erase.alert.unsent` (plural), `settings.erase.alert.unconfirmed`, `settings.erase.alert.notSyncing`, `settings.erase.alert.nothingWritten`; the host is the server's host.

| Case | Primary | Secondary | Close | Default button |
| --- | --- | --- | --- | --- |
| Journals would be lost (unsent, unconfirmed, not syncing) | `common.exportArchive`, accent | `settings.erase.alert.erase` | `common.cancel` | Primary |
| Nothing would be lost (on server, nothing written) | `settings.erase.alert.erase` | none | `common.cancel` | None |

When journals would be lost the dialog's first button is Export archive…, the safe action the message asks for ("Export an archive first…"), and it is the default so Enter never erases. Erase is the second button, not accent-coloured. This is the one place where a destructive confirmation does not follow the rule "primary is the verb" ([8.1, rule 3](../platform.md#81-rules)); the rule's purpose, that Enter and a quick click never erase, is kept, and the reason is the message's own advice. Export archive… closes this dialog and opens the Export archive dialog ([settings-backup](settings-backup.md)); to erase afterwards the person chooses the Erase button again. In the nothing-lost case neither button is default and Close is Cancel.

If more would be lost than the warning said when Erase is chosen (the spec's second count), the dialog is replaced by the warning for the current case, as a new dialog in the queue.

### Failure dialog

`ContentDialog`: `Title` `settings.erase.failed.title`, content `settings.erase.failed.message`, Close `common.ok`. Nothing was removed.

### Windows Hello and the result

When App Lock is on, Erase first closes the dialog and asks Windows Hello through [the authentication gate](settings.md#the-authentication-gate) with `settings.erase.authReason`. Cancelled or failed: nothing happens and nothing is said. A PC where Hello is not set up continues without it. After the commit, the window navigates to the first-launch page ([welcome](welcome.md)); focus moves to that page's primary action, and Narrator reads the page title. No message announces the erase.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | The card in General; dialogs 548 epx wide | Mac alert |
| Small | The dialog fills the width; buttons stack | iPhone action sheet |
| Text size 200% or more | Buttons stack in the order Primary, Secondary, Close | Accessibility sizes |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `erase-device` | The button in the action card in General | — | As above. Saves the open entry, counts what would be lost, shows the warning |
| `export-archive` | Button in the warning dialog | — | Journals would be lost |
| `erase-confirm` | Button in the warning dialog | — | Always in the dialog; no accelerator and no default |

## Copy differences

Sentence case applies ("Erase journals and settings?", "Erase", "Couldn’t erase"). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.erase.button` | Erase Journals and Settings… | Erase journals and settings | ellipsis (platform.md, 12.2) |
| `settings.erase.footerFormerServer` | A copy of your journals from the server this Mac used to run isn’t removed. | Not shown | removed (platform.md, 12.3) |
| `settings.erase.authReason` | {"default": "Erase journals on this device", "mac": "erase journals on this device"} | The default form | vocabulary (platform.md, 12.3) |

## Accessibility

- The card's button reads "Erase journals and settings" with the card's footer as description; it is not coloured red, so no meaning rests on colour. The warning dialog reads its title, then the message, which starts with what to do when something would be lost, then the buttons.
- Focus: the dialog opens on its default button (Export archive…) or, with no default, on Close (Cancel), as in [8.1, rule 7](../platform.md#81-rules); Close returns focus to the button. After the erase, focus is on the first-launch page.
- Contrast themes and 225% text: standard dialog layout.

## Different by design

- **Button arrangement** as described above: the safe, recommended action is the default and first.
- **No ellipsis** on the button: it asks only for confirmation ([12.2](../platform.md#122-ellipsis)).
- **A real button in the card**, not a clickable card, for this and every destructive action ([settings](settings.md#card-patterns)).
- **No former-server footer.**

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): D44 (Erase warning buttons).
