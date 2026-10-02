# Native macOS undo and document binding

## Observed problem

A hosted JournalTextView configured with the production `isRichText = true` restores its visible text through the native UndoManager, but the Coordinator's bound JournalDocument remains the edited version. `/tmp/journal-editor-isolation-mac4.log` fails the exact document assertion while the native text assertion passes. Existing image-arrival undo coverage uses a view without the production rich-text configuration and does not catch this. No live desktop acceptance is inferred.

## Proposed behavior

Preserve the native Undo/Redo menus, keyboard shortcuts, selection, and history. After the native manager finishes undo or redo, reconcile the current text view through the existing document-conversion callback so autosave observes exactly the visible restored content. No layout, controls, labels, or error copy change. The existing entry-change clear of undo/redo history remains.

The macOS coordinator observes UndoManager didUndoChange/didRedoChange through selector notifications. Filter each callback by identity against the current view's UndoManager; ignore notifications from other windows/editors/managers. Reuse textDidChange, including its existing applying guard and image presentation handling. Register once in coordinator initialization; NotificationCenter selector registrations have automatic cleanup when the coordinator is released. No Task or shared global document state is added. iOS keeps its existing explicit restore path unless the matching native test demonstrates a problem there.

## Verification

Use real native views and UndoManager, configured as production. Assert visible and bound document after undo/redo, clear history on switch, reject a formatting closure retained from the prior entry, and retain the first document when undoing the second. Preserve block identity in test edits by using existing attributed-text attributes. Run Mac and iOS focused tests, existing image-arrival regression, lint/format, and appropriate Apple checks. Live Mac keyboard/menu/VoiceOver acceptance remains separate while the desktop is locked. No appearance/accessibility changes are proposed.
