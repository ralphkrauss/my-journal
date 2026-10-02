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
| [default-journal.md](default-journal.md) | Current. Settings ▸ Default Journal, and New Entry outside a journal (Recently Deleted, Templates, All Entries, the iPhone Journals screen). Replaces the default-journal rule of feedback-stabilization-2026-09-23.md and the "Which journal" rule of new-entry-template-suggestion.md. |
| [recently-deleted-2026-09-30.md](recently-deleted-2026-09-30.md) | Current. Cancelling a swipe to delete permanently keeps the row; the footer check. |
| [device-orientations.md](device-orientations.md), [review](device-orientations-review.md) | Current, amended. The constrained iOS header was replaced by unified-entry-scrolling.md. |
| [unified-entry-scrolling.md](unified-entry-scrolling.md), [review](unified-entry-scrolling-review.md) | Current. |
| [entry-title-accessibility.md](entry-title-accessibility.md), [review](entry-title-accessibility-review.md) | Current, amended. The header layout was replaced by unified-entry-scrolling.md. |
| [mac-live-acceptance.md](mac-live-acceptance.md), [review](mac-live-acceptance-review.md) | Evidence. Live Mac checks of a 2026-09-21 build. |
| [mac-settings-navigation-review.md](mac-settings-navigation-review.md) | Evidence. The Settings window was later redesigned (owner-decisions-2026-09-25.md §9). |

## Writing and templates

| Record | Status |
| --- | --- |
| [native-undo-binding.md](native-undo-binding.md), [review](native-undo-binding-review.md) | Current. |
| [paragraph-identity-recovery.md](paragraph-identity-recovery.md), [review](paragraph-identity-recovery-review.md) | Current. |
| [template-initial-insertion.md](template-initial-insertion.md), [review](template-initial-insertion-review.md) | Current. |
| [writing-workflow-review.md](writing-workflow-review.md) | Evidence. Led to template-initial-insertion.md. |
| [template-setup-review.md](template-setup-review.md) | Evidence. |
| [new-entry-template-suggestion.md](new-entry-template-suggestion.md) | Current (reviewed; review outcome recorded in the record). One New Entry button; “Use a Template…” in a fresh entry opens the chooser and fills the entry in place. Supersedes the Templates… button in mac-window-appkit.md §3 and feedback-stabilization-2026-09-23.md §3. |
| [new-entry-button-options.md](new-entry-button-options.md) | Evidence. Research and prototypes for folding Templates… into New Entry; the owner chose option D. |
| [title-paste-workflow-review.md](title-paste-workflow-review.md) | Evidence. |
| [pasted-text.md](pasted-text.md), [review](pasted-text-review.md) | Current. Text pasted from other apps (owner-decisions-2026-10-01.md §6). |
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

## Journals, deletion and history

| Record | Status |
| --- | --- |
| [move-entry.md](move-entry.md), [review](move-entry-review.md), [implementation review](move-entry-implementation-review.md) | Current, amended. The explanation for journals with the same name changed (pre-release-fixes-2026-09-27.md). |
| [journal-conflicts.md](journal-conflicts.md), [review](journal-conflicts-review.md), [implementation review](journal-conflicts-implementation-review.md) | Current. |
| [journal-deletion.md](journal-deletion.md), [review](journal-deletion-review.md) | Superseded by journal-lifecycle-ui.md. |
| [journal-lifecycle-proposal.md](journal-lifecycle-proposal.md), [review](journal-lifecycle-review.md) | Current. Implemented as [protocol/journal-lifecycle.md](../../protocol/journal-lifecycle.md). |
| [journal-lifecycle-ui.md](journal-lifecycle-ui.md), [review](journal-lifecycle-ui-review.md), [implementation review](journal-lifecycle-ui-implementation-review.md), [navigation implementation review](journal-navigation-implementation-review.md) | Current, amended. Delete confirmations are standard alerts (owner-decisions-2026-09-25.md §1). |
| [large-text-recovery.md](large-text-recovery.md), [review](large-text-recovery-review.md) | Current. |
| [permanent-deletion.md](permanent-deletion.md), [review](permanent-deletion-review.md) | Current, amended. The review sheet was replaced by a standard alert (owner-decisions-2026-09-25.md §1). Semantics: [protocol/permanent-deletion.md](../../protocol/permanent-deletion.md). |
| [history-recovery.md](history-recovery.md), [review](history-recovery-review.md), [implementation review](history-recovery-implementation-review.md) | Current. |
| [version-checkpoints.md](version-checkpoints.md) | Current. Storage behavior only; the Version History interface is unchanged. |
| [entry-archiving.md](entry-archiving.md), [review](entry-archiving-review.md) | Removed feature (Archive and the Archived collection, owner-decisions-2026-09-25.md §1). The stored field is kept for compatibility. |

## Conflicts

| Record | Status |
| --- | --- |
| [entry-conflict-accessibility.md](entry-conflict-accessibility.md), [review](entry-conflict-accessibility-review.md) | Current. |
| [stale-conflict-recovery.md](stale-conflict-recovery.md), [review](stale-conflict-recovery-review.md) | Current. |
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
| [journal-name-uniqueness.md](journal-name-uniqueness.md) | Current. Journal names stay unique: Name Taken for local names, numbers for restore, import, joining and sync, Merge Into…, and a repeated join respects deletions. Its review is recorded in the record. |
| [join-with-local-journals.md](join-with-local-journals.md) | Current, amended by journal-name-uniqueness.md; amends connection-onboarding.md. A device that already has journals scans or types a server like a new device, then agrees on Merge Journals; same-name journals combine, templates are deduplicated or reviewed, and retries never duplicate. Reviews are recorded in the record. |
| [sync-health-and-recovery.md](sync-health-and-recovery.md) | Current (revision 2, approved by the owner and implemented 2026-10-01; Check Connection left out; §4.2 amended by quiet-sync-and-title-alignment.md). Every sync failure classified into a few states with one action each (Set Up Server Again…, Connect Again…, Sign In…), automatic retries stopped where they can't help, Merge Journals only for a different library (lineage), Stop Syncing in Settings > Sync. |
| [sync-protocol-efficiency.md](sync-protocol-efficiency.md), [review](sync-protocol-efficiency-review.md) | Current (revision 9, approved after nine independent review rounds; implemented 2026-10-02, waiting for a red team before build 10). Short push receipts (`sync-short-receipt`) and waiting for changes instead of polling (`sync-wait`), with the server contract in protocol/README.md. |
| [quiet-sync-and-title-alignment.md](quiet-sync-and-title-alignment.md), [review](quiet-sync-and-title-alignment-review.md) | Current (implemented 2026-10-02). Sync Status shows only when the person must act or after a day of failing, in a toolbar place kept for it on the Mac so nothing moves; the entry title starts exactly where the body text does. |
| [app-lock-system-auth.md](app-lock-system-auth.md) | Current. App Lock uses only the device's own authentication (Face ID, Touch ID, Optic ID, passcode or Mac login password); the PIN, its sheet and attempt delay are removed and PIN users are migrated. The review outcome is recorded in the record. |
| [app-lock-accessibility.md](app-lock-accessibility.md), [review](app-lock-accessibility-review.md) | Current, amended by app-lock-system-auth.md (no PIN field; the scrolling lock-screen layout still applies). The iPhone and iPad privacy cover is in pre-release-fixes-2026-09-27.md. |
| [missing-device-key-unlock.md](missing-device-key-unlock.md), [review](missing-device-key-unlock-review.md) | Current. |
| [local-server.md](local-server.md), [review](local-server-review.md), [implementation review](local-server-implementation-review.md) | Current. |
| [mac-app-store-sandbox.md](mac-app-store-sandbox.md) | Current (prototype and plan). App Sandbox for the Mac App Store: entitlements, data locations, the bundled server and agent connector, migration and App Review. No interface change. |

## Agent access

| Record | Status |
| --- | --- |
| [agent-access.md](agent-access.md), [review](agent-access-review.md), [implementation review](agent-access-implementation-review.md) | Removed feature. The Mac-only local connection was removed by agent-access-simplified.md §8. |
| [agent-access-server.md](agent-access-server.md) | Current, amended by agent-access-simplified.md: approval, the Add Agent sheet and the pane's UI (§5.4 approval, §6). Contract: [protocol/agent-access-server.md](../../protocol/agent-access-server.md). |
| [agent-access-simplified.md](agent-access-simplified.md) | Current. Requests appear in the app and are approved with the page's number; All Journals; editing an agent's journals; removal of Agents on This Mac. |

## Website

| Record | Status |
| --- | --- |
| [website.md](website.md), [review](website-review.md) | Superseded: the repository is the website. The custom site was removed; its privacy policy and support copy moved to [PRIVACY.md](../../PRIVACY.md) and [SUPPORT.md](../../SUPPORT.md). |

## Adding a record

Name new records after their topic (`topic.md`, with `topic-review.md` for the review) and start them with a date and a one-line scope. Add a row here, and update the status of any record the new one changes.
