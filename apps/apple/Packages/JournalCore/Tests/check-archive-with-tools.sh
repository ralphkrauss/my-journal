#!/bin/bash
# Reads file archives with tools that are not this repository's code: Info-ZIP unzip and zipinfo, bsdtar (where
# installed) and Python's zipfile. Pass the archives. ArchiveIndependentToolsTests runs it on the writer's output;
# run it by hand on any archive before a release:  Tests/check-archive-with-tools.sh MyArchive.journalarchive
set -euo pipefail

for archive in "$@"; do
  echo "== $archive"
  unzip -tq "$archive"
  zipinfo "$archive" >/dev/null
  if command -v bsdtar >/dev/null; then
    bsdtar -tf "$archive" >/dev/null
  fi
  python3 -I - "$archive" <<'PY'
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    assert archive.testzip() is None, "a CRC-32 does not match"
    entries = archive.infolist()
    names = [entry.filename for entry in entries]
    images = names[1:-1]
    assert names[0] == "journal.sqlite", names
    assert names[-1] == "archive.json", names
    assert images == sorted(images), "images are written in name order"
    assert all(name.startswith("attachments/") for name in images), names
    assert len(set(names)) == len(names), "no duplicate names"
    for entry in entries:
        assert entry.compress_type == zipfile.ZIP_STORED, entry.filename
        assert entry.flag_bits == 0, entry.filename
        assert entry.date_time == (1980, 1, 1, 0, 0, 0), entry.filename
        assert entry.external_attr == 0 and entry.comment == b"", entry.filename
        assert entry.file_size == entry.compress_size, entry.filename
print("ok")
PY
done
