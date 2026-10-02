using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using Journal.Api.Features;

namespace Journal.Api.Tests;

public sealed class RequestBoundaryTests
{
    [Theory]
    [InlineData(null, null, "rebound.attacker.example", HttpStatusCode.BadRequest)]
    [InlineData(null, null, "127.0.0.1", HttpStatusCode.OK)]
    [InlineData(null, null, "journal.example-tailnet.ts.net", HttpStatusCode.OK)]
    [InlineData("http://+:8080", null, "journal.example.com", HttpStatusCode.OK)]
    [InlineData(null, "journal.example.com", "journal.example.com", HttpStatusCode.OK)]
    [InlineData(null, "journal.example.com", "localhost", HttpStatusCode.BadRequest)]
    public async Task ALoopbackServerAcceptsOnlyLoopbackHostNamesUnlessConfigured(string? urls, string? allowedHosts, string host, HttpStatusCode expected)
    {
        using var factory = new JournalFactory();
        if (urls is not null)
        {
            factory.Settings["urls"] = urls;
        }
        if (allowedHosts is not null)
        {
            factory.Settings["AllowedHosts"] = allowedHosts;
        }
        using var client = factory.CreateClient();
        using var request = new HttpRequestMessage(HttpMethod.Get, "/v1/server");
        request.Headers.Host = host;
        Assert.Equal(expected, (await client.SendAsync(request)).StatusCode);
    }

    [Fact]
    public async Task ForwardedClientAddressesAreTrustedOnlyFromConfiguredProxies()
    {
        using var factory = new JournalFactory();
        factory.Settings["Journal:TrustedProxies"] = "10.20.0.2";
        using var client = factory.CreateClient();
        async Task<HttpStatusCode> BeginPairing(string connection, string forwarded)
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/pairing")
            {
                Content = JsonContent.Create(new BeginPairing("Phone", PairingEndpoints.Commitment(new byte[32]))),
            };
            request.Headers.Add(JournalFactory.ClientAddressHeader, connection);
            request.Headers.Add("X-Forwarded-For", forwarded);
            return (await client.SendAsync(request)).StatusCode;
        }

        var throughProxy = new List<HttpStatusCode>();
        var direct = new List<HttpStatusCode>();
        for (var attempt = 0; attempt < 11; attempt++)
        {
            throughProxy.Add(await BeginPairing("10.20.0.2", "198.51.100.1"));
            // A client connecting directly cannot choose a fresh limit with the header.
            direct.Add(await BeginPairing("203.0.113.5", "198.51.100." + (attempt + 10)));
        }
        Assert.Equal(HttpStatusCode.TooManyRequests, throughProxy[^1]);
        Assert.Equal(HttpStatusCode.TooManyRequests, direct[^1]);
        // Another client behind the proxy has its own limit, also when the proxy connects over IPv6.
        Assert.NotEqual(HttpStatusCode.TooManyRequests, await BeginPairing("::ffff:10.20.0.2", "198.51.100.2"));
    }

    [Theory]
    [InlineData("")]
    [InlineData("Authorization: Bearer 0000000000000000000000000000000000000000000000000000000000000000\r\n")]
    public async Task UnauthenticatedWritesAreRejectedBeforeTheirBodyIsRead(string authorization)
    {
        using var factory = new JournalFactory();
        factory.UseKestrel(options => options.Listen(IPAddress.Loopback, 0));
        var (client, _) = await factory.SetUp();
        var server = client.BaseAddress ?? throw new InvalidOperationException("The test server has no address.");
        using var connection = new TcpClient();
        await connection.ConnectAsync(server.Host, server.Port);
        var stream = connection.GetStream();
        // Announce a large body and send none: a server that read it before checking the credential
        // would still be waiting when the timeout ends.
        var head = $"PUT /v1/sync/{Guid.NewGuid()} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: 4000000\r\n{authorization}\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head));
        var buffer = new byte[64];
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var read = await stream.ReadAsync(buffer, timeout.Token);
        Assert.StartsWith("HTTP/1.1 401 ", Encoding.ASCII.GetString(buffer, 0, read), StringComparison.Ordinal);
    }

    [Fact]
    public async Task EachRouteAcceptsOnlyTheBodySizeItNeeds()
    {
        using var factory = new JournalFactory();
        factory.UseKestrel(options => options.Listen(IPAddress.Loopback, 0));
        var (client, _) = await factory.SetUp();
        async Task<HttpStatusCode> Send(HttpMethod method, string path, string json)
        {
            using var request = new HttpRequestMessage(method, path) { Content = new StringContent(json, Encoding.UTF8, "application/json") };
            // The server may answer before reading the body; the client then never sends it.
            request.Headers.ExpectContinue = true;
            return (await client.SendAsync(request)).StatusCode;
        }

        var name = new string('x', 100 * 1024);
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, await Send(HttpMethod.Post, "/v1/recovery", JsonSerializer.Serialize(new RecoveryRequest(new string('a', 64), name))));
        var record = new PutRecord(Guid.NewGuid(), 0, "entry", Convert.ToBase64String(new byte[1024 * 1024]));
        Assert.Equal(HttpStatusCode.OK, await Send(HttpMethod.Put, $"/v1/sync/{Guid.NewGuid()}", JsonSerializer.Serialize(record, JsonSerializerOptions.Web)));
        var oversized = record with
        {
            OperationId = Guid.NewGuid(),
            Payload = Convert.ToBase64String(new byte[7 * 1024 * 1024])
        };
        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, await Send(HttpMethod.Put, $"/v1/sync/{Guid.NewGuid()}", JsonSerializer.Serialize(oversized, JsonSerializerOptions.Web)));
    }
}
