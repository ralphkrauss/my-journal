---
id: allow-agent
title: Allow access, agent request (Windows)
spec: screens/allow-agent.md
features: [agent-requests]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Allow access, agent request (Windows)

The dialog that shows who is asking to read the journals, asks for the number on the agent's sign-in page and for the journals to share. Behaviour and copy keys are the spec's [Allow Access](../../../screens/allow-agent.md); the whole task is the [allow-agent flow](../flows/allow-agent.md). The dialog patterns are in [settings](settings.md#dialog-patterns).

## Controls

A `ContentDialog`, `Title` `settings.allowAgent.title`, default width, content scrolling.

| Spec element | Control | Notes |
| --- | --- | --- |
| Loading | A `ProgressRing` and `settings.agents.loading` | |
| Couldn't load | An `InfoBar` (Error) `common.couldntReachHost` | |
| Request details | One element: heading `settings.allowAgent.wants`, or `settings.allowAgent.wantsReconnect`; `settings.allowAgent.returns` or `settings.allowAgent.returnsLocal`; secondary text `settings.allowAgent.identified` (when identified and not returning to this PC) or `settings.allowAgent.cantConfirm` (identified but returning to this PC); secondary text `settings.allowAgent.limit` at the limit, otherwise `settings.allowAgent.onlyIfYou` | Names and identities are plain text, cleaned as in [settings-agent-access](settings-agent-access.md). The block has `AutomationProperties.Name` joining its lines, and its children are hidden from the tree, so Narrator reads it as one element in order |
| Number | `TextBox`, `Header` `settings.allowAgent.number.field`, group heading `settings.allowAgent.number.header`, `InputScope` Number, `MaxLength` 2; a `BeforeTextChanging` handler drops anything that is not a digit; focused on open | At most two digits. No keyboard to close on a PC |
| Journals (new agent) | The journals choice of [agent-detail](agent-detail.md): `RadioButtons` `settings.agents.allJournals` and `settings.agents.selectedJournals` with nothing chosen at first, and check boxes; the footer composed from `settings.agents.includesLater`, `settings.agents.readOnly` and `settings.agents.aiProvider`; until a choice is made the footer under the group is the one the spec names | |
| Journals (reconnect) | Heading `common.journals` and the agent's journals as text; footer `settings.agents.readOnly` | |
| Errors under the form | An `InfoBar` (Error), announced: `settings.allowAgent.limit`, `settings.allowAgent.error.tooManyAttempts`, `common.couldntReachHost`, `settings.allowAgent.error.failed` | |
| Buttons | Primary `settings.allowAgent.allow`, default; Close `settings.allowAgent.dontAllow` (Esc) | While allowing: a `ProgressRing` replaces the Primary label, Close is disabled, the dialog cannot be dismissed |

The dialog cannot be dismissed any other way. Enter in the number field presses Allow when it is enabled.

**Alerts become content.** The spec's two alerts are not second dialogs. Numbers don't match: the dialog's content is replaced with `settings.allowAgent.mismatch.message`, the title becomes `settings.allowAgent.mismatch.title`, and the only button is Close `common.ok`, which closes the dialog (the request was declined by the server). Request ended: the same with `settings.allowAgent.ended.title` and `settings.allowAgent.ended.message`.

**Results.** Allowed: `settings.allowAgent.allowedAnnouncement` is announced (a notification event, `ImportantMostRecent`) and the dialog closes as soon as the server accepts; the upload of the chosen journals' copy continues in the app in the background ([flows/allow-agent](../flows/allow-agent.md)). Declined: `settings.allowAgent.declinedAnnouncement`. Locked: the dialog closes.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Dialog 548 epx wide | Mac sheet 480 × 540 points |
| Small and text size 200% or more | The dialog fills the width and scrolls; the number field stays full width | iPhone sheet |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `allow-agent` | Primary button | `Enter` in the number field | Request loaded, two digits, not at the limit, not busy; for a new agent: All journals, or Selected journals with at least one journal on this PC |
| `decline-agent` | Close button | `Esc` | Not while allowing |

## Copy differences

Sentence case applies ("Allow access", "Don’t allow", "Number shown on the page", "Numbers don’t match", "Request ended", "All journals"). `settings.allowAgent.returnsLocal` says "the computer that opened the page"; it is correct on Windows ("computer" is neutral). No other differences.

## Accessibility

- The request details are one element. The number field has a visible header; its error is its help text. Results and errors are announced; the two close announcements are notification events.
- Focus starts in the number field; after the mismatch or ended content appears focus moves to its Close button; closing returns focus to the request's card, or to the next one.
- The check boxes and radio group are standard controls; Narrator reads the group name "Journals".

## Different by design

- **Alerts are replaced content,** not alerts over a sheet ([Dialog patterns, 1](settings.md#dialog-patterns)).
- **No "swipe away" rule**: a dialog has no swipe; it cannot be dismissed with Esc while allowing, which is the same effect.
- **Digits only is enforced as the person types** on a PC, since a number pad does not exist.

## Open questions

None.
