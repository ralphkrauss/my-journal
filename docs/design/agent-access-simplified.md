# Agent access, simplified

Status: **revision 2, approved by an independent design review with required changes (section 14), which this revision addresses; implemented.** It changes the UI and approval parts of [agent-access-server.md](agent-access-server.md) sections 5.4, 5.5 and 6, and removes the local Mac connection ([agent-access.md](agent-access.md)). The MCP transport, tools, OAuth endpoints, tokens and key wrapping stay as they are.

**Revision 2 in short:**

- The owner **types the two-digit number** the page shows, instead of choosing it from three.
- Client-supplied names are sanitized and shortened. Every request shows where it returns to.
- Declining always sends the page back to the agent.
- Narrowing an agent's journals empties their items on the server in the same step, with no new scope format.
- Settings revisions are mandatory.
- Requests load as soon as the pane appears or My Journal becomes active.
- The request sheet can only be closed with **Don’t Allow** or **Allow**.
- A picker offers **All Journals** / **Selected Journals**.
- The section 8 facts about This Mac's server are corrected.

The owner tested the flow with Claude Code against their own server (2026-09-30). They said the setup "seemed very complicated". A page with a code to copy opened on the desktop. The Add Agent screens showed "all kinds of information that I wouldn't need". **Agents on This Mac** didn't seem necessary. "Preparing the journals" appeared after Allow. There was no way to change the journals afterwards or to give an agent all journals. The owner also asked for confirmation that access is read-only. Their earlier requirements still apply:

- "The server should simply provide the mcp access to any agent of your choice, all we have to do in the app is provide the access to it."
- "Implement mcp properly according to the best practices."

## 1. Short answers to the owner

- **Is a browser page normal?** Yes. Every remote MCP server with authorization opens a browser page when the agent connects: Notion, Linear, GitHub, Atlassian and Sentry all do, because MCP uses OAuth, and OAuth consent happens at the authorization endpoint, which is a web page. What isn't normal is copying a code into another app. Those services can finish in the browser because you're signed in to their website. Our server has no web sign-in, and it shouldn't get one. Only the owner's devices can approve, and with encryption on only a device can do the approval work, because it creates the agent's encrypted copy with the vault key. So the page has to hand over to the app. The proposal makes that handover as light as it can be. The request **appears in My Journal by itself**. You type the two-digit number the page shows and tap **Allow**.
- **Too much information?** Yes. Section 3 lists about 100 elements. Roughly 45 go and 25 get shorter. The approval sheet keeps who is asking, where access goes, a number to enter, the journals, one footer and **Don’t Allow** / **Allow**. Name, end date, warnings about sync state and the "Access Allowed" step leave the flow.
- **Agents on This Mac?** Removed (section 8). The sync server, including the server built into the Mac app, covers the same need through standard MCP, with the gaps section 8 lists.
- **"Preparing"?** It uploads the agent's copy. It stays, but moves out of the way (section 6). Allow closes the sheet at once, and the upload continues in the background.
- **Edit journals later, all journals?** Both added (section 7). **All Journals** covers journals you create later; the owner asked for it (owner decision, 2026-09-30).
- **Read-only?** Confirmed (section 9). The server has three tools (`list_journals`, `search_entries`, `read_entry`), all marked read-only. It has no code path from MCP to your journals' records. The approval sheet says so in one sentence.

## 2. The flow before this change, step by step

With Claude Code and the owner's server (`https://server.example.ts.net:18443`):

1. The owner copies the MCP address from Settings > Agent Access and runs `claude mcp add --transport http my-journal https://…/mcp`, then `/mcp` > **Authenticate**. Claude Code registers or uses its [client ID metadata document](https://www.claude.com/docs/connectors/building/authentication), opens the browser at `/oauth/authorize`, and waits for the redirect to `http://localhost:<port>/callback`. It waits about 5 minutes. That figure comes from an [unofficial source copy](https://tangled.org/oppi.li/claude-code/blob/main/services/mcp/auth.ts), not from documentation.
2. The browser shows **Allow Access in My Journal**: the client name, "Returns to localhost, an app on the computer that opened this page.", sometimes "Identified as …", a paragraph about opening Settings > Agent Access > Add Agent…, the code `K7QM-3XRD`, a **Copy Code** button, and "Waiting for approval…".
3. In My Journal: Settings > Agent Access. On the Mac, the tab shows **Connect an Agent** (address, Copy, reachability line, **Add Agent…**, footer and a guide link), **Agents**, **Agents on This Mac** and **Activity on This Mac**.
4. **Add Agent…** opens a sheet. It repeats the instruction and the address, then asks for the 8-character code. The owner types it and chooses **Continue**.
5. **Review** shows the client and three secondary lines, a **Connect As** picker when a matching agent exists, **Name**, **Journals** (none on), **Access Ends**, and up to four paragraphs of warnings. Then **Decline Request**, **Cancel** and **Allow**.
6. After **Allow**: "Preparing entries… Keep My Journal open." for up to 15 seconds. The server gives the page its authorization code only once the first copy is uploaded, or after 15 seconds.
7. **Access Allowed**: a checkmark, "‹name› can now read ‹journals›. Return to your agent to finish.", and **Done**.
8. The browser redirects, and Claude Code stores its tokens.
9. Later, the agent's detail shows client, return address, "Read Only", dates, "Last Updated" and its footer, activity, and **Revoke Access** with "To change which journals it can read, revoke access and add the agent again."
10. **Reconnect** (after 30 days unused, or after refresh-token reuse): the detail says to start again from the agent. **Reconnect…** opens the same code sheet again.

## 3. Inventory

**Keep**: needed as it is. **Simplify**: needed, but shorter or merged. **Remove**: goes away. The numbers are used later in this document.

### 3.1 Authorization page (browser)

| # | Element | Verdict | Why / replacement |
| --- | --- | --- | --- |
| 1 | Title and heading "Allow Access in My Journal" | Keep | Tells the owner which server the page belongs to. |
| 2 | "‹client› wants to read journals on this server." | Simplify | "‹client› wants to read your journals." |
| 3 | "Returns to ‹host›." / loopback variant | Remove from page | The decision happens in the app, which shows it (MCP requires the redirect host on the consent screen, and our consent screen is the app sheet). |
| 4 | "Identified as ‹host›." / "My Journal can’t confirm which app receives access." | Remove from page | Shown in the app sheet (#45–47). |
| 5 | Paragraph "To allow access, open My Journal on a device that syncs with this server, choose Settings > Agent Access > Add Agent…, and enter this code:" | Simplify | "In My Journal, open Settings > Agent Access and enter this number:" |
| 6 | Code `XXXX-XXXX` and its spelled-out text for screen readers | Remove | Replaced by a two-digit number (section 5). |
| 7 | **Copy Code** button | Remove | Nothing to copy. |
| 8 | "Waiting for approval…" | Keep | |
| 9 | "Access allowed. Continue to return to your agent." / "Returning to your agent…" | Simplify | "Access allowed. Returning to ‹client›…", shown as soon as the owner allows. |
| 10 | "Access was declined." | Simplify | "Access wasn’t allowed. Returning to ‹client›…" (it redirects with `access_denied`). |
| 11 | **Continue** link | Keep | Needed without JavaScript and when automatic navigation is blocked. |
| 12 | "This request expired. Return to your agent and try again." | Keep | |
| 13 | Seven error pages (HTTPS, registration, identity document ×3, sign-in method, redirect) | Keep | Shown only on failures. |

### 3.2 Settings > Agent Access pane

| # | Element | Verdict | Why / replacement |
| --- | --- | --- | --- |
| 14 | Section header **Connect an Agent** | Keep | |
| 15 | Mac without a server: "To let an agent on another computer read your journals, set up sync." | Simplify | "Agents read your journals through a sync server, which can run on this Mac." Local connections are gone (section 8). |
| 16 | iPhone/iPad without a server: "Let an agent such as Claude read the journals you choose. This needs a sync server." | Keep | |
| 17 | **Set Up Sync…** | Keep | |
| 18–22 | Loading…, needs an update, no longer has access + **Connect Again…**, address not usable + link, "Couldn’t reach ‹host›." + **Try Again** | Keep | Real states. |
| 23 | **MCP Server Address** row | Keep | The one thing the agent needs. |
| 24–25 | **Copy** / **Share…** | Keep | |
| 26 | Reachability line (loopback, tailnet) | Keep | It prevents trying a cloud agent that can't reach the server. |
| 27 | **Add Agent…** | Remove | Requests appear on their own (section 5). |
| 28 | "Create a journal before adding an agent." | Remove | **All Journals** works even with none yet. |
| 29 | "You can have up to 20 agents. Revoke one to add another." | Simplify | Shown in the approval sheet at the limit: "…Revoke one to allow another." |
| 30 | Footer "Add this address to your agent as a custom connector or MCP server. When your agent opens a page with a code, choose Add Agent and enter it." | Simplify | "Add this address to your agent as an MCP server or custom connector. When the agent asks for access, the request appears here." |
| 31 | **How to Connect an Agent** | Keep | |
| 32 | Section **Agents** | Keep | |
| 33 | "No agents have access through ‹host›." | Remove | The section is hidden when empty. |
| 34 | Row: name, journals, status | Keep | Status "Waiting for your agent to finish connecting" becomes "Connecting…". The journals line reads "All Journals" for that choice. |
| 35 | Hint "Shows details." | Keep | |

### 3.3 Add Agent sheet (today's steps 1–3)

| # | Element | Verdict | Why / replacement |
| --- | --- | --- | --- |
| 36 | Title "Add Agent" / "Reconnect ‹name›" | Remove | The sheet opens from a request row as **Allow Access** (6.3). |
| 37 | "In your agent, add an MCP server with this address. When your agent opens a page with a code, enter the code here." | Remove | Already in the pane footer. |
| 38 | Address + **Copy** (repeated) | Remove | Duplicate. |
| 39 | **Code** field, `PasteButton`, hint | Remove | No code. |
| 40 | Footer "Only enter a code shown on a page you opened from your agent." | Simplify | Becomes #48. |
| 41 | **Continue**, "Checking Code…", three code errors | Remove | |
| 42 | Title "Review" | Simplify | "Allow Access". |
| 43 | "‹client› wants to read your journals." | Keep | Reconnecting: "‹name› wants to reconnect." |
| 44 | "Started ‹relative›" | Simplify | Moves to the request row ("‹host› · just now"). |
| 45 | "Returns to ‹host›" / loopback variant | Keep | MCP: the redirect host MUST be shown. |
| 46 | "Identified as ‹host›" (metadata-document clients with HTTPS redirects) | Keep | |
| 47 | Metadata document + loopback: "My Journal can’t confirm which app receives access." | Simplify | "My Journal can’t confirm which app this is." MCP says servers SHOULD warn for localhost redirects. |
| 48 | "Only do this if you just started connecting from your agent." | Simplify | "Only allow access if you just connected from your agent." |
| 49 | **Connect As** picker (Reconnect / Add as a New Agent / Replace) | Remove | Signed-out agents reconnect automatically. Other requests become new agents (7.5). |
| 50 | "‹name› stops working where it’s connected now." | Remove | No Replace. |
| 51 | Reconnect text, "different app" warning, read-only journal list | Remove | Matching is by client ID, so the app can't differ. Journals are shown as editable toggles instead. |
| 52 | **Name** field and its footer and length error | Remove from flow | The name defaults to the client name and can be renamed in the detail. |
| 53 | **Journals** toggles | Keep | Adds **All Journals**. |
| 54 | Footer "…Journals you create later aren’t included. To change them, revoke access and add the agent again." | Remove | No longer true (section 7). |
| 55 | **Access Ends** picker | Remove from flow | Moves to the detail. The default stays Never (owner decision). |
| 56 | "Agents not used for 30 days need to reconnect." | Remove | Kept in the guide. |
| 57 | Encrypted-copy paragraph (4 sentences) | Simplify | One sentence, only for encrypted libraries on a server other than this Mac's (6.3). |
| 58 | Unencrypted-copy paragraph | Remove | Adds nothing: that server can already read everything. |
| 59 | "Agents such as Claude send what they read to their AI provider." | Simplify | Merged into the footer. App Review guideline 5.1.2(i) requires disclosure before sharing with third-party AI. |
| 60 | "Revoking access stops future reads. It can’t take back what the agent already read." | Remove | In the revoke confirmation. |
| 61 | "Some changes haven’t synced yet…" | Remove | Syncing stays quiet. The agent gets changes after they sync. |
| 62 | **Decline Request** (form button) | Simplify | **Don’t Allow** in the toolbar, with the same weight as **Allow** (RFC 10027 §6.1.14). |
| 63 | "Preparing entries… Keep My Journal open." | Remove | Section 6. |
| 64 | **Cancel** | Remove | **Don’t Allow** declines; swipe-to-dismiss is off, so the sheet has one way out besides **Allow**. |
| 65 | **Allow** / **Reconnect** / **Replace** | Simplify | Always **Allow**. |
| 66 | Allow errors (expired, limit, unreachable, generic) | Keep | Plus a mismatch and a "no longer waiting" error. |
| 67–69 | **Access Allowed** step: checkmark, "‹name› can now read …", "Some entries couldn’t be prepared yet…", **Done** | Remove | The sheet closes. The page confirms. VoiceOver announces "Access allowed." |

### 3.4 Agent detail

| # | Element | Verdict | Why / replacement |
| --- | --- | --- | --- |
| 70 | "Waiting for your agent to finish connecting" | Simplify | "Waiting for ‹client› to finish connecting." |
| 71 | Needs-reconnect text + **Reconnect…** | Simplify | Text only: "Connect again from ‹client› to reconnect it." The request then appears in Agent Access. |
| 72 | **Journals** read-only list | Simplify | Becomes the editable toggles (7.2). |
| 73 | "‹name› (Deleted)", "A journal that isn’t on this device" | Simplify | Deleted journals aren't listed. Unknown IDs: "1 journal that isn’t on this device". |
| 74 | **Agent** (client name) | Remove | The name defaults to it. The request row and page show it. |
| 75 | **Returns To** | Remove | Only matters when deciding. |
| 76 | **Access** "Read Only" | Simplify | Journals footer sentence. |
| 77 | **Added** | Keep | |
| 78 | **Access Ends** | Keep | Now editable. |
| 79 | **Last Used** | Keep | |
| 80 | **Last Updated** + footer about the copy | Remove | The copy is an implementation detail. Tool results give the agent `copy.asOf`. |
| 81 | **Recent Activity** list + footer | Simplify | Moves behind a **Recent Activity** row. |
| 82 | **Revoke Access** + confirmation | Keep | Shorter message. |
| 83 | **Remove** (ended) | Keep | |
| 84 | **Stop Connecting** + its own confirmation | Remove | **Revoke Access** does the same for a connecting agent. |
| 85 | Footer "To change which journals it can read, revoke access and add the agent again." | Remove | |
| 86 | "This agent’s access was revoked." | Keep | |
| 87 | Mac **Done** | Keep | |

### 3.5 Agents on This Mac (Mac only)

| # | Element | Verdict |
| --- | --- | --- |
| 88 | Section **Agents on This Mac**, "No local connections.", rows, **Add Local Connection…**, limit texts, error + **Try Again**, footer | Remove |
| 89 | Section **Activity on This Mac** | Remove |
| 90–95 | **Add Agent Access** sheet: Name, Journals, **Continue**, confirmation text, cloud warning, **Back**, **Allow Read Access**, "Adding Access…" | Remove |
| 96–100 | Local detail: Read Only, date, journals, **Connection Instructions**, **Copy Connection Instructions**, warning, Copied, **Revoke Access**, **Done**, "instructions are unavailable" | Remove |

## 4. Research

### 4.1 Standards

- **MCP authorization** ([2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)):
  - How the authorization server interacts with the user is out of the spec's scope. Clients see only the standard flow: authorize URL, redirect with `code`, then token exchange with PKCE and `resource`. **Approval on another device is compliant as long as `/oauth/authorize` ends with that redirect.** This proposal keeps that exactly.
  - For client ID metadata documents: a document "cannot prevent localhost URL impersonation". The consent screen MUST show the redirect host and SHOULD warn for localhost redirects. That is #45–47, kept in the app sheet.
  - Clients try pre-registration, then metadata documents (SHOULD), then dynamic registration (MAY, for backwards compatibility). The server keeps both.
- **MCP security best practices** ([page](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices)): per-client consent is a MUST only for proxy servers with a static upstream client ID. We aren't one. Its consent-screen advice still applies: name the client, show the scope and redirect, block framing. The [Cloudflare workers-oauth-provider consent guidance](https://github.com/cloudflare/workers-oauth-provider/blob/main/docs/consent-page.md) says the same.
- **RFC 8628** ([device grant](https://www.rfc-editor.org/rfc/rfc8628)):
  - §5.4 "Remote Phishing": an attacker starts the flow and gets the victim to approve it. Servers should show device information and, with `verification_uri_complete`, "ask the user to verify that the same code is currently being displayed".
  - §6.1: typed codes need entropy and rate limits (8 characters from 20 letters, about 34 bits).
- **Cross-device security BCP** ([RFC 10027](https://www.rfc-editor.org/rfc/rfc10027.html), formerly draft-ietf-oauth-cross-device-security):
  - §4.1.1: typing a code across devices makes the user compensate for the unauthenticated channel between them.
  - §6.1.14: the approval screen SHOULD say who asked and tell the user to decline if they didn't start it. Decline SHOULD be at least as prominent as approve.
  - §6.1.16: showing a one-time code on the trusted device is the stronger direction.
- **RFC 9700** ([OAuth security BCP](https://www.rfc-editor.org/rfc/rfc9700)): exact redirect matching except loopback ports, PKCE, and rotated refresh tokens. Already implemented and unchanged.

### 4.2 How others do it

| Service | Consent | Scope at consent | Edit later | Manage / revoke |
| --- | --- | --- | --- | --- |
| [Notion MCP](https://www.notion.com/help/notion-mcp) | Browser, signed in | None: "everything you can access" | No | Settings → Connections |
| [Linear MCP](https://linear.app/docs/mcp) | Browser, signed in | Workspace from the account; `read` scope | No | Token revocation |
| [GitHub MCP](https://docs.github.com/en/copilot/how-tos/provide-context/use-mcp/set-up-the-github-mcp-server) | Browser, signed in | Scopes added on demand | Re-consent | [Authorized apps](https://docs.github.com/en/enterprise-cloud@latest/apps/using-github-apps/reviewing-and-revoking-authorization-of-github-apps) |
| [Atlassian Rovo MCP](https://developer.atlassian.com/cloud/rovo-mcp/guides/authentication-and-authorization/) | Browser, signed in | Site | Reconnect | Profile → Connected apps |
| Sentry MCP ([repo mirror](https://glama.ai/mcp/servers/@getsentry/sentry-mcp/blob/0151a7149343bcf072fcd673817a0a6437000831/docs/cloudflare/oauth-architecture.md)) | Browser, signed in | "Skills" and organization | Unverified | Sentry settings |

Choosing a scope at consent is uncommon and coarse, and changing it usually means reconnecting. Choosing journals in our consent step and editing them later would be better than most of these services, not worse. None of them has an out-of-band approver, because each has a web login.

"Approve on your other device" patterns:

- **Apple**: the trusted device shows location, then Allow, then a 6-digit code typed on the new device ([HT204974](https://support.apple.com/en-us/HT204974)).
- **Google**: match a number shown on the computer on your phone ([9907994](https://support.google.com/accounts/answer/9907994)).
- **Microsoft Authenticator**: number matching has been mandatory since May 2023 because of push-fatigue attacks ([ITPro](https://itpro.com/security/cyber-attacks/microsoft-authenticator-mandates-number-matching-to-counter-mfa-fatigue-attacks)). [CISA](https://www.cisa.gov/sites/default/files/publications/fact-sheet-implement-number-matching-in-mfa-applications-508c.pdf) recommends it, and notes that it doesn't stop a live phishing relay.
- **Tailscale**: an admin approves new devices in the console ([device approval](https://tailscale.com/kb/1099/device-approval)).

**The lesson:** a bare "Approve" invites fatigue and mistakes. Making the person compare something between the two screens, shown with context, fixes most of that.

### 4.3 Options for our server

The server has no web login, and with encryption on an approving device must create the copy key and copy.

| Option | Steps for the owner | Security | Phone approving for a computer | Verdict |
| --- | --- | --- | --- | --- |
| **(a) Typed code** (revision 10 of agent-access-server.md) | Navigate, **Add Agent…**, type 8 characters, Continue, review | The code binds the page to the approval. Phishable per RFC 8628 §5.4: an attacker's page can show a code the owner types. The 40 bits add nothing, because only paired devices can look codes up. | Read 8 characters across screens | Replaced |
| **(b) Request appears in the app, number typed** | Open Agent Access, tap the request, type the page's two digits, choose journals, **Allow** | The number binds the decision to the page the owner is looking at, so another waiting request (a stranger's, or an old one) can't be approved by mistake. A wrong number declines the request, so a blind guess succeeds one time in 90, once. Remote phishing is no worse than (a). | Glance at two digits on the computer | **Chosen** |
| (b′) Choose the number from three | As (b), with a tap instead of typing | A blind tap succeeds one time in three. The review found this too weak: anyone can present Claude Code's shared metadata URL with a loopback redirect, so the name and "Returns to localhost" match the owner's own request, and the number is the only gate. | Easy | Rejected in review |
| (b″) Compare only (Yes/No) | As (b), without entering anything | Weakest against inattention. Microsoft moved away from bare approval because of push fatigue. | Easy | Rejected |
| (b‴) Reverse: app shows a code, typed into the page | As (b), then type on the page | Strongest against phishing (RFC 10027 §6.1.16): the owner would have to give the attacker the code. | Type on the computer | Rejected for now: typing again, and a form on the page (the CSP forbids forms). Kept as the upgrade path if servers become public by default. |
| **(c) "Open My Journal" link** (custom URL scheme) | Click, the app opens at Agent Access | The link must carry nothing. Any app can claim a scheme, and Apple calls the target "undefined" when several do ([Apple](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app)). Universal links need an `apple-app-site-association` file on a domain listed in the app's entitlements ([Apple](https://developer.apple.com/documentation/xcode/supporting-associated-domains)), so they can't work for self-hosted domains. | Useless: the page is on the computer. On a computer without My Journal the browser shows an error. | Not now (owner decision Q2) |
| (d) Approve on the page with a passkey | Touch ID on the page | Needs the server to become a WebAuthn relying party. With encryption, the approving party must create the copy key, which the page can't do. | Works | Rejected |
| (e) App prompts on its own (modal alert when a request arrives) | None beyond Allow | A stranger who can reach the server could make prompts appear on every device (a fatigue vector). There's no push service, so it only works while the app is open. | Needs the app open | Rejected. The request waits in Agent Access, where the page sends the owner. |

**Threats under (b):**

- **Strangers creating requests:** limits stay at 3 waiting per address and 20 in all. A stranger's request shows up as an extra row with its return host. Approving it needs the number from a page the owner isn't looking at, and a wrong number ends it.
- **Client impersonation:** anyone can register as "Claude Code" (DCR), or present Claude Code's real metadata URL with their own localhost listener. The sheet shows the literal redirect host at primary weight, "Identified as …" only for HTTPS redirects, and the localhost warning. That is what MCP requires. The number is the gate.
- **Hostile names:** client names are the client's own text. The app and the page remove control and formatting characters (which could reorder text), keep them to one line and at most 40 characters, and never treat them as markup.
- **Stale requests:** a new request from the same client ID and the same network address replaces that client's waiting request, so retries don't pile up (5.2). A stranger from another address never replaces or reconnects the owner's request, even with the same shared client ID. Behind a proxy the server doesn't trust, every client shares one address. Then a stranger with the same client ID could replace the owner's waiting request (the owner's page then says it was replaced), but can't approve it. The deployment guides configure trusted proxies.

## 5. The flow

```mermaid
sequenceDiagram
    actor O as Owner
    participant A as Agent (e.g. Claude Code)
    participant B as Browser
    participant S as Sync server
    participant J as My Journal (any device)
    O->>A: claude mcp add … then /mcp Authenticate
    A->>S: discovery, registration or metadata document
    A->>B: open /oauth/authorize (PKCE, resource)
    B->>S: GET /oauth/authorize
    S-->>B: "Claude Code wants to read your journals" + number 47
    O->>J: Settings > Agent Access
    J->>S: GET /v1/agent-requests (on appear, on activation, then every 3 s)
    S-->>J: Claude Code · localhost · just now
    O->>J: tap request
    J->>S: GET /v1/agent-requests/{id} (details; no number)
    O->>J: type 47, choose journals, Allow
    J->>S: POST …/approve {number, grant, settings, wrapped key}
    S-->>J: 204 (sheet closes; row shows "Connecting…")
    S-->>B: status approved: "Access allowed. Returning to Claude Code…"
    J->>S: first copy upload in the background, then …/ready
    S-->>B: redirect with code (on ready, or 15 s after approval)
    B->>A: localhost callback
    A->>S: POST /oauth/token (code + verifier)
    A->>S: MCP tools/call (read-only)
```

A wrong number, **Don’t Allow**, or revoking an agent that's still connecting sends the page back at once to `redirect_uri` with `error=access_denied`, `state` and `iss`. The page says "Access wasn’t allowed. Returning to ‹client›…".

### 5.1 The owner's steps

1. Copy the address (once) and add it to the agent.
2. In the agent, **Authenticate**. The page opens and shows **47**.
3. In My Journal, go to Settings > Agent Access. The request is at the top. Tap it.
4. Type **47**, choose **All Journals** or **Selected Journals**, then **Allow**.
5. Switch back. The page has already moved on.

That's six or seven interactions, down from about sixteen, as the review counted.

### 5.2 Request lifecycle (server)

- Each request gets a **number** from 10 to 99, unique among waiting requests. The page shows it, and devices never receive it.
- A new `/oauth/authorize` request with the same `client_id` from the same client address replaces that client's waiting request. The old page says "This request was replaced by a newer one. You can close this page." It gets no redirect: the agent already opened the new page.
- Lifetimes are unchanged: 10 minutes waiting, plus 5 after approval. The page's status is `approved` from the moment of approval. The code is released on `ready`, or 15 seconds after approval.
- Listing requests doesn't protect them from eviction. Opening one (`GET /v1/agent-requests/{id}`) does.

## 6. "Preparing the journals": why, and how it disappears

**Why a copy exists.** With encryption on, the server holds only ciphertext under one vault key. It can't tell which entries belong to which journal, and giving it the vault key would expose every journal ([agent-access-server.md](agent-access-server.md) §2). So a device re-encrypts only the chosen journals under a key for that agent and uploads them. The server can unlock that key only with the agent's live token. That is what makes access per journal and keeps the other journals end-to-end encrypted.

**Unencrypted libraries.** A copy isn't strictly needed: the server could read the records itself. It would then have to parse the document format, work out readable text, and apply the sync rules a device applies today: leave out conflicts, unsettled changes, Recently Deleted, templates and history. That means a second implementation of client logic in C#, a second MCP read path, and different behavior depending on the mode. **One path for both modes.**

**What changed.**

- **Allow** sends `approve` and closes the sheet as soon as the server accepts it.
- The first upload runs in a task the publisher owns. It is cancelled when My Journal locks, and on iOS it runs under a background task.
- When the upload finishes, the device calls `ready`.
- The page shows "Access allowed. Returning to ‹client›…" right after approval and redirects on `ready`, or after at most 15 seconds.
- If the copy isn't complete yet, tool results already say so (`copy.complete: false`), and the next sync completes it.
- Nothing in the app mentions a copy, preparing or "Last Updated".

## 7. Choosing journals, All Journals, and editing later

### 7.1 Semantics

- **All Journals, including new ones** (owner decision, 2026-09-30).
  - Settings format version 2 stores `journals: "all"` or `journals: [ids]`.
  - With `"all"`, the shared set is every live journal at each publish. A journal created later, on any device, is shared after its first sync.
  - A deleted journal leaves the copy, and restoring it brings it back. A rename updates the name the agent sees.
  - Devices joining a library don't count an agent with All Journals when deciding what to combine: it reads every journal either way (`journalsAgentsCanRead` returns only journals chosen with Selected Journals; amended by [journal-name-uniqueness.md](journal-name-uniqueness.md) §4.5).
- **Selected journals.** The rules are unchanged.
  - A deleted journal leaves the copy. Restoring it from Recently Deleted shares it again, because its ID is still chosen.
  - Entries moved out leave the copy.
  - IDs of journals this device doesn't have are kept when saving, never dropped. The detail shows them as "1 journal that isn’t on this device".
- **How this meets AGENTS.md** (explicit, journal-scoped, revocable, read-only):
  - Nothing is preselected in the approval sheet.
  - **All Journals** is labelled, and its footer says "Includes journals you create later." It stays a journal-level scope, shown as "All Journals" in the agent's row.
  - With **All Journals** on, the detail lists which journals it currently includes, as switched-on, disabled rows.
  - Switching to **Selected Journals**, or revoking, narrows access at once (7.4).

### 7.2 Controls (approval sheet and detail)

Section **Journals**:

- A `Picker` with **All Journals** and **Selected Journals**, like the access choices in iOS Settings for Photos and Contacts. It's an inline list on iPhone and iPad and a radio group on the Mac, with no default in the approval sheet.
- Below it, one row per journal: switched on and disabled for **All Journals**, a `Toggle` each for **Selected Journals**. In the detail, the last chosen journal can't be switched off. Its VoiceOver hint is "To stop all access, revoke it."
- Footer:
  - With All Journals: "Includes journals you create later. ‹name› can search and read entries in these journals but can’t change anything. It may send what it reads to its AI provider."
  - Otherwise, the same without the first sentence.

### 7.3 Changing settings after approval

- **Detail changes apply right away**, like app permissions in iOS Settings, and saving is quiet:
  - the name, on Return or when the field loses focus;
  - the journals, collected for 0.5 seconds;
  - **Access Ends**.
- **`PUT /v1/agents/{id}`** takes `{revision, metadata, expiresAt?, removedItems?}` and returns `{revision}`:
  - A missing `revision` returns `400`, and a stale one returns `409 agent_settings_changed`.
  - `GET /v1/agents/` returns `revision`.
  - On a conflict the app reloads the agent and says "This agent was changed on another device. Showing the latest settings." It never overwrites silently.
- **`POST /v1/agents/{id}/items`** requires the `revision` its plan used. Without one it returns `400`; with an old one, `409 agent_settings_changed`. The publisher then reads the agents again and plans with the new settings. A device holding old settings can't re-upload a journal that was just removed.
- A sooner end date also shortens tokens already issued. Once access has ended, the agent has to be allowed again.

### 7.4 Enforcing narrower access

- The device sends `removedItems` with the change: the item IDs of the journals no longer shared and of their entries, as far as it knows them.
- In the same transaction as the revision bump, the server empties those items. It keeps their rows at version 0, so sharing the journal again later publishes it whatever the device's cursor.
- `McpTools` already returns only entries whose journal item is in the copy. So emptying a journal's item hides all of its entries at once, even entries the device didn't know about, which the next publish removes.
- No new encrypted scope format and no migration mode are needed. **All Journals** is a publishing rule on the device.

### 7.5 Reconnecting and duplicates

- A request whose `client_id` matches a signed-out grant (**Needs to reconnect**) is offered as a reconnect. The first line reads "‹name› wants to reconnect.", and the sheet shows its journals, the "Returns to" line and any loopback warning. **Allow** with the right number reconnects it, keeping name, journals, activity and copy.
- A request whose `client_id` matches an **active** grant becomes a new agent, never a replacement. Client IDs aren't unique per installation: Claude Code's metadata document `https://claude.ai/oauth/claude-code-client-metadata` is shared by every copy.
- The new agent is named after its client, numbered when that name is taken: "Claude Code 2". It can be renamed in the detail.

## 8. Agents on This Mac: removed

**Why:**

- The owner's model: "the server should simply provide the mcp access … all we have to do in the app is provide the access to it."
- It was a second MCP implementation, with its own grants, activity, a sandboxed helper and connection files. It also had a known weakness: any process that could read the `agent-connections` folder could use every local connection. For App Review, it was the extra helper most likely to draw questions.

**What replaces it, and the gaps:**

- The Mac app's own server (Settings > Sync > **Use This Mac…**) serves `http://127.0.0.1:…/mcp` to agents on the same Mac, through the same standard OAuth flow.
  - That server binds only to `127.0.0.1`.
  - Setting it up requires that the Mac isn't connected to another server and that the recovery key is confirmed. Setup uploads the library to it.
  - It runs while My Journal runs, the same condition the local connection had.
- **A Mac with no sync** must choose **Use This Mac…** before an agent can read its journals.
- **A Mac syncing with a plain-HTTP LAN server** has no agent path: that server reports `mcpUnavailable: https-required` until it has an HTTPS address, such as Tailscale Serve or a proxy.
- **Agents see entries as of the last sync.** They no longer see unsynced edits on the Mac. With This Mac's server, the Mac syncs with itself, so the delay is short.
- Copy on a Mac without a server: "To let agents read your journals, use this Mac as your server or connect to one." with **Set Up Sync…**.

**What was removed** (see the implementation report for the file list):

- App: the local-connection views and controller, the Mac window hooks that served them, and the Settings section.
- JournalCore: the local grant store, bridge and stdio MCP.
- The `journal-agent` target and product, its entitlements, the connector steps of the Mac packaging and sandbox scripts, and the tests of all of the above.
- The contract `protocol/agent-access.md`: its tool semantics are now in `protocol/agent-access-server.md`.
- On first launch, the Mac app deletes what local connections left: the `agent-connections` folder (grants, activity, connection files, discovery file) in the app group container or the data folder, and its two Keychain keys (`LocalAgentCleanup.swift`).

## 9. Read-only: confirmed

- **Tools:** `McpTools.Names` = `list_journals`, `search_entries`, `read_entry`, each annotated `readOnlyHint: true, destructiveHint: false`.
- **Code paths:** the MCP handler reads only the grant's `AgentItems` (its copy) and writes only activity events and `lastUsedAt`. There is no path from `/mcp` to records, attachments, templates, history or sync.
- **Tokens:** they carry only the scope `journals:read` and the `/mcp` audience. Device routes refuse them.
- **UI:** "‹name› can search and read entries in these journals but can’t change anything." That sentence appears in the approval sheet and the detail.

## 10. Screens

Terms: **agent**, **MCP server address**, **request**. There is no code, credential or "preparing" anywhere in the UI. Client and agent names are always `Text(verbatim:)`, and client names go through `ServerAgentText.displayName`. `‹host›` is the server host, or "this Mac".

### 10.1 Settings > Agent Access (iPhone, iPad, Mac)

A native grouped `Form`: the Settings tab on the Mac, the pushed Settings pane on iPhone and iPad.

**Requests** (only while requests are waiting)

- One row per request, newest first:
  - Primary: the client name, one line.
  - Secondary: "‹redirect host› · just now", or "‹redirect host› · 2 min. ago".
  - A chevron.
- VoiceOver reads one button: "‹client›, returns to ‹host›, just now". Hint: "Reviews the request."
- Requests load when the pane appears (whether or not My Journal is active), when My Journal becomes active (scene phase on iPhone and iPad, app activation on the Mac), and every 3 seconds while the pane is visible and the app is active.
- When a new request arrives, the agents list reloads too, so an agent that signed out shows as such.

**Agents** (only when there is at least one)

- Name; journals ("All Journals", or names over at most 2 lines); status.
- Statuses: "Connecting…", "Needs to reconnect" (with `exclamationmark.circle`), "Access ended ‹date›", "Access ends ‹date›" (within 7 days), "Last used ‹relative›", "Never used".

**Connect an Agent**

- **MCP Server Address**: monospaced and selectable, with **Copy**, and **Share…** on iPhone and iPad.
- Reachability, when limited:
  - loopback: "Only agents running on this Mac, such as Claude Code, can use this address."
  - tailnet: "Only agents on devices in your tailnet can use this address. Agents that connect from the cloud, such as ChatGPT or Claude on the web, can’t reach it."
- Footer:
  - "Add this address to your agent as an MCP server or custom connector. When the agent asks for access, the request appears here."
  - With encryption, on a server other than this Mac's: "While an agent has access, anyone who controls ‹host› could read the journals it reads."
  - **How to Connect an Agent**.

**States that replace Connect an Agent's content:**

- **No server:**
  - Mac: "To let agents read your journals, use this Mac as your server or connect to one." with **Set Up Sync…**.
  - iPhone/iPad: "To let agents read your journals, connect to a sync server." with **Set Up Sync…**.
- "Loading…".
- "‹Host› needs an update before agents can connect."
- "This device no longer has access to ‹host›." with **Connect Again…**.
- The two address-not-usable texts, with the guide link.
- Offline: "Couldn’t reach ‹host›." with **Try Again**. An already loaded list stays visible.

With no requests and no agents, only **Connect an Agent** shows.

### 10.2 Allow Access sheet

A `NavigationStack` sheet titled **Allow Access**: 480 × 540 ideal on the Mac, 440 × 420 minimum.

**Closing.** Swipe-to-dismiss is disabled, so the only ways out are the two buttons:

- **Don’t Allow** (`cancellationAction`; Escape on the Mac) declines the request, and its page returns to the agent with `access_denied`.
- **Allow** (`confirmationAction`, Return) is enabled with two digits and a journal choice. For a reconnect, the two digits are enough.

**Content:**

1. **Who and where** (no header):
   - First line: "‹client› wants to read your journals." For a reconnect: "‹name› wants to reconnect."
   - Then, at primary weight: "Returns to ‹host›". For a loopback redirect: "Returns to ‹localhost|127.0.0.1›, an app on the computer that opened the page".
   - Secondary: "Identified as ‹host›" (metadata document with an HTTPS redirect), or "My Journal can’t confirm which app this is." (metadata document with a loopback redirect).
   - Last line, secondary: "Only allow access if you just connected from your agent." At 20 agents it reads instead "You can have up to 20 agents. Revoke one to allow another.", and **Allow** stays disabled.
2. **Number**: a `TextField` labelled "Number Shown on the Page", limited to two digits.
   - On the Mac the label sits beside the field. On iPhone and iPad it shows as the prompt, the field uses the number pad, and the keyboard closes once both digits are in so the journals show.
   - The field is focused when the sheet opens.
3. **Journals** (7.2). For a reconnect: the agent's journals as text, with the read-only footer.

"Loading…" shows until the request's details arrive.

**Allowing:**

- While allowing, a small progress indicator replaces **Allow**.
- On success the sheet closes, VoiceOver announces "Access allowed.", and the row appears with "Connecting…".

**Errors:**

- Wrong number: alert **Numbers Don’t Match**, "The request was declined. If you started it, connect again from your agent.", **OK**. The sheet closes.
- Request ended (expired, replaced, decided elsewhere, server restarted): alert **Request Ended**, "Start again from your agent if you still want to connect it.", **OK**.
- Inline, red:
  - "Couldn’t reach ‹host›. Check your connection and try again."
  - "Too many attempts. Try again in a minute."
  - "You can have up to 20 agents. Revoke one to allow another."
  - "Couldn’t allow access. Try again."

Locking My Journal closes the sheet.

### 10.3 Agent detail

A pushed page on iPhone and iPad; on the Mac, a sheet with **Done**. Sections, in order:

1. **Status**, only when relevant:
   - "Waiting for ‹client› to finish connecting."
   - "Connect again from ‹client› to reconnect it."
   - "Access ended ‹date›."
2. **Name** (`TextField`, 1–80 characters, with a "Name" header on iPhone and iPad; an invalid name reverts to the saved one).
3. **Journals** (7.2).
4. **Access Ends**: a menu with "Never", the current end date if one is set, "In 30 Days" and "In 90 Days".
5. **Last Used**, **Added**, and a **Recent Activity** row that pushes the list of tool uses:
   - rows "Searched Entries", "Read an Entry", "Listed Journals";
   - "No activity yet." or "Couldn’t load activity.";
   - footer "My Journal records which tools the agent used, not what it searched for or read."
6. **Revoke Access**, with a confirmation:
   - "Revoke access for ‹name›?"
   - "‹name› won’t be able to read your journals anymore. It keeps anything it already read."

   For an ended agent: **Remove**, without confirmation.

**Errors and other states:**

- Save failure (the controls return to the saved settings): "Couldn’t save this change. Check your connection and try again."
- Conflict: "This agent was changed on another device. Showing the latest settings."
- Revoke failure: "Couldn’t revoke access. Check your connection and try again."
- Revoked elsewhere: "This agent’s access was revoked."
- Unreadable settings: "Details aren’t available on this device."

### 10.4 Authorization page (server)

```
Allow Access in My Journal                      (h1; also <title>)
Claude Code wants to read your journals.        (sanitized client name in <strong>)
In My Journal, open Settings > Agent Access and enter this number:
                     47                          (large monospaced digits)
Waiting for approval…                           (role=status, aria-live=polite)
Continue                                         (link, hidden until there's somewhere to go)
```

- Statuses:
  - approved/allowed: "Access allowed. Returning to ‹client›…"
  - declined: "Access wasn’t allowed. Returning to ‹client›…", with the redirect to `access_denied`
  - replaced: "This request was replaced by a newer one. You can close this page."
  - expired: "This request expired. Return to your agent and try again."
- Once the request is decided, the number is hidden.
- The number is ordinary text, so screen readers read "47".
- The page keeps the same CSP and headers, with one hashed script. Without JavaScript, `/oauth/authorize/wait` refreshes every 15 seconds.
- Error pages are unchanged.

### 10.5 Accessibility and platform behavior

- Dynamic Type to the largest sizes. VoiceOver labels are given above. Announcements: "Access allowed.", "Request declined.", "Access revoked.", "Copied.", and errors.
- System colors only. Status never relies on color alone.
- Mac keyboard in the sheet: Tab moves through the number, the journal choice, the journals and the buttons. Return means **Allow**, and Escape means **Don’t Allow**.

## 11. Server and protocol changes, and migration

**Capability:** `agent-access` becomes `agent-access-2`. There is no compatibility with builds from before this change (owner decision Q3). Every device must be updated.

**Endpoints:**

- **Removed:** `POST /v1/agent-requests/lookup`.
- **Added:**
  - `GET /v1/agent-requests` → `[{id, clientName, clientId, identifiedAs?, redirectHost, redirectKind, requestedAt, expiresAt, reconnectCandidate?}]`, waiting requests only. `reconnectCandidate` is only ever a signed-out grant.
  - `GET /v1/agent-requests/{id}` → the same fields for one request, which it also keeps from eviction.
  - `PUT /v1/agents/{id}` (7.3).
- **Changed:**
  - `POST …/approve` requires `number`. A wrong number declines the request and returns `409 agent_request_mismatch`.
  - `GET /v1/agents/` includes `revision`.
  - `POST /v1/agents/{id}/items` requires `revision`.
  - Status polling adds `approved` and `replaced`.

**Formats:** settings version 2 (`journals: "all" | [ids]`). Version 1 still opens, and the next change writes version 2.

**Migration:**

- An EF migration adds `AgentGrants.Revision`, with 1 for existing grants, which keep working.
- Waiting requests live in memory and disappear when the server restarts with the update.
- Local connections are removed on first launch (section 8).

## 12. Tests (AGENTS.md: meaningful behavior only)

**Server** (`server/tests/Journal.Api.Tests/AgentApprovalTests.cs`, plus changes in `AgentAccessTests.cs` and `AgentFlow.cs`):

1. **The number decides; a wrong number or Don’t Allow sends the page back.**
   - Devices never receive the number, and the request row carries its return host.
   - A wrong number returns `409`, ends the request (the right number can't follow), grants nothing, and the page redirects with `access_denied`, `state` and `iss`.
   - **Don’t Allow** does the same.
2. **Retries and strangers.**
   - A retry from the same client and address replaces the waiting request.
   - The same shared client ID from another address replaces nothing, and neither request is offered as a reconnect of the connected agent, which keeps working.
3. **Narrowing and revisions.**
   - After a change with the journal's item removed, `list_journals`, `search_entries` and `read_entry` hide that journal while its entry items are still stored.
   - Uploads and changes without a revision are refused, and ones with an old revision return `409`.
   - The change is sent as the app sends it, with no `expiresAt` field.
4. **The page reports `approved` at once.** Without `ready`, the code is released after 15 seconds, and an unredeemed approval leaves no grant (`AnApprovalWhoseCodeIsNeverRedeemedLeavesNoGrant`).
5. **Revoking a connecting agent declines its page with a redirect** (existing test).
6. **A signed-out agent reconnects to the same grant.** The request is offered as a reconnect of that agent, and the approval is sent as the app sends it, without `metadata`. The agent then reads its old copy again.

**JournalCore** (`AgentCopyTests.swift`):

- Settings version 1 opens. Version 2 round-trips with All Journals and with unknown journal IDs kept.
- All Journals follows journals created, renamed and deleted later.
- Embedded image data is left out of what agents read (moved from the local-connection tests).
- The existing tests of settled-only publishing, deleted journals and the fixture still pass.

**iOS UI test** (`AgentAccessUITests.testAllowAgentByNumberThenChangeJournalsAndRevoke`):

- A request appears on its own. A wrong number shows **Numbers Don’t Match**, and the page reports `declined`.
- The next request, with its number and **All Journals**, closes the sheet and shows "Connecting…".
- The detail switches to one selected journal, and the list reflects it.
- Revoking returns the page to the agent.

**End to end:** the `test-sync.sh` probe approves by number. The MCP Inspector and conformance runs are unchanged.

## 13. Owner decisions

- **Q1. Number entry:** type the two digits. This was a security requirement from the review, overriding the earlier "choose one of three".
- **Q2. "Open My Journal" link:** not now.
- **Q3. Compatibility with earlier builds:** none.
- **All Journals:** added at the owner's request, including journals created later.
- **Agents on This Mac:** removed.

## 14. Reviews

**Independent design review (revision 1): APPROVED WITH REQUIRED CHANGES.** The reviewer confirmed the step count falls from about 16 interactions to 6–7. Required changes, all addressed in revision 2:

1. Type the two digits instead of choosing one of three, because a remote party can present Claude Code's shared metadata URL with a loopback redirect. The number is never sent to devices, iOS uses the number pad, and a wrong entry declines.
2. Treat client names as attacker-controlled: cap them at about 40 characters on one line, strip control and bidi characters, show the redirect host in every request row and at primary weight in the sheet, and keep the "Returns to" line and loopback warning for reconnects.
3. Declining, a wrong number and revoking a connecting agent must redirect with `access_denied`, `state` and `iss`, with "Access wasn’t allowed. Returning to ‹client›…". Replacement needs no redirect.
4. Correct section 8's facts about This Mac's server and state the gaps.
5. Enforce narrowing by emptying the removed journals' items in the same transaction as the revision bump, instead of a new scope format.
6. Make `revision` mandatory on uploads and changes.
7. Load requests at once when the pane appears and when the app becomes active.
8. Make dismissal consistent: no swipe-to-dismiss on iPhone, Escape means Don't Allow on the Mac.
9. With All Journals on, the detail shows the journals it currently includes.
10. Copy changes to the page, the request row, the Number section, the needs-reconnect text and **Request Ended**.
11. Test changes: drop the three-choices test and the scope-format test; add tests for a stranger with the same client ID, a narrowed journal invisible while stored, an upload without a revision, and declining with a redirect.

Optional suggestions adopted:

- the All Journals / Selected Journals picker;
- "Claude Code 2" for a second agent of the same client;
- the server-exposure sentence moved to the Connect an Agent footer;
- the proxy limitation of request replacement, documented in section 4.3.

The owner accepted the defaults and asked for a UI audit after implementation (section 15).

## 15. Implementation check and UI audit

**Implemented:** server, JournalCore, and the app on iPhone, iPad and Mac, per this revision. The owner asked for an audit because the old flow "looked much more complicated than it had to".

**Screens captured:**

- **iPhone**, via a temporary UI test on a disposable server:
  - light mode;
  - dark mode at the largest accessibility text size;
  - with no server (both appearances).

  They covered the request row, the empty sheet, a wrong number, Numbers Don't Match, Selected and All Journals, Connecting…, the detail (All Journals, a selected journal, the bottom), Recent Activity, Needs to reconnect with a waiting reconnect request, the reconnect sheet, and the revoke confirmation. VoiceOver labels came from accessibility dumps.
- **Mac**, via a team-signed build: the Agent Access tab with no server and with a server, the request row, the Allow Access sheet (number, Selected Journals, Allow, Don't Allow), the agent detail and Recent Activity.
- **The authorization page** in a browser: waiting, and replaced.

The screenshots aren't kept.

**Found and changed:**

1. **Reconnecting failed** with "Couldn’t allow access". The app leaves `metadata` out for a reconnect, and the server's binding required the field; the same was true before this revision. `metadata` and `PUT`'s optional fields now default to null, and a server test sends both requests exactly as the app does.
2. **On the Mac, the request row couldn't be activated through accessibility** (AXPress, and so VoiceOver), because a combined accessibility element replaced the button. The button now keeps its own label.
3. **The sheet's first section read as three list rows.** It's now one cell: a headline, "Returns to …" at primary weight, and the secondary lines.
4. **The number field needed clearer labelling.**
   - On iPhone, a prompt of "00" didn't say what to enter, and the monospaced placeholder looked odd. The prompt is now "Number Shown on the Page" in the body font.
   - On the Mac, where the label already shows, the prompt is gone.
   - The iOS keyboard now closes after two digits, because it covered the journal choice.
5. **The journals footer sat between the choice and the journal rows.** It now comes after the rows.
6. **Name in the detail** looked like static text on iPhone. It now has a "Name" header on iPhone; the Mac, which labels the field itself, has no header.
7. **Text was cut off at the largest sizes.** The request row's host and time, and agent names in the list, now wrap at accessibility text sizes.
8. **Requests appeared only after the next 3-second poll** when the pane opened while My Journal was in the background (the Mac Settings window). The pane now loads requests as soon as it appears, and reloads the agents list when a new request arrives, so "Needs to reconnect" is current.

**Checked and kept:**

- The pane shows only the sections it needs.
- **Don’t Allow** and **Allow** are the only ways out of the sheet.
- The revoke confirmation is the system popover (iOS 26).
- Status uses both a symbol and text.
- The sheet title truncates ("Allow Acce…") at the largest size, which is system behavior.

**Not verified:**

- Escape as **Don’t Allow** on the Mac: the automation used accessibility actions, not a real keystroke.
- The Mac revoke confirmation. It's the same code as on iOS.
- The iPad layout, which is the iPhone form in a form sheet.

**Leftovers:**

- The App Store Mac screenshot `04-insights.jpg` (used in README.md) shows the removed local connection and needs a new capture through a server.
- The app group entitlement now serves only the cleanup of old connection files. Removing it is a separate signing change.

## 16. Security review of revision 2

**Outcome.** An independent security review found no critical defects. It confirmed:

- exact redirect matching;
- PKCE S256;
- resource and audience binding;
- revoking the token family when a code is reused;
- detecting refresh-token reuse;
- one guess per number;
- mandatory revisions;
- tool scoping;
- the migration defaults;
- the scope of `LocalAgentCleanup`.

**Findings and fixes.** Each fix has a test that would fail if the behaviour broke.

1. **Narrowing missed journals this device doesn't know.** For example, the Mac shares "Therapy" under All Journals, and an iPhone that hasn't synced it yet narrows to Selected.
   - Narrowing now empties the item of every chosen journal that is no longer chosen, whether or not this device has it.
   - Leaving All Journals reads the copy's manifest and empties everything that isn't a still-shared journal or an entry this device knows in one. Over-removed entries are published again from version 0 by the devices that have them.
   - Test: `AgentCopyNarrowing`.
2. **A failed exchange left a grant "Connecting…" forever.** When the code was redeemed but the exchange failed (wrong verifier or client), the grant stayed pending. The sweep now deletes it when its request expires, and only grants still pending are ever deleted.
3. **Look-alike hosts.** "Returns to" and "Identified as" now show an internationalized host in its punycode form.
4. **Flooding.**
   - When the waiting list is full, eviction starts with the address (or IPv6 /64) that has the most waiting requests.
   - Opened requests are never evicted.
   - Numbers of kept, replaced and evicted requests aren't reused until those requests would have expired.
   - With all 90 numbers in use, new requests are refused for now.
5. **The server didn't check reconnects.** A reconnect now requires the same client ID and no live refresh token, and it updates the agent's client name and return host.
6. **Resources.**
   - `read_entry` reads only the entry's item and its journal's item.
   - Search decrypts the copy once, one item at a time, and keeps only the date and ID of the offset + limit newest matches; it then reads the page's entries again for their excerpts, from at most 16,000 UTF-16 units of each.
   - Status polling with a handle the server doesn't know is limited per client address.
7. **Origin policy.** A tokenless request from a browser client on an https origin, or a loopback http origin, now gets the 401 challenge with CORS, so browser clients can start OAuth. The `null` origin and other http origins still get 403, and the Host check is unchanged.
8. **Display names.** Tests pin the stripping of control, bidi and formatting characters, folding to one line, and the 40-character cap in both implementations. The tests found that line breaks were being removed rather than turned into spaces ("Claude\nCode" became "ClaudeCode"); that is fixed on both sides.
