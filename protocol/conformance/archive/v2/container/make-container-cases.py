#!/usr/bin/env python3
"""Writes the container cases of protocol/conformance/archive/v2 and container-v2.json.

    python3 make-container-cases.py

The output is deterministic: running it again gives the same bytes. The archives are assembled with `struct`,
because most of the invalid ones are forgeries that Python's zipfile (or any ZIP library) refuses to write.
zipfile is used for the opposite job: every `accept` case is read back with it as a cross-check, so a case
that is meant to be valid but that a mainstream library cannot read is caught here.

The cases exercise the container layer of protocol/archive.md only: the ZIP structure and the extraction of the
entries a given manifest lists. Each case carries the manifest the reader is given (plain JSON, as `manifest` or,
where the text itself is the defect, as `manifestText`), so no case needs a key or a cipher. A case whose
`parseHeader` is true also checks `archive.json` as a header up to the envelope bounds (no password).
"""

import base64
import hashlib
import json
import random
import struct
import sys
import zipfile
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
STORED, DEFLATED = 0, 8
MAX_U32 = 0xFFFFFFFF
DOS_DATE = 0x0021  # 1980-01-01

IMAGE_A = "01234567-89ab-4cde-8fab-0123456789ab"
IMAGE_B = "fedcba98-7654-4321-8fed-cba987654321"
UNLISTED = "11111111-2222-4333-8444-555555555555"


def pseudo_text(seed, length):
    """Hex text from a hash chain: compresses about 2:1, stable across machines."""
    out, block = b"", seed.encode()
    while len(out) < length:
        block = hashlib.sha256(block).hexdigest().encode()
        out += block
    return out[:length]


DATABASE = pseudo_text("database", 640)
PICTURE_A = pseudo_text("picture-a", 70)
PICTURE_B = pseudo_text("picture-b", 150)
OPAQUE_HEADER = b'{"archiveVersion":2,"standIn":"container tests do not read the header"}'


def deflate(data, level=9):
    compressor = zlib.compressobj(level, zlib.DEFLATED, -15)
    return compressor.compress(data) + compressor.flush()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def manifest_for(files):
    """The manifest a correct reader is given for {name: bytes}."""
    images = {
        name.split("/", 1)[1]: {"sha256": sha(data), "bytes": len(data)}
        for name, data in files.items()
        if name.startswith("attachments/")
    }
    database = files["journal.sqlite"]
    return {"database": {"sha256": sha(database), "bytes": len(database)}, "attachments": images}


# ---------------------------------------------------------------- ZIP assembly


class Entry:
    """One entry. Every `l*` field overrides what the local header says, every `c*` field the central one."""

    def __init__(self, name, data=b"", method=STORED, **options):
        self.name = name.encode() if isinstance(name, str) else name
        self.data = data
        self.method = method
        self.payload = options.pop("payload", None)  # the bytes stored, if not computed from data
        self.flags = options.pop("flags", 0)
        self.crc = options.pop("crc", None)
        self.csize = options.pop("csize", None)
        self.usize = options.pop("usize", None)
        self.lcrc = options.pop("lcrc", None)
        self.lcsize = options.pop("lcsize", None)
        self.lusize = options.pop("lusize", None)
        self.lflags = options.pop("lflags", None)
        self.lmethod = options.pop("lmethod", None)
        self.lname = options.pop("lname", None)
        self.lextra = options.pop("lextra", b"")
        self.cextra = options.pop("cextra", b"")
        self.comment = options.pop("comment", b"")
        self.descriptor = options.pop("descriptor", False)
        self.zip64 = options.pop(
            "zip64", False
        )  # central: saturate sizes and offset, ZIP64 extra field
        self.lzip64 = options.pop("lzip64", False)  # local: saturate sizes, ZIP64 extra field
        self.offset = options.pop("offset", None)
        self.zip64_extra = options.pop(
            "zip64_extra", None
        )  # replaces the generated ZIP64 extra field
        self.disk = options.pop("disk", 0)
        assert not options, options

    def stored_bytes(self):
        if self.payload is not None:
            return self.payload
        return deflate(self.data) if self.method == DEFLATED else self.data


def pick(value, default):
    return default if value is None else value


def local_header(entry, stored):
    crc = pick(entry.lcrc, zlib.crc32(entry.data))
    csize = pick(entry.lcsize, len(stored))
    usize = pick(entry.lusize, len(entry.data))
    extra = entry.lextra
    if entry.descriptor and entry.lcrc is None and entry.lcsize is None and entry.lusize is None:
        crc = csize = usize = 0
    if entry.lzip64:
        extra = struct.pack("<HHQQ", 1, 16, usize, csize) + extra
        csize = usize = MAX_U32
    name = pick(entry.lname, entry.name)
    flags = pick(entry.lflags, entry.flags | (8 if entry.descriptor else 0))
    method = pick(entry.lmethod, entry.method)
    header = struct.pack(
        "<IHHHHHIIIHH",
        0x04034B50,
        45 if entry.lzip64 else 20,
        flags,
        method,
        0,
        DOS_DATE,
        crc,
        csize,
        usize,
        len(name),
        len(extra),
    )
    return header + name + extra


def descriptor_bytes(entry, stored):
    return struct.pack("<IIII", 0x08074B50, zlib.crc32(entry.data), len(stored), len(entry.data))


def central_header(entry, stored, offset):
    crc = pick(entry.crc, zlib.crc32(entry.data))
    csize = pick(entry.csize, len(stored))
    usize = pick(entry.usize, len(entry.data))
    extra = entry.cextra
    offset = pick(entry.offset, offset)
    flags = entry.flags | (8 if entry.descriptor else 0)
    if entry.zip64:
        values = entry.zip64_extra
        if values is None:
            values = struct.pack("<QQQ", usize, csize, offset)
        extra = struct.pack("<HH", 1, len(values)) + values + extra
        csize = usize = offset32 = MAX_U32
    else:
        offset32 = offset
    fixed = struct.pack(
        "<IHHHHHHIIIHHHHHII",
        0x02014B50,
        20,
        45 if entry.zip64 else 20,
        flags,
        entry.method,
        0,
        DOS_DATE,
        crc,
        csize & MAX_U32,
        usize & MAX_U32,
        len(entry.name),
        len(extra),
        len(entry.comment),
        entry.disk,
        0,
        0,
        offset32 & MAX_U32,
    )
    return fixed + entry.name + extra + entry.comment


def end_record(count, size, offset, comment=b"", disk=0, cd_disk=0, count_disk=None):
    return (
        struct.pack(
            "<IHHHHIIH",
            0x06054B50,
            disk,
            cd_disk,
            pick(count_disk, count),
            count,
            size,
            offset,
            len(comment),
        )
        + comment
    )


def zip64_end(count, size, offset, disk=0, cd_disk=0):
    record = struct.pack(
        "<IQHHIIQQQQ", 0x06064B50, 44, 45, 45, disk, cd_disk, count, count, size, offset
    )
    return record


def zip64_locator(record_offset, disks=1):
    return struct.pack("<IIQI", 0x07064B50, 0, record_offset, disks)


def assemble(entries, **options):
    """The archive bytes. Options: comment, zip64 (write ZIP64 end records), saturate (ordinary end record
    holds 0xFFFF/0xFFFFFFFF), count, disk, cd_disk, zip64_count, trailing, suffix_before_cd."""
    body = b""
    placed = []
    for entry in entries:
        offset = len(body)
        stored = entry.stored_bytes()
        body += local_header(entry, stored) + stored
        if entry.descriptor:
            body += descriptor_bytes(entry, stored)
        placed.append((entry, stored, offset))
    directory = b"".join(central_header(entry, stored, offset) for entry, stored, offset in placed)
    cd_offset, cd_size = len(body), len(directory)
    count = options.get("count", len(entries))
    tail = b""
    if options.get("zip64"):
        record_offset = cd_offset + cd_size
        tail += zip64_end(options.get("zip64_count", len(entries)), cd_size, cd_offset)
        tail += zip64_locator(record_offset)
    ordinary = (count, cd_size, cd_offset)
    if options.get("saturate"):
        ordinary = (0xFFFF, MAX_U32, MAX_U32)
    tail += end_record(
        *ordinary,
        comment=options.get("comment", b""),
        disk=options.get("disk", 0),
        cd_disk=options.get("cd_disk", 0),
    )
    return body + directory + tail + options.get("trailing", b"")


# ---------------------------------------------------------------- cases

CASES = []


def case(
    name, expect, note, archive, manifest=None, manifest_text=None, parse_header=False, files=None
):
    """Registers a case. `files` are the stand-in contents the manifest is computed from by default."""
    files = files if files is not None else standard_files()
    record = {"name": name, "file": f"container/{name}.zip", "expect": expect, "note": note}
    if manifest_text is not None:
        record["manifestText"] = manifest_text
    else:
        record["manifest"] = manifest if manifest is not None else manifest_for(files)
    if parse_header:
        record["parseHeader"] = True
    CASES.append((record, archive))


def standard_files():
    return {
        "journal.sqlite": DATABASE,
        f"attachments/{IMAGE_A}": PICTURE_A,
        f"attachments/{IMAGE_B}": PICTURE_B,
    }


def standard_entries(method=STORED, **per_entry):
    """The four entries of an archive: database, two images, header."""
    entries = []
    for name, data in standard_files().items():
        entries.append(Entry(name, data, method, **per_entry.get(name, {})))
    entries.append(
        Entry("archive.json", OPAQUE_HEADER, method, **per_entry.get("archive.json", {}))
    )
    return entries


def accept(name, note, entries=None, files=None, **options):
    entries = entries if entries is not None else standard_entries()
    case(name, "accept", note, assemble(entries, **options), files=files)


def damaged(name, note, archive, **kwargs):
    case(name, "damaged", note, archive, **kwargs)


def with_entry(entries, name, **changes):
    for entry in entries:
        if entry.name == name.encode():
            for key, value in changes.items():
                setattr(entry, key, value)
    return entries


def build_accepted():
    accept("stored", "Stored entries, no extras: the baseline.")
    accept("deflated", "Every entry deflated (method 8).", entries=standard_entries(DEFLATED))
    descriptors = [Entry(e.name, e.data, e.method, descriptor=True) for e in standard_entries()]
    accept(
        "data-descriptors",
        "Flag bit 3: sizes and CRC-32 only in the descriptor and the central directory.",
        descriptors,
    )
    garbage = [
        Entry(
            e.name, e.data, e.method, descriptor=True, lcrc=0xDEADBEEF, lcsize=12345, lusize=67890
        )
        for e in standard_entries()
    ]
    accept(
        "local-bit3-nonzero-sizes",
        "Flag bit 3 with non-zero, wrong local sizes and CRC-32: the local values are ignored.",
        garbage,
    )
    wrong_local = [
        Entry(e.name, e.data, e.method, lcrc=0x01020304, lcsize=3, lusize=4)
        for e in standard_entries()
    ]
    accept(
        "local-sizes-ignored",
        "No flag bit 3, local sizes and CRC-32 disagree with the central directory: still ignored.",
        wrong_local,
    )
    local64 = [Entry(e.name, e.data, e.method, lzip64=True) for e in standard_entries()]
    accept(
        "local-zip64-extra",
        "Local headers carry saturated sizes and a ZIP64 extra field; the central sizes are not saturated.",
        local64,
    )
    z64 = [Entry(e.name, e.data, e.method, zip64=True) for e in standard_entries()]
    accept(
        "zip64-small",
        "ZIP64 structures on a small archive: saturated central fields and extra fields, ZIP64 end records.",
        z64,
        zip64=True,
        saturate=True,
    )
    accept(
        "zip64-end-records-unsaturated",
        "ZIP64 end records present although the ordinary record is not saturated (and agrees).",
        zip64=True,
    )
    extras = []
    for e in standard_entries():
        unix = struct.pack("<HHBIII", 0x5455, 13, 7, 0, 0, 0)
        extras.append(
            Entry(
                e.name, e.data, e.method, lextra=unix, cextra=struct.pack("<HH", 0xCAFE, 3) + b"abc"
            )
        )
    accept(
        "unknown-extra-fields-and-comment",
        "Unknown extra fields and an archive comment are ignored.",
        extras,
        comment=b"made by a test; no end record in here",
    )
    noise = standard_entries()
    noise += [
        Entry("__MACOSX/._journal.sqlite", b"AppleDouble"),
        Entry(".DS_Store", b"\0\0\0\1Bud1"),
        Entry("notes.txt", b"hello"),
        Entry("attachments/", b""),
        Entry(f"attachments/{UNLISTED}", pseudo_text("unlisted", 40)),
        Entry("unknown-method.bin", b"\1\2\3", method=99, flags=0x0041, payload=b"\xfe\xed"),
    ]
    accept(
        "unlisted-noise",
        "Unlisted entries, including an unlisted UUID-named file once and one with an unknown flag and method, are ignored.",
        noise,
    )
    shuffled = standard_entries()
    shuffled = [shuffled[3], shuffled[2], shuffled[0], shuffled[1]]
    accept(
        "entry-order",
        "archive.json first and the database last: the order is not part of the contract.",
        shuffled,
    )
    files_no_images = {"journal.sqlite": DATABASE}
    accept(
        "no-images",
        "An empty attachments map and no image entries.",
        [Entry("journal.sqlite", DATABASE), Entry("archive.json", OPAQUE_HEADER)],
        files=files_no_images,
    )
    empty_files = {"journal.sqlite": DATABASE, f"attachments/{IMAGE_A}": b""}
    accept(
        "zero-length-stored",
        "A zero-length listed entry, stored.",
        [
            Entry("journal.sqlite", DATABASE),
            Entry(f"attachments/{IMAGE_A}", b""),
            Entry("archive.json", OPAQUE_HEADER),
        ],
        files=empty_files,
    )
    accept(
        "zero-length-deflated",
        "A zero-length listed entry as the two-byte empty deflate stream.",
        [
            Entry("journal.sqlite", DATABASE),
            Entry(f"attachments/{IMAGE_A}", b"", DEFLATED, payload=b"\x03\x00"),
            Entry("archive.json", OPAQUE_HEADER),
        ],
        files=empty_files,
    )
    differing = [
        Entry(e.name, e.data, e.method, lextra=b"\x99\x99\x04\x00abcd", cextra=b"")
        if i % 2 == 0
        else Entry(
            e.name, e.data, e.method, lextra=b"", cextra=struct.pack("<HH", 0x9999, 6) + b"ABCDEF"
        )
        for i, e in enumerate(standard_entries())
    ]
    accept(
        "local-extra-length-differs",
        "The local extra field is longer or shorter than the central one: the data starts after the local lengths.",
        differing,
    )
    cased = standard_entries()
    cased += [
        Entry("Journal.sqlite", b"other"),
        Entry("ARCHIVE.JSON", b"other"),
        Entry("attachments/01234567-89AB-4CDE-8FAB-0123456789AB", b"upper-case name"),
        Entry("attachments\\01234567-89ab-4cde-8fab-0123456789ab", b"backslash"),
        Entry("attachments/../journal.sqlite", b"traversal name"),
        Entry(b"attachments/\x00" + IMAGE_A.encode()[1:], b"nul in name"),
    ]
    accept(
        "names-that-only-look-like-profile-names",
        "Names that differ from a profile name by case, a backslash, '..' or NUL are just unlisted names.",
        cased,
    )
    # About six-fold expansion: allowed.
    rng = random.Random(6)
    sixfold = None
    for repeat in range(2, 60):
        unit = bytes(rng.randrange(256) for _ in range(40))
        data = unit * repeat
        ratio = len(data) / len(deflate(data))
        if 5.5 <= ratio <= 7.0:
            sixfold = data
            break
    assert sixfold, "no six-fold sample"
    six_files = {"journal.sqlite": sixfold}
    accept(
        "deflate-about-6x",
        "A deflated database that expands about 6 times: below the cap of 8.",
        [Entry("journal.sqlite", sixfold, DEFLATED), Entry("archive.json", OPAQUE_HEADER)],
        files=six_files,
    )
    boundary = exact_expansion(8)
    accept(
        "deflate-exactly-8x",
        "Uncompressed size equals 8 times the compressed size: allowed.",
        [Entry("journal.sqlite", boundary, DEFLATED), Entry("archive.json", OPAQUE_HEADER)],
        files={"journal.sqlite": boundary},
    )
    manifest = manifest_for(standard_files())
    manifest["comment"] = "unknown members are ignored"
    manifest["database"]["note"] = {"future": True}
    case(
        "manifest-unknown-members",
        "accept",
        "Unknown members of the manifest are ignored.",
        assemble(standard_entries()),
        manifest=manifest,
    )
    header = valid_header()
    case(
        "header-valid",
        "accept",
        "A header within the envelope bounds: salt of 16 bytes, 100,000 iterations, recovery format 1.",
        assemble([Entry("journal.sqlite", DATABASE), Entry("archive.json", header)]),
        files={"journal.sqlite": DATABASE},
        parse_header=True,
    )


def exact_expansion(factor):
    """Zero bytes of a length n whose raw deflate is c bytes with n == factor * c."""
    for compressed in range(2, 40):
        data = b"\0" * (factor * compressed)
        if len(deflate(data)) == compressed:
            return data
    raise AssertionError("no exact expansion sample")


def just_over_expansion(factor):
    for compressed in range(2, 40):
        for extra in (1,):
            data = b"\0" * (factor * compressed + extra)
            if len(deflate(data)) == compressed:
                return data
    raise AssertionError("no over-expansion sample")


def b64(data):
    return base64.b64encode(data).decode()


def header_json(**changes):
    envelope = {
        "salt": b64(bytes(range(1, 17))),
        "wrappedKey": b64(bytes(range(60))),
        "iterations": 600000,
        "formatVersion": 1,
    }
    envelope.update(changes.pop("envelope", {}))
    header = {"archiveVersion": 2, "manifest": b64(bytes(60)), "recovery": envelope}
    header.update(changes)
    return json.dumps(header, separators=(",", ":"), sort_keys=True)


def valid_header():
    return header_json().encode()


def build_structure():
    base = standard_entries()
    good = assemble(base)
    damaged(
        "random-bytes",
        "Not a ZIP file at all.",
        bytes(random.Random(1).randrange(256) for _ in range(300)),
    )
    damaged("truncated", "The end of the file is cut off: no end record.", good[:-40])
    damaged("empty-file", "Zero bytes.", b"")
    damaged(
        "directory-offset-out-of-range",
        "The end record points the central directory beyond the file.",
        bytes_replace_end(good, offset=len(good) + 500),
    )
    damaged(
        "directory-size-too-large",
        "The end record claims a larger central directory than the file holds before it.",
        assemble_with_end(base, size_delta=500),
    )
    damaged(
        "comment-length-mismatch",
        "The comment length in the end record does not reach the end of the file.",
        good[:-2] + struct.pack("<H", 5),
    )
    damaged(
        "trailing-bytes-after-end-record",
        "Bytes after a complete end record: no end record reaches the end of the file.",
        good + b"trailing",
    )
    damaged(
        "two-end-records",
        "A second, internally consistent end record forged inside the comment: two candidates reach the end of the file.",
        forged_end_record(base),
    )
    damaged(
        "entry-count-too-small",
        "The end record counts fewer entries than the central directory holds.",
        assemble(base, count=3),
    )
    damaged(
        "entry-count-too-large",
        "The end record counts more entries than the central directory holds.",
        assemble(base, count=5),
    )
    damaged(
        "nonzero-disk-number", "The disk number of the end record is 1.", assemble(base, disk=1)
    )
    damaged(
        "nonzero-directory-disk",
        "The disk holding the central directory is 1.",
        assemble(base, cd_disk=1),
    )
    damaged(
        "zip64-and-ordinary-disagree",
        "ZIP64 and ordinary end records give different entry counts, and the ordinary one is not saturated.",
        assemble(base, zip64=True, zip64_count=3),
    )
    damaged(
        "zip64-locator-without-record",
        "A ZIP64 locator that points at no ZIP64 end record.",
        zip64_locator_nowhere(base),
    )
    damaged(
        "saturated-end-without-zip64",
        "The end record is saturated but there are no ZIP64 end records.",
        assemble(base, saturate=True),
    )
    near = (1 << 64) - 10
    big = standard_entries()
    big[0] = Entry(
        "journal.sqlite",
        DATABASE,
        zip64=True,
        zip64_extra=struct.pack("<QQQ", len(DATABASE), near, 0),
    )
    damaged(
        "compressed-size-near-2-64",
        "A listed entry's compressed size is near 2^64: adding it to the offset overflows.",
        assemble(big, zip64=True, saturate=True),
    )
    big = standard_entries()
    big[1] = Entry(
        f"attachments/{IMAGE_A}",
        PICTURE_A,
        zip64=True,
        zip64_extra=struct.pack("<QQQ", len(PICTURE_A), len(PICTURE_A), near),
    )
    damaged(
        "offset-near-2-64",
        "A listed entry's local header offset is near 2^64.",
        assemble(big, zip64=True, saturate=True),
    )
    nosuch = standard_entries()
    nosuch[0] = Entry("journal.sqlite", DATABASE, zip64=True, zip64_extra=b"")
    damaged(
        "zip64-saturated-without-extra-value",
        "Sizes and offset are saturated but the ZIP64 extra field is empty.",
        assemble(nosuch, zip64=True, saturate=True),
    )
    short = standard_entries()
    short[0] = Entry(
        "journal.sqlite",
        DATABASE,
        zip64=True,
        zip64_extra=struct.pack("<QQ", len(DATABASE), len(DATABASE)),
    )
    damaged(
        "zip64-extra-too-short",
        "The ZIP64 extra field lacks the offset the saturated field asks for.",
        assemble(short, zip64=True, saturate=True),
    )
    damaged(
        "central-extra-past-directory",
        "A central directory entry whose extra field runs past the end of the directory.",
        patch_central_length(base, entry_index=3, field=30, value=4000),
    )
    damaged(
        "central-comment-past-directory",
        "A central directory entry whose comment runs past the end of the directory.",
        patch_central_length(base, entry_index=3, field=32, value=4000),
    )
    damaged(
        "central-name-past-directory",
        "A central directory entry whose name runs past the end of the directory.",
        patch_central_length(base, entry_index=3, field=28, value=4000),
    )
    huge = standard_entries()
    huge[1] = Entry(f"attachments/{IMAGE_A}", PICTURE_A, csize=500000, usize=500000)
    damaged(
        "compressed-size-larger-than-file",
        "A listed compressed size larger than the file.",
        assemble(huge),
        manifest=huge_manifest(500000),
    )
    duplicate = standard_entries() + [Entry("journal.sqlite", b"second database")]
    damaged("duplicate-database", "Two entries named journal.sqlite.", assemble(duplicate))
    duplicate = standard_entries() + [Entry("archive.json", b"{}")]
    damaged("duplicate-header", "Two entries named archive.json.", assemble(duplicate))
    twice = standard_entries() + [
        Entry(f"attachments/{UNLISTED}", b"one"),
        Entry(f"attachments/{UNLISTED}", b"two"),
    ]
    damaged(
        "duplicate-unlisted-uuid",
        "Two entries with the same UUID name that the manifest does not list: refused, so readers that keep only listed names cannot disagree.",
        assemble(twice),
    )
    damaged(
        "local-name-differs",
        "The local header repeats a different name than the central directory.",
        assemble(
            with_entry(
                standard_entries(),
                f"attachments/{IMAGE_A}",
                lname=f"attachments/{IMAGE_B}".encode(),
            )
        ),
    )
    damaged(
        "local-method-differs",
        "The local header says deflate, the central directory says stored.",
        assemble(with_entry(standard_entries(), "journal.sqlite", lmethod=DEFLATED)),
    )
    damaged(
        "local-header-signature",
        "A listed entry whose offset does not point at a local header.",
        bad_local_signature(base),
    )
    damaged(
        "overlapping-listed-entries",
        "Two listed entries whose data ranges overlap: the second lies inside the first's data.",
        overlapping(inside_header=False),
        manifest=overlap_manifest(False),
    )
    damaged(
        "header-overlaps-listed-entry",
        "archive.json lies inside a listed entry's data.",
        overlapping(inside_header=True),
        manifest=overlap_manifest(True),
    )
    damaged(
        "data-covers-central-directory",
        "A listed entry whose data range reaches over the central directory.",
        cover_directory(),
        manifest=cover_manifest(),
    )


def central_size(entries):
    return sum(len(central_header(e, e.stored_bytes(), 0)) for e in entries)


def bytes_replace_end(archive, offset):
    return archive[:-6] + struct.pack("<I", offset) + archive[-2:]


def assemble_with_end(entries, size_delta):
    good = assemble(entries)
    size_at = len(good) - 22 + 12
    size = struct.unpack("<I", good[size_at : size_at + 4])[0]
    return good[:size_at] + struct.pack("<I", size + size_delta) + good[size_at + 4 :]


def forged_end_record(entries):
    """The real end record's comment ends in a forged end record that is consistent with the directory."""
    body = assemble(entries)
    cd_size = central_size(entries)
    cd_offset = len(body) - 22 - cd_size
    forged = end_record(len(entries), cd_size, cd_offset)
    real = body[:-22] + end_record(len(entries), cd_size, cd_offset, comment=b"padding " + forged)
    return real


def zip64_locator_nowhere(entries):
    body = assemble(entries)
    return body[:-22] + zip64_locator(len(body) + 100) + body[-22:]


def patch_central_length(entries, entry_index, field, value):
    body = bytearray(assemble(entries))
    offset = len(body) - 22 - central_size(entries)
    for index, entry in enumerate(entries):
        if index == entry_index:
            struct.pack_into("<H", body, offset + field, value)
        offset += len(central_header(entry, entry.stored_bytes(), 0))
    return bytes(body)


def huge_manifest(size):
    manifest = manifest_for(standard_files())
    manifest["attachments"][IMAGE_A]["bytes"] = size
    return manifest


def bad_local_signature(entries):
    body = bytearray(assemble(entries))
    first_local = len(local_header(entries[0], entries[0].stored_bytes())) + len(
        entries[0].stored_bytes()
    )
    body[first_local : first_local + 4] = b"XXXX"
    return bytes(body)


def overlapping(inside_header):
    """An archive whose first entry's data holds a complete local header and data of a second entry."""
    inner_name = b"archive.json" if inside_header else f"attachments/{IMAGE_A}".encode()
    inner_data = OPAQUE_HEADER if inside_header else PICTURE_A
    inner = Entry(inner_name, inner_data)
    inner_blob = local_header(inner, inner.stored_bytes()) + inner.stored_bytes()
    prefix = b"x" * 20
    outer_data = prefix + inner_blob + b"y" * 20
    outer = Entry("journal.sqlite", outer_data)
    outer_header = local_header(outer, outer.stored_bytes())
    inner_offset = len(outer_header) + len(prefix)
    inner.offset = inner_offset
    body = outer_header + outer_data
    others = (
        [Entry("archive.json", OPAQUE_HEADER)]
        if not inside_header
        else [Entry(f"attachments/{IMAGE_A}", PICTURE_A)]
    )
    placed = [(outer, outer_data, 0), (inner, inner.stored_bytes(), inner_offset)]
    for other in others:
        placed.append((other, other.stored_bytes(), len(body)))
        body += local_header(other, other.stored_bytes()) + other.stored_bytes()
    directory = b"".join(central_header(e, s, o) for e, s, o in placed)
    return body + directory + end_record(len(placed), len(directory), len(body))


def overlap_manifest(inside_header):
    """Sizes agree with the central directory, so that only the overlap is the defect."""
    outer = overlapping_outer_data(inside_header)
    return {
        "database": {"sha256": sha(outer), "bytes": len(outer)},
        "attachments": {IMAGE_A: {"sha256": sha(PICTURE_A), "bytes": len(PICTURE_A)}},
    }


def overlapping_outer_data(inside_header):
    inner = Entry(
        b"archive.json" if inside_header else f"attachments/{IMAGE_A}".encode(),
        OPAQUE_HEADER if inside_header else PICTURE_A,
    )
    return b"x" * 20 + local_header(inner, inner.stored_bytes()) + inner.stored_bytes() + b"y" * 20


def cover_directory():
    """The last entry's compressed size runs on over the central directory."""
    entries = [
        Entry("archive.json", OPAQUE_HEADER),
        Entry("journal.sqlite", DATABASE),
        Entry(f"attachments/{IMAGE_A}", PICTURE_A),
        Entry(
            f"attachments/{IMAGE_B}",
            PICTURE_B,
            csize=len(PICTURE_B) + 400,
            usize=len(PICTURE_B) + 400,
        ),
    ]
    return assemble(entries)


def cover_manifest():
    manifest = manifest_for(standard_files())
    manifest["attachments"][IMAGE_B]["bytes"] = len(PICTURE_B) + 400
    return manifest


def build_entries():
    def listed(name, **changes):
        return assemble(with_entry(standard_entries(), name, **changes))

    img = f"attachments/{IMAGE_A}"
    damaged(
        "encrypted-flag",
        "General-purpose flag bit 0 (encrypted) on a listed entry.",
        listed(img, flags=1),
    )
    damaged(
        "strong-encryption-flag",
        "Flag bit 6 (strong encryption) on a listed entry.",
        listed(img, flags=1 << 6),
    )
    damaged("method-12", "Compression method 12 (bzip2) on a listed entry.", listed(img, method=12))
    damaged("method-99", "Method 99 (AES encryption) on a listed entry.", listed(img, method=99))
    noisy = standard_entries() + [Entry("hidden.bin", b"x", flags=1 << 13)]
    damaged(
        "central-directory-encryption-flag",
        "Flag bit 13 (central directory encryption) on any entry refuses the archive.",
        assemble(noisy),
    )
    missing = standard_files()
    manifest = manifest_for(missing)
    manifest["attachments"][UNLISTED] = {"sha256": sha(b"absent"), "bytes": 6}
    damaged(
        "listed-entry-missing",
        "The manifest lists an image that has no entry.",
        assemble(standard_entries()),
        manifest=manifest,
    )
    wrong = manifest_for(standard_files())
    wrong["attachments"][IMAGE_A]["bytes"] = len(PICTURE_A) + 1
    damaged(
        "size-differs-from-manifest",
        "The manifest says a different size than the central directory.",
        assemble(standard_entries()),
        manifest=wrong,
    )
    damaged(
        "stored-size-mismatch",
        "A stored entry whose compressed size is not its size.",
        listed(img, csize=len(PICTURE_A) + 1),
    )
    zero = [
        Entry("journal.sqlite", DATABASE),
        Entry(img, b"", DEFLATED, payload=b"", csize=0),
        Entry("archive.json", OPAQUE_HEADER),
    ]
    damaged(
        "deflate-compressed-size-zero",
        "Method 8 with a compressed size of 0.",
        assemble(zero),
        files={"journal.sqlite": DATABASE, img: b""},
    )
    damaged(
        "stale-crc",
        "The CRC-32 of a listed entry is wrong in the local header and the central directory.",
        listed(img, crc=0x12345678, lcrc=0x12345678),
    )
    changed = bytearray(PICTURE_A)
    changed[3] ^= 1
    different = standard_entries()
    different[1] = Entry(img, bytes(changed))
    damaged(
        "sha256-differs",
        "The data and its CRC-32 are consistent, but the manifest hash is of other data.",
        assemble(different),
    )
    # A deflate stream that produces far more than the declared size (a small file, a large output).
    bomb = deflate(b"A" * 800)
    declared = b"A" * 60
    expanding = [
        Entry("journal.sqlite", DATABASE),
        Entry(img, declared, DEFLATED, payload=bomb),
        Entry("archive.json", OPAQUE_HEADER),
    ]
    damaged(
        "deflate-expands-past-declared-size",
        "A deflate stream that would produce 800 bytes for a declared size of 60: the reader stops at the declared size.",
        assemble(expanding),
        files={"journal.sqlite": DATABASE, img: declared},
    )
    declared = b"B" * 40
    early = [
        Entry("journal.sqlite", DATABASE),
        Entry(img, declared, DEFLATED, payload=deflate(b"B" * 20)),
        Entry("archive.json", OPAQUE_HEADER),
    ]
    damaged(
        "deflate-ends-early",
        "A deflate stream that ends after 20 of the 40 declared bytes.",
        assemble(early),
        files={"journal.sqlite": DATABASE, img: declared},
    )
    declared = b"C" * 60
    trailing = [
        Entry("journal.sqlite", DATABASE),
        Entry(img, declared, DEFLATED, payload=deflate(declared) + b"JUNK"),
        Entry("archive.json", OPAQUE_HEADER),
    ]
    damaged(
        "deflate-trailing-bytes",
        "Bytes after the end of the deflate stream, still inside the compressed size.",
        assemble(trailing),
        files={"journal.sqlite": DATABASE, img: declared},
    )
    over = just_over_expansion(8)
    damaged(
        "deflate-just-over-8x",
        "Uncompressed size is one byte more than 8 times the compressed size.",
        assemble([Entry("journal.sqlite", over, DEFLATED), Entry("archive.json", OPAQUE_HEADER)]),
        files={"journal.sqlite": over},
    )
    claim = [
        Entry("journal.sqlite", DATABASE),
        Entry(img, b"D" * 5000, DEFLATED),
        Entry("archive.json", OPAQUE_HEADER),
    ]
    damaged(
        "deflate-highly-compressed",
        "A stream that expands 5000 bytes from about 20: well over 8 times.",
        assemble(claim),
        files={"journal.sqlite": DATABASE, img: b"D" * 5000},
    )
    big_header = Entry(
        "archive.json", OPAQUE_HEADER, csize=16 * 1024 * 1024 + 1, usize=16 * 1024 * 1024 + 1
    )
    damaged(
        "header-larger-than-16-mib",
        "archive.json declares more than 16 MiB.",
        assemble([Entry("journal.sqlite", DATABASE), big_header]),
        files={"journal.sqlite": DATABASE},
    )
    damaged(
        "central-offset-not-a-local-header",
        "The central directory points a listed entry at an offset that holds no local header.",
        assemble(with_entry(standard_entries(), img, offset=5)),
    )


def manifest_text_cases():
    files = standard_files()
    good = manifest_for(files)

    def text(manifest):
        return json.dumps(manifest, separators=(",", ":"))

    base = text(good)
    entry_a = json.dumps(good["attachments"][IMAGE_A], separators=(",", ":"))

    def bad(name, note, value):
        damaged(name, note, assemble(standard_entries()), manifest_text=value)

    bad(
        "manifest-duplicate-member",
        "A repeated member name in the manifest.",
        base.replace(
            '"database"', '"database":{"sha256":"' + "0" * 64 + '","bytes":1},"database"', 1
        ),
    )
    bad(
        "manifest-duplicate-attachment-key",
        "The same image key twice.",
        base.replace(f'"{IMAGE_A}":{entry_a}', f'"{IMAGE_A}":{entry_a},"{IMAGE_A}":{entry_a}', 1),
    )
    bad(
        "manifest-bytes-float",
        "A size written as 70.0.",
        base.replace('"bytes":70', '"bytes":70.0', 1),
    )
    bad(
        "manifest-bytes-exponent",
        "A size written as 7e1.",
        base.replace('"bytes":70', '"bytes":7e1', 1),
    )
    bad("manifest-bytes-negative", "A negative size.", base.replace('"bytes":70', '"bytes":-70', 1))
    bad(
        "manifest-bytes-above-2-53",
        "A size above 2^53 - 1.",
        base.replace('"bytes":70', '"bytes":9007199254740992', 1),
    )
    bad(
        "manifest-bytes-leading-zero",
        "A size with a leading zero.",
        base.replace('"bytes":70', '"bytes":070', 1),
    )
    for name, key, note in [
        ("manifest-key-uppercase", IMAGE_A.upper(), "An upper-case UUID key."),
        ("manifest-key-braces", "{" + IMAGE_A + "}", "A key in braces."),
        ("manifest-key-no-hyphens", IMAGE_A.replace("-", ""), "A key without hyphens."),
        ("manifest-key-traversal", "../x", "A key that names a file outside the folder."),
        ("manifest-key-path", "attachments/" + IMAGE_A, "A key with a path."),
    ]:
        bad(name, note, base.replace(IMAGE_A, key, 1))
    bad(
        "manifest-hash-uppercase",
        "A hash in upper-case hex.",
        base.replace(
            good["attachments"][IMAGE_A]["sha256"],
            good["attachments"][IMAGE_A]["sha256"].upper(),
            1,
        ),
    )
    bad("manifest-not-json", "Text that is not JSON.", "{not json")


def header_cases():
    def header_archive(text):
        return assemble([Entry("journal.sqlite", DATABASE), Entry("archive.json", text.encode())])

    def bad(name, note, text):
        damaged(
            name, note, header_archive(text), files={"journal.sqlite": DATABASE}, parse_header=True
        )

    good = header_json()
    bad(
        "header-duplicate-recovery",
        "A repeated recovery member in archive.json.",
        good[:-1]
        + ',"recovery":'
        + json.dumps({"salt": "", "wrappedKey": "", "iterations": 0, "formatVersion": 4})
        + "}",
    )
    bad(
        "header-iterations-below-minimum",
        "99,999 iterations: outside the bounds a reader enforces before it asks for a password.",
        header_json(envelope={"iterations": 99999}),
    )
    bad(
        "header-iterations-above-maximum",
        "2,000,001 iterations.",
        header_json(envelope={"iterations": 2000001}),
    )
    bad(
        "header-salt-15-bytes",
        "A salt of 15 bytes.",
        header_json(envelope={"salt": b64(bytes(15))}),
    )
    bad(
        "header-recovery-format-3",
        "A file archive is always encrypted: recovery format 3 is damage.",
        header_json(envelope={"formatVersion": 3}),
    )
    bad(
        "header-recovery-format-4",
        "Recovery format 4 (no password).",
        header_json(envelope={"formatVersion": 4, "salt": "", "wrappedKey": "", "iterations": 0}),
    )
    bad(
        "header-without-archive-version",
        "No archiveVersion member: not a file archive.",
        json.dumps({"manifest": b64(bytes(60)), "recovery": json.loads(header_json())["recovery"]}),
    )
    bad(
        "header-archive-version-1",
        "archiveVersion 1 is not defined.",
        header_json(archiveVersion=1),
    )
    bad(
        "header-archive-version-float",
        "archiveVersion written as 2.0.",
        header_json().replace('"archiveVersion":2', '"archiveVersion":2.0'),
    )
    bad("header-bom", "A byte order mark in front of the JSON.", "﻿" + header_json())
    bad("header-trailing-comma", "A trailing comma.", header_json()[:-1] + ",}")
    bad(
        "header-manifest-not-base64",
        "The manifest member is not base64.",
        header_json(manifest="not base64 !!"),
    )
    damaged(
        "header-newer-archive-version",
        "archiveVersion 3: a newer archive. Reported as newer, not damaged.",
        header_archive(header_json(archiveVersion=3)),
        files={"journal.sqlite": DATABASE},
        parse_header=True,
    )
    CASES[-1][0]["expect"] = "newer"


def main():
    build_accepted()
    build_structure()
    build_entries()
    manifest_text_cases()
    header_cases()
    out = HERE
    for old in out.glob("*.zip"):
        if not old.name.startswith("real-"):
            old.unlink()
    records = []
    names = set()
    for record, archive in CASES:
        assert record["name"] not in names, record["name"]
        names.add(record["name"])
        (out / f"{record['name']}.zip").write_bytes(archive)
        if record["expect"] == "accept":
            cross_check(record, archive)
        records.append(record)
    for sample in sorted(out.glob("real-*.zip")):
        records.append(real_tool_case(sample))
    document = {
        "corpusVersion": 1,
        "purpose": "Archives that exercise the ZIP container layer of protocol/archive.md (the file archive): structure, entry validation, and extraction of the entries a given manifest lists. See README.md in this folder.",
        "outcomes": "accept: every listed entry extracts and matches the manifest. damaged and newer are the message classes of protocol/archive.md (Failures): compare the class, not the reason.",
        "cases": records,
    }
    (HERE.parent / "container-v2.json").write_text(
        json.dumps(document, indent=2, sort_keys=True) + "\n"
    )
    print(f"{len(CASES)} generated cases, {len(records) - len(CASES)} real-tool samples")


def real_tool_case(sample):
    with zipfile.ZipFile(sample) as archive:
        files = {
            n: archive.read(n)
            for n in archive.namelist()
            if n in standard_files() or n == "archive.json"
        }
    return {
        "name": sample.stem,
        "file": f"container/{sample.name}",
        "expect": "accept",
        "note": "Written by a real tool (see README.md in this folder).",
        "manifest": manifest_for({k: v for k, v in files.items() if k != "archive.json"}),
    }


def cross_check(record, archive):
    """Python's zipfile must read an accepted case, and the bytes must match the manifest."""
    path = HERE / f"{record['name']}.zip"
    if "manifestText" in record:
        return
    if record.get("parseHeader"):
        return
    with zipfile.ZipFile(path) as zf:
        listed = ["journal.sqlite"] + [
            f"attachments/{key}" for key in record["manifest"]["attachments"]
        ]
        for name in listed:
            data = zf.read(name)
            expected = (
                record["manifest"]["database"]
                if name == "journal.sqlite"
                else record["manifest"]["attachments"][name.split("/", 1)[1]]
            )
            assert sha(data) == expected["sha256"] and len(data) == expected["bytes"], (
                record["name"],
                name,
            )


if __name__ == "__main__":
    sys.exit(main())
