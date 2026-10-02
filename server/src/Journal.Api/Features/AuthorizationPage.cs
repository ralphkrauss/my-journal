using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using Journal.Api.Security;

namespace Journal.Api.Features;

// The page a browser shows while the owner approves an agent in My Journal (protocol/agent-access-server.md,
// Authorization page). Everything the client supplied is HTML-encoded; the only script is the fixed poller below,
// allowed by its hash.
public static class AuthorizationPage
{
    private const string Script = """
        (function () {
          var page = document.getElementById("page");
          var handle = page.getAttribute("data-handle");
          var client = page.getAttribute("data-client");
          var status = document.getElementById("status");
          var next = document.getElementById("continue");
          var number = document.getElementById("number");
          function poll() {
            fetch("/oauth/authorize/status?handle=" + encodeURIComponent(handle), { cache: "no-store" })
              .then(function (response) { return response.json(); })
              .then(function (result) {
                if (result.status === "waiting") { setTimeout(poll, 2000); return; }
                if (number) { number.hidden = true; }
                if (result.status === "expired") { status.textContent = "This request expired. Return to your agent and try again."; return; }
                if (result.status === "replaced") { status.textContent = "This request was replaced by a newer one. You can close this page."; return; }
                status.textContent = result.status === "declined" ? "Access wasn\u2019t allowed. Returning to " + client + "\u2026" : "Access allowed. Returning to " + client + "\u2026";
                if (!result.redirect) { setTimeout(poll, 1000); return; }
                next.href = result.redirect;
                next.hidden = false;
                if (result.automatic) { window.location.assign(result.redirect); }
              })
              .catch(function () { setTimeout(poll, 5000); });
          }
          setTimeout(poll, 2000);
        })();
        """;
    private static readonly string ScriptHash = Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(Script)));

    public static string StatusName(PendingAuthorization request)
    {
        ArgumentNullException.ThrowIfNull(request);
        return request.Status switch
        {
            PendingStatus.Approved => "approved",
            PendingStatus.Released or PendingStatus.Redeemed => "allowed",
            PendingStatus.Declined => "declined",
            PendingStatus.Replaced => "replaced",
            _ => "waiting",
        };
    }

    // Where the browser goes back to once the owner answered; null while waiting.
    public static string? Destination(PendingAuthorization request)
    {
        ArgumentNullException.ThrowIfNull(request);
        var details = request.Details;
        return request.Status switch
        {
            PendingStatus.Released => OAuthEndpoints.WithParameters(details.RedirectUri, new() { ["code"] = request.Code, ["state"] = details.State, ["iss"] = details.Issuer }),
            PendingStatus.Declined => OAuthEndpoints.WithParameters(details.RedirectUri, new() { ["error"] = "access_denied", ["state"] = details.State, ["iss"] = details.Issuer }),
            _ => null,
        };
    }

    public static IResult Waiting(HttpContext http, PendingAuthorization request)
    {
        ArgumentNullException.ThrowIfNull(http);
        ArgumentNullException.ThrowIfNull(request);
        var html = HtmlEncoder.Default;
        var client = DisplayName(request.Details.Client.Name);
        var destination = Destination(request);
        var status = StatusName(request) switch
        {
            "approved" or "allowed" => "Access allowed. Returning to " + client + "…",
            "declined" => "Access wasn’t allowed. Returning to " + client + "…",
            "replaced" => "This request was replaced by a newer one. You can close this page.",
            _ => "Waiting for approval…",
        };
        var body = new StringBuilder();
        body.Append("<main id=\"page\" data-handle=\"").Append(html.Encode(request.BrowserHandle)).Append("\" data-client=\"").Append(html.Encode(client)).Append("\">");
        body.Append("<h1>Allow Access in My Journal</h1>");
        body.Append("<p><strong>").Append(html.Encode(client)).Append("</strong> wants to read your journals.</p>");
        if (request.Status == PendingStatus.Waiting)
        {
            body.Append("<div id=\"number\"><p>In My Journal, open Settings &gt; Agent Access and enter this number:</p>");
            body.Append("<p class=\"number\">").Append(request.Number.ToString(System.Globalization.CultureInfo.InvariantCulture)).Append("</p></div>");
        }
        body.Append("<p id=\"status\" role=\"status\" aria-live=\"polite\">").Append(html.Encode(status)).Append("</p>");
        body.Append("<p><a id=\"continue\" href=\"").Append(html.Encode(destination ?? "#")).Append('"').Append(destination is null ? " hidden" : "").Append(">Continue</a></p>");
        body.Append("</main>");
        return Page(body.ToString(), request.Status is PendingStatus.Waiting or PendingStatus.Approved ? "/oauth/authorize/wait?handle=" + request.BrowserHandle : null);
    }

    // A client's self-chosen name as the page shows it: without control or formatting characters (which could reorder
    // text), on one line and at most 40 characters.
    public static string DisplayName(string name)
    {
        ArgumentNullException.ThrowIfNull(name);
        // Line breaks and tabs become spaces first, so words on separate lines stay apart.
        var visible = new string(name.Select(c => char.IsWhiteSpace(c) ? ' ' : c)
            .Where(c => !char.IsControl(c) && char.GetUnicodeCategory(c) != System.Globalization.UnicodeCategory.Format).ToArray());
        var single = string.Join(' ', visible.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        var elements = System.Globalization.StringInfo.GetTextElementEnumerator(single);
        var result = new StringBuilder();
        var count = 0;
        while (elements.MoveNext())
        {
            if (++count > 40)
            {
                return result.ToString().TrimEnd() + "…";
            }
            result.Append(elements.GetTextElement());
        }
        return result.Length > 0 ? result.ToString() : "An agent";
    }

    public static IResult Error(string message) => new PageResult(
        "<main><h1>Allow Access in My Journal</h1><p role=\"alert\">" + HtmlEncoder.Default.Encode(message) + "</p></main>", null, StatusCodes.Status400BadRequest);

    private static PageResult Page(string main, string? refresh) => new(main, refresh, StatusCodes.Status200OK);

    private sealed class PageResult(string main, string? refresh, int status) : IResult
    {
        public Task ExecuteAsync(HttpContext httpContext)
        {
            var response = httpContext.Response;
            response.StatusCode = status;
            response.ContentType = "text/html; charset=utf-8";
            response.Headers.CacheControl = "no-store";
            response.Headers.XFrameOptions = "DENY";
            response.Headers["Referrer-Policy"] = "no-referrer";
            response.Headers.ContentSecurityPolicy = $"default-src 'none'; connect-src 'self'; script-src 'sha256-{ScriptHash}'; style-src 'unsafe-inline'; frame-ancestors 'none'; form-action 'none'; base-uri 'none'";
            var noscript = refresh is null ? "" : "<noscript><meta http-equiv=\"refresh\" content=\"15;url=" + HtmlEncoder.Default.Encode(refresh) + "\"></noscript>";
            var script = refresh is null ? "" : "<script>" + Script + "</script>";
            var document = "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Allow Access in My Journal</title>" +
                noscript + "<style>:root{color-scheme:light dark}body{font:17px -apple-system,BlinkMacSystemFont,system-ui,sans-serif;margin:0;padding:24px;display:flex;justify-content:center}main{max-width:32em}h1{font-size:1.6em}.number{font:600 3em ui-monospace,SFMono-Regular,Menlo,monospace;letter-spacing:.08em;margin:.3em 0}</style></head><body>" +
                main + script + "</body></html>";
            return response.WriteAsync(document, httpContext.RequestAborted);
        }
    }
}
