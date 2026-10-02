# Entry archive timestamp

The apps no longer have an Archive command or an Archived collection; they were removed in favor of Recently Deleted ([design record](../docs/design/owner-decisions-2026-09-25.md)). The portable field is kept for compatibility, because records written by earlier versions carry it and every client must preserve it.

`archivedAt` is an optional timestamp allowed only on entries ([records.md](records.md)). Missing or null means not archived. Journals, templates and permanent-deletion markers can't carry it; a record that does is kept as unreadable. The field is encrypted with the rest of the record, and the server is unaware of it.

Current clients don't set it. An entry that has it is shown in its journal like any other entry, and agent tools return it as `archivedAt`. It never changes journal membership, entry date, content or agent access, and it is never used to order competing revisions.

Clients keep the field when they save other changes, move an entry or restore a whole journal, and archives preserve it. These operations clear it on the entry they produce:

- Restore and Move of an entry, and restoring an entry together with its deleted journal;
- copying an earlier version from Version History;
- Keep Entry and Keep Entry as Copy when resolving a conflict with a permanent deletion.

The shared core still has a transactional operation that sets or clears the field against an expected previous value. Only the sync test client uses it, to check that other clients preserve and converge on the field.
