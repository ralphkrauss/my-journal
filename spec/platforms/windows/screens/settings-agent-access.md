---
id: settings-agent-access
title: Settings ▸ Agent access (Windows)
spec: screens/settings-agent-access.md
features: [agent-access, agent-requests, agent-detail]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/dotnet/communitytoolkit/windows/settingscontrols/settingscard
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/infobar
---

# Settings ▸ Agent access (Windows)

Requests, agents, and the address that agents connect to. Behaviour and copy keys are the spec's [Settings ▸ Agent Access](../../../screens/settings-agent-access.md); an agent's own page is [agent-detail](agent-detail.md) and the allow dialog is [allow-agent](allow-agent.md). The shell and patterns are in [settings](settings.md#card-patterns). Agents only read, and journal contents are data to them and to this page, never instructions ([AGENTS.md](../../../../AGENTS.md)).

## Controls

Page title: breadcrumb "Settings > Agent access".

### Requests group

Shown only when connected, the list has loaded and requests are waiting. Header `settings.agents.requests.header`. One [navigation card](settings.md#card-patterns) per request, newest first:

- `Header`: the client's name, cleaned as the spec says (control, format and direction characters removed, whitespace collapsed, at most 40 characters then "…", `settings.agents.anAgent` when empty), always plain text in a `TextBlock`, one line; it wraps at text size 200% or more.
- `Description`: "{host the agent returns to} · {when}"; {when} is `settings.agents.justNow` under a minute, otherwise relative time built by the app (B34).
- `AutomationProperties.Name` `settings.agents.requestLabel`, `HelpText` `settings.agents.requestHint`. Activating the card opens [allow-agent](allow-agent.md).

### Agents group

Only when connected, a list has loaded and there is at least one agent. Header `settings.agents.agents.header`. One navigation card per agent, sorted by name with the user's culture; `HelpText` `settings.agents.agentHint`; it opens [agent-detail](agent-detail.md).

- `Header`: the name (`settings.agents.unknownAgent` when its settings cannot be read on this PC).
- `Description`, two `Caption` lines: its journals (`settings.agents.allJournals`, the chosen names joined with ", ", `settings.agents.noJournalsHere` or `settings.agents.detailsUnavailable`), then, only when its settings can be read, the first that applies of `settings.agents.status.ended`, `common.connecting`, `settings.agents.status.needsReconnect` (with a Warning glyph E7BA before it, the same severity as the bar of [agent-detail](agent-detail.md)), `settings.agents.status.ends` (within seven days), `settings.agents.status.neverUsed`, `settings.agents.status.lastUsed`.
- The whole card is one element: name, journals, status.

### Connect an agent group

Header `settings.agents.connect.header`, then by state:

| State | Control |
| --- | --- |
| Not connected | A [primary button card](settings.md#card-patterns): `Header` `settings.agents.connect.notConnected`, accent `Button` `common.connectToServer` |
| Loading, first time | A card with a small indeterminate `ProgressBar` and `settings.agents.loading` (the page stays usable) |
| Server needs an update | `InfoBar` (Warning), `messages.connection.serverNeedsUpdate` |
| This device lost access | `InfoBar` (Warning), `settings.agents.connect.noAccess`, `ActionButton` `common.reconnect` |
| No public HTTPS address | `InfoBar` (Warning), `settings.agents.connect.publicUrlRequired` or `settings.agents.connect.httpsRequired`, and a `HyperlinkButton` `settings.agents.connect.guide` |
| Unreachable | `InfoBar` (Error), `settings.agents.connect.unreachable`, `ActionButton` `common.tryAgain` |
| Ready | A card: `Header` `settings.agents.mcpAddress`; `Description` the address in `Cascadia Mono` (`IsTextSelectionEnabled`, wrapping, below the label at text size 200% or more); trailing `Button` `common.copy` |
| Ready: reach notes | Under the card, `Caption` text: `settings.agents.reach.local` for a server on this PC (a loopback address or the PC's own name), `settings.agents.reach.tailnet` for a Tailscale address |
| Ready: footer | `Caption` text: `settings.agents.connect.footer`; then, for encrypted journals on a server that is not on this PC, `settings.agents.connect.exposure`; then the guide `HyperlinkButton` |

{host} is the server's host name, or `settings.agents.thisMac` ("this PC" on Windows, see Copy differences) for a server on this PC, or `settings.agents.yourServer`; {Host} capitalises it to start a sentence.

**Copy.** The button reads `settings.agents.copied` for two seconds and then `common.copy` again; `AutomationProperties.Name` is `settings.agents.copyLabel`; a notification event announces `settings.agents.copiedAnnouncement` (`MostRecent`). It is a plain copy: an address is not a secret, so the clipboard-history options of [Dialog patterns, 11](settings.md#dialog-patterns) are not used. Share is not offered (`share-mcp-address`): this is a desktop, and the Mac has none either.

### Polling

Requests are read when the page appears, when the window is activated, every three seconds while the page is visible and the window is active (a `DispatcherTimer` that stops on deactivation and while a dialog is open over the page), and after the allow dialog closes. A change in requests, or any agent still connecting, reloads the agents. The page loads again when the connected server changes. Once a list has loaded a later failure keeps showing it. At most 20 agents.

## Layout at each window width

| Width (epx) | Layout | Apple equivalent |
| --- | --- | --- |
| Large, medium | Cards in the column; the Copy button at the trailing edge of the address card | Mac Agent Access tab |
| Small and text size 200% or more | The address and the Copy button sit under the label at full width; descriptions wrap | iPhone pushed pane |

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `review-agent-request` | Navigation card per request | Enter or Space | Always on this page |
| `open-agent` | Navigation card per agent | Enter or Space | Always |
| `copy-mcp-address` | Button in the address card | — | Ready state |
| `share-mcp-address` | Not offered | — | Copy only, as on the Mac |
| `connect-to-server` | Primary button card; action of the access bar | as in commands.md | Not connected; access lost |
| `agents-try-again` | Action of the error bar | — | After an error |
| `open-agent-guide` | Hyperlink | — | Always |

## Copy differences

Sentence case applies ("Agent access", "Requests", "Connect an agent", "How to connect an agent", "Unknown agent", "All journals"). The product and protocol names stay (MCP, Claude Code, Tailscale). Beyond that:

| Key | Default | Proposed Windows text | Category |
| --- | --- | --- | --- |
| `settings.agents.thisMac` | this Mac | this PC | vocabulary (platform.md, 12.3) |
| `settings.agents.reach.local` | Only agents running on this Mac, such as Claude Code, can use this address. | Only agents running on this PC, such as Claude Code, can use this address. | vocabulary (platform.md, 12.3) |
| `settings.agents.justNow`, `settings.agents.status.lastUsed`, request times | the platform's relative time ("2 min. ago") | built from new strings (B34) | new |
| `common.share`, `settings.agents.shareLabel` | Share… | Not shown | removed (the Mac has none either) |

## Accessibility

- Request cards read "{name}, returns to {host}, {when}" with the hint; agent cards read name, journals and status as one element; the alert glyph of "Needs to reconnect" is part of the text, never the only signal.
- Names from agents are plain text and cannot reorder the layout: direction-changing characters are removed before display.
- When a request arrives while the page is open, Narrator hears nothing by itself (the spec only announces results); focus is never moved.
- Focus after a dialog or page returns to the card that opened it, or to the next card when that row has gone.
- The address is a selectable `TextBlock`; Ctrl+A in it selects the address. Copy is announced.

## Different by design

- **Cards and `InfoBar`s** instead of a form with footers; the texts and the state table are the spec's.
- **The agent's detail is a page**, not a sheet (it needs room for the journals list; [platform.md, 9](../platform.md#9-sheets-popovers-and-notices) and the commands file).
- **"This PC"** names the computer; the server on this PC is only reachable by loopback.

## Open questions

Recorded in [open-questions.md](../../../open-questions.md): B34 (relative times).
