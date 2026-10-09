---
id: settings-agent-access
title: Settings ▸ Agent Access
features: [agent-access, agent-requests, agent-detail]
sources:
  - apps/apple/JournalApp/Views/ServerAgentsView.swift
  - apps/apple/JournalApp/Model/ServerAgentsController.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/AgentCopy.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/AgentCopyPublisher.swift
  - docs/design/agent-access-simplified.md
  - docs/design/agent-access-server.md
  - docs/design/client-only-mac-lists-markdown-2026-10-05.md
  - protocol/agent-access-server.md
---

# Settings ▸ Agent Access

## Purpose

Lets AI agents (such as Claude or ChatGPT) read chosen journals through the sync server, read-only, and lets the person see, change and revoke that access. Agents connect to the server's MCP address; each request appears here and is allowed with the number its page shows (`flows/allow-agent`).

## Entry points

- Settings ▸ Agent Access (`screens/settings`).

## Content

In order:

### 1. Requests (only when connected, the list loaded, and requests are waiting)

Header `settings.agents.requests.header` ("Requests"). One row per waiting request, newest first, each a button with a trailing chevron:
- the client's name (cleaned, see Rules), one line (wraps at accessibility sizes);
- secondary: “{host the agent returns to} · {when}”, where {when} is `settings.agents.justNow` ("just now") under a minute, otherwise the platform's abbreviated relative time (“2 min. ago”).
- Accessibility label `settings.agents.requestLabel` ("{name}, returns to {host}, {when}"), hint `settings.agents.requestHint` ("Reviews the request.").
Choosing a row opens Allow Access (`screens/allow-agent`). A request being declined (Don’t Allow, not yet answered by the server) is left out of the list, even when a refresh still lists it. Footer of the section, only after a decline could not be sent: `settings.agents.requests.declineFailed` ("Couldn’t decline the request from {name}. Open it and choose Don’t Allow to try again."), in the pane's ordinary secondary text (the words and the announcement carry it, not colour), read after the rows and announced once when it appears; the request's row is back in the list. {name} is the client name cleaned as for the row; it is the agent's own text, shown as data and never as an instruction. It goes when a later decline succeeds, the person opens that request again, a reload lists the request no more, or the app locks.

### 2. Agents (only when connected and a list has loaded, with at least one agent)

Header `settings.agents.agents.header` ("Agents"). One row per agent, sorted by name, opening the agent's detail (`screens/agent-detail`; pushed on phone/tablet, a sheet on the computer), hint `settings.agents.agentHint` ("Shows details."):
- the agent's name (`settings.agents.unknownAgent` "Unknown Agent" when its settings can't be read on this device);
- secondary: its journals: `settings.agents.allJournals` ("All Journals"), the chosen journals' names joined with “, ”, `settings.agents.noJournalsHere` ("No journals on this device") when none of them are here, or `settings.agents.detailsUnavailable` when its settings can't be read;
- secondary (only when its settings can be read), the first that applies:
  - access ended: `settings.agents.status.ended` ("Access ended {date}");
  - still connecting: `common.connecting` ("Connecting…");
  - needs to reconnect: `settings.agents.status.needsReconnect` ("Needs to reconnect"), with an alert icon;
  - access ends within seven days: `settings.agents.status.ends` ("Access ends {date}");
  - never used: `settings.agents.status.neverUsed` ("Never used");
  - otherwise: `settings.agents.status.lastUsed` ("Last used {relative time}").

### 3. Connect an Agent

Header `settings.agents.connect.header` ("Connect an Agent"). Content by state:
- **Not connected to a server:** `settings.agents.connect.notConnected` ("To let agents read your journals, connect to a server.") and `common.connectToServer` ("Connect to a Server…").
- **Loading (first time):** busy row `settings.agents.loading` ("Loading…").
- **Server needs an update:** `settings.agents.connect.needsUpdate` ("{Host} needs an update before agents can connect.").
- **This device lost access:** `settings.agents.connect.noAccess` ("This device no longer has access to {host}.") and `common.reconnect` ("Reconnect…") → Reconnect (`flows/reconnect-to-server`).
- **The server has no public HTTPS address:** `settings.agents.connect.publicUrlRequired` ("Set your server’s public address before agents can connect.") when the server says a public address is required, otherwise `settings.agents.connect.httpsRequired` ("{Host} doesn’t know its HTTPS address. Set its public address before agents can connect."); plus the link `settings.agents.connect.guide` ("How to Connect an Agent").
- **Unreachable:** `settings.agents.connect.unreachable` ("Couldn’t reach {host}.") and `common.tryAgain`.
- **Ready:** a row labelled `settings.agents.mcpAddress` ("MCP Server Address") with the address in monospaced type (selectable; below the label at accessibility sizes); a button `common.copy` ("Copy", reading `settings.agents.copied` "Copied" for two seconds; accessibility label `settings.agents.copyLabel` "Copy MCP Server Address"); on phone/tablet also `common.share` ("Share…", accessibility label `settings.agents.shareLabel`). Under it, when reach is limited:
  - a server on this computer: `settings.agents.reach.local`;
  - a Tailscale address: `settings.agents.reach.tailnet`.
- Footer (ready only): `settings.agents.connect.footer`; then, for encrypted journals on a server that isn't on this computer, `settings.agents.connect.exposure` ("While an agent has access, anyone who controls {host} could read the journals it reads."); then the link `settings.agents.connect.guide`.

{host} is the server's host name, or `settings.agents.thisMac` ("this Mac") for a server on this computer, or `settings.agents.yourServer` ("your server") when unknown; {Host} capitalises it to start a sentence.

## Actions

| Action | Command | Result |
| --- | --- | --- |
| Review a request | `review-agent-request` | Opens Allow Access. |
| Open an agent | `open-agent` | Opens its detail. |
| Copy | `copy-mcp-address` | Copies the address; announces `settings.agents.copiedAnnouncement` ("Copied."). |
| Share… | `share-mcp-address` | The system share sheet with the address (phone/tablet). |
| Connect to a Server… | `connect-to-server` | Opens Connect to a Server. |
| Reconnect… | `sync-reconnect` | Opens Reconnect (this device lost access). |
| Try Again | `agents-try-again` | Loads again. |
| How to Connect an Agent | `open-agent-guide` | Opens `<repository>/blob/main/docs/guide/agent-access.md`. |

## States

- **Loading, unreachable, needs update, no access, address unavailable, ready:** as above. Once a list has loaded, a later failure keeps showing the agents.
- **Locked:** the list, requests and the decline message are cleared and sheets close.

## Rules

- Requests are read when the pane appears, when the app becomes active, every three seconds while the pane is visible and the app is active, and after Allow Access closes. A change in requests, or any agent still connecting, reloads the agents.
- The pane loads again when the connected server changes.
- Client names are cleaned: control, format and direction characters removed, whitespace collapsed to single spaces, one line, at most 40 characters (then “…”), `settings.agents.anAgent` ("An agent") when empty. They're always shown as plain text.
- Agents only ever read; they can't change anything. Access is enforced by the server for the chosen journals.
- At most 20 agents.

## Accessibility

- Request rows remain buttons and read who, where and when, with a hint.
- Agent rows read name, journals and status as one element.

## Platform notes (Apple)

- Mac: the agent detail opens as a sheet (about 480 × 560 points) with Done; iPhone and iPad push it.
- Share… exists only on iPhone and iPad, since the address is usually needed on a computer.

## Open questions

Open questions about this file are collected in [open-questions.md](../open-questions.md).
