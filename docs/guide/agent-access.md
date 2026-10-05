# Agent access

Agent access lets an AI agent read the journals you choose, so you can ask it about your own writing: look back on a month, find patterns, or answer a question about something you wrote. You use the agent you already have. Anything that supports the Model Context Protocol (MCP) with authorization works, such as Claude Code, the Claude apps, ChatGPT, VS Code or Cursor. My Journal doesn’t include an AI service and doesn’t choose one for you.

Agent access is:

- **Through your sync server.** Your server is an MCP server. You add its address to your agent, and you allow the agent in My Journal. Nothing is installed.
- **Off until you allow it.**
- **Read-only.** An agent can list the journals you allowed, search them and read entries. It can’t change, add or delete anything.
- **Per journal.** Each agent reads only the journals you chose. Choose **All Journals** to include journals you create later too. You can change the journals at any time.
- **Revocable** at any time, and optionally time-limited.

Agents read the version of each entry that last synced. They don’t get images, templates, earlier versions or Recently Deleted.

## Connect an agent

You need a sync server (see [Sync](sync.md)) and My Journal on a device that syncs with it. Without one, Agent Access says so and offers **Connect to a Server…**.

1. In My Journal, open Settings > Agent Access. Under **MCP Server Address**, choose **Copy** (on iPhone or iPad you can also **Share** it to your computer).
2. In your agent, add an MCP server (sometimes called a custom connector) with that address. For example:
   - **Claude Code:** `claude mcp add --transport http my-journal <address>`
   - **Claude apps and claude.ai:** Settings > Connectors > Add custom connector, and enter the address.
   - **VS Code:** add an HTTP MCP server with the address.
   - **Clients that only run local (stdio) servers:** use `npx mcp-remote <address> --auth-timeout 300`.
3. Your agent opens a web page titled **Allow Access in My Journal** with a two-digit number, such as **47**.
4. In My Journal, open Settings > Agent Access. The agent’s request appears there, showing where it returns to. Choose it and enter the number from the page. Only allow a request you just started from your agent.
5. Choose **All Journals** or **Selected Journals**, then **Allow**. A wrong number declines the request; start again from your agent.
6. Return to your agent; the page continues on its own.

### Which agents can reach your server

- **An address on your tailnet** (`https://….ts.net`) works for agents on devices in your tailnet, such as Claude Code or VS Code on your computer. Agents that connect from their provider’s cloud — ChatGPT, and custom connectors in the Claude apps and claude.ai — can’t reach it.
- **A server on the same computer** (`http://127.0.0.1:…`), such as the container on your Mac, works only for agents on that computer.
- **A public HTTPS address** works for every agent. Making your server public exposes its whole sync API to the internet, which is protected by device credentials, rate limits and the setup-code limits. To expose only what agents need, publish just `/mcp`, `/oauth/` and `/.well-known/` through your proxy. With Tailscale Funnel, which publishes a whole host and port, use a separate Funnel port (such as 8443) that forwards only those paths, and set `JOURNAL_URL` to that address.

If Agent Access says your server doesn’t know its HTTPS address, or asks you to set its public address, set `JOURNAL_URL` (or `Journal__PublicUrl`) for the server to its HTTPS address, such as `https://journal.example.ts.net`, and connect My Journal to that address. The `compose.https.yaml` example sets it from `JOURNAL_DOMAIN`.

### If your agent can’t finish connecting

- **The page says your server couldn’t connect to the agent’s address.** Some agents identify themselves with a web address the server looks up. A server without internet access, such as the `compose.https.yaml` example, can’t, so use an agent that registers itself instead, or allow the server to reach the internet.
- **The agent says its redirect address isn’t allowed.** The address an agent returns to must match the one it registered exactly, apart from the port of a `localhost` address. Remove the server from your agent and add it again.
- **Your agent gave up waiting.** Start the connection again from your agent and enter the new number. Clients that allow it can wait longer, for example `mcp-remote --auth-timeout 300`.

## What My Journal shows

Settings > Agent Access lists waiting requests, each agent with its journals and when it was last used, and your server’s MCP address. Choose an agent to rename it, change its journals and when access ends, and see recent activity: which tools it used and when. My Journal doesn’t record what an agent searched for or read. Changes apply right away.

An agent you allowed that hasn’t collected its access yet shows **Connecting…**. An agent that signed out, for example after 30 days unused, shows **Needs to reconnect**: connect again from your agent, and the request appears in Agent Access. Allowing it keeps the agent’s name, journals and end date.

## Revoke access

Choose the agent, then **Revoke Access**. The server deletes the agent’s access and its copy of your journals; the agent can’t read anything from then on. Revoking can’t take back what the agent already read. When access ends on its own, choose **Remove**.

To stop sharing a journal, choose the agent and turn the journal off, or choose **Selected Journals** instead of **All Journals**. The agent can’t read that journal from then on.

## How it works

When you allow an agent, your device keeps a copy of the chosen journals on your server for that agent, and updates it whenever one of your devices syncs. With encryption on, the copy is encrypted with a key that only the agent’s access can unlock: the server can read the shared journals only while it answers the agent, and your other journals stay end-to-end encrypted. Anyone who controls your server could read the journals you shared while that agent has access. See [SECURITY.md](../../SECURITY.md#agent-access-through-mcp).

## Agents on the same Mac

Agents running on your Mac connect the same way, through your sync server’s MCP address. If you don’t sync yet, set up a server first; see [Sync](sync.md). It can run on the same Mac, in a container; see [running the server on a Mac](../self-hosting/README.md#running-the-server-on-a-mac). Agents read what has synced, so your entries reach them once My Journal syncs, a moment after you write them.

## Before you share

- **Cloud agents.** Agents such as Claude send what they read to their AI provider, under the provider’s privacy policy. Cloud connectors also keep their access at the provider until you revoke it.
- **Entries are data, not instructions.** Journal names, titles and text are passed to the agent as untrusted content, never as instructions. This relies on the agent too, so use one you trust.
- **Proxies.** Don’t let a proxy in front of your server log request headers: an agent’s access token is also the key to its copy.
- **Check the request.** The request shows where access returns to. `localhost` or `127.0.0.1` means an app on the computer that opened the page; My Journal can’t confirm which app that is, so only allow a request you just started.
