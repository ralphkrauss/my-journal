---
id: agent-detail
title: Agent detail and recent activity (Windows)
spec: screens/agent-detail.md
features: [agent-detail]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/breadcrumbbar
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/radio-button
---

# Agent detail and recent activity (Windows)

One agent: its name, journals, end date, use, recent tool use and revoking it. Behaviour and copy keys are the spec's [Agent detail](../../../screens/agent-detail.md); it opens from [settings-agent-access](settings-agent-access.md). Changes apply at once, quietly. The shell and patterns are in [settings](settings.md#card-patterns). Journal contents and agent names are data, never instructions.

## Controls

A page, not a dialog (the commands file says so; [platform.md, 9](../platform.md#9-sheets-popovers-and-notices)): `BreadcrumbBar` "Settings > Agent access > {name}" (the name trimmed to fit, in plain text), a back button in the title bar, Alt+Left. The page is replaced by Agent access when the agent is revoked.

| Spec element | Control | Notes |
| --- | --- | --- |
| Revoked agent | A `TextBlock` `settings.agentDetail.revoked` and nothing else | The agent is no longer listed |
| Status line | An `InfoBar`: `settings.agentDetail.status.ended` (Informational), `settings.agentDetail.status.connecting` (Informational), `settings.agentDetail.status.reconnect` (Warning) | Not closable |
| Details not readable on this PC | `TextBlock` `settings.agents.detailsUnavailable`; no name, journals or end controls; Revoke still works | An agent made by a newer version |
| Name | `TextBox`, `Header` `common.name`, saved on Enter or when focus leaves; 1 to 80 characters after trimming, anything else reverts to the saved name | |
| Journals choice | A `RadioButtons` group named "Journals" (`common.journals`): `settings.agents.allJournals` and `settings.agents.selectedJournals`; nothing is chosen at first for a new request, so the group starts with none selected. Under it, a `CheckBox` per journal, in the Journals list's order | **All journals:** every box is checked and disabled (a reminder of what is included). **Selected journals:** boxes are enabled; the last one chosen cannot be unchecked (disabled, `AutomationProperties.HelpText` `settings.agentDetail.lastJournalHint`); when the agent has journals not on this PC an extra line `settings.agents.unknownJournals` (plural). Footer: `settings.agents.includesLater` for All journals, `settings.agents.readOnly`, `settings.agents.aiProvider`, joined as the spec says |
| Access ends | A choice card with a `ComboBox` named `settings.agentDetail.ends`: `common.never`, the current end date (when one is set, as a date in the user's format), `settings.agentDetail.ends.thirty`, `settings.agentDetail.ends.ninety` | 30 and 90 days count from now. The name, journals and end controls are disabled once access has ended |
| Last used, Added | Value cards: `settings.agentDetail.lastUsed` (relative time or `common.never`, B34) and `settings.agentDetail.added` (the date) | |
| Recent activity | A navigation card `settings.agentDetail.activity` to the sub-page below | |
| Revoke access / Remove | An action card with a real `Button` (the card is not clickable on its own): `common.revokeAccess`, or `settings.agentDetail.remove` once access has ended; while working a small indeterminate `ProgressBar` with `settings.agentDetail.revoking` or `settings.agentDetail.removing`; an `InfoBar` (Error) for the failure | |

**Saving.** Changes to the name, journals and end date save without a button; journal and end changes save half a second after the last change (a `DispatcherTimer` that restarts). Switching to Selected journals starts with none chosen and saves only once one is chosen; the previous access stays until then (open-questions A28). Changes made on another device: the latest settings are shown with `settings.agentDetail.error.changedElsewhere`; a failed save shows the saved settings again with `settings.agentDetail.error.saveFailed`; failures are `InfoBar`s (Error) announced when they open.

**Revoke confirmation.** `ContentDialog`: `Title` `common.revokeAccessFor`, content `settings.agentDetail.revoke.message`, Primary `common.revokeAccess`, Close `common.cancel`, no default button. Remove (ended access) does not ask. On success a notification announces `settings.agentDetail.revokedAnnouncement` (`ImportantMostRecent`), the page goes back to Agent access and focus lands on the next agent card, or on the Connect group when none remain. A failure: `common.couldntRevokeAccess` or `settings.agentDetail.error.removeFailed`.

### Recent activity page

Breadcrumb "Settings > Agent access > {name} > Recent activity" (`settings.agentDetail.activity`). A `ListView` of rows: the tool (`settings.agentDetail.tool.search`, `settings.agentDetail.tool.read`, `settings.agentDetail.tool.list`, `settings.agentDetail.tool.other`) and its date and time in the user's format. Otherwise `settings.agentDetail.activity.empty`, an `InfoBar` (Error) `settings.agentDetail.activity.failed`, or a busy row with `settings.agents.loading`. Footer `settings.agentDetail.activity.footer`.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Cards in the column; the journals list full width under its radio group | Mac sheet 480 × 560 points |
| Small and text size 200% or more | Controls under their labels; the breadcrumb collapses to its last item with an ellipsis menu | iPhone pushed pane |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `rename-agent` | Text box | `Enter` | Access not ended |
| `change-agent-journals` | Radio buttons and check boxes | — | Access not ended; Selected journals with none chosen is not saved |
| `change-agent-expiry` | Combo box | — | Access not ended |
| `revoke-agent` | Action card | — | Not while revoking |
| `agent-detail-done` | Not offered | — | A page: Back leaves it |

## Copy differences

Sentence case applies ("Recent activity", "Access ends", "Last used", "Searched entries", "In 30 days", "All journals", "Selected journals", "Revoke access"). Beyond that: relative times for Last used and Added are built from the new strings of B34. No other differences.

## Accessibility

- The page is Main with the breadcrumb as its heading. The last chosen journal's check box explains why it cannot be turned off through its help text. Status lines are read when their bar opens.
- Every change and error is announced as the spec lists; saves are quiet. Narrator reads the combo box as "Access ends, Never".
- Focus: entering the page puts focus on the name box; going back returns it to the agent's card; after a revoke it lands on the next card.
- Keyboard: Tab through name, choice group, boxes, end date, activity, revoke; arrow keys in the radio group; Space toggles a box.

## Different by design

- **A page with a breadcrumb**, not a Mac sheet with Done or a pushed pane.
- **Check boxes** where Apple has switches in a list: the Windows idiom for selecting several items; the "all journals" reminder is a set of checked, disabled boxes.
- **The activity list is a page**, not a push inside a sheet.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B34 (relative times).
