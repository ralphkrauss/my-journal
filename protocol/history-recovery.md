# Version History recovery

This operation copies an earlier version of an entry or template. The interaction is described in [docs/design/history-recovery.md](../docs/design/history-recovery.md) and its reviews. Restoring a journal's earlier settings was removed in 1.1 ([docs/design/1-1-library-simplifications.md](../docs/design/1-1-library-simplifications.md), K): no screen offers earlier versions of a journal, though the rows that earlier versions stored stay in the database and in archives, and are removed with the journal by Delete Permanently.

## Copy an earlier entry or template

restoreHistoryCopy(version, to:) runs one SQLite write transaction. It accepts only supported entry/template records that exactly match an authenticated, decoded history row in this vault. A changed caller-supplied preview is not a valid historical record. History is scanned with a cursor, avoiding loading every version into a temporary array for this check.

An entry requires an explicit destination journal that is currently present, supported, live and conflict-free. A template refuses a destination and retains its kind with no parent. The copy receives a new record ID and modification timestamp, retaining historical title, document, image references and journal date, and clearing its deletion state, archive timestamp and restoration provenance. Missing attachment bytes remain preserved references; the operation does not claim to reconstruct bytes not available locally.

The original record, every historical version, attachment bytes and existing immutable outbox operations remain unchanged. The current source and old parent need not be editable or available: this is a copy of a supported immutable historical record, not a write to the source. An unresolved or unsupported current source conflict is left intact. Recovery never treats copying a version as resolving that conflict. The new copy enters the ordinary encrypted outbox at revision zero.

Precommit cancellation is checked before entering the synchronous transaction. Native callers must own commit and canonical reconciliation, suppress repeat actions after durable success and distinguish postcommit display failure from failed creation. New identity generation is not a duplicate-retry token; a caller must not invoke creation again after a confirmed commit merely because refresh failed.

## Tests

HistoryRecoveryTests use real encrypted stores and real conflict resolution to create history. They cover history membership, copying into a valid journal while the source is unavailable, preservation of rich text, images and dates, unchanged original, history, image and pending bytes, template kind, refusal of deleted or conflicted destinations and of unsupported supplied versions, preservation of an unsupported unresolved source conflict, and persistence after reopening.
