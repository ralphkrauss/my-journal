---
id: allow-agent
title: Allow Access (agent request)
features: [agent-requests]
sources:
  - apps/apple/JournalApp/Views/ServerAgentsView.swift
  - apps/apple/JournalApp/Model/ServerAgentsController.swift
  - docs/design/agent-access-simplified.md
---

# Allow Access

## Purpose

Shows who is asking to read the journals and where access will go, asks for the number shown on the agent's sign-in page, and the journals to share. Flow: `flows/allow-agent`.

## Entry points

- Settings ▸ Agent Access ▸ a request row.

## Content

A sheet titled `settings.allowAgent.title` ("Allow Access"). On the computer before macOS 26 a heading row repeats it.

- **Loading:** busy row `settings.agents.loading`.
- **Couldn't load:** `common.couldntReachHost` ("Couldn’t reach {host}. Check your connection and try again.") in red.
- **Request:**
  1. One element:
     - heading: `settings.allowAgent.wants` ("{name} wants to read your journals."), or for a reconnect `settings.allowAgent.wantsReconnect` ("{agent} wants to reconnect.");
     - `settings.allowAgent.returns` ("Returns to {host}") or, when the agent returns to an app on the computer that opened the page, `settings.allowAgent.returnsLocal` ("Returns to {host}, an app on the computer that opened the page");
     - secondary: `settings.allowAgent.identified` ("Identified as {identity}") when the request is identified and doesn't return to this computer; `settings.allowAgent.cantConfirm` ("My Journal can’t confirm which app this is.") when identified but returning to this computer;
     - secondary: `settings.allowAgent.limit` ("You can have up to 20 agents. Revoke one to allow another.") at the limit, otherwise `settings.allowAgent.onlyIfYou` ("Only allow access if you just connected from your agent.").
  2. Section `settings.allowAgent.number.header` ("Number"): a field `settings.allowAgent.number.field` ("Number Shown on the Page"; on phone/tablet as its placeholder, on the computer as its label), number pad, at most two digits (anything else is dropped). After two digits the keyboard closes.
  3. **New agent:** the journals choice (below). **Reconnect:** section `common.journals` ("Journals") showing the agent's journals as text, footer `settings.agents.readOnly`.
  4. An error, in red, when there is one.
- Toolbar: cancel button `settings.allowAgent.dontAllow` ("Don’t Allow"), disabled while allowing; primary `settings.allowAgent.allow` ("Allow"), replaced by an indicator while allowing.

### The journals choice (shared with the agent detail)

Section `common.journals` with an unlabelled single choice (accessibility label "Journals"): `settings.agents.allJournals` ("All Journals") or `settings.agents.selectedJournals` ("Selected Journals"). Nothing is chosen at first; until then the footer below shows under this section.
- **All Journals:** a section listing every journal with a switch shown on and disabled (a reminder of what's included).
- **Selected Journals:** a section listing every journal with a switch. When the agent's choice includes journals not on this device: `settings.agents.unknownJournals` ("{count} journals that aren’t on this device", plural).
- Footer: `settings.agents.includesLater` ("Includes journals you create later. ") for All Journals, then `settings.agents.readOnly` ("{name} can search and read entries in these journals but can’t change anything."), then `settings.agents.aiProvider` (" It may send what it reads to its AI provider.").

## Actions

| Action | Command | Enabled | Result |
| --- | --- | --- | --- |
| Allow | `allow-agent` | Request loaded, two digits, not at the limit, not busy; for a new agent: All Journals, or Selected Journals with at least one journal on this device | Allows; announces `settings.allowAgent.allowedAnnouncement` ("Access allowed."); closes. |
| Don’t Allow | `decline-agent` | Not while allowing | Declines; announces `settings.allowAgent.declinedAnnouncement` ("Request declined."); closes. |

Return in the number field allows (when enabled); Escape is Don’t Allow on the computer. The sheet can't be swiped away.

## States

- **Numbers don't match:** alert `settings.allowAgent.mismatch.title` ("Numbers Don’t Match"), `settings.allowAgent.mismatch.message`, `common.ok` closes the sheet. The request is declined by the server.
- **Request ended (expired, replaced or already answered):** alert `settings.allowAgent.ended.title` ("Request Ended"), `settings.allowAgent.ended.message`, `common.ok` closes.
- **Errors under the form:** `settings.allowAgent.limit` (limit reached on the server), `settings.allowAgent.error.tooManyAttempts` ("Too many attempts. Try again in a minute."), `common.couldntReachHost`, `settings.allowAgent.error.failed` ("Couldn’t allow access. Try again."). Each is announced.
- **Locked:** closes.

## Rules

- See `flows/allow-agent`.

## Accessibility

- The request's details are one element, read in order.
- The number field has a label even where it shows as a placeholder.

## Platform notes (Apple)

- Mac: a sheet of about 480 × 540 points.

## Open questions

- None.
