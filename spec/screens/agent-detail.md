---
id: agent-detail
title: Agent detail and Recent Activity
features: [agent-detail]
sources:
  - apps/apple/JournalApp/Views/ServerAgentsView.swift
  - apps/apple/JournalApp/Model/ServerAgentsController.swift
  - docs/design/agent-access-simplified.md
---

# Agent detail

## Purpose

One agent: its name, its journals, when its access ends, when it was used, what tools it used recently, and revoking it. Changes apply at once, quietly.

## Entry points

- Settings ▸ Agent Access ▸ an agent row.

## Content

Titled with the agent's name (on the computer, a sheet with `common.done`; before macOS 26 a heading row repeats the name).

- **Revoked** (no longer listed): `settings.agentDetail.revoked` ("This agent’s access was revoked.").
- **Otherwise**, in order:
  1. A status line when one applies: `settings.agentDetail.status.ended` ("Access ended {date}."), `settings.agentDetail.status.connecting` ("Waiting for {client} to finish connecting."), `settings.agentDetail.status.reconnect` ("Connect again from {client} to reconnect it.").
  2. When its settings can't be read on this device: `settings.agents.detailsUnavailable` ("Details aren’t available on this device.") in secondary text, and no controls 3–5.
  3. A field `common.name` ("Name"; a section header on phone/tablet, the field's label on the computer). Saved on Return or when the field loses focus.
  4. The journals choice (as in `screens/allow-agent`), where the last chosen journal can't be switched off (hint `settings.agentDetail.lastJournalHint` "To stop all access, revoke it.").
  5. A pop-up `settings.agentDetail.ends` ("Access Ends"): `common.never` ("Never"), the current end date (when one is set), `settings.agentDetail.ends.thirty` ("In 30 Days"), `settings.agentDetail.ends.ninety` ("In 90 Days").
     Controls 3–5 are disabled once access has ended.
  6. Rows: `settings.agentDetail.lastUsed` ("Last Used") → relative time or `common.never` ("Never"); `settings.agentDetail.added` ("Added") → date; `settings.agentDetail.activity` ("Recent Activity") → pushes Recent Activity.
  7. A destructive button: `common.revokeAccess` ("Revoke Access"), or `settings.agentDetail.remove` ("Remove") once access has ended; while working, a busy row `settings.agentDetail.revoking` ("Revoking…") or `settings.agentDetail.removing` ("Removing…"); an error in red.

### Revoke confirmation

Title `common.revokeAccessFor` ("Revoke access for {name}?"), message `settings.agentDetail.revoke.message` ("{name} won’t be able to read your journals anymore. It keeps anything it already read."), buttons destructive `common.revokeAccess` and `common.cancel`. Remove (ended) doesn't ask.

### Recent Activity

Titled `settings.agentDetail.activity`. One row per recent tool use: the tool (`settings.agentDetail.tool.search` "Searched Entries", `settings.agentDetail.tool.read` "Read an Entry", `settings.agentDetail.tool.list` "Listed Journals", `settings.agentDetail.tool.other` "Used a Tool") and its date and time. Otherwise `settings.agentDetail.activity.empty` ("No activity yet."), `settings.agentDetail.activity.failed` ("Couldn’t load activity."), or busy `settings.agents.loading`. Footer `settings.agentDetail.activity.footer`.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Change name | `rename-agent` | 1–80 characters after trimming; anything else reverts to the saved name. |
| Change journals | `change-agent-journals` | Saved half a second after the last change. Selected Journals with none chosen isn't saved. |
| Access Ends | `change-agent-expiry` | Saved half a second after the change. 30 and 90 days count from now. |
| Revoke Access / Remove | `revoke-agent` | Revokes; announces `settings.agentDetail.revokedAnnouncement` ("Access revoked."); closes. |
| Done (computer) | `agent-detail-done` | Closes; disabled while revoking. |

## States

- **Changed on another device:** the latest settings are shown with `settings.agentDetail.error.changedElsewhere`.
- **Couldn't save:** the saved settings are shown again with `settings.agentDetail.error.saveFailed`.
- **Couldn't revoke / remove:** `common.couldntRevokeAccess` / `settings.agentDetail.error.removeFailed`.
- All errors are announced.
- **Locked:** closes.

## Rules

- Changes save without a Save button.
- Narrowing access removes the journals' copies from the agent's view on the server; switching from All Journals to Selected Journals starts with none chosen and saves only once one is chosen.
- An agent whose settings can't be read on this device (made by a newer version) can still be revoked.

## Accessibility

- The last chosen journal's switch explains why it can't be turned off.

## Platform notes (Apple)

- Mac: a sheet; iPhone/iPad: pushed in the Settings navigation.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
