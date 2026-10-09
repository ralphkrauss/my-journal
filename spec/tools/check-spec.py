#!/usr/bin/env python3
"""Checks the product specification in spec/ for consistency.

Usage:  python3 spec/tools/check-spec.py          (from the repository root)
        python3 tools/check-spec.py               (from spec/)

Standard library only. Exit status 1 when there are errors; warnings never fail the run.

Errors
  - copy/en.json (and copy/same-wording.json) don't parse, have duplicate or unsorted keys, or a bad entry shape (a text object is
    a plural one/other, or a variant: default plus at least one of mac, sentence, windows or android)
  - parity.yaml doesn't parse or breaks the structure described in its header (every entry needs `reference:` apple, windows or
    android, and the reference platform must not be marked not-applicable or different-by-design unless the feature is removed)
  - a copy key referenced in a spec file doesn't exist in copy/en.json
  - a command id is defined twice in commands.md, or a Command column names an unknown id
  - a feature id in a screen or flow's front matter isn't in parity.yaml
  - a relative link, a screens/ or flows/ path, or a link anchor doesn't resolve
  - a screen, flow or messages.md front matter is missing, or its id doesn't match the file name
  - a spec file contains a home path, an e-mail address or a personal name
  - a platform page (platforms/<platform>/screens, flows or messages.md) has a bad front matter (id, title, spec link, features,
    status; for Apple also devices), is missing a required section, isn't in the platform's index.md, or the platform's
    commands.md (every platform has one) doesn't cover every command id once;
    where a platform's commands.md has Shortcut and Scope columns, app-wide or editor-wide shortcuts must be unique
  - a screenshot a platform page lists under `screenshots:` doesn't exist, isn't named
    screenshots/<device>/<page id>-<state>.png, uses a device the platform doesn't define, or is listed by two pages

Warnings
  - copy keys that no spec file references
  - the same English text under different keys that copy/same-wording.json doesn't explain
  - features in parity.yaml that no screen, flow or messages.md lists (removed features excepted)
  - files named under `sources:` in a front matter that don't exist in the repository
  - screenshot files in a platform's screenshots/ folder that no page of that platform lists
"""
import json
import re
import sys
from pathlib import Path

SPEC = Path(__file__).resolve().parent.parent
REPO = SPEC.parent
AREAS = ("common", "library", "messages", "settings", "editor")
# Shapes a catalog entry's text object may take: plurals, and variants. A variant object has "default" plus at least one of
# the names below: "mac" (Apple's Mac text), "sentence" (the same wording in sentence case, shared by the platforms whose
# convention is sentence case, Windows and Android), and "windows" or "android" (a platform's own vocabulary, written in the
# casing that platform uses). The most specific name wins: a platform's own variant, then "sentence" on a sentence-case
# platform, then "mac" on the Mac, then "default".
PLURAL_SHAPE = {"one", "other"}
VARIANT_NAMES = {"mac", "sentence", "windows", "android"}
MAPPING_STATUSES = ("draft", "reviewed", "done")
# Sections every platform page of a screen, flow or messages.md has, in this order (matched by the start of the heading).
# A platform may add others (Implementation, Screenshots); it may not leave these out.
MAPPING_SECTIONS = (
    "Controls",
    "Layout",
    "Commands and shortcuts",
    "Copy differences",
    "Accessibility",
    "Different by design",
    "Open questions",
)
# Apple's pages record how the shipped apps implement a page, so they say where iPhone, iPad and Mac differ, and list the
# screenshots and the source files.
APPLE_SECTIONS = (
    "Controls",
    "Layout",
    "Commands and shortcuts",
    "Copy differences",
    "Accessibility",
    "Differences between iPhone, iPad and Mac",
    "Screenshots",
    "Source files",
    "Open questions",
)
APPLE_STATUSES = ("draft", "verified")
APPLE_DEVICES = ("iphone", "ipad", "mac")


class PlatformKind:
    """What a platform folder under platforms/ must hold. Apple differs; every other platform follows the Windows folder."""

    def __init__(self, sections, statuses, devices, required_files, needs_devices):
        self.sections = sections
        self.statuses = statuses
        self.index_statuses = ("todo",) + statuses
        self.devices = devices  # allowed screenshot device folders, or None for any kebab-case name
        self.required_files = required_files
        self.needs_devices = needs_devices


APPLE_KIND = PlatformKind(
    APPLE_SECTIONS, APPLE_STATUSES, APPLE_DEVICES, ("README.md", "platform.md", "commands.md", "index.md"), True
)
DEFAULT_KIND = PlatformKind(
    MAPPING_SECTIONS, MAPPING_STATUSES, None, ("README.md", "platform.md", "commands.md", "index.md"), False
)
SCREENSHOT_NAME = re.compile(r"screenshots/([a-z0-9]+(?:-[a-z0-9]+)*)/([a-z0-9]+(?:-[a-z0-9]+)*)\.png")
STATUSES = {"shipped", "partial", "planned", "different-by-design", "not-applicable"}
PLATFORMS = ("apple", "windows", "android")
# Kebab-case words in backticks that are neither commands, features nor pages (server capability names).
OTHER_IDS = {"pairing-check-code", "pairing-invite"} | STATUSES
FORBIDDEN = [
    (re.compile(r"/Users/|/home/[a-z]"), "home path"),
    (re.compile(r"[A-Za-z0-9._%+-]+@(?!example\.(?:com|org|net)\b)[A-Za-z0-9-]+\.[A-Za-z]{2,}"), "e-mail address"),
    (re.compile(r"Krauss|\bRalph\b", re.I), "personal name"),
]

errors = []
warnings = []


def err(where, message):
    errors.append(f"{where}: {message}")


def warn(where, message):
    warnings.append(f"{where}: {message}")


def rel(path):
    return str(Path(path).relative_to(SPEC))


# ---------------------------------------------------------------- JSON
def load_json_strict(path):
    def no_duplicates(pairs):
        seen = {}
        for key, value in pairs:
            if key in seen:
                err(rel(path), f"duplicate key {key!r}")
            seen[key] = value
        return seen

    try:
        return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=no_duplicates)
    except (OSError, ValueError) as exc:
        err(rel(path), f"doesn't parse as JSON: {exc}")
        return None


def check_catalog(catalog):
    keys = list(catalog)
    if keys != sorted(keys):
        err("copy/en.json", "keys are not sorted")
    for key, entry in catalog.items():
        if not re.fullmatch(r"(?:%s)(?:\.[A-Za-z0-9_]+)+" % "|".join(AREAS), key):
            err("copy/en.json", f"{key}: key doesn't follow <area>.<screen>.<element>")
        if not isinstance(entry, dict) or set(entry) != {"text", "context"}:
            err("copy/en.json", f"{key}: entry must be an object with exactly text and context")
            continue
        text, context = entry["text"], entry["context"]
        if not isinstance(context, str) or not context.strip():
            err("copy/en.json", f"{key}: empty context")
        if isinstance(text, str):
            if not text:
                err("copy/en.json", f"{key}: empty text")
        elif isinstance(text, dict):
            names = set(text)
            is_variant = "default" in names and len(names) > 1 and names <= VARIANT_NAMES | {"default"}
            if names != PLURAL_SHAPE and not is_variant:
                err(
                    "copy/en.json",
                    f"{key}: text object must be one/other, or default plus mac, sentence, windows or android, not {sorted(names)}",
                )
            elif not all(isinstance(v, str) and v for v in text.values()):
                err("copy/en.json", f"{key}: empty text variant")
        else:
            err("copy/en.json", f"{key}: text must be a string or an object")
        if "!" in json.dumps(text, ensure_ascii=False):
            warn("copy/en.json", f"{key}: text contains an exclamation mark")
        check_update_wording(key, text)


def check_update_wording(key, text):
    """A text about a newer version of the app tells the person to update My Journal, and never says that the
    app "needs an update": only a server needs an update, because the person can't do that from here."""
    variants = list(text.values()) if isinstance(text, dict) else [text]
    for variant in variants:
        if not isinstance(variant, str):
            continue
        if re.search(r"newer version", variant, re.I) and "update my journal" not in variant.lower():
            err("copy/en.json", f"{key}: a text about a newer version must say \"Update My Journal\"")
        if re.search(r"needs? an update", variant, re.I) and not re.search(r"server|\{host\}", variant, re.I):
            err("copy/en.json", f"{key}: only a server \"needs an update\"; the app says \"Update My Journal\"")


def flat_text(entry):
    return json.dumps(entry["text"], sort_keys=True, ensure_ascii=False)


# ---------------------------------------------------------------- YAML (parity.yaml)
def parse_scalar(raw, where):
    raw = raw.strip()
    if raw.startswith('"'):
        try:
            return json.loads(raw)
        except ValueError:
            raise ValueError(f"{where}: bad quoted string {raw[:40]!r}")
    if raw.startswith("["):
        if not raw.endswith("]"):
            raise ValueError(f"{where}: unterminated list")
        inner = raw[1:-1].strip()
        return [item.strip() for item in inner.split(",") if item.strip()]
    if not raw:
        raise ValueError(f"{where}: empty value")
    if re.search(r":\s", raw) or raw.startswith(("{", "&", "*", "!", "|", ">")):
        raise ValueError(f"{where}: plain value needs quotes: {raw[:40]!r}")
    return raw


def parse_parity_minimal(text):
    """Parses the small YAML subset parity.yaml uses: comments, `id:` mappings of `  field: value` lines."""
    data = {}
    current = None
    for number, line in enumerate(text.splitlines(), 1):
        where = f"parity.yaml:{number}"
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "\t" in line:
            raise ValueError(f"{where}: tab character")
        top = re.fullmatch(r"([a-z0-9][a-z0-9-]*):\s*", line)
        if top:
            current = top.group(1)
            if current in data:
                raise ValueError(f"{where}: duplicate feature id {current}")
            data[current] = {}
            continue
        field = re.fullmatch(r"  ([a-z][a-z-]*):\s+(.*)", line)
        if not field or current is None:
            raise ValueError(f"{where}: can't read {line[:60]!r}")
        name = field.group(1)
        if name in data[current]:
            raise ValueError(f"{where}: duplicate field {name}")
        data[current][name] = parse_scalar(field.group(2), where)
    return data


def load_parity():
    path = SPEC / "parity.yaml"
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        err("parity.yaml", f"can't read: {exc}")
        return {}
    try:
        data = parse_parity_minimal(text)
    except ValueError as exc:
        err("parity.yaml", str(exc))
        return {}
    try:
        import yaml  # optional: a strict second opinion when PyYAML is installed
    except ImportError:
        return data
    try:
        strict = yaml.safe_load(text)
    except Exception as exc:  # noqa: BLE001 - any parser error is a spec error
        err("parity.yaml", f"PyYAML can't parse it: {exc}")
        return data
    if strict != data:
        err("parity.yaml", "PyYAML and the minimal parser read different content")
    return data


ALLOWED_FIELDS = {"title", "specs", "reference"} | {p for p in PLATFORMS} | {f"{p}-{s}" for p in PLATFORMS for s in ("reason", "notes")}


def check_parity_structure(parity):
    for fid, entry in parity.items():
        where = f"parity.yaml ({fid})"
        for field in entry:
            if field not in ALLOWED_FIELDS:
                err(where, f"unknown field {field}")
        if not isinstance(entry.get("title"), str) or not entry.get("title"):
            err(where, "missing title")
        specs = entry.get("specs")
        if not isinstance(specs, list):
            err(where, "specs must be a list")
            specs = []
        for spec in specs:
            target, _, anchor = spec.partition("#")
            path = SPEC / target
            if not path.is_file():
                err(where, f"spec file {spec} doesn't exist")
            elif anchor and anchor not in anchors_of(path):
                err(where, f"spec anchor {spec} doesn't exist")
        reference = entry.get("reference")
        if reference not in PLATFORMS:
            err(where, f"reference must be one of {list(PLATFORMS)}, not {reference!r}")
        removed = all(entry.get(p) == "not-applicable" for p in PLATFORMS)
        if reference in PLATFORMS and not removed and entry.get(reference) == "not-applicable":
            err(where, f"the reference platform {reference} can't be not-applicable; it is where the feature originates")
        for platform in PLATFORMS:
            status = entry.get(platform)
            if status not in STATUSES:
                err(where, f"{platform}: status must be one of {sorted(STATUSES)}, not {status!r}")
            elif status in ("different-by-design", "not-applicable") and not entry.get(f"{platform}-reason"):
                err(where, f"{platform}: {status} needs {platform}-reason")


# ---------------------------------------------------------------- Markdown helpers
_anchor_cache = {}


def slugify(heading):
    text = re.sub(r"`", "", heading.strip().lower())
    text = re.sub(r"[^\w\- ]", "", text, flags=re.UNICODE)
    return text.replace(" ", "-")


def anchors_of(path):
    if path not in _anchor_cache:
        found = set()
        counts = {}
        in_code = False
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.startswith("```"):
                in_code = not in_code
            if in_code:
                continue
            m = re.match(r"#{1,6}\s+(.*?)\s*#*\s*$", line)
            if m:
                slug = slugify(m.group(1))
                n = counts.get(slug, 0)
                counts[slug] = n + 1
                found.add(slug if n == 0 else f"{slug}-{n}")
        _anchor_cache[path] = found
    return _anchor_cache[path]


def front_matter(text):
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not m:
        return None
    block = m.group(1)
    fm = {"_raw": block}
    for key in ("id", "title", "spec", "status"):
        k = re.search(rf"^{key}:\s*(.*?)\s*(?:#.*)?$", block, re.M)
        if k:
            fm[key] = k.group(1)
    f = re.search(r"^features:\s*\[(.*?)\]", block, re.M)
    fm["features"] = [s.strip() for s in f.group(1).split(",") if s.strip()] if f else None
    fm["sources"] = front_matter_list(block, "sources") or []
    fm["screenshots"] = front_matter_list(block, "screenshots") or []
    fm["devices"] = front_matter_list(block, "devices")
    return fm


def front_matter_list(block, key):
    """A list under `key:`, written inline (`key: [a, b]`) or as `- item` lines; None when the key is absent."""
    inline = re.search(rf"^{key}:\s*\[(.*?)\]", block, re.M)
    if inline:
        return [s.strip() for s in inline.group(1).split(",") if s.strip()]
    found = re.search(rf"^{key}:[ \t]*(?:#.*)?\n((?:[ \t]+- .*\n?)+)", block + "\n", re.M)
    if found:
        return [re.sub(r"\s+#.*$", "", re.sub(r"^\s+- ", "", line)).strip() for line in found.group(1).splitlines()]
    return None


# ---------------------------------------------------------------- Commands
def command_ids(path=None):
    """Command ids (and `format-*` style group names) defined in the first column of the tables headed `id`."""
    path = path or SPEC / "commands.md"
    defined = {}
    in_id_table = False
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.startswith("|"):
            in_id_table = False
            continue
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line)[1:-1]]
        if cells and cells[0] == "id":
            in_id_table = True
            continue
        if not in_id_table or cells[0].startswith("---"):
            continue
        for token in re.findall(r"`([^`]+)`", cells[0]):
            if token in defined:
                err(f"{rel(path)}:{number}", f"command id {token} is also defined at line {defined[token]}")
            else:
                defined[token] = number
    return defined


def is_command(token, commands):
    if token in commands:
        return True
    if token.endswith("*") and any(c.startswith(token[:-1]) for c in commands):
        return True
    return any(c.endswith("*") and token.startswith(c[:-1]) for c in commands)


# ---------------------------------------------------------------- Platform mappings
SHORTCUT_SCOPES = ("app", "editor", "list", "dialog", "system", "—")


def table_rows(text):
    """Yields (line number, header cells, row cells) for every body row of every table in text."""
    header = None
    for number, line in enumerate(text.splitlines(), 1):
        if not line.startswith("|"):
            header = None
            continue
        cells = [c.strip() for c in re.split(r"(?<!\\)\|", line)[1:-1]]
        if header is None:
            header = cells
            continue
        if cells and cells[0].startswith("---"):
            continue
        yield number, header, cells


def level2_headings(text):
    """The `## ` headings of a Markdown file, ignoring fenced code."""
    found = []
    in_code = False
    for line in text.splitlines():
        if line.startswith("```"):
            in_code = not in_code
        elif not in_code:
            m = re.match(r"## (.+?)\s*$", line)
            if m:
                found.append(m.group(1))
    return found


def spec_pages():
    """(kind, id) -> path relative to spec/, for every screen, flow and messages.md."""
    pages = {}
    for kind, folder in (("screen", "screens"), ("flow", "flows")):
        for path in sorted((SPEC / folder).glob("*.md")):
            pages[(kind, path.stem)] = f"{folder}/{path.name}"
    pages[("messages", "messages")] = "messages.md"
    return pages


def mapping_pages(platform_dir):
    """(kind, id) -> path of every mapping file of one platform."""
    found = {}
    for kind, folder in (("screen", "screens"), ("flow", "flows")):
        if (platform_dir / folder).is_dir():
            for path in sorted((platform_dir / folder).glob("*.md")):
                found[(kind, path.stem)] = path
    if (platform_dir / "messages.md").is_file():
        found[("messages", "messages")] = platform_dir / "messages.md"
    return found


def check_mapping_page(kind, page_id, path, pages, parity, platform, platform_kind, screenshot_owners):
    """Checks one platform page's front matter and sections; returns its status (or None)."""
    where = rel(path)
    text = path.read_text(encoding="utf-8")
    fm = front_matter(text)
    if fm is None:
        err(where, "missing front matter")
        return None
    if fm.get("id") != page_id:
        err(where, f"front matter id {fm.get('id')!r} doesn't match the file name")
    if not fm.get("title"):
        err(where, "front matter has no title")
    expected = pages.get((kind, page_id))
    spec_link = fm.get("spec")
    if not spec_link:
        err(where, "front matter has no spec link")
    elif expected is None:
        err(where, f"there is no {kind} {page_id} in the spec")
    elif spec_link != expected:
        err(where, f"front matter spec {spec_link!r} must be {expected!r}")
    if fm["features"] is None:
        err(where, "front matter has no features list")
    elif expected is not None and (SPEC / expected).is_file():
        spec_fm = front_matter((SPEC / expected).read_text(encoding="utf-8")) or {}
        listed = set(spec_fm.get("features") or [])
        for fid in fm["features"]:
            if fid not in parity:
                err(where, f"feature {fid} isn't in parity.yaml")
            elif fid not in listed:
                err(where, f"feature {fid} isn't listed by {expected}")
    status = fm.get("status")
    if status not in platform_kind.statuses:
        err(where, f"front matter status must be one of {list(platform_kind.statuses)}, not {status!r}")
    if platform_kind.needs_devices:
        devices = fm["devices"]
        if not devices:
            err(where, f"front matter has no devices list (any of {list(platform_kind.devices)})")
        else:
            for device in devices:
                if device not in platform_kind.devices:
                    err(where, f"device {device!r} must be one of {list(platform_kind.devices)}")
    for source in fm["sources"]:
        name = re.sub(r"\s*\(.*\)\s*$", "", source)
        if not source.startswith("https://") and not (REPO / name).exists():
            warn(where, f"source {source} doesn't exist in the repository")
    for shot in fm["screenshots"]:
        check_screenshot(where, page_id, shot, SPEC / "platforms" / platform, platform_kind, screenshot_owners)
    headings = level2_headings(text)
    position = 0
    for section in platform_kind.sections:
        for index in range(position, len(headings)):
            if headings[index].lower().startswith(section.lower()):
                position = index + 1
                break
        else:
            err(where, f"missing section ## {section}, or it is out of order")
    if platform_kind is APPLE_KIND and status == "verified" and not fm["screenshots"]:
        shots = section_text(text, "Screenshots")
        if not shots.lower().startswith("none"):
            err(where, "a verified page lists its screenshots in the front matter, or its Screenshots section starts with None and why")
    return status


def section_text(text, heading):
    """The text under the `## ` heading that starts with `heading`, up to the next `## ` heading."""
    lines = text.splitlines()
    for index, line in enumerate(lines):
        if line.startswith("## ") and line[3:].strip().lower().startswith(heading.lower()):
            body = []
            for following in lines[index + 1 :]:
                if following.startswith("## "):
                    break
                body.append(following)
            return "\n".join(body).strip()
    return ""


def check_screenshot(where, page_id, shot, platform_dir, platform_kind, owners):
    """A listed screenshot is screenshots/<device>/<page id>-<state>.png, exists, and belongs to one page."""
    match = SCREENSHOT_NAME.fullmatch(shot)
    if not match:
        err(where, f"screenshot {shot!r} must be named screenshots/<device>/<page id>-<state>.png in lower-case kebab-case")
        return
    device, name = match.groups()
    if platform_kind.devices is not None and device not in platform_kind.devices:
        err(where, f"screenshot {shot}: device must be one of {list(platform_kind.devices)}")
    if not name.startswith(page_id + "-"):
        err(where, f"screenshot {shot}: the file name must start with the page id {page_id}- and end with the state")
    if not (platform_dir / shot).is_file():
        err(where, f"screenshot {shot} doesn't exist")
    key = str(platform_dir / shot)
    if key in owners and owners[key] != where:
        err(where, f"screenshot {shot} is also listed by {owners[key]}")
    owners[key] = where


def check_mapping_commands(platform_dir, commands):
    """The platform's commands.md defines each command id once; app-wide shortcuts don't collide."""
    path = platform_dir / "commands.md"
    if not path.is_file():
        return
    defined = command_ids(path)
    for token in commands:
        if token not in defined:
            err(rel(path), f"command id {token} has no row")
    for token, number in defined.items():
        if token not in commands:
            err(f"{rel(path)}:{number}", f"command id {token} is not defined in commands.md")
    seen = {}
    list_rows = []
    for number, header, cells in table_rows(path.read_text(encoding="utf-8")):
        if "Shortcut" not in header or "Scope" not in header:
            continue
        row = dict(zip(header, cells, strict=False))
        scope = re.sub(r"[`*]", "", row.get("Scope", "")).strip().lower()
        if scope not in SHORTCUT_SCOPES:
            err(
                f"{rel(path)}:{number}",
                f"shortcut scope {scope!r} must be one of {list(SHORTCUT_SCOPES)}",
            )
            continue
        shortcuts = re.findall(r"`([^`]+)`", row.get("Shortcut", ""))
        if scope == "—" and shortcuts:
            err(f"{rel(path)}:{number}", "a row with shortcuts needs a scope")
        for shortcut in shortcuts:
            if scope in ("app", "editor"):
                if shortcut in seen:
                    err(
                        f"{rel(path)}:{number}",
                        f"shortcut {shortcut} is also used at line {seen[shortcut]}",
                    )
                else:
                    seen[shortcut] = number
            elif scope == "list":
                list_rows.append((shortcut, number))
    for shortcut, number in list_rows:
        if shortcut in seen:
            err(
                f"{rel(path)}:{number}",
                f"list shortcut {shortcut} is an app or editor shortcut (line {seen[shortcut]})",
            )


def check_mapping_index(platform_dir, pages, found, platform_kind):
    """index.md lists every spec page once, with its platform page and status (columns Spec, Kind, Mapping file or Page file, Status)."""
    path = platform_dir / "index.md"
    if not path.is_file():
        return
    files = {"screen": "screens/{}.md", "flow": "flows/{}.md", "messages": "messages.md"}
    listed = {}
    for number, header, cells in table_rows(path.read_text(encoding="utf-8")):
        if not header or header[0] != "Spec":
            continue
        where = f"{rel(path)}:{number}"
        row = dict(zip(header, cells, strict=False))
        ids = re.findall(r"`([^`]+)`", row.get("Spec", ""))
        kind = row.get("Kind", "").strip()
        names = re.findall(r"`([^`]+)`", row.get("Mapping file", row.get("Page file", "")))
        status = row.get("Status", "").strip()
        if len(ids) != 1 or kind not in files:
            err(where, "a row needs one spec id in backticks and a kind: screen, flow or messages")
            continue
        key = (kind, ids[0])
        if key not in pages:
            err(where, f"there is no {kind} {ids[0]} in the spec")
            continue
        if key in listed:
            err(where, f"{kind} {ids[0]} is also listed at line {listed[key]}")
        listed[key] = number
        if names != [files[kind].format(ids[0])]:
            err(where, f"the mapping file must be {files[kind].format(ids[0])}")
        if status not in platform_kind.index_statuses:
            err(where, f"status must be one of {list(platform_kind.index_statuses)}, not {status!r}")
        elif status == "todo" and key in found:
            err(where, "the mapping file exists, so the status can't be todo")
        elif status != "todo" and key not in found:
            err(where, f"status {status} needs the mapping file {files[kind].format(ids[0])}")
        elif status != "todo" and found.get(key) != status:
            err(where, f"status {status} differs from the file's own status {found.get(key)}")
    for key in sorted(pages):
        if key not in listed:
            err(rel(path), f"{key[0]} {key[1]} is not in the index")


def platform_kind_of(name):
    return APPLE_KIND if name == "apple" else DEFAULT_KIND


def check_platforms(parity, commands):
    root = SPEC / "platforms"
    if not root.is_dir():
        err("platforms", "folder is missing")
        return
    if not (root / "README.md").is_file():
        err("platforms", "missing README.md")
    pages = spec_pages()
    for platform_dir in sorted(p for p in root.iterdir() if p.is_dir()):
        name = platform_dir.name
        if name not in PLATFORMS:
            err(rel(platform_dir), f"platform folder must be named for one of {list(PLATFORMS)}")
            continue
        kind = platform_kind_of(name)
        for required in kind.required_files:
            if not (platform_dir / required).is_file():
                err(rel(platform_dir), f"missing {required}")
        statuses = {}
        owners = {}
        for (page_kind, page_id), path in mapping_pages(platform_dir).items():
            statuses[(page_kind, page_id)] = check_mapping_page(
                page_kind, page_id, path, pages, parity, name, kind, owners
            )
        if "commands.md" in kind.required_files:
            check_mapping_commands(platform_dir, commands)
        check_mapping_index(platform_dir, pages, statuses, kind)
        referenced = {Path(key).resolve() for key in owners}
        shots_dir = platform_dir / "screenshots"
        for shot in sorted(shots_dir.rglob("*.png")) if shots_dir.is_dir() else []:
            if shot.resolve() not in referenced:
                warn(rel(shot), "no page of this platform lists this screenshot")


# ---------------------------------------------------------------- Main checks
def main():
    md_files = sorted(p for p in SPEC.rglob("*.md") if "tools" not in p.relative_to(SPEC).parts)
    yaml_files = [SPEC / "parity.yaml"]

    # catalog
    catalog = load_json_strict(SPEC / "copy" / "en.json") or {}
    check_catalog(catalog)
    allowlist = load_json_strict(SPEC / "copy" / "same-wording.json") or []
    keys = set(catalog)
    prefixes = set()
    for key in keys:
        parts = key.split(".")
        for i in range(1, len(parts)):
            prefixes.add(".".join(parts[:i]))

    # parity
    parity = load_parity()
    check_parity_structure(parity)

    commands = command_ids()
    pages = {p.stem for p in (SPEC / "screens").glob("*.md")} | {p.stem for p in (SPEC / "flows").glob("*.md")}

    keyref = re.compile(
        r"(?<![\w./-])((?:%s)(?:\.[A-Za-z0-9_]+)+)(\.\*)?" % "|".join(AREAS)
    )
    ignored_suffix = {"md", "json", "yaml", "py", "swift", "txt", "html"}
    used = set()
    group_refs = 0

    def check_keys(text, where_prefix):
        nonlocal group_refs
        for number, line in enumerate(text.splitlines(), 1):
            for m in keyref.finditer(line):
                ref, wildcard = m.group(1), m.group(2)
                if ref.rsplit(".", 1)[-1] in ignored_suffix and not wildcard:
                    continue
                where = f"{where_prefix}:{number}"
                if ref in keys and not wildcard:
                    used.add(ref)
                elif ref in prefixes:
                    group_refs += 1
                    used.update(k for k in keys if k.startswith(ref + "."))
                    if ref in keys:
                        used.add(ref)
                else:
                    err(where, f"unknown copy key {ref}{wildcard or ''}")

    for path in md_files + yaml_files:
        check_keys(path.read_text(encoding="utf-8"), rel(path))
    # keys named inside the catalog's own contexts must exist too
    for key, entry in catalog.items():
        if isinstance(entry, dict) and isinstance(entry.get("context"), str):
            for m in keyref.finditer(entry["context"]):
                ref = m.group(1)
                if ref.rsplit(".", 1)[-1] in ignored_suffix:
                    continue
                if ref not in keys and ref not in prefixes:
                    err("copy/en.json", f"{key}: context names unknown key {ref}")

    # unused keys
    unused = sorted(keys - used)
    for key in unused:
        warn("copy/en.json", f"{key}: no spec file references this key")

    # same wording
    by_text = {}
    for key, entry in catalog.items():
        if isinstance(entry, dict) and "text" in entry:
            by_text.setdefault(flat_text(entry), []).append(key)
    allowed = []
    for group in allowlist:
        group_keys = group.get("keys", []) if isinstance(group, dict) else []
        allowed.append(frozenset(group_keys))
        if not group.get("reason"):
            err("copy/same-wording.json", f"group {group_keys} has no reason")
        texts = {flat_text(catalog[k]) for k in group_keys if k in catalog}
        missing = [k for k in group_keys if k not in catalog]
        if missing:
            err("copy/same-wording.json", f"unknown keys {missing}")
        elif len(texts) != 1:
            err("copy/same-wording.json", f"group {group_keys} doesn't share one text")
    for text, group_keys in by_text.items():
        if len(group_keys) > 1 and frozenset(group_keys) not in allowed:
            warn("copy/en.json", f"same text under different keys, not in same-wording.json: {sorted(group_keys)}")

    # links, paths and anchors
    link = re.compile(r"\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
    pathref = re.compile(r"(?<![\w/.<-])((?:\.\./)?(?:screens|flows)/[a-z0-9][a-z0-9-]*)(\.md)?(#[\w-]+)?(?![\w*-])")
    for path in md_files:
        text = path.read_text(encoding="utf-8")
        in_code = False
        for number, line in enumerate(text.splitlines(), 1):
            if line.startswith("```"):
                in_code = not in_code
            where = f"{rel(path)}:{number}"
            for m in link.finditer(re.sub(r"`[^`]*`", "", line)):
                target = m.group(1)
                if re.match(r"(https?:|mailto:)", target) or target.startswith("<"):
                    continue
                file_part, _, anchor = target.partition("#")
                if not file_part:
                    resolved = path
                else:
                    resolved = (path.parent / file_part).resolve()
                    if not resolved.exists():
                        err(where, f"link target {target} doesn't exist")
                        continue
                if anchor and resolved.suffix == ".md" and anchor not in anchors_of(resolved):
                    err(where, f"link anchor {target} doesn't exist")
            for m in pathref.finditer(line):
                base = m.group(1).replace("../", "")
                if not (SPEC / f"{base}.md").is_file():
                    err(where, f"{base} is not a spec file")
                elif m.group(3) and m.group(3)[1:] not in anchors_of(SPEC / f"{base}.md"):
                    err(where, f"anchor {m.group(3)} doesn't exist in {base}.md")
        for m in re.finditer(r"commands\.md#([\w-]+)", text):
            if m.group(1) not in anchors_of(SPEC / "commands.md"):
                err(rel(path), f"anchor commands.md#{m.group(1)} doesn't exist")

    # front matter, features, command ids
    features_used = set()
    for path in md_files:
        parts = path.relative_to(SPEC).parts
        text = path.read_text(encoding="utf-8")
        if parts[0] in ("screens", "flows") or path.name == "messages.md":
            fm = front_matter(text)
            if fm is None:
                err(rel(path), "missing front matter")
                continue
            if fm.get("id") != path.stem:
                err(rel(path), f"front matter id {fm.get('id')!r} doesn't match the file name")
            if not fm.get("title"):
                err(rel(path), "front matter has no title")
            if fm["features"] is None:
                err(rel(path), "front matter has no features list")
            for fid in fm["features"] or []:
                features_used.add(fid)
                if fid not in parity:
                    err(rel(path), f"feature {fid} isn't in parity.yaml")
            for source in fm["sources"]:
                name = re.sub(r"\s*\(.*\)\s*$", "", source)
                if not (REPO / name).exists():
                    warn(rel(path), f"source {name} doesn't exist in the repository")
        # command ids named in a "Command" column
        header = None
        for number, line in enumerate(text.splitlines(), 1):
            if not line.startswith("|"):
                header = None
                continue
            cells = [c.strip() for c in re.split(r"(?<!\\)\|", line)[1:-1]]
            if header is None:
                header = cells
                continue
            if cells and cells[0].startswith("---"):
                continue
            if parts[0] == "commands.md":
                continue
            for index, name in enumerate(header):
                if name in ("Command", "Commands") and index < len(cells):
                    for token in re.findall(r"`([^`]+)`", cells[index]):
                        if not is_command(token, commands):
                            err(f"{rel(path)}:{number}", f"unknown command id {token}")
        # kebab-case words in backticks must be a known command, feature or page
        if path.name != "commands.md":
            for number, line in enumerate(text.splitlines(), 1):
                for m in re.finditer(r"`([a-z][a-z0-9]*(?:-[a-z0-9]+)+\*?)`", line):
                    token = m.group(1)
                    if (
                        is_command(token, commands)
                        or token in parity
                        or token in pages
                        or token in OTHER_IDS
                        or token.rstrip("*") in {c.rstrip("*") for c in commands}
                    ):
                        continue
                    err(f"{rel(path)}:{number}", f"unknown command, feature or page id {token}")
        for pattern, label in FORBIDDEN:
            for number, line in enumerate(text.splitlines(), 1):
                if pattern.search(line):
                    err(f"{rel(path)}:{number}", f"contains a {label}")
    for fid, entry in parity.items():
        removed = all(entry.get(p) == "not-applicable" for p in PLATFORMS)
        if fid not in features_used and not removed:
            warn("parity.yaml", f"feature {fid} isn't listed by any screen, flow or messages.md")
    for pattern, label in FORBIDDEN:
        for number, line in enumerate((SPEC / "copy" / "en.json").read_text(encoding="utf-8").splitlines(), 1):
            if pattern.search(line):
                err(f"copy/en.json:{number}", f"contains a {label}")

    # platform folders
    check_platforms(parity, commands)

    # report
    print(f"copy keys: {len(keys)}, referenced: {len(keys & used)}, group references: {group_refs}")
    print(f"command ids: {len(commands)}, features: {len(parity)}, spec pages: {len(pages)}")
    for line in warnings:
        print("warning:", line)
    for line in errors:
        print("error:", line)
    print(f"{len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
