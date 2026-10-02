# Initial concept review

Date: 2026-09-20  
Reviewer: independent design agent  
Scope: supplied concept and project requirements; no implemented UI inspected.

## Outcome

The two-pane timeline and editor, journal selector, system appearance, and editable template content form a suitable native macOS starting point. The concept is **not ready for implementation**. Concrete screen designs and the decisions below need review first. This review does not approve UI implementation.

## Material findings and required decisions

1. **Clarify what collapses.** The proposal alternates between an entry list and a sidebar. Treat the left pane as the journal selector, search, and entry list; do not quietly introduce a third navigation pane. Specify its minimum width, resizing, collapse behavior, and how users change journals or search when it is hidden. Put New Entry in the window toolbar and File menu so it remains available. Use the standard sidebar toggle and preserve selection when toggling.

2. **Keep editor typography conventional.** A centered, readable-width writing column is sensible; centered paragraph text is not a suitable default. Specify a left-aligned optional title and body, a date display, width behavior, and focus after creating an entry. Decide whether titleless rows use a body preview or “Untitled,” and how empty drafts are retained without silently discarding intentional content. Define creation date versus journal date and the chronological sort order.

3. **Make journal scope explicit.** Specify whether search covers the selected journal or all journals, including how scope is announced. A selected-journal default is simpler. Define journal creation, renaming, switching, and entry movement without losing edits. Personal and Work should be editable names, not permanent product categories. Include “New Journal…” and “Rename Journal…” where applicable.

4. **Define the editing surface.** A generic Formatting button does not establish usable rich text. Specify a native Format menu, a compact formatting popover, familiar keyboard commands, selection behavior, and undo/redo. Define heading levels, bullet and numbered lists, emphasis, links, and image insertion through paste, drag, and “Insert Image…”. Specify image selection, resizing if supported, removal, accessible descriptions, and missing-image behavior. Respect macOS spelling, substitutions, and correction settings. Preserve unsupported content visibly instead of removing it during edits.

5. **Separate local save failure from delayed sync.** Continuous pending indicators could create unnecessary visual activity. Keep successful saving quiet. Reserve an unobtrusive status for actionable or prolonged pending states, with details on request. Proposed copy: “Saved on this Mac. Waiting to sync.” for a durable local copy; “Couldn’t sync. Your changes are saved on this Mac.” with “Try Again”; and “Couldn’t save changes on this Mac.” for a local failure. The last case requires recovery actions that remain available while edits are retained in memory. Do not claim local durability before it is confirmed. Offline writing must remain usable.

6. **Design conflict resolution before implementing sync UI.** Specify how users discover a conflict, identify versions by device and date, compare them, retain both, or explicitly choose one. Suggested entry notice: “This entry has changes from another device.” and “Review Changes”. Make “Keep Both” a clear option; preview the result of any merge. Avoid a technical “Conflict” badge as the only explanation. Define behavior if another edit arrives during review and how retained originals can be recovered.

7. **Separate getting started from server administration.** “Set up on this Mac” does not clearly say whether a server is required. Prefer “Start a Journal” and “Connect to a Server…” with short supporting copy: “Write on this Mac. You can set up sync later.” Confirm that this is true of the implementation. The connection flow needs explicit server address, connection verification, authentication, recovery-key requirements, and recoverable failure states. Clarify that connecting cannot replace existing local entries without an explicit migration or reconciliation choice.

8. **Resolve protection and recovery language.** A local unlock code and recovery passphrase must have distinct names, purposes, and flows. Prefer platform authentication where supported. Define behavior without Touch ID, after failed authentication, after forgetting each credential, and when restoring on a new device. Explain the actual recovery consequence in plain language before setup is completed; do not suggest a short PIN can restore encrypted journals. Decide how users verify and safely retain recovery material before finalizing this screen.

9. **Keep templates optional and safe to apply.** Start every journal with a normal blank-entry action. Use “New Entry from Template…” as an additional command. Template text becomes ordinary editable content, with undo for insertion. Decide whether applying a template to an existing entry inserts at the cursor, appends, or is unavailable; never replace writing silently. Define template editing, naming, and deletion separately from journal content.

## Required states and accessibility details in the next proposal

- Empty journal: “No Entries” and “New Entry”; no forced template or tutorial. No selection: “Select an Entry”. Search with no matches: “No Results”, with a clear-search action.
- Loading or restoring: name the operation; preserve readable cached content when possible. Specify locked, offline, connection failure, local storage failure, missing attachment, and conflict states individually.
- Destructive actions: define recovery through Recently Deleted or an equivalent design; distinguish deleting an entry, journal, template, and local server connection.
- Keyboard: menu equivalents for all actions, expected search and new-entry shortcuts, visible focus, predictable navigation between list and editor, and no focus theft from save or sync events.
- VoiceOver: meaningful row summaries, current journal and search scope, labeled icon controls, editor structure, image descriptions, and restrained announcements for actionable failures.
- Appearance: system colors and native controls; verify light/dark mode, increased contrast, reduced transparency, reduced motion, supported text sizing, long titles, and narrow windows. Avoid color-only status distinctions and fixed-height rows that clip larger text.

## Next review gate

Submit concrete main-window, first-run, connection/recovery, template, and conflict designs with exact copy and interactions. Address the findings above and identify deferred features explicitly. Review substantial revisions independently before implementation, then inspect the actual macOS UI against the reviewed design.
