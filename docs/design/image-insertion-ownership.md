# Keep image insertion with its originating entry

## Observed gap

RootView opens the file picker without capturing the originating entry/native selection. Its completion uses the then-current model, and after awaiting attachment storage plus a yield it calls the editor's latest global action. A selection change can therefore retarget image insertion. Native paste/drop retains entry ID after storage but uses a later selection rather than the original native range.

## Interaction design

Insert Image retains its existing toolbar placement, native picker, and label. Capture an insertion session before presenting: exact store identity, entry ID/document, and the native formatting closure that already preserves range and refuses a changed editor/document. Validate that session before storage and again after awaits before insertion. A canceled picker, changed entry/document, locked/replaced vault, or disappearing editor abandons the insertion quietly; it must never insert into a different entry. Preserve ordinary successful image insertion and native undo. No new copy, control, or confirmation.

RootView owns the picker session and import Task; cancel/clear on lock, selected-entry change and disappearance. Capture the exact session into the completion task, rather than looking up a later session. Scope file-read errors to that current session; cancellation is quiet. Session uses model.canEdit and document/store identity at both boundaries. After storage, yield to allow the current image map to render as before, then validate and invoke captured native command. Bytes may have been saved before cancellation but no entry references are written by an abandoned operation; existing attachment housekeeping applies.

Native paste/drop captures its existing formattingSession closure at receipt before awaiting imageHandler, then invokes that closure rather than perform using the later selection. Keep the existing item-ID guard and model's store/lock guards. No new unowned background task is introduced by the picker.

## Verification

Use focused native/store tests: successful insertion at captured selection; changing entry or document, locking or replacing store refuses before writing; post-storage cancellation/session rejection preserves both entries; native captured command refuses stale editor/document. Preserve image-loading and undo regression tests. Tests should inspect real documents/attachment state, not only mocked call counts. Actual system picker navigation/live Mac interaction remains separate UI acceptance; no layout change is proposed.

## Irreversible ownership revision

Add a model image-insertion generation UUID, synchronously renewed on selected entry change, draft entry/document change, lock, vault replacement, or store identity change. Picker session captures it at presentation. AppModel.addImage captures it before suspension and validates after storage and before error publication as well, protecting native paste/drop across transient transitions. Thus A→B→A or lock→unlock does not restore ownership even if current equality matches.

Both native coordinators track a generation renewed on view rebinding, entry/editability changes, externally rendered document changes, and real native document edits. A formattingSession captures the generation along with entry/document/range, validates before commands, then advances its own captured generation after its accepted command to preserve consecutive formatting. Old sessions cannot revive on document undo or navigation return. Existing delegate/render guards still apply.

The picker session additionally has explicit cancellation/consumption; RootView owns its task and cancels on navigation, lock and disappearance. A new picker session cannot be cleared by completion of an older task. Verify stale native commands after A→B→A, and picker/model ownership after lock→unlock and store-away→same-store, using actual native content/store rather than delayed UI timing.
