using System.Net;

namespace mywebapp.Tests;

public sealed class SystemEndpointsTests : IDisposable
{
    private readonly MyWebAppFactory _factory = new();
    private readonly HttpClient _client;

    public SystemEndpointsTests()
    {
        _client = _factory.CreateClient();
    }

    [Fact]
    public async Task AliveEndpointReturnsOkPlainText()
    {
        var response = await _client.GetAsync("/health/alive");
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("text/plain", response.Content.Headers.ContentType?.MediaType);
        Assert.Equal("OK", body);
    }

    [Fact]
    public async Task ReadyEndpointReturnsOkWhenDatabaseIsReachable()
    {
        var response = await _client.GetAsync("/health/ready");
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("OK", body);
    }

    [Fact]
    public async Task RootEndpointRequiresHtmlAcceptHeader()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/");
        request.Headers.Accept.ParseAdd("application/json");

        var response = await _client.SendAsync(request);

        Assert.Equal(HttpStatusCode.NotAcceptable, response.StatusCode);
    }

    [Fact]
    public async Task RootEndpointReturnsHtmlEndpointIndex()
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, "/");
        request.Headers.Accept.ParseAdd("text/html");

        var response = await _client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("text/html", response.Content.Headers.ContentType?.MediaType);
        Assert.Contains("mywebapp", body, StringComparison.OrdinalIgnoreCase);
        Assert.Contains("/notes", body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Demo_Failing_Test()
    {
        Assert.True(false);
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
    }
}
