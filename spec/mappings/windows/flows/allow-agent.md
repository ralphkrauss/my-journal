---
id: allow-agent
title: Connect and allow an agent (Windows)
spec: flows/allow-agent.md
features: [agent-access, agent-requests]
status: reviewed
sources:
  - https://learn.microsoft.com/en-us/windows/apps/develop/ui/controls/dialogs-and-flyouts/dialogs
---

# Connect and allow an agent (Windows)

An agent asks for access from its own app; the person allows it in My Journal by typing the number the agent's sign-in page shows, so a request from anyone else cannot be allowed by mistake. Steps, errors and rules are the spec's [flow](../../../flows/allow-agent.md); the pages are [settings-agent-access](../screens/settings-agent-access.md), [allow-agent (dialog)](../screens/allow-agent.md) and [agent-detail](../screens/agent-detail.md). Agents only read; journal contents are data to them and to My Journal, never instructions ([AGENTS.md](../../../../AGENTS.md)).

## Controls

| Spec step | Windows |
| --- | --- |
| 1 Connect the agent | The person copies the MCP server address with the Copy button (a plain copy; no clipboard-history options, because an address is not a secret) and adds it to the agent. On Windows the agent is often a desktop app on the same PC (Claude Desktop, Claude Code, another MCP client) or a web agent in a browser; `settings.agents.reach.local` and `settings.agents.reach.tailnet` explain what can reach the address. A server on this PC is reached by a loopback address, and the browser page that shows the number opens in the person's default browser on this PC |
| 2 The agent asks | The agent's sign-in page, on the server, shows a two-digit number (10 to 99) and waits. The number is shown only there, never sent to devices |
| 3 The request appears | In Settings > Agent access > Requests within a few seconds: the page polls every three seconds while visible and the window is active, and when the window is activated, and after the allow dialog closes. When the window is not the one in front (the person is in the agent's app) the request waits until the window is activated; nothing notifies the person, because the app has no notifications in version 1 ([platform.md, 19](../platform.md#19-single-instance-and-activation)) |
| 4 to 6 Review, number, journals | The allow dialog; digits only; All journals (including ones created later) or Selected journals; a reconnect keeps its journals and end date and needs only the number |
| 7 Allow | The server checks the number; a wrong number declines the request, one try (`settings.allowAgent.mismatch.title`, `settings.allowAgent.mismatch.message`). A new agent is named after its client, numbered when the name is taken. The dialog closes as soon as the server accepts, then this PC uploads the chosen journals' copy for the agent in the background |
| 8 Don't allow | Declines; the agent's page tells the agent. No error is shown if the server does not answer; the request reappears and can be declined again |

### Windows adds

- **The background upload lives and dies with the window.** Windows has no background sync when the app is closed ([platform.md, 30](../platform.md#30-sync-lifecycle-and-power)). If the window is closed before the upload finishes, the agent shows as still connecting (`common.connecting`, `settings.agentDetail.status.connecting`) and the upload resumes the next time the app opens. The app holds the window close for a few seconds to finish a short upload, as it does for saves, but never for a long one. The person can leave the window open until the agent's page finishes.
- **Reconnects and revokes** work as in the spec: an agent that signed out appears as a request "{agent} wants to reconnect." (`settings.allowAgent.wantsReconnect`); revoke is in the agent's page and the agent keeps what it already read; turning on encryption removes every agent's access ([turn-on-encryption](turn-on-encryption.md)).
- **No agent state is stored in a settings file of its own**: the agent copy's keys, like the library's, go through `ISecretStore` ([platform.md, 14](../platform.md#14-secure-storage)).
- **Locking** closes the dialog and clears the lists; they load again after unlocking.
- **Errors** are the spec's table: `common.couldntReachHost`, `settings.allowAgent.ended.title` with `settings.allowAgent.ended.message`, `settings.allowAgent.mismatch.title` with `settings.allowAgent.mismatch.message`, `settings.allowAgent.limit`, `settings.allowAgent.error.tooManyAttempts`, `settings.allowAgent.error.failed`.

## Layout at each window width

Not applicable: the flow does not change with width; each page is described in its own file.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `copy-mcp-address` | Button in Settings > Agent access | — | The ready state |
| `review-agent-request` | Request card | `Enter` on the focused card | Always on the page |
| `allow-agent`, `decline-agent` | Dialog buttons | `Enter`, `Esc` | As in the screen file |
| `change-agent-journals`, `change-agent-expiry`, `rename-agent`, `revoke-agent` | The agent's page | — | As in [agent-detail](../screens/agent-detail.md) |

## Copy differences

None beyond the page files (sentence case; "this PC").

## Accessibility

Allowed and declined are announced as notification events (`settings.allowAgent.allowedAnnouncement`, `settings.allowAgent.declinedAnnouncement`, `ImportantMostRecent`); the rest is in the page files.

## Different by design

- **No notification when a request arrives**, because the Windows app shows no notifications in version 1; the agent's own page tells the person to return to My Journal.
- **The upload stops with the window**, because a Windows app does not run when closed.

## Open questions

None.
