#!/usr/bin/env python3
"""Writes the real-tool samples: the stand-in archive written by tools other than this repository's code.

    python3 make-real-tool-samples.py        # then python3 make-container-cases.py to list them

Each sample holds journal.sqlite, the two attachments and archive.json of make-container-cases.py. The tools and
versions that wrote the committed files are listed in README.md. Tools that are not installed are skipped.
Info-ZIP zip and macOS ditto add their own extra fields and entries (extended timestamps, Unix owners,
AppleDouble `__MACOSX/._...` files), which is the point.
"""

import importlib.util
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("cases", HERE / "make-container-cases.py")
cases = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cases)

FILES = {**cases.standard_files(), "archive.json": cases.OPAQUE_HEADER}

DOTNET = """\
using System.IO.Compression;

var folder = args[0];
var times = new DateTimeOffset(1980, 1, 1, 0, 0, 0, TimeSpan.Zero);
var names = new[] { "journal.sqlite", "attachments/01234567-89ab-4cde-8fab-0123456789ab", "attachments/fedcba98-7654-4321-8fed-cba987654321", "archive.json" };

void Write(Stream stream)
{
    using var archive = new ZipArchive(stream, ZipArchiveMode.Create, leaveOpen: false);
    foreach (var name in names)
    {
        var entry = archive.CreateEntry(name, CompressionLevel.NoCompression);
        entry.LastWriteTime = times;
        using var output = entry.Open();
        using var input = File.OpenRead(Path.Combine(folder, name));
        input.CopyTo(output);
    }
}

Write(File.Create(args[1]));
Write(new Forward(File.Create(args[2])));

// A stream that cannot seek makes ZipArchive write data descriptors.
sealed class Forward(Stream inner) : Stream
{
    public override bool CanRead => false;
    public override bool CanSeek => false;
    public override bool CanWrite => true;
    public override long Length => throw new NotSupportedException();
    public override long Position { get => throw new NotSupportedException(); set => throw new NotSupportedException(); }
    public override void Flush() => inner.Flush();
    public override int Read(byte[] buffer, int offset, int count) => throw new NotSupportedException();
    public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
    public override void SetLength(long value) => throw new NotSupportedException();
    public override void Write(byte[] buffer, int offset, int count) => inner.Write(buffer, offset, count);
    protected override void Dispose(bool disposing) { if (disposing) inner.Dispose(); base.Dispose(disposing); }
}
"""


def lay_out(folder):
    for name, data in FILES.items():
        path = folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)


def python_sample(out):
    with zipfile.ZipFile(out, "w", zipfile.ZIP_STORED) as archive:
        for name, data in FILES.items():
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED
            archive.writestr(info, data)
    return f"Python {'.'.join(map(str, __import__('sys').version_info[:3]))} zipfile, ZIP_STORED"


def info_zip_sample(folder, out):
    if not shutil.which("zip"):
        return None
    out.unlink(missing_ok=True)
    names = list(FILES)
    subprocess.run(["zip", "-q", str(out), *names], cwd=folder, check=True)
    version = subprocess.run(["zip", "-v"], capture_output=True, text=True).stdout.splitlines()[1]
    return version.strip()


def ditto_sample(folder, out):
    if not shutil.which("ditto") or not shutil.which("xattr"):
        return None
    for name in FILES:
        subprocess.run(["xattr", "-w", "com.apple.test", "sample", str(folder / name)], check=True)
    out.unlink(missing_ok=True)
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", str(folder), str(out)], check=True)
    return "macOS ditto -c -k --sequesterRsrc (the system's Archive Utility engine)"


def dotnet_samples(folder, tmp):
    if not shutil.which("dotnet"):
        return None
    program = tmp / "sample.cs"
    program.write_text(DOTNET)
    seekable = HERE / "real-dotnet-seekable.zip"
    forward = HERE / "real-dotnet-nonseekable.zip"
    subprocess.run(
        ["dotnet", "run", str(program), "--", str(folder), str(seekable), str(forward)],
        check=True,
        cwd=tmp,
    )
    version = subprocess.run(
        ["dotnet", "--version"], capture_output=True, text=True, cwd=tmp
    ).stdout.strip()
    return f".NET SDK {version}, System.IO.Compression.ZipArchive (Create mode), NoCompression"


def main():
    with tempfile.TemporaryDirectory() as scratch:
        scratch = Path(scratch)
        folder = scratch / "files"
        lay_out(folder)
        print(python_sample(HERE / "real-python-zipfile.zip"))
        print(info_zip_sample(folder, HERE / "real-info-zip.zip"))
        print(dotnet_samples(folder, scratch))
        ditto_folder = scratch / "ditto"
        lay_out(ditto_folder)
        print(ditto_sample(ditto_folder, HERE / "real-ditto.zip"))
    for sample in sorted(HERE.glob("real-*.zip")):
        with zipfile.ZipFile(sample) as archive:
            print(sample.name, archive.namelist())


if __name__ == "__main__":
    os.chdir(HERE)
    main()
