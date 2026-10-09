#!/usr/bin/env python3
"""Builds the foreign.sqlite family: empty libraries written by something other than the Apple app.

Only Python's sqlite3 module writes them, in a different style from GRDB (quoted identifiers, lower-case types,
table constraints), so they prove that a reader compares the structure of the tables and not the text of the
CREATE statements (protocol/archive.md, Database). They hold no records, because Python cannot seal records.

    python3 make-foreign-database.py          # writes the files next to this script

The files are fixtures: commit them, do not regenerate them to follow a code change. SQLite stores its own
version number in the file header, so a rebuilt file differs in a few header bytes from the committed one.
"""

import sqlite3
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


def build(name, applied=None, recorded=None, mutate=None, journal_mode="DELETE"):
    """Writes one database. `applied` migrations create their objects, `recorded` names the ones listed in
    grdb_migrations (default: the same), and `mutate` may change the result."""
    path = HERE / name
    path.unlink(missing_ok=True)
    applied = MIGRATIONS if applied is None else applied
    recorded = [identifier for identifier, _ in applied] if recorded is None else recorded
    connection = sqlite3.connect(path)
    connection.execute('CREATE TABLE "grdb_migrations" ("identifier" text not null primary key)')
    for _, statements in applied:
        for statement in statements:
            connection.execute(statement)
    connection.executemany(
        'INSERT INTO "grdb_migrations" ("identifier") VALUES (?)', [(item,) for item in recorded]
    )
    connection.execute(
        "INSERT INTO settings (key, value) VALUES ('content-protection', 'encrypted')"
    )
    if mutate:
        mutate(connection)
    connection.commit()
    connection.execute(f"PRAGMA journal_mode = {journal_mode}")
    connection.close()


def main():
    build("foreign.sqlite")
    # Only the first three migrations are recorded: a reader applies the other two.
    build("foreign-older.sqlite", applied=MIGRATIONS[:3])
    build(
        "foreign-trigger.sqlite",
        mutate=lambda db: db.execute(
            "CREATE TRIGGER copy_outbox AFTER INSERT ON outbox BEGIN DELETE FROM history; END"
        ),
    )
    build(
        "foreign-view.sqlite",
        mutate=lambda db: db.execute("CREATE VIEW everything AS SELECT id FROM records"),
    )
    build(
        "foreign-extra-table.sqlite",
        mutate=lambda db: db.execute("CREATE TABLE notes (id text primary key)"),
    )
    # A column of records that the migration should have created is missing.
    broken = [
        (
            "v1",
            [
                statement.replace(', "dirty" integer not null default 1', "")
                if 'CREATE TABLE "records"' in statement
                else statement
                for statement in MIGRATIONS[0][1]
            ],
        )
    ] + MIGRATIONS[1:]
    build("foreign-missing-column.sqlite", applied=broken)
    # A column that is not NOT NULL where the migration says it is.
    loose = [
        (
            "v1",
            [
                statement.replace(
                    '"kind" text not null, "payload" text not null, "revision"',
                    '"kind" text, "payload" text not null, "revision"',
                )
                for statement in MIGRATIONS[0][1]
            ],
        )
    ] + MIGRATIONS[1:]
    build("foreign-nullable-column.sqlite", applied=loose)
    build(
        "foreign-unknown-migration.sqlite",
        recorded=[identifier for identifier, _ in MIGRATIONS] + ["a-later-migration"],
    )
    # server-versions is recorded but its table was never created.
    build(
        "foreign-migration-objects-missing.sqlite",
        applied=MIGRATIONS[:4],
        recorded=[i for i, _ in MIGRATIONS],
    )
    # history-checkpoints is recorded without the migrations before it.
    build(
        "foreign-migrations-out-of-order.sqlite",
        applied=MIGRATIONS,
        recorded=["v1", "history-checkpoints"],
    )
    # File format versions 2 and 2: write-ahead logging, not a one-file snapshot.
    build("foreign-wal.sqlite", journal_mode="WAL")


if __name__ == "__main__":
    main()
