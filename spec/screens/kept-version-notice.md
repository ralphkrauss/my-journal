---
id: kept-version-notice
title: Other version notice
features: [kept-both-notice]
sources:
  - apps/apple/JournalApp/Views/KeptVersionNotice.swift
  - apps/apple/JournalApp/Model/ConflictNotes.swift
  - apps/apple/JournalApp/Views/RootView.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/KeptNotes.swift
  - docs/design/1-1-conflicts-and-reconnect.md
---

# Other version notice

## Purpose

When the same entry or template changed on this device and on another, the device keeps both versions and saves the other as a separate entry or template ([flows/resolve-conflict.md](../flows/resolve-conflict.md)). This notice tells the person, on the device that kept both, in the entry or template that is open, and offers to open the other version. It asks nothing: there is nothing to decide. It replaces the Review Changes notice, the marker on a list row and the Review Changes sheet of 1.0, none of which exist any more.

The list of everything the device kept is in Settings ▸ Sync ▸ Changed on Two Devices ([settings-sync.md](settings-sync.md)).

## Entry points

The notice appears above the writing of the open entry or template when this device has kept both versions of it and the person has not seen the note yet. It is local to this device: other devices see only the other version as an ordinary entry, with its title ending "(other version)". It is never shown for a journal.

## Content

A band above the writing, in the style of the other notices (callout text on a quaternary fill, no animation, wrapping), in this order: the text, then two buttons below it.

| Text | When |
| --- | --- |
| `messages.conflict.kept.notice.entry` | An entry; the other version is not later than this one |
| `messages.conflict.kept.notice.entryNewer` | An entry; the other version's last-change time is later (the two devices' clocks; the wording only) |
| `messages.conflict.kept.notice.template` | A template; as the first row |
| `messages.conflict.kept.notice.templateNewer` | A template; as the second row |
| `messages.conflict.kept.noticeUpdate` | The conflict is held because a version of the entry or template was saved by a newer My Journal. No buttons |

Buttons: **Show Other Version** (`messages.conflict.kept.showOther`) and **Dismiss** (`common.dismiss`). The text is always above the buttons; at accessibility text sizes the buttons stack one above the other.

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Show Other Version | `show-other-version` | Unlocked, the library not being replaced, the other version still exists | Opens the other version wherever it is: the journal it is in is selected and the search cleared, or Recently Deleted or Templates is opened when that is where it is. Marks the note seen, so the notice goes |
| Dismiss | `dismiss-kept-notice` | Unlocked, the library not being replaced | Marks the note seen and removes the notice. The row in Settings ▸ Sync stays until it expires |

## States

- **When it appears.** Nothing is settled while the entry is being written, so a notice never arrives mid-keystroke. It is added when neither the title nor the text has the keyboard focus. If the cursor is resting in the title or the text it waits until the entry is shown again, or until focus leaves, so the writing never moves under a resting cursor. Once it has appeared it stays when the person starts writing again.
- **Replaced copy.** When a later version from the other device replaces an untouched copy, the existing note is updated, not added; if the person has already dismissed it, it stays dismissed.
- **Held.** The notice shows `messages.conflict.kept.noticeUpdate` with no buttons until a newer My Journal can read both versions; it settles by itself then.
- **The other version is gone** (deleted permanently, or removed): the note is dropped silently and no notice shows.
- **Locked.** Not shown; nothing it names is read.
- **Library being replaced.** The buttons do nothing.
- **Offline.** The same; nothing here needs the network.

## Rules

- The notice never changes what the editor holds: this device's version is the record, unchanged.
- No alert, badge, sound or announcement; nothing is added to Sync Status.
- It appears once per kept copy, on the device that kept both. A notice that was seen is never shown again, but its row in Settings stays for 30 days.
- The text decides nothing about which version is the record; "newer" is the other version's last-change time by device clocks, as a hint.

## Accessibility

- No announcement is posted, so it never talks over the typing echo; the notice is read when focus reaches it, as text followed by two buttons.
- Voice Control and speech: "Show Other Version", "Dismiss". Return and Escape are not bound.
- Text wraps at every size; nothing is told by colour alone.

## Platform notes (Apple)

- iPhone and iPad: full width above the writing, which scrolls beneath it so the notice stays in view; Mac: the first element of the detail column, below any recovery notice. See [platforms/apple/screens/kept-version-notice.md](../platforms/apple/screens/kept-version-notice.md).

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
