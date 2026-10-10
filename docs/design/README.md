# Design records

Every interface change starts with a written design and an independent review (see [CONTRIBUTING.md](../../CONTRIBUTING.md)). This folder keeps those designs and reviews. They are a history: later records change earlier ones, and some describe features that were removed. Use this index to find the record that describes today's behavior.

When records disagree, the newer one applies. [owner-decisions-2026-09-25.md](owner-decisions-2026-09-25.md) is the most recent owner decision across the whole app, and [pre-release-fixes-2026-09-27.md](pre-release-fixes-2026-09-27.md) records the changes made since then as bug fixes. Protocol and storage contracts live in [protocol/](../../protocol/README.md), not here.

Evidence records cite screenshots, logs and result bundles from local runs. Those files are not in the repository.

Most records were written with AI agents. In reviews, "the parent" usually means the agent that wrote the design and implemented it, and "CUA" means computer-use automation. "The user" means either the person using the app or the project owner who asked for a change.

## Status

- **Current**: describes the app as it is.
- **Current, amended**: still applies, except for the parts a later record changed.
- **Superseded**: replaced by the named record.
- **Removed feature**: the feature no longer exists.
- **Evidence**: an acceptance check or audit of a specific build. It explains a decision but does not define behavior.

A design and its reviews share one row.

## App structure and navigation

| Record | Status |
| --- | --- |
| [initial-review.md](initial-review.md) | Superseded. Review of the first concept. |
| [screens.md](screens.md), [screens-review.md](screens-review.md) | Superseded. The original interface baseline; navigation, editor and Settings were replaced by the records below. |
| [native-source-review.md](native-source-review.md) | Superseded. Source review of the first implementation. |
| [notes-navigation-refinement.md](notes-navigation-refinement.md), [review](notes-navigation-refinement-review.md) | Superseded by notes-alignment-revision.md. Its three-column Mac layout remains. |
| [testing-feedback-revision.md](testing-feedback-revision.md), [review](testing-feedback-revision-review.md) | Superseded by markdown-writing-revision.md and notes-alignment-revision.md. |
| [markdown-writing-revision.md](markdown-writing-revision.md), [review](markdown-writing-revision-review.md) | Current, amended. Onboarding (master password or Continue Without Encryption) applies; the source-only fallback and Format Text command picker were replaced by notes-alignment-revision.md. |
| [notes-alignment-audit.md](notes-alignment-audit.md) | Evidence. Audit that led to notes-alignment-revision.md. |
| [notes-alignment-revision.md](notes-alignment-revision.md), [review](notes-alignment-revision-review.md) | Current, amended by feedback-stabilization-2026-09-23.md and owner-decisions-2026-09-25.md. |
| [feedback-stabilization-2026-09-23.md](feedback-stabilization-2026-09-23.md), [review](feedback-stabilization-2026-09-23-review.md) | Current, amended by owner-decisions-2026-09-25.md. |
| [owner-decisions-2026-09-25.md](owner-decisions-2026-09-25.md), [review](owner-decisions-2026-09-25-review.md) | Current, amended. §5 (discarding untouched new entries) was reversed by new-entry-template-suggestion.md. Delete and Recently Deleted, removal of Archive and Export Entry, Insert Image, Markdown as you type, menus, keyboard and Settings. |
| [pre-release-fixes-2026-09-27.md](pre-release-fixes-2026-09-27.md) | Current. Changes made as bug fixes (connection, sync messages, App Lock cover, search, Move Entry, agent access, image descriptions), their design review, unreviewed editor changes and open owner decisions. |
| [pre-release-ui-2026-09-27.md](pre-release-ui-2026-09-27.md) | Current. Deleted templates in Recently Deleted, the template sheet, Backspace in lists, the iPhone Format sheet, Search Entries ⌥⌘F, Devices, the new device’s check code, the one-time password check and Forgot Password?, and the Delete Permanently alert. Supersedes owner-decisions-2026-09-25.md §6 and the §1 alert message, and decides pre-release-fixes items (a) and (e). |
| [default-journal.md](default-journal.md) | Current, amended by template-journal-choice-2026-10-03.md (templates started from the Templates list) and 1-1-library-simplifications.md (M). Settings ▸ Default Journal, and New Entry outside a journal (Recently Deleted, Templates, All Entries, the iPhone Journals screen). Replaces the default-journal rule of feedback-stabilization-2026-09-23.md and the "Which journal" rule of new-entry-template-suggestion.md. New Entry is always an empty entry in the shown journal, else the Default Journal; the per-journal default template is gone. |
| [recently-deleted-2026-09-30.md](recently-deleted-2026-09-30.md) | Current, amended by ios-delete-all-and-settings-2026-10-03.md (the Recently Deleted swipe is destructive again; Cancel brings the row back). The footer check. |
| [ios-delete-all-and-settings-2026-10-03.md](ios-delete-all-and-settings-2026-10-03.md) | Current. Deletion motion on iOS, Delete All in Recently Deleted (iPhone, iPad, and the Mac in §4: a header in the list and File ▸ Delete All in Recently Deleted… ⇧⌘⌫), Settings at the top left of Journals on iPhone. Includes its reviews. |
| [device-orientations.md](device-orientations.md), [review](device-orientations-review.md) | Current, amended. The constrained iOS header was replaced by unified-entry-scrolling.md. |
| [unified-entry-scrolling.md](unified-entry-scrolling.md), [review](unified-entry-scrolling-review.md) | Current. |
| [typing-scroll.md](typing-scroll.md), [review](typing-scroll-review.md) | Current. Scrolling while typing on iPhone and iPad: the writing controls' area is the entry's bottom inset and the text view follows the caret, as in Notes. |
| [entry-title-accessibility.md](entry-title-accessibility.md), [review](entry-title-accessibility-review.md) | Current, amended. The header layout was replaced by unified-entry-scrolling.md. |
| [mac-live-acceptance.md](mac-live-acceptance.md), [review](mac-live-acceptance-review.md) | Evidence. Live Mac checks of a 2026-09-21 build. |
| [mac-settings-navigation-review.md](mac-settings-navigation-review.md) | Evidence. The Settings window was later redesigned (owner-decisions-2026-09-25.md §9). |
| [about-and-ratings-2026-10-05.md](about-and-ratings-2026-10-05.md) | Current. Settings ▸ About on iPhone and iPad (Privacy Policy, Support, Source Code, Rate My Journal, the version), the Help menu on the Mac and iPad, the system rating request's timing rules, and Use This Mac… disabled on Intel Macs. Includes its review. Amended by client-only-mac-lists-markdown-2026-10-05.md: §4 (Intel Macs) no longer applies, because the Mac app has no server. |
| [1-1-encryption-and-passwords.md](1-1-encryption-and-passwords.md) | Design for 1.1, two independent reviews passed. C "Update My Journal" and D migration floor are built (1.1 phase 1); G every library encrypted (with Not Now only where encryption can't succeed) and J Change Password are built (1.1 phase 5). Owner decisions of 2026-10-09: G confirmed as recommended, and no minimum length for new master passwords. Amends enable-encryption.md, connection-onboarding.md (the Protect step), the onboarding part of markdown-writing-revision.md and the password check in pre-release-ui-2026-09-27.md. Superseded in part by the owner decision of 2026-10-10 at its end: 1.1 supports no unencrypted libraries, so the Encrypt Your Journals screen and everything that served it are removed. |
| [1-1-conflicts-and-reconnect.md](1-1-conflicts-and-reconnect.md) | Design for 1.1, includes its two independent reviews. I one Reconnect action is built (1.1 phase 3). H conflicts keep both versions, in two steps, both built: step 1 (journals and permanent deletions settle themselves; Settings ▸ Sync ▸ Changed on Two Devices) in 1.1 phase 4; step 2 (entries and templates that differ keep this device's version and save the other as a separate item titled “… (other version)”; a notice above the open entry with Show Other Version and Dismiss; the Review Changes sheet, the list marker and Changes to Review removed; the opening pass also settles what 1.0 left in its review) after phase 6. The spec pages are flows/resolve-conflict.md and screens/kept-version-notice.md. Amends journal-conflicts.md, permanent-deletion.md and stale-conflict-recovery.md. |
| [1-1-library-simplifications.md](1-1-library-simplifications.md) | Design for 1.1, includes its two independent reviews and the owner decisions of 2026-10-09. K, L, M and N are built (1.1 phase 4): no journal Version History, no Merge Into… (Rename and Move Entry… instead), no default template per journal (a template is used from inside a new entry), plain Restore. Amends history-recovery.md, journal-name-uniqueness.md, journal-lifecycle-ui.md, new-entry-template-suggestion.md, template-journal-choice-2026-10-03.md, default-journal.md and no-built-in-templates-2026-10-04.md. |
| [1-1-settings-messages-editor.md](1-1-settings-messages-editor.md) | Design for 1.1, independent review passed. B save messages, F rating request and A dead code (the confirmed items) are built (1.1 phase 1); D5–D7 editor rules and D55 are built (phase 2); E Settings panes (five panes, Devices in Sync) is built (phase 3). |
| [1-1-server-cleanup.md](1-1-server-cleanup.md) | Design for 1.1, independent review passed (not built yet). O: protocol revision, no LAN discovery, one setup path. |
| [1-1-archive-v2.md](1-1-archive-v2.md) | Design for 1.1, two independent reviews passed (not built yet). The single-file archive, after a file-type spike. |
| [release-1-1-scope.md](release-1-1-scope.md) | Owner-approved scope for 1.1 (2026-10-07), not designed or built yet: simplifications A to O, the single-file archive, iPhone Duo and iOS 17. |
| [build-18-fixes-2026-10-06.md](build-18-fixes-2026-10-06.md) | Current. Built in build 18. Bug fixes after build 17 (save-failure alerts, Sync Status after unlock, Review Changes when deleting, plain error messages, menu and copy corrections) and four designed changes: the screen for a library that can't be opened and protection of an unreadable configuration file, agent access with no journals chosen, Return in an empty quote, and editing and removing links. Records three owner decisions: Export Archive asks for device authentication without encryption, Back from Merge Journals revokes the grant, and the Mac's Add Device code hides only in the background. |

## Writing and templates

| Record | Status |
| --- | --- |
| [native-undo-binding.md](native-undo-binding.md), [review](native-undo-binding-review.md) | Current. |
| [paragraph-identity-recovery.md](paragraph-identity-recovery.md), [review](paragraph-identity-recovery-review.md) | Current. |
| [template-initial-insertion.md](template-initial-insertion.md), [review](template-initial-insertion-review.md) | Current. |
| [writing-workflow-review.md](writing-workflow-review.md) | Evidence. Led to template-initial-insertion.md. |
| [template-setup-review.md](template-setup-review.md) | Evidence. |
| [new-entry-template-suggestion.md](new-entry-template-suggestion.md) | Current (reviewed; review outcome recorded in the record). One New Entry button; “Use a Template…” in a fresh entry opens the chooser and fills the entry in place. Supersedes the Templates… button in mac-window-appkit.md §3 and feedback-stabilization-2026-09-23.md §3. Amended by 1-1-library-simplifications.md (M): File ▸ Use a Template… is added; File ▸ New Blank Entry and File ▸ New Entry from Template… are gone. |
| [new-entry-button-options.md](new-entry-button-options.md) | Evidence. Research and prototypes for folding Templates… into New Entry; the owner chose option D. |
| [title-paste-workflow-review.md](title-paste-workflow-review.md) | Evidence. |
| [pasted-text.md](pasted-text.md), [review](pasted-text-review.md) | Current. Text pasted from other apps (owner-decisions-2026-10-01.md §6). |
| [checklists-2026-10-03.md](checklists-2026-10-03.md) | Current, amended by list-markers-2026-10-03.md (no hidden marker characters). Checklist (was Task List): square checkboxes on iPhone and iPad, one list column for every kind of list that grows with the text, nested items under their parent's text, Mark as Checked / Mark as Unchecked. Includes its review. |
| [editor-fixes-2026-10-04.md](editor-fixes-2026-10-04.md) | Current. Bug fixes after build 14: a new list item no longer jumps when its first letter is typed, Markdown shortcuts typed on the iPhone keyboard convert reliably, Mac checkboxes stay in place while scrolling. |
| [mac-typing-room-2026-10-04.md](mac-typing-room-2026-10-04.md) | Current. Room below the line being typed on the Mac (two lines, the scroll view's bottom inset), and the caret revealed after the editor's own edits. Includes its review. |
| [list-markers-2026-10-03.md](list-markers-2026-10-03.md) | Current. List, checklist and quote markers are drawn, not stored: the text holds only what the person wrote, so the keyboard capitalizes new items. Why the editor stays on TextKit 1, the own end of a final item, and the visible differences. Includes its reviews. |
| [list-indentation-2026-10-04.md](list-indentation-2026-10-04.md) | Current. Increase and Decrease Indent for list items only, kept as Markdown reads them (no indent on a list's first item, at most one level below the item above, subtrees move, numbered lists renumber); the Format panel always shows both buttons, dimmed where they don't apply, and stays open; the empty line after a list is a plain line. Includes its review. Amended by client-only-mac-lists-markdown-2026-10-05.md §2: lists start 18 points in from the body text, aligned with quotes. |
| [save-failure-retry.md](save-failure-retry.md), [review](save-failure-retry-review.md) | Current, amended. The Export Entry option was removed (owner-decisions-2026-09-25.md §2). |
| [unsaved-draft-export-review.md](unsaved-draft-export-review.md) | Removed feature (Export Entry). |

## Images

| Record | Status |
| --- | --- |
| [document-image-loading.md](document-image-loading.md), [review](document-image-loading-review.md) | Current. |
| [image-insertion-ownership.md](image-insertion-ownership.md), [review](image-insertion-ownership-review.md) | Current. |
| [imported-image-type.md](imported-image-type.md), [review](imported-image-type-review.md) | Current. |
| [image-block-spacing.md](image-block-spacing.md), [review](image-block-spacing-review.md) | Current. |
| [image-descriptions.md](image-descriptions.md), [review](image-descriptions-review.md), [implementation review](image-descriptions-implementation-review.md) | Current. |
| [image-description-keyboard.md](image-description-keyboard.md), [review](image-description-keyboard-review.md) | Superseded by image-description-native-form.md. |
| [image-description-native-form.md](image-description-native-form.md), [review](image-description-native-form-review.md) | Current, amended. Descriptions are one line; Return moves to the next (pre-release-fixes-2026-09-27.md). |
| [several-photos-2026-10-03.md](several-photos-2026-10-03.md) | Current. Insert Image takes several photos or files at once, in the order chosen, with a progress notice, Stop and one undo step. Includes its reviews. |
| [image-actions-ios-2026-10-03.md](image-actions-ios-2026-10-03.md) | Current. Long press on a picture on iPhone and iPad: Copy, Share…, Save to Photos, Image Descriptions…, Delete; VoiceOver actions. Includes its review. |
| [image-actions-mac-2026-10-03.md](image-actions-mac-2026-10-03.md) | Current. Right-click on a picture on the Mac: Cut, Copy, Paste, Share…, Save Image As…, Image Descriptions…, Delete; Copy, Cut and dragging hand other apps the original; VoiceOver actions. Includes its reviews. |

## Journals, deletion and history

| Record | Status |
| --- | --- |
| [move-entry.md](move-entry.md), [review](move-entry-review.md), [implementation review](move-entry-implementation-review.md) | Current, amended. The explanation for journals with the same name changed (pre-release-fixes-2026-09-27.md). |
| [journal-conflicts.md](journal-conflicts.md), [review](journal-conflicts-review.md), [implementation review](journal-conflicts-implementation-review.md) | Current, amended by 1-1-conflicts-and-reconnect.md (H): a journal conflict is settled by the device, keeping both versions, with no review form. |
| [journal-deletion.md](journal-deletion.md), [review](journal-deletion-review.md) | Superseded by journal-lifecycle-ui.md. |
| [journal-lifecycle-proposal.md](journal-lifecycle-proposal.md), [review](journal-lifecycle-review.md) | Current. Implemented as [protocol/journal-lifecycle.md](../../protocol/journal-lifecycle.md). |
| [journal-lifecycle-ui.md](journal-lifecycle-ui.md), [review](journal-lifecycle-ui-review.md), [implementation review](journal-lifecycle-ui-implementation-review.md), [navigation implementation review](journal-navigation-implementation-review.md) | Current, amended. Delete confirmations are standard alerts (owner-decisions-2026-09-25.md §1). Amended by 1-1-library-simplifications.md (N, L): Restore acts at once with no sheet and names the Default Journal when an entry's journal is gone, Restore and Move and Merge Into… are gone, and a journal has no Version History. |
| [large-text-recovery.md](large-text-recovery.md), [review](large-text-recovery-review.md) | Current. |
| [permanent-deletion.md](permanent-deletion.md), [review](permanent-deletion-review.md) | Current, amended. The review sheet was replaced by a standard alert (owner-decisions-2026-09-25.md §1). Semantics: [protocol/permanent-deletion.md](../../protocol/permanent-deletion.md). Amended by 1-1-conflicts-and-reconnect.md (H): an item deleted permanently on one device and changed on another stays deleted, and the changed version is saved separately in Recently Deleted; the Keep Deletion and Keep Entry choices are gone. |
| [history-recovery.md](history-recovery.md), [review](history-recovery-review.md), [implementation review](history-recovery-implementation-review.md) | Current, amended by 1-1-library-simplifications.md (K): a journal has no Version History or Restore Settings; entries and templates keep theirs. |
| [version-checkpoints.md](version-checkpoints.md) | Current. Storage behavior only; the Version History interface is unchanged. |
| [entry-archiving.md](entry-archiving.md), [review](entry-archiving-review.md) | Removed feature (Archive and the Archived collection, owner-decisions-2026-09-25.md §1). The stored field is kept for compatibility. |

## Conflicts

| Record | Status |
| --- | --- |
| [entry-conflict-accessibility.md](entry-conflict-accessibility.md), [review](entry-conflict-accessibility-review.md) | Current. |
| [stale-conflict-recovery.md](stale-conflict-recovery.md), [review](stale-conflict-recovery-review.md) | Current, amended by 1-1-conflicts-and-reconnect.md (H): journal and permanent-deletion conflicts are settled by the device and no longer reach a review, so it applies to entries and templates only. |
| [already-resolved-conflict-review.md](already-resolved-conflict-review.md) | Evidence. |
| [conflict-refresh-failure-review.md](conflict-refresh-failure-review.md) | Evidence. |
| [conflict-background-lock-review.md](conflict-background-lock-review.md) | Evidence. |
| [unsupported-conflict-review.md](unsupported-conflict-review.md) | Evidence. |
| [changed-format-acceptance.md](changed-format-acceptance.md) | Evidence. |

## Backup archives and export

| Record | Status |
| --- | --- |
| [archives.md](archives.md), [review](archives-review.md), [implementation review](archives-implementation-review.md) | Current, amended. Export Archive and Import Archive are now in Settings > Backup (owner-decisions-2026-09-25.md §9); the entry export parts were removed (§2). |
| [archive-actions-accessibility.md](archive-actions-accessibility.md), [review](archive-actions-accessibility-review.md) | Current. |
| [archive-preview-lifecycle.md](archive-preview-lifecycle.md), [review](archive-preview-lifecycle-review.md) | Current. |
| [export-operation-lifetime.md](export-operation-lifetime.md), [review](export-operation-lifetime-review.md) | Current for archive export and inspection; the entry export parts were removed. |
| [entry-export-accessibility.md](entry-export-accessibility.md), [review](entry-export-accessibility-review.md) | Removed feature (Export Entry). |
| [readable-export-fidelity.md](readable-export-fidelity.md), [review](readable-export-fidelity-review.md) | Removed feature (readable entry export). |

## Devices, sync and security

| Record | Status |
| --- | --- |
| [devices.md](devices.md), [review](devices-review.md) | Current, amended by sync-security-2026-09-24.md (pairing check code). |
| [sync-security-2026-09-24.md](sync-security-2026-09-24.md) | Current. Pairing check code and Change Password. |
| [journal-name-uniqueness.md](journal-name-uniqueness.md) | Current. Journal names stay unique: Name Taken for local names, numbers for restore, import, joining and sync, and a repeated join respects deletions. Its review is recorded in the record. Amended 2026-10-09 by 1-1-library-simplifications.md (K, L): §5 (Merge Into…), the earlier-name remedy in Version History and the Merge Journals footer decisions now say Rename; Merge Into… is gone. |
| [join-with-local-journals.md](join-with-local-journals.md) | Current, amended by journal-name-uniqueness.md and no-built-in-templates-2026-10-04.md (template rule 1); amends connection-onboarding.md. A device that already has journals scans or types a server like a new device, then agrees on Merge Journals; same-name journals combine, templates are deduplicated or reviewed, and retries never duplicate. Reviews are recorded in the record. |
| [sync-health-and-recovery.md](sync-health-and-recovery.md) | Current (revision 2, approved by the owner and implemented 2026-10-01; Check Connection left out; §4.2 amended by quiet-sync-and-title-alignment.md). Every sync failure classified into a few states with one action each (Set Up Server Again…, Connect Again…, Sign In…), automatic retries stopped where they can't help, Merge Journals only for a different library (lineage), Stop Syncing in Settings > Sync. |
| [sync-protocol-efficiency.md](sync-protocol-efficiency.md), [review](sync-protocol-efficiency-review.md) | Current (revision 9, approved after nine independent review rounds; implemented 2026-10-02, waiting for a red team before build 10). Short push receipts (`sync-short-receipt`) and waiting for changes instead of polling (`sync-wait`), with the server contract in protocol/README.md. |
| [quiet-sync-and-title-alignment.md](quiet-sync-and-title-alignment.md), [review](quiet-sync-and-title-alignment-review.md) | Current (implemented 2026-10-02). Sync Status shows only when the person must act or after a day of failing, in a toolbar place kept for it on the Mac so nothing moves; the entry title starts exactly where the body text does. |
| [app-lock-system-auth.md](app-lock-system-auth.md) | Current, amended by mac-inactivity-lock-2026-10-03.md (the Mac now locks after inactivity, on sleep and on switching users). App Lock uses only the device's own authentication (Face ID, Touch ID, Optic ID, passcode or Mac login password); the PIN, its sheet and attempt delay are removed and PIN users are migrated. The review outcome is recorded in the record. Since 2026-10-03, locking the iPhone with My Journal open asks for Face ID only once the app is in front again. |
| [mac-inactivity-lock-2026-10-03.md](mac-inactivity-lock-2026-10-03.md) | Current. Settings ▸ Privacy ▸ Lock when inactive on the Mac (30 minutes by default), locking on sleep and on switching users, what counts as use, and saving before locking. The review outcome is recorded in the record. |
| [app-lock-accessibility.md](app-lock-accessibility.md), [review](app-lock-accessibility-review.md) | Current, amended by app-lock-system-auth.md (no PIN field; the scrolling lock-screen layout still applies). The iPhone and iPad privacy cover is in pre-release-fixes-2026-09-27.md. |
| [missing-device-key-unlock.md](missing-device-key-unlock.md), [review](missing-device-key-unlock-review.md) | Current. |
| [erase-device-2026-10-04.md](erase-device-2026-10-04.md) | Current. Erase Journals and Settings…, in a last section of Settings on iPhone and iPad and at the end of General on the Mac (moved out of Privacy after build 15, §11): removes this device's library, Keychain items and configuration and returns to the first screen; the server is only asked to sign this device out. Commit order, interrupted erases, warnings by sync state. Includes its review. Amended by client-only-mac-lists-markdown-2026-10-05.md §1: there is no longer a block for a Mac that runs the server; the old server's files are still kept. |
| [local-server.md](local-server.md), [review](local-server-review.md), [implementation review](local-server-implementation-review.md) | Removed feature (Use This Mac and the server bundled in the Mac app), removed by [client-only-mac-lists-markdown-2026-10-05.md](client-only-mac-lists-markdown-2026-10-05.md) §1. |
| [mac-app-store-sandbox.md](mac-app-store-sandbox.md) | Current, amended (prototype and plan). App Sandbox for the Mac App Store: entitlements, data locations, migration and App Review. No interface change. The bundled server was removed by client-only-mac-lists-markdown-2026-10-05.md §1 and the agent connector by agent-access-simplified.md §8, so the app is the only sandboxed executable. |
| [client-only-mac-lists-markdown-2026-10-05.md](client-only-mac-lists-markdown-2026-10-05.md) | Current. The Mac app is only a client: Use This Mac and the bundled server were removed, Settings ▸ Sync matches iPhone and iPad with How to Set Up a Server, and a Mac still connected to the removed server stops syncing once and keeps the old server's files, even through Erase (§1). Also lists that start 18 points in, aligned with quotes (§2), and Export as Markdown (§3; format in [protocol/markdown-export.md](../../protocol/markdown-export.md)). Includes its two reviews (§5, §6). |

## Agent access

| Record | Status |
| --- | --- |
| [agent-access.md](agent-access.md), [review](agent-access-review.md), [implementation review](agent-access-implementation-review.md) | Removed feature. The Mac-only local connection was removed by agent-access-simplified.md §8. |
| [agent-access-server.md](agent-access-server.md) | Current, amended by agent-access-simplified.md: approval, the Add Agent sheet and the pane's UI (§5.4 approval, §6). Contract: [protocol/agent-access-server.md](../../protocol/agent-access-server.md). |
| [agent-access-simplified.md](agent-access-simplified.md) | Current. Requests appear in the app and are approved with the page's number; All Journals; editing an agent's journals; removal of Agents on This Mac. |

## Website

| Record | Status |
| --- | --- |
| [pinned-entries.md](pinned-entries.md) | Current, built 2026-10-03 (implementation notes in the record). Pinned entries, and the `library` record that syncs pins and journal order. |
| [journal-order.md](journal-order.md) | Current, built 2026-10-03 (prototype outcome and implementation notes in the record); rows keep their height in edit mode since 2026-10-04. Reordering journals: edit mode on iPhone and iPad, drag on the Mac. |
| [mac-list-separators-2026-10-04.md](mac-list-separators-2026-10-04.md) | Current, built 2026-10-04; includes its review. The Mac entries list draws lines between rows only: none under section headers or after a section's last row. |
| [no-built-in-templates-2026-10-04.md](no-built-in-templates-2026-10-04.md) | Current, built 2026-10-04; includes its two reviews. New libraries start without templates; existing ones keep theirs (pending owner confirmation); the empty Templates screen, dimmed Default Template, and the amended merge rule for unedited built-ins. Amends join-with-local-journals.md §2.3 and §2.6. Amended by 1-1-library-simplifications.md (M): the dimmed Default Template in the journal actions no longer exists. |
| [template-journal-choice-2026-10-03.md](template-journal-choice-2026-10-03.md) | Current, built 2026-10-03; includes its reviews; New Entry In ▸ is a plain journal list since 2026-10-04 (owner). New Entry In ▸ a journal from the Templates list, and the Journal picker of File ▸ New Entry from Template… outside a journal. Supersedes the template rules of default-journal.md and new-entry-template-suggestion.md. Amended by 1-1-library-simplifications.md (M): New Entry In ▸ and the Journal picker of the chooser are gone; the template chooser opens only from inside an empty entry. |
| [website.md](website.md), [review](website-review.md) | Superseded: the repository is the website. The custom site was removed; its privacy policy and support copy moved to [PRIVACY.md](../../PRIVACY.md) and [SUPPORT.md](../../SUPPORT.md). |

## Adding a record

Name new records after their topic (`topic.md`, with `topic-review.md` for the review) and start them with a date and a one-line scope. Add a row here, and update the status of any record the new one changes.
