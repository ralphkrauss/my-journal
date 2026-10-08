---
id: allow-agent
title: Connect and allow an agent (Apple)
spec: flows/allow-agent.md
features: [agent-access, agent-requests]
devices: [iphone, ipad, mac]
status: draft
sources:
  - apps/apple/JournalApp/Views/ServerAgentsView.swift
  - apps/apple/JournalApp/Model/ServerAgentsController.swift
  - apps/apple/JournalApp/Model/AppModel.swift
  - apps/apple/JournalApp/Model/SyncSchedule.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/AgentCopyPublisher.swift
  - apps/apple/Packages/JournalCore/Sources/JournalCore/AgentCopyClient.swift
  - docs/design/agent-access-simplified.md
  - protocol/agent-access-server.md
---

# Connect and allow an agent (Apple)

Implements [flows/allow-agent.md](../../../flows/allow-agent.md): an agent asks for access from its own app, and the person allows it here by typing the number the agent's sign-in page shows. The screens are [screens/settings-agent-access.md](../screens/settings-agent-access.md) (the pane and its Requests), [screens/allow-agent.md](../screens/allow-agent.md) (Allow Access, with the only screenshot of the flow, on the Mac) and [screens/agent-detail.md](../screens/agent-detail.md) (changing and revoking). This page records how the steps are wired in the Apple apps. Sync and background conventions: [platform.md](../platform.md#30-sync-lifecycle-and-background). The agent's own sign-in page is served by the sync server, not by the app; the app never sees the number except as the two digits the person types.

## Controls

Steps of the spec, with the control or code that does each. The state lives in `ServerAgentsController` (one per Settings view) over `AppModel.agentCopies` (an `AgentCopyPublisher`) and `AppModel.connectedClient()`.

1. **Connect the agent.** Settings ▸ Agent Access, Connect an Agent, `MCPAddressRow`: Copy (`PlainPasteboard.copy`) or Share… (`ShareLink`, iPhone and iPad), and a `Link` to the repository's agent-access guide. The address is the `mcpUrl` of the server's status (`client.status()`); with no HTTPS address the pane shows the "public address" texts instead and nothing can be copied. `AppModel.agentCopies` exists only while the library has a server connection (`AppModel.configureSync`).
2. **The agent asks.** Nothing happens in the app. The request exists on the server for 10 minutes (`AgentRequest.expiresAt`).
3. **The request appears.** `ServerAgentsPresentation` calls `controller.refreshRequests` when the pane appears, every 3 seconds while the pane is visible and the app is active, when the app becomes active (`scenePhase` on iPhone and iPad, `NSApplication.didBecomeActiveNotification` on the Mac) and after Allow Access closes. A new request id, or any agent still pending, reloads the agent list too, so an agent that signed out shows as needing to reconnect. The request is a row in the Requests section.
4. **Review.** The row sets `controller.reviewing`; `AllowAgentView` opens as a sheet and fetches the full request (`controller.request`). It shows the cleaned client name (`AgentDisplayName.clean`: control, format and direction characters removed, whitespace collapsed, one line, at most 40 characters), where it returns to and whether that was identified.
5. **Number.** A `TextField` limited to two ASCII digits (`AllowAgentView`).
6. **Journals.** `AgentJournalsSection`, or for a reconnect the agent's own journals as text (`controller.reconnectTarget`).
7. **Allow.** `controller.approve` or `controller.reconnect`:
   - `AgentCopyPublisher.approve` seals the agent's settings (name, client, journals, end, a random copy key) with the vault key, wraps the copy key with a random secret, and sends the number, grant id, sealed settings and wrapped key to the server. A wrong number comes back as `AgentCopyError.numberMismatch` and the server declines the request; the app then forgets it and shows the Numbers Don't Match alert.
   - The new agent is named after its client (`defaultName`: "Claude Code", then "Claude Code 2", "Claude Code 3").
   - The sheet closes when the server accepts. The first upload of the agent's copy (`AgentCopyPublisher.firstCopy`) continues in a task kept by the controller; approval lets the agent continue after 15 seconds even if the upload is still running, or earlier when it finishes (`agentRequestReady`). On iPhone and iPad the upload is wrapped in `UIApplication.beginBackgroundTask` (`UploadActivity`) because the person normally switches back to the agent's app; the Mac does not need it.
   - Afterwards the copy follows each successful sync: `AppModel.sync` calls `agentCopies.requestPublishing()` after every sync that succeeds, and a publishing request of the sync schedule does the same, so agents read what has synced, not unsaved edits.
   - A reconnect (`AgentCopyPublisher.reconnect`) keeps the agent's journals, end date and copy and only sends the number.
8. **Don't Allow.** `controller.decline` removes the request from the list and sends the decline in a detached task; failures are ignored, and the request reappears at the next poll if the server did not take it.

Later: changing, revoking and the agent's recent tool use are in [screens/agent-detail.md](../screens/agent-detail.md). Turning on encryption warns that agents lose access (`TurnOnEncryptionView`, a line naming the host) and they must be allowed again.

Errors map to the spec's table in `AllowAgentView.allow()`: `AgentCopyError.requestNotFound` (alert Request Ended), `numberMismatch` (alert), `limit`, `ServerRateLimited`, `URLError`, anything else. Locking the app cancels the sheet and `controller.clear()` empties the lists and cancels first-copy uploads.

## Layout

The flow has no layout of its own. The pane, the sheet and the detail adapt as described on the screen pages: iPhone pushes the pane, shows Allow Access as a full-height sheet and pushes the detail; iPad does the same inside the Settings card; the Mac shows the pane as a tab of the Settings window and Allow Access and the detail as sheets over it. Nothing about the flow changes with Dynamic Type.

## Commands and shortcuts

| Command | Placement | Shortcut | Enabled when |
| --- | --- | --- | --- |
| `copy-mcp-address` | Copy in Connect an Agent | None | Address shown |
| `share-mcp-address` | Share… in Connect an Agent, iPhone and iPad only | None | Address shown |
| `review-agent-request` | Request row | None | A request waits |
| `allow-agent` | Allow in Allow Access | Return in the number field | Two digits, a journal choice, under the limit |
| `decline-agent` | Don’t Allow in Allow Access | Escape (Mac) | Not while allowing |

Placement and shortcuts as in [commands.md](../commands.md). No flow-wide shortcut exists.

## Copy differences

None. The flow's text has no `mac` variants; the one structural difference (number field label versus prompt) is on [screens/allow-agent.md](../screens/allow-agent.md).

## Accessibility

- Allowed and declined are announced (`announceForAccessibility`, `UIAccessibility.post` on iOS and `NSAccessibility` announcements on the Mac), because the person has just switched from the agent's page and the sheet closes at once. Every error under the form is announced.
- The request row is a button with a label that reads the client, where it returns to and when; Allow Access reads the request as one element, in order.
- Copy announces "Copied." through the same function.

## Differences between iPhone, iPad and Mac

- Share… and the background upload time exist on iPhone and iPad only: the address is usually needed on a computer, and an iOS app that is switched away from is suspended unless it asks for time.
- The Mac refreshes requests on `NSApplication.didBecomeActiveNotification`; iPhone and iPad use `scenePhase`, because each is the activation signal of its platform.
- The Mac removes leftovers of the older local agent connections at launch (`LocalAgentCleanup`); no other device had them.
- Presentation: pushed screens on iPhone and iPad, tab and sheets on the Mac (see the screen pages).

## Screenshots

None for this page itself: the flow is a sequence across three screens and shares its id with the Allow Access screen, whose Mac capture is on [screens/allow-agent.md](../screens/allow-agent.md); the pane and detail captures are on [screens/settings-agent-access.md](../screens/settings-agent-access.md) and [screens/agent-detail.md](../screens/agent-detail.md). All are Mac only because an MCP agent client and a server are needed. The agent's sign-in page is part of the server and is not captured. This page stays a draft: the steps were checked against the source, not run end to end.

## Source files

View:

- `Views/ServerAgentsView.swift`: the pane, `AllowAgentView`, `ServerAgentDetailView`, polling and sheets (`ServerAgentsPresentation`).

Model:

- `Model/ServerAgentsController.swift`: requests, approve, reconnect, decline, first-copy tasks, `UploadActivity`.
- `Model/AppModel.swift` (`configureSync`, `agentCopies`, `sync`) and `Model/SyncSchedule.swift`: keep copies current after syncs.

Core:

- `JournalCore/AgentCopyPublisher.swift`: `approve`, `reconnect`, `decline`, `firstCopy`, `publishAll`.
- `JournalCore/AgentCopyClient.swift`: `AgentRequest`, `AgentCopyError`. Server contract: [agent-access-server.md](../../../../protocol/agent-access-server.md).

Design record: [agent-access-simplified.md](../../../../docs/design/agent-access-simplified.md).

## Open questions

See [open-questions.md](../../../open-questions.md). Found while writing: the spec says declining sends no error to the person if the server does not answer and the request reappears; the code does exactly that, but nothing tells the person the decline did not arrive.
