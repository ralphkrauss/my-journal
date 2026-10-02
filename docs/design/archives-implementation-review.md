# Archive/export implementation review

Date: 2026-09-20. Independent review against `archives.md` revision 2 and `archives-review.md`. Inspected `ExportView.swift`, `ArchiveView.swift`, and the archive/export methods in `AppModel.swift`. No implementation edits or independent execution tests.

## Actual visual inspection

Viewed these supplied iPhone screenshots:

- `artifacts/export-attachments/82A488D7-7208-4C8F-A8EC-02DAC13D3F86.png`: entry-export format sheet, Readable Document selected.
- `artifacts/export-attachments/D30DED09-D232-4817-96E0-B056A56CDBA8.png`: native Files save picker opened for Journal Entry.

**The pictured states meet the visual direction.** Familiar native sheet/picker controls, clear primary action, readable spacing, and concise unencrypted-file disclosure. No clipping or overlap is visible. The native save picker exposes filename and destination. These screenshots show normal-size light-mode states only; they do not establish successful file writing, cancellation, content fidelity, VoiceOver, large text, or any archive-import state.

## Actionable findings

1. **P1 — Distinguish a committed import from a failed post-commit refresh.** `AppModel.installArchive` atomically persists the new configuration and assigns the new store, then calls throwing `refresh()`. If refresh fails, `ArchiveImportView.install` presents failure and leaves the same Import as New Journals action available. Retrying can add the already-committed archive a second time. Make the commit outcome explicit: after commit, retry only reloads the committed vault, and never repeats additive import. The error must not imply that current journals were untouched when commit already succeeded. Verify a refresh/read failure immediately after configuration commit.

2. **P2 — Freeze the export format for the prepared file.** The format Picker remains enabled during `EntryExportView.prepare`, while `fileExporter` derives its content type and filename from the live `readable` state. Image retrieval can suspend preparation. Changing the selection then can pair prepared HTML bytes with a JSON name/type, or the reverse. Capture the selected format with the document and use that same value for bytes, filename, and content type; disable format changes while preparing/picking a destination.

3. **P2 — Cancel preparation when dismissing export.** Entry export launches an untracked Task; Cancel dismisses the sheet without canceling preparation or preventing its completion from setting `exporting = true`. `ArchiveControls` similarly tracks a task but only cancels on lock, not disappearance. Cancel/dismiss must end that UI operation and clean temporary state without a late save-picker presentation. Keep cancellation of preparation distinct from OS save-picker cancellation. This is a source lifecycle concern; the screenshots do not demonstrate the failure.

4. **P2 — Archive errors currently overstate corruption.** `ArchiveImportView.inspect` maps every error except invalid recovery key/cancellation to “This archive is incomplete or damaged.” Permission errors, temporary storage failure, and unavailable source files do not establish corruption. Distinguish inaccessible/unreadable source or staging failure from validated damage and supply an appropriate retry/open-another-copy action. Retain the existing local draft and vault in all precommit failures.

5. **P2 — Implement the specified key-error focus behavior.** The Recovery Key field has no explicit focus binding or focus restoration on validation failure. Pressing Continue does not establish that keyboard focus remains on the invalid key. Add/verify predictable focus after errors, an accessible error announcement, and selectable preview/error text. The proposal explicitly requires these; source currently does not establish them.

## Matches and limits

Source includes a failed-save entry-export path that captures the current draft without flushing, both readable and lossless formats, unsupported-readable messaging, native recovery-key export, separate live/deleted preview counts, connected-destination disclosure, additive/restoration completion labels, and lock handling on the export/import sheets. The import model flushes before setting its replacement guard, stages additive import under the existing key/configuration, and checks cancellation/lock before commit. These are positive source observations, not proof of all timing or persistence behavior.

The archive import preview, wrong-key error, missing-image error, unsupported document, Save Recovery Key picker, actual exported files, lock during preparation/commit, failed local persistence, dark appearance, Mac layouts, and accessibility text sizes remain uninspected visually. Resolve the findings and verify the narrow failure cases before claiming the archive/export flow complete.

## Source recheck after corrections — 2026-09-20

Re-read the current export/import views and post-commit model path. No new screenshots or independently run tests were supplied for this recheck.

1. **Resolved in source:** once import configuration commits, a display-refresh failure is caught separately, reports that journals were imported, and returns through completion. The same sheet no longer offers the failed-import retry that could duplicate journals.
2. **Resolved in source:** the format picker is disabled throughout preparation and destination selection, keeping the prepared bytes, file type, and filename consistent for that operation.
3. **Resolved in source; verify picker lifecycle:** entry-export preparation now owns a cancellable task, checks cancellation before presenting, and cancels on lock/disappearance. Archive controls cancel on disappearance and retain the package while the exporter is active. Test actual save and cancel after these lifecycle changes, particularly that an OS picker presentation does not cause entry-export `onDisappear` to clear its document before writing completes. This is a verification item, not an observed failure.
4. **Resolved in source:** invalid key, unsupported format, validated invalid data, and generic file/storage failures now have separate messages. Ordinary access/storage errors no longer claim archive damage.
5. **Key-focus part resolved in source:** the Recovery Key field uses FocusState and regains focus after an invalid-key error; archive errors are selectable. VoiceOver error announcement/reading order and actual keyboard focus remain unverified. Preview text is still not explicitly selectable, a minor departure that does not block further feature work.

**Current outcome:** no demonstrated material source blocker remains from the five findings. It is reasonable to continue other work while retaining the required archive/export behavioral and actual-UI checks. This does not expand the earlier visual approval beyond the two supplied normal-size light-mode screenshots. Failed import/refresh, completed file writing, cancellation after the new cleanup handlers, lock, Mac layout, large text, and assistive-technology behavior remain uninspected by this reviewer.
