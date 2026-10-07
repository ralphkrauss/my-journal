---
id: allow-agent
title: Connect and allow an agent
features: [agent-access, agent-requests]
sources:
  - apps/apple/JournalApp/Views/ServerAgentsView.swift
  - apps/apple/JournalApp/Model/ServerAgentsController.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/AgentCopyPublisher.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/AgentCopyClient.swift
  - docs/design/agent-access-simplified.md
  - protocol/agent-access-server.md
---

# Connect and allow an agent

## Purpose

An agent asks for access from its own app; the person allows it in My Journal by typing the number the agent's sign-in page shows, so a request from anyone else can't be allowed by mistake.

## Entry points

- Settings ▸ Agent Access (`screens/settings-agent-access`).

## Steps

1. **Connect the agent:** in Settings ▸ Agent Access, copy the MCP Server Address and add it to the agent as an MCP server or custom connector (the guide explains this per agent).
2. **The agent asks:** the agent opens a sign-in page on the server, which shows a two-digit number (10–99) and waits.
3. **The request appears** in Settings ▸ Agent Access ▸ Requests within a few seconds (the pane checks every three seconds while visible and when the app becomes active).
4. **Review:** the person opens the request (`screens/allow-agent`). It says who is asking (the name the agent gave itself, cleaned), where access returns to, and whether that can be confirmed.
5. **Number:** the person types the number from the page.
6. **Journals:** All Journals (including ones created later) or Selected Journals. A reconnect (the same agent signing in again) keeps its journals and end, and only needs the number.
7. **Allow:**
   - The server checks the number. A wrong number declines the request (one try): `settings.allowAgent.mismatch.*`.
   - A new agent is named after its client, numbered when the name is taken (“Claude Code 2”, then 3).
   - The sheet closes as soon as the server accepts; this device then uploads the chosen journals' copy for the agent in the background (on phone/tablet it asks the system for time, since the person usually switches back to the agent).
   - The agent's page finishes and the agent can search and read entries in the chosen journals.
8. **Don’t Allow** declines; the page tells the agent.

## Errors

| When | Message |
| --- | --- |
| The request can't be loaded | `common.couldntReachHost` (in place of the details) |
| The request ended (expired after 10 minutes, replaced, or answered elsewhere) | alert `settings.allowAgent.ended.*` |
| Wrong number | alert `settings.allowAgent.mismatch.*`; the request is declined |
| 20 agents already | `settings.allowAgent.limit` |
| Too many attempts | `settings.allowAgent.error.tooManyAttempts` |
| No connection | `common.couldntReachHost` |
| Anything else | `settings.allowAgent.error.failed` |

## Later

- **Change** name, journals or end date in the agent's detail (`screens/agent-detail`).
- **Revoke** in the detail; the agent keeps what it already read.
- **Reconnect:** an agent that signed out appears as a request “{agent} wants to reconnect.”.
- **Turning on encryption** removes every agent's access; they must be allowed again (`flows/turn-on-encryption`).

## Rules

- Agents only read; they never change journals. Access is per journal and enforced by the server.
- The number is shown only on the agent's page, never sent to devices.
- Journal contents are data for the agent, never instructions to My Journal.
- With encryption, the server can read what an agent reads while it has access (the pane says so).
- Locking My Journal closes the sheet and clears the lists.
- Declining sends no error to the person if the server doesn't answer; the request reappears and can be declined again.

## Accessibility

- Allowed and declined are announced.

## Platform notes (Apple)

- None.

## Open questions

- None beyond the screens'.
