using System.Security.Cryptography;
using Journal.Api.Data;
using Journal.Api.Security;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Features;

public static class AttachmentEndpoints
{
    public const long MaximumBytes = 25 * 1024 * 1024;
    public static void MapAttachments(this WebApplication app)
    {
        var group = app.MapGroup("/v1/attachments").RequireAuthorization().RequireRateLimiting(RateLimits.Sync);
        group.MapPut("/{id:guid}", Upload).WithBodyLimit(MaximumBytes);
        // Lets a client check which images a restored server still has without downloading them.
        group.MapMethods("/{id:guid}", [HttpMethods.Head], async (Guid id, JournalDb db, StoragePaths paths, AuditLog audit, CancellationToken ct) =>
        {
            if (!await db.Attachments.AsNoTracking().AnyAsync(x => x.Id == id, ct))
            {
                return Results.NotFound();
            }
            if (!File.Exists(FilePath(paths, id)))
            {
                audit.AttachmentFileMissing(id);
                return Results.NotFound();
            }
            return Results.Ok();
        });
        group.MapGet("/{id:guid}", async (Guid id, JournalDb db, StoragePaths paths, AuditLog audit, CancellationToken ct) =>
        {
            if (!await db.Attachments.AsNoTracking().AnyAsync(x => x.Id == id, ct))
            {
                return Problems.Of(StatusCodes.Status404NotFound, "attachment_not_found");
            }

            var path = FilePath(paths, id);
            if (!File.Exists(path))
            {
                audit.AttachmentFileMissing(id);
                return Problems.Of(StatusCodes.Status503ServiceUnavailable, "attachment_unavailable");
            }
            return Results.File(path, "application/octet-stream", enableRangeProcessing: true);
        });
    }

    private static string FilePath(StoragePaths paths, Guid id) => Path.Combine(paths.AttachmentDirectory, id.ToString("D"));

    private static async Task<IResult> Upload(Guid id, JournalDb db, StoragePaths paths, WriteGate gate, AuditLog audit, HttpContext http)
    {
        var ct = http.RequestAborted;
        if (id == Guid.Empty)
        {
            return Problems.Of(StatusCodes.Status400BadRequest, "invalid_attachment");
        }

        if (http.Request.ContentLength is > MaximumBytes)
        {
            return Problems.Of(StatusCodes.Status413PayloadTooLarge, "attachment_too_large");
        }

        var temp = Path.Combine(paths.AttachmentDirectory, $".upload-{Guid.NewGuid():N}");
        try
        {
            long length = 0;
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            await using (var output = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None, 65536, true))
            {
                var buffer = new byte[65536];
                int read;
                while ((read = await http.Request.Body.ReadAsync(buffer, ct)) > 0)
                {
                    length += read;
                    if (length > MaximumBytes)
                    {
                        return Problems.Of(StatusCodes.Status413PayloadTooLarge, "attachment_too_large");
                    }

                    hash.AppendData(buffer, 0, read);
                    await output.WriteAsync(buffer.AsMemory(0, read), ct);
                }
                await output.FlushAsync(ct);
                output.Flush(true);
            }
            if (length < (await db.Vaults.AsNoTracking().AnyAsync(v => v.FormatVersion == 3 || v.FormatVersion == 4, ct) ? 1 : 29))
            {
                return Problems.Of(StatusCodes.Status400BadRequest, "invalid_ciphertext");
            }

            var digest = Convert.ToHexStringLower(hash.GetHashAndReset());
            using var lease = await gate.Enter(ct);
            if (!await DeviceAuthentication.IsStillAuthorized(http, db))
            {
                return Problems.Of(StatusCodes.Status401Unauthorized, "unauthorized");
            }

            var destination = FilePath(paths, id);
            var existing = await db.Attachments.FindAsync([id], ct);
            if (existing is not null)
            {
                if (existing.Sha256 != digest)
                {
                    return Problems.Of(StatusCodes.Status409Conflict, "attachment_is_immutable");
                }
                // The record survived but its file was lost (a partial copy of the data directory, a
                // disk fault). Identical bytes restore it; HEAD and GET report the file missing until then.
                if (!File.Exists(destination))
                {
                    File.Move(temp, destination, overwrite: false);
                    audit.AttachmentFileRestored(id);
                }
                return Results.Ok(new
                {
                    id,
                    sha256 = digest
                });
            }

            // Replacing an unreferenced file repairs a crash between rename and DB commit.
            File.Move(temp, destination, true);
            db.Attachments.Add(new Attachment { Id = id, Sha256 = digest, Length = length });
            await db.SaveChangesAsync(ct);
            return Results.Ok(new
            {
                id,
                sha256 = digest
            });
        }
        finally
        {
            if (File.Exists(temp))
            {
                File.Delete(temp);
            }
        }
    }
}
