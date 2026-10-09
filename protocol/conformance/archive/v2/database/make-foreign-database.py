#!/usr/bin/env python3
"""Builds the foreign.sqlite family: empty libraries written by something other than the Apple app.

Only Python's sqlite3 module writes them, in a different style from GRDB (quoted identifiers, lower-case types,
table constraints), so they prove that a reader compares the structure of the tables and not the text of the
CREATE statements (protocol/archive.md, Database). They hold no records, because Python cannot seal records.

    python3 make-foreign-database.py          # writes every file next to this script
    python3 make-foreign-database.py NAME...  # writes only the named files (without .sqlite)

The files are fixtures: commit them, do not regenerate them to follow a code change. SQLite stores its own
version number in the file header, so a rebuilt file differs in a few header bytes from the committed one.
"""

import sqlite3
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# The objects each migration creates, in order. The text is deliberately not GRDB's.
MIGRATIONS = [
    (
        "v1",
        [
            'CREATE TABLE "records" ("id" text not null primary key, "kind" text not null, '
            '"payload" text not null, "revision" integer not null default 0, '
            '"dirty" integer not null default 1)',
            'CREATE TABLE "outbox" ("operation" text not null, "record" text not null, '
            '"kind" text not null, "payload" text not null, "base" integer not null, '
            'primary key ("operation"), unique ("record"), foreign key ("record") references "records" ("id"))',
            'CREATE TABLE "conflicts" ("record" text not null primary key, "payload" text not null, '
            '"revision" integer not null, "device" text not null, "modified" text not null, '
            'foreign key ("record") references "records" ("id"))',
            'CREATE TABLE "history" ("id" integer primary key autoincrement not null, "record" text not null, '
            '"kind" text not null, "payload" text not null, "saved" text not null)',
            'CREATE TABLE "settings" ("key" text not null primary key, "value" blob not null)',
            'CREATE TABLE "attachments" ("id" text not null primary key, "uploaded" integer not null default 0)',
        ],
    ),
    (
        "sync-reconciliation",
        [
            'CREATE TABLE "reconcile_heads" ("record" text not null primary key, "kind" text not null, '
            '"payload" text not null, "revision" integer not null, "cursor" integer not null, '
            '"device" text not null, "modified" text not null, "seen_payload" text)'
        ],
    ),
    ("history-record-index", ['CREATE INDEX "history_record" ON "history" ("record")']),
    (
        "history-checkpoints",
        [
            'ALTER TABLE "history" ADD COLUMN "checkpoint" integer NOT NULL DEFAULT (0)',
        ],
    ),
    (
        "server-versions",
        [
            'CREATE TABLE "server_versions" ("record" text not null primary key, '
            '"revision" integer not null, "digest" text not null)'
        ],
    ),
]


def build(
    name,
    applied=None,
    recorded=None,
    mutate=None,
    journal_mode="DELETE",
    page_size=None,
    protection_value="'encrypted'",
):
    """Writes one database. `applied` migrations create their objects, `recorded` names the ones listed in
    grdb_migrations (default: the same), `mutate` may change the result and `page_size` sets the page size
    (small pages make the schema table a b-tree with interior pages, and the file small). `protection_value` is
    the SQL that makes the value of the content-protection setting (a STRICT table wants a real blob)."""
    path = HERE / name
    path.unlink(missing_ok=True)
    applied = MIGRATIONS if applied is None else applied
    recorded = [identifier for identifier, _ in applied] if recorded is None else recorded
    connection = sqlite3.connect(path)
    if page_size:
        connection.execute(f"PRAGMA page_size = {page_size}")
    connection.execute('CREATE TABLE "grdb_migrations" ("identifier" text not null primary key)')
    for _, statements in applied:
        for statement in statements:
            connection.execute(statement)
    connection.executemany(
        'INSERT INTO "grdb_migrations" ("identifier") VALUES (?)', [(item,) for item in recorded]
    )
    connection.execute(
        f"INSERT INTO settings (key, value) VALUES ('content-protection', {protection_value})"
    )
    if mutate:
        mutate(connection)
    connection.commit()
    connection.execute(f"PRAGMA journal_mode = {journal_mode}")
    connection.close()


def with_statement(old, new):
    """The migrations with `old` replaced by `new` in the statement that creates the table it belongs to."""
    changed = []
    for identifier, statements in MIGRATIONS:
        replaced = [statement.replace(old, new) for statement in statements]
        changed.append((identifier, replaced))
    assert changed != MIGRATIONS, old
    return changed


def variant_cases():
    """Libraries that one clause makes different, in ways PRAGMA table_info and index_list do not show. Each is
    otherwise the foreign.sqlite library, on small pages."""
    small = 512
    return {
        # records has a second, generated column that PRAGMA table_info leaves out (table_xinfo lists it).
        "foreign-generated-column": dict(
            applied=with_statement(
                ', "dirty" integer not null default 1)',
                ', "dirty" integer not null default 1, "digest" text generated always as ("kind" || "id") virtual)',
            ),
            page_size=small,
        ),
        # A CHECK that no pragma lists.
        "foreign-check-constraint": dict(
            applied=with_statement(
                '"revision" integer not null default 0,',
                '"revision" integer not null default 0 check ("revision" >= 0),',
            ),
            page_size=small,
        ),
        # A column that compares text another way.
        "foreign-collate": dict(
            applied=with_statement(
                '"records" ("id" text not null primary key, "kind" text not null,',
                '"records" ("id" text not null primary key, "kind" text not null collate nocase,',
            ),
            page_size=small,
        ),
        # A foreign key that deletes the outbox row with its record.
        "foreign-foreign-key-action": dict(
            applied=with_statement(
                'foreign key ("record") references "records" ("id"))',
                'foreign key ("record") references "records" ("id") on delete cascade)',
            ),
            page_size=small,
        ),
        # A foreign key that is checked at commit.
        "foreign-deferred-foreign-key": dict(
            applied=with_statement(
                'foreign key ("record") references "records" ("id"))',
                'foreign key ("record") references "records" ("id") deferrable initially deferred)',
            ),
            page_size=small,
        ),
        # An insert that replaces the row it collides with.
        "foreign-on-conflict-replace": dict(
            applied=with_statement(
                'unique ("record"),', 'unique ("record") on conflict replace,'
            ),
            page_size=small,
        ),
        "foreign-without-rowid": dict(
            applied=with_statement(
                '"value" blob not null)', '"value" blob not null) without rowid'
            ),
            page_size=small,
        ),
        "foreign-strict": dict(
            applied=with_statement('"value" blob not null)', '"value" blob not null) strict'),
            page_size=small,
            protection_value="CAST('encrypted' AS BLOB)",
        ),
        # history's ids may be reused: no sqlite_sequence.
        "foreign-no-autoincrement": dict(
            applied=with_statement(
                '"id" integer primary key autoincrement not null', '"id" integer primary key not null'
            ),
            page_size=small,
        ),
        # A virtual table, and the shadow tables FTS5 makes for it. Connecting it runs the module's code.
        "foreign-virtual-table": dict(
            mutate=lambda db: db.execute('CREATE VIRTUAL TABLE "notes" USING fts5("body")'),
            page_size=small,
        ),
        # Accepted: the same library on small pages (the schema table is a b-tree of several pages) ...
        "foreign-small-pages": dict(page_size=small),
        # ... and with a foreign key that names no parent column, which means the parent's primary key.
        "foreign-implicit-parent-key": dict(
            applied=with_statement(
                'foreign key ("record") references "records" ("id"))',
                'foreign key ("record") references "records")',
            ),
            page_size=small,
        ),
    }


def main(names):
    builders = {
        "foreign": lambda: build("foreign.sqlite"),
        # Only the first three migrations are recorded: a reader applies the other two.
        "foreign-older": lambda: build("foreign-older.sqlite", applied=MIGRATIONS[:3]),
        "foreign-trigger": lambda: build(
            "foreign-trigger.sqlite",
            mutate=lambda db: db.execute(
                "CREATE TRIGGER copy_outbox AFTER INSERT ON outbox BEGIN DELETE FROM history; END"
            ),
        ),
        "foreign-view": lambda: build(
            "foreign-view.sqlite",
            mutate=lambda db: db.execute("CREATE VIEW everything AS SELECT id FROM records"),
        ),
        "foreign-extra-table": lambda: build(
            "foreign-extra-table.sqlite",
            mutate=lambda db: db.execute("CREATE TABLE notes (id text primary key)"),
        ),
        # A column of records that the migration should have created is missing.
        "foreign-missing-column": lambda: build(
            "foreign-missing-column.sqlite",
            applied=with_statement(', "dirty" integer not null default 1', ""),
        ),
        # A column that is not NOT NULL where the migration says it is.
        "foreign-nullable-column": lambda: build(
            "foreign-nullable-column.sqlite",
            applied=with_statement(
                '"kind" text not null, "payload" text not null, "revision"',
                '"kind" text, "payload" text not null, "revision"',
            ),
        ),
        "foreign-unknown-migration": lambda: build(
            "foreign-unknown-migration.sqlite",
            recorded=[identifier for identifier, _ in MIGRATIONS] + ["a-later-migration"],
        ),
        # server-versions is recorded but its table was never created.
        "foreign-migration-objects-missing": lambda: build(
            "foreign-migration-objects-missing.sqlite",
            applied=MIGRATIONS[:4],
            recorded=[i for i, _ in MIGRATIONS],
        ),
        # history-checkpoints is recorded without the migrations before it.
        "foreign-migrations-out-of-order": lambda: build(
            "foreign-migrations-out-of-order.sqlite",
            applied=MIGRATIONS,
            recorded=["v1", "history-checkpoints"],
        ),
        # File format versions 2 and 2: write-ahead logging, not a one-file snapshot.
        "foreign-wal": lambda: build("foreign-wal.sqlite", journal_mode="WAL"),
    }
    for name, options in variant_cases().items():
        builders[name] = lambda name=name, options=options: build(f"{name}.sqlite", **options)
    unknown = [name for name in names if name not in builders]
    if unknown:
        raise SystemExit(f"unknown: {', '.join(unknown)}")
    for name in names or builders:
        builders[name]()


if __name__ == "__main__":
    main(sys.argv[1:])
