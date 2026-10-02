using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.RateLimiting;
using Journal.Api.Data;
using Journal.Api.Security;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.EntityFrameworkCore;

namespace Journal.Api.Features;

// The authorization server of the MCP endpoint (protocol/agent-access-server.md, Authorization): metadata, client
// registration, the authorization page the owner answers from My Journal, and the token and revocation endpoints.
public static class OAuthEndpoints
{
    public const int MaximumClients = 500;
    private static readonly PartitionedRateLimiter<string> Registrations = PartitionedRateLimiter.Create<string, string>(_ =>
        RateLimitPartition.GetFixedWindowLimiter("all", _ => new FixedWindowRateLimiterOptions { PermitLimit = 100, Window = TimeSpan.FromHours(1), QueueLimit = 0 }));

    public static void MapOAuth(this WebApplication app)
    {
        app.MapGet("/.well-known/oauth-protected-resource" + PublicOrigin.McpPath, ProtectedResource).AllowAnonymous().RequireRateLimiting(RateLimits.OAuthMetadata).DisableStatusCodePages();
        app.MapGet("/.well-known/oauth-authorization-server", AuthorizationServer).AllowAnonymous().RequireRateLimiting(RateLimits.OAuthMetadata).DisableStatusCodePages();
        app.MapPost("/oauth/register", Register).AllowAnonymous().RequireRateLimiting(RateLimits.OAuthRegister).DisableStatusCodePages();
        app.MapGet("/oauth/authorize", Authorize).AllowAnonymous().RequireRateLimiting(RateLimits.OAuthAuthorize).DisableStatusCodePages();
        app.MapGet("/oauth/authorize/wait", Wait).AllowAnonymous().RequireRateLimiting(RateLimits.OAuthStatus).DisableStatusCodePages();
        app.MapGet("/oauth/authorize/status", Status).AllowAnonymous().RequireRateLimiting(RateLimits.OAuthStatus).DisableStatusCodePages();
        app.MapPost("/oauth/token", Token).AllowAnonymous().RequireRateLimiting(RateLimits.OAuthToken).DisableStatusCodePages();
        app.MapPost("/oauth/revoke", Revoke).AllowAnonymous().RequireRateLimiting(RateLimits.OAuthToken).DisableStatusCodePages();
        foreach (var path in new[] { "/.well-known/oauth-protected-resource" + PublicOrigin.McpPath, "/.well-known/oauth-authorization-server", "/oauth/register", "/oauth/token", "/oauth/revoke" })
        {
            app.MapMethods(path, [HttpMethods.Options], (HttpContext http) =>
            {
                OpenCors(http);
                http.Response.Headers.AccessControlAllowMethods = "GET, POST, OPTIONS";
                http.Response.Headers.AccessControlAllowHeaders = "Authorization, Content-Type, MCP-Protocol-Version";
                http.Response.Headers.AccessControlMaxAge = "600";
                return Results.NoContent();
            }).AllowAnonymous().DisableStatusCodePages();
        }
    }

    // Browser clients read metadata and call these endpoints from their own origin; no credentials are involved.
    private static void OpenCors(HttpContext http)
    {
        http.Response.Headers.AccessControlAllowOrigin = "*";
        http.Response.Headers.AccessControlExposeHeaders = "WWW-Authenticate";
    }

    private static IResult Metadata(HttpContext http, JsonObject document)
    {
        OpenCors(http);
        http.Response.Headers.CacheControl = "no-store";
        http.Response.Headers.Vary = "Host";
        return Results.Text(document.ToJsonString(), "application/json", Encoding.UTF8);
    }

    private static IResult ProtectedResource(HttpContext http)
    {
        if (!PublicOrigin.RequestHostMatches(http))
        {
            return Results.NotFound();
        }
        var origin = PublicOrigin.Of(http);
        if (origin.Origin is null)
        {
            return Results.NotFound();
        }
        return Metadata(http, new JsonObject
        {
            ["resource"] = origin.McpResource,
            ["authorization_servers"] = new JsonArray(origin.Origin),
            ["scopes_supported"] = new JsonArray(AgentTokens.Scope),
            ["bearer_methods_supported"] = new JsonArray("header"),
            ["resource_name"] = "My Journal",
        });
    }

    private static IResult AuthorizationServer(HttpContext http, OAuthClients clients)
    {
        if (!PublicOrigin.RequestHostMatches(http))
        {
            return Results.NotFound();
        }
        if (PublicOrigin.Of(http).Origin is not { } issuer)
        {
            return Results.NotFound();
        }
        var methods = new JsonArray("none", "client_secret_basic", "client_secret_post");
        var document = new JsonObject
        {
            ["issuer"] = issuer,
            ["authorization_endpoint"] = issuer + "/oauth/authorize",
            ["token_endpoint"] = issuer + "/oauth/token",
            ["registration_endpoint"] = issuer + "/oauth/register",
            ["revocation_endpoint"] = issuer + "/oauth/revoke",
            ["response_types_supported"] = new JsonArray("code"),
            ["response_modes_supported"] = new JsonArray("query"),
            ["grant_types_supported"] = new JsonArray("authorization_code", "refresh_token"),
            ["code_challenge_methods_supported"] = new JsonArray("S256"),
            ["token_endpoint_auth_methods_supported"] = methods,
            ["revocation_endpoint_auth_methods_supported"] = methods.DeepClone(),
            ["scopes_supported"] = new JsonArray(AgentTokens.Scope),
            ["authorization_response_iss_parameter_supported"] = true,
            ["client_id_metadata_document_supported"] = clients.MetadataDocumentsEnabled,
        };
        return Metadata(http, document);
    }

    // RFC 7591. Public clients get no secret; confidential ones get a random secret whose hash is kept.
    private static async Task<IResult> Register(HttpContext http, JournalDb db, WriteGate gate, TimeProvider clock, AuditLog audit)
    {
        OpenCors(http);
        http.Response.Headers.CacheControl = "no-store";
        var ct = http.RequestAborted;
        if (PublicOrigin.Of(http).Origin is null)
        {
            return RegistrationError("invalid_client_metadata", "HTTPS is required.");
        }
        JsonObject? body;
        try
        {
            body = await JsonNode.ParseAsync(http.Request.Body, cancellationToken: ct) as JsonObject;
        }
        catch (JsonException)
        {
            body = null;
        }
        if (body is null)
        {
            return RegistrationError("invalid_client_metadata", "Send the client metadata as a JSON object.");
        }
        var method = body["token_endpoint_auth_method"] is null ? "client_secret_basic" : StringValue(body["token_endpoint_auth_method"]);
        var name = body["client_name"] is null ? "" : StringValue(body["client_name"])?.Trim();
        if (method is not ("none" or "client_secret_basic" or "client_secret_post") || name is null ||
            !Subset(body["grant_types"], "authorization_code", "refresh_token") || !Subset(body["response_types"], "code"))
        {
            return RegistrationError("invalid_client_metadata", "Unsupported client metadata.");
        }
        if (body["redirect_uris"] is not JsonArray requested || requested.Count is 0 or > 10)
        {
            return RegistrationError("invalid_redirect_uri", "Register between one and ten redirect URIs.");
        }
        // Keep only redirect URIs MCP permits (https, loopback http); clients such as Cursor also register others.
        var kept = requested.Select(StringValue).Where(x => OAuthRedirects.Classify(x) is not null).Distinct(StringComparer.Ordinal).ToList();
        if (kept.Count == 0)
        {
            return RegistrationError("invalid_redirect_uri", "Use https or loopback http redirect URIs.");
        }
        using (var lease = Registrations.AttemptAcquire("all"))
        {
            if (!lease.IsAcquired)
            {
                return Results.Json(new
                {
                    error = "temporarily_unavailable",
                    error_description = "Too many registrations. Try again later."
                }, statusCode: StatusCodes.Status429TooManyRequests);
            }
        }
        // Without a name, the redirect's host names the client; long names are shortened.
        name = name.Length == 0 ? OAuthRedirects.Describe(kept[0]!) : name.Length > 100 ? name[..100] : name;
        var id = Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(16));
        var secret = method == "none" ? null : Convert.ToHexStringLower(RandomNumberGenerator.GetBytes(32));
        var now = clock.GetUtcNow();
        using (await gate.Enter(ct))
        {
            if (await db.OAuthClients.CountAsync(ct) >= MaximumClients)
            {
                var oldest = (await db.OAuthClients.Where(x => !x.Used).ToListAsync(ct)).MinBy(x => x.CreatedAt);
                if (oldest is null)
                {
                    return RegistrationError("invalid_client_metadata", "This server has too many registered clients.");
                }
                db.OAuthClients.Remove(oldest);
            }
            db.OAuthClients.Add(new OAuthClient { Id = id, Name = name, RedirectUris = JsonSerializer.Serialize(kept), AuthMethod = method, SecretHash = secret is null ? null : Secrets.Hash(secret), CreatedAt = now });
            await db.SaveChangesAsync(ct);
        }
        audit.OAuthClientRegistered(id);
        var response = new JsonObject
        {
            ["client_id"] = id,
            ["client_id_issued_at"] = now.ToUnixTimeSeconds(),
            ["client_name"] = name,
            ["redirect_uris"] = new JsonArray(kept.Select(x => (JsonNode)x!).ToArray()),
            ["grant_types"] = new JsonArray("authorization_code", "refresh_token"),
            ["response_types"] = new JsonArray("code"),
            ["token_endpoint_auth_method"] = method,
            ["scope"] = AgentTokens.Scope,
        };
        if (secret is not null)
        {
            response["client_secret"] = secret;
            response["client_secret_expires_at"] = 0;
        }
        return Results.Text(response.ToJsonString(), "application/json", Encoding.UTF8, StatusCodes.Status201Created);
    }

    private static IResult RegistrationError(string code, string description) =>
        Results.Json(new
        {
            error = code,
            error_description = description
        }, statusCode: StatusCodes.Status400BadRequest);

    private static string? StringValue(JsonNode? node) => node is JsonValue value && value.GetValueKind() == JsonValueKind.String ? value.GetValue<string>() : null;

    private static bool Subset(JsonNode? node, params string[] allowed) =>
        node is null || (node is JsonArray array && array.All(x => StringValue(x) is { } value && allowed.Contains(value, StringComparer.Ordinal)));

    // The authorization request: validated as OAuth 2.1 and RFC 8707 require, then a page that shows the code to enter in
    // My Journal. Errors before the client and redirect URI are known are shown, never redirected.
    private static async Task<IResult> Authorize(HttpContext http, JournalDb db, OAuthClients clients, AgentAuthorizations authorizations)
    {
        var ct = http.RequestAborted;
        var query = http.Request.Query;
        var origin = PublicOrigin.Of(http);
        if (!PublicOrigin.RequestHostMatches(http) || origin.Origin is not { } issuer || origin.McpResource is not { } resource)
        {
            return AuthorizationPage.Error("This server needs a secure (HTTPS) address before agents can connect.");
        }
        var client = await clients.Find(Single(query, "client_id"), db, ct);
        if (client is null)
        {
            var id = Single(query, "client_id");
            return AuthorizationPage.Error(id is not null && id.StartsWith("https://", StringComparison.Ordinal)
                ? clients.ProblemWith(id) switch
                {
                    OAuthClients.Problem.UnsupportedAuthentication => "This agent uses a sign-in method this server doesn’t support.",
                    OAuthClients.Problem.Unreachable => "This server couldn’t check this agent’s identity. Make sure the server can reach the internet, then try again.",
                    _ => "This agent’s identity document isn’t valid. Ask the agent’s maker.",
                }
                : "This agent’s registration isn’t valid on this server. Remove the server from your agent and add it again.");
        }
        // May be omitted only for a single registered non-loopback redirect (loopback ports vary per run).
        var given = Single(query, "redirect_uri");
        var redirectUri = given ?? (client.RedirectUris.Count == 1 && !OAuthRedirects.IsLoopback(client.RedirectUris[0]) ? client.RedirectUris[0] : null);
        if (redirectUri is null || !client.Allows(redirectUri))
        {
            return AuthorizationPage.Error("This agent asked to return to an address it didn’t register.");
        }
        var state = Single(query, "state");
        IResult Fail(string error, string description) => Results.Redirect(WithParameters(redirectUri, new Dictionary<string, string?>
        {
            ["error"] = error,
            ["error_description"] = description,
            ["state"] = state,
            ["iss"] = issuer,
        }));
        if (Single(query, "response_type") != "code")
        {
            return Fail("unsupported_response_type", "Only the authorization code flow is supported.");
        }
        var challenge = Single(query, "code_challenge");
        if (Single(query, "code_challenge_method") != "S256" || challenge is not { Length: 43 } || !challenge.All(IsBase64Url))
        {
            return Fail("invalid_request", "PKCE with S256 is required.");
        }
        var requestedResource = Single(query, "resource");
        if (requestedResource is not null && !PublicOrigin.SameResource(requestedResource, resource))
        {
            return Fail("invalid_target", "This server's resource is " + resource + ".");
        }
        var details = new AuthorizationRequestDetails(client, redirectUri, given is not null, state, challenge, resource, AgentTokens.Scope, issuer);
        var (result, request) = authorizations.Start(details, RateLimits.ClientAddress(http));
        if (result != AgentAuthorizations.StartResult.Started || request is null)
        {
            return Fail("temporarily_unavailable", "Too many requests are waiting for approval. Try again in a few minutes.");
        }
        return AuthorizationPage.Waiting(http, request);
    }

    private static string? Single(IQueryCollection query, string name) => query.TryGetValue(name, out var values) && values.Count == 1 ? values[0] : null;

    private static bool IsBase64Url(char c) => char.IsAsciiLetterOrDigit(c) || c is '-' or '_';

    internal static string WithParameters(string uri, Dictionary<string, string?> parameters) =>
        QueryHelpers.AddQueryString(uri, parameters.Where(x => x.Value is not null).ToDictionary(x => x.Key, x => x.Value));

    // The page the browser shows while it waits, for browsers without scripts.
    private static IResult Wait(HttpContext http, AgentAuthorizations authorizations)
    {
        var request = authorizations.ByHandle(http.Request.Query["handle"]);
        if (request is null)
        {
            return AuthorizationPage.Error("This request expired. Return to your agent and try again.");
        }
        authorizations.ReleaseIfDue(request);
        authorizations.Delivered(request);
        return AuthorizationPage.Waiting(http, request);
    }

    // What the page's script polls: whether the owner answered, and where to go.
    private static IResult Status(HttpContext http, AgentAuthorizations authorizations)
    {
        http.Response.Headers.CacheControl = "no-store";
        var request = authorizations.ByHandle(http.Request.Query["handle"]);
        if (request is null)
        {
            return Results.Json(new
            {
                status = "expired"
            });
        }
        authorizations.ReleaseIfDue(request);
        authorizations.Delivered(request);
        return Results.Json(new
        {
            status = AuthorizationPage.StatusName(request),
            redirect = AuthorizationPage.Destination(request),
            automatic = true
        });
    }

    private static async Task<IResult> Token(HttpContext http, JournalDb db, OAuthClients clients, AgentAuthorizations authorizations, AgentTokens tokens, WriteGate gate, AuditLog audit)
    {
        OpenCors(http);
        http.Response.Headers.CacheControl = "no-store";
        http.Response.Headers.Pragma = "no-cache";
        var ct = http.RequestAborted;
        if (!http.Request.HasFormContentType)
        {
            return TokenError("invalid_request", "Send the request as application/x-www-form-urlencoded.");
        }
        var form = await http.Request.ReadFormAsync(ct);
        var resource = PublicOrigin.Of(http).McpResource;
        if (resource is null || !PublicOrigin.RequestHostMatches(http))
        {
            return TokenError("invalid_request", "Use the server's public HTTPS address.");
        }
        var (client, clientFailure) = await Authenticate(http, form, db, clients, ct);
        if (client is null)
        {
            return clientFailure!;
        }
        return Field(form, "grant_type") switch
        {
            "authorization_code" => await Exchange(form, client, resource, db, authorizations, tokens, gate, audit, ct),
            "refresh_token" => await Refresh(form, client, resource, db, tokens, gate, ct),
            _ => TokenError("unsupported_grant_type", "Use authorization_code or refresh_token."),
        };
    }

    private static async Task<IResult> Exchange(IFormCollection form, OAuthClientInfo client, string resource, JournalDb db, AgentAuthorizations authorizations, AgentTokens tokens, WriteGate gate, AuditLog audit, CancellationToken ct)
    {
        var (request, reused) = authorizations.Redeem(Field(form, "code"));
        if (reused && request?.Family is { } family)
        {
            using (await gate.Enter(ct))
            {
                await AgentTokens.RevokeFamily(db, family, ct);
            }
            audit.AuthorizationCodeReused(request.GrantId ?? Guid.Empty);
            return TokenError("invalid_grant", "This authorization code was already used.");
        }
        var redirect = Field(form, "redirect_uri");
        if (request is null || reused || request.Details.Client.ClientId != client.ClientId ||
            (redirect is null ? request.Details.RedirectUriGiven : redirect != request.Details.RedirectUri))
        {
            return TokenError("invalid_grant", "The authorization code is invalid or expired.");
        }
        if (Field(form, "resource") is { } requested && !PublicOrigin.SameResource(requested, resource))
        {
            return TokenError("invalid_target", "This server's resource is " + resource + ".");
        }
        var verifier = Field(form, "code_verifier");
        if (verifier is not { Length: >= 43 and <= 128 } || !verifier.All(c => char.IsAsciiLetterOrDigit(c) || c is '-' or '.' or '_' or '~') ||
            Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier))) != request.Details.CodeChallenge ||
            request.Details.Resource != resource || request.GrantId is not { } grantId || request.Secret is not { } secret || request.WrappedKey is not { } wrapped)
        {
            request.Forget();
            return TokenError("invalid_grant", "The code verifier doesn't match.");
        }
        var copyKey = AgentKeys.Unwrap(wrapped, secret, grantId);
        request.Forget();
        if (copyKey is null)
        {
            return TokenError("invalid_grant", "The authorization is no longer valid.");
        }
        try
        {
            using (await gate.Enter(ct))
            {
                var grant = await db.AgentGrants.SingleOrDefaultAsync(x => x.Id == grantId, ct);
                if (grant is null)
                {
                    return TokenError("invalid_grant", "Access was revoked.");
                }
                if (request.Reconnect)
                {
                    await db.OAuthTokens.Where(x => x.GrantId == grantId).ExecuteDeleteAsync(ct);
                }
                grant.State = AgentGrantState.Active;
                grant.ClientId = client.ClientId;
                await db.OAuthClients.Where(x => x.Id == client.ClientId).ExecuteUpdateAsync(x => x.SetProperty(c => c.Used, true), ct);
                request.Family = Guid.NewGuid();
                var issued = await tokens.Issue(db, grant, copyKey, resource, request.Family.Value, ct);
                return TokenResponse(issued);
            }
        }
        finally
        {
            CryptographicOperations.ZeroMemory(copyKey);
        }
    }

    private static async Task<IResult> Refresh(IFormCollection form, OAuthClientInfo client, string resource, JournalDb db, AgentTokens tokens, WriteGate gate, CancellationToken ct)
    {
        var presented = Field(form, "refresh_token");
        if (AgentToken.Parse(presented, OAuthTokenKind.Refresh) is { } parsed)
        {
            var grantId = await db.OAuthTokens.AsNoTracking().Where(x => x.Id == parsed.Id).Select(x => (Guid?)x.GrantId).SingleOrDefaultAsync(ct);
            var owner = grantId is null ? null : await db.AgentGrants.AsNoTracking().Where(x => x.Id == grantId).Select(x => x.ClientId).SingleOrDefaultAsync(ct);
            if (owner is not null && owner != client.ClientId)
            {
                return TokenError("invalid_grant", "This refresh token was issued to another client.");
            }
        }
        using (await gate.Enter(ct))
        {
            var (issued, failure) = await tokens.Refresh(db, presented, Field(form, "resource"), resource, ct);
            return failure switch
            {
                AgentTokens.RefreshFailure.InvalidTarget => TokenError("invalid_target", "This server's resource is " + resource + "."),
                AgentTokens.RefreshFailure.None when issued is not null => TokenResponse(issued),
                _ => TokenError("invalid_grant", "The refresh token is invalid or expired. Connect again."),
            };
        }
    }

    // RFC 7009: always 200 for a well-formed request, whether or not the token was known.
    private static async Task<IResult> Revoke(HttpContext http, JournalDb db, OAuthClients clients, AgentTokens tokens, WriteGate gate)
    {
        OpenCors(http);
        http.Response.Headers.CacheControl = "no-store";
        var ct = http.RequestAborted;
        if (!http.Request.HasFormContentType)
        {
            return TokenError("invalid_request", "Send the request as application/x-www-form-urlencoded.");
        }
        var form = await http.Request.ReadFormAsync(ct);
        var (client, failure) = await Authenticate(http, form, db, clients, ct);
        if (client is null)
        {
            return failure!;
        }
        var presented = Field(form, "token");
        var parsed = AgentToken.Parse(presented, OAuthTokenKind.Refresh) ?? AgentToken.Parse(presented, OAuthTokenKind.Access);
        if (parsed is not null)
        {
            var grantId = await db.OAuthTokens.AsNoTracking().Where(x => x.Id == parsed.Id).Select(x => (Guid?)x.GrantId).SingleOrDefaultAsync(ct);
            var owner = grantId is null ? null : await db.AgentGrants.AsNoTracking().Where(x => x.Id == grantId).Select(x => x.ClientId).SingleOrDefaultAsync(ct);
            if (owner == client.ClientId)
            {
                using (await gate.Enter(ct))
                {
                    await tokens.Revoke(db, presented, ct);
                }
            }
        }
        return Results.Ok();
    }

    // Client authentication at the token and revocation endpoints: public clients send only client_id; confidential
    // clients use HTTP Basic or form parameters, as registered.
    private static async Task<(OAuthClientInfo? Client, IResult? Failure)> Authenticate(HttpContext http, IFormCollection form, JournalDb db, OAuthClients clients, CancellationToken ct)
    {
        string? id = Field(form, "client_id");
        string? secret = Field(form, "client_secret");
        var basic = false;
        var header = http.Request.Headers.Authorization.ToString();
        if (header.StartsWith("Basic ", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var decoded = Encoding.UTF8.GetString(Convert.FromBase64String(header[6..].Trim()));
                var colon = decoded.IndexOf(':', StringComparison.Ordinal);
                if (colon > 0)
                {
                    id = WebUtility.UrlDecode(decoded[..colon]);
                    secret = WebUtility.UrlDecode(decoded[(colon + 1)..]);
                    basic = true;
                }
            }
            catch (FormatException)
            {
                return (null, InvalidClient(http, true));
            }
        }
        var client = await clients.Find(id, db, ct);
        if (client is null)
        {
            return (null, InvalidClient(http, basic));
        }
        var authenticated = client.AuthMethod switch
        {
            "none" => secret is null,
            "client_secret_basic" or "client_secret_post" => secret is not null && client.SecretHash is { } hash && Secrets.Matches(secret, hash),
            _ => false,
        };
        return authenticated ? (client, null) : (null, InvalidClient(http, basic));
    }

    private static IResult InvalidClient(HttpContext http, bool basic)
    {
        if (basic)
        {
            http.Response.Headers.WWWAuthenticate = "Basic";
        }
        return Results.Json(new
        {
            error = "invalid_client",
            error_description = "Client authentication failed."
        }, statusCode: StatusCodes.Status401Unauthorized);
    }

    private static string? Field(IFormCollection form, string name) => form.TryGetValue(name, out var values) && values.Count == 1 ? values[0] : null;

    private static IResult TokenError(string code, string description) =>
        Results.Json(new
        {
            error = code,
            error_description = description
        }, statusCode: StatusCodes.Status400BadRequest);

    private static IResult TokenResponse(AgentTokens.Issued issued) => Results.Json(new
    {
        access_token = issued.AccessToken,
        token_type = "Bearer",
        expires_in = issued.ExpiresIn,
        refresh_token = issued.RefreshToken,
        scope = AgentTokens.Scope,
    });

    private static string Base64Url(byte[] bytes) => System.Buffers.Text.Base64Url.EncodeToString(bytes);
}
