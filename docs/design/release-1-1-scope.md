# Release 1.1 scope — 2026-10-07

Status: owner-approved scope, not yet designed or built. Each user-visible change below still goes through the design gate in [AGENTS.md](../../AGENTS.md) before implementation, and the spec changes with the code ([spec/README.md](../../spec/README.md)). Open questions that a change makes moot say “Superseded in 1.1 by simplification X” in [spec/open-questions.md](../../spec/open-questions.md).

## Simplifications

The owner approved all of these on 2026-10-07, to reduce complexity for people and in the code before the Windows and Android clients rebuild every screen.

| | Change |
| --- | --- |
| A | Remove dead code. |
| B | Replace the ~26 “save before …” messages with two. |
| C | Every “this version is too old” state says “Update My Journal”. |
| D | Remove migrations for TestFlight builds older than 16. |
| E | Settings goes from six tabs to four or five: Devices moves into Sync, Writing into General. |
| F | Simpler timing for the rating request. |
| G | Every library is encrypted: Continue Without Encryption and Turn On Encryption go away. This reverses the earlier onboarding decision. |
| H | Conflicts resolve themselves by keeping both versions, in two steps: first the journal and deletion review forms go, then entries keep both versions automatically. |
| I | One Reconnect action. |
| J | Check Your Password and Forgot Password fold into Change Password. |
| K | No journal-level version history. |
| L | No journal Merge Into…. |
| M | One way to start from a template: the per-journal default template and New Entry In go. |
| N | Recently Deleted offers plain Restore only. |
| O | Server cleanup: capability flags become a version, unused endpoints and LAN discovery go, one setup path. Check the MCP agent access first. |

Not doing: polling instead of instant sync, and dropping in-place table editing.

## Also in 1.1

- **Single-file archive.** The archive becomes one file (zip-based `.journalarchive`) with a new version of [protocol/archive.md](../../protocol/archive.md) and conformance fixtures, built on the Apple side first; the Apple app keeps reading the directory format. Answers open question D29; the Windows client builds on it directly.
- **iPhone Duo support**, with the iOS deployment target moving from 16 to 17.
- **Conformance fixes** found by the fixtures in [protocol/conformance/](../../protocol/conformance/).
- Owner decisions of 2026-10-09 that change behaviour ([spec/open-questions.md](../../spec/open-questions.md)): one formatting rule for all five inline styles (D5), Return in the middle of a heading makes two headings (D6), one list and order of table commands on every device (D7), and a message when Don't Allow can't reach the server (D55). Each goes through the design gate.
- The bugs and copy fixes still open in [spec/open-questions.md](../../spec/open-questions.md) sections A and B.
