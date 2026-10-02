# Owner decisions — 1 October 2026

Answers to the open questions after the red-team and real-user passes.

1. **Showing what changed between versions** (Review Changes, Version History): later. Versions stay shown one at a time, without diff highlighting or device names, for now.
2. **Automatic links for typed web and email addresses:** no. Typed addresses stay plain text; links are added with Add Link (which accepts plain addresses such as `name@example.com` and `www.apple.com`).
3. **Change Date on iPhone:** move Cancel and Save to the navigation bar, as iOS sheets do.
4. **Default Journal setting:** per device, not synced.
5. **Kept as they are:**
   - Empty entries the owner creates are kept, synced, and visible to agents as empty entries.
   - An agent limited to a journal sees new entries written into that journal.
6. **Pasting formatted text:** keep lists, headings, quotes and code, but only if it works without glitches. It is checked against common sources, with screenshots, before it ships.
