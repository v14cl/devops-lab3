using System.Net;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace mywebapp.Tests;

public sealed class NotesEndpointsTests : IDisposable
{
    private readonly MyWebAppFactory _factory = new();
    private readonly HttpClient _client;

    public NotesEndpointsTests()
    {
        _client = _factory.CreateClient();
    }

    [Fact]
    public async Task NotesEndpointStartsWithEmptyList()
    {
        var notes = await _client.GetFromJsonAsync<List<NoteSummary>>("/notes");

        Assert.NotNull(notes);
        Assert.Empty(notes);
    }

    [Fact]
    public async Task PostNotesCreatesTrimmedJsonNote()
    {
        var response = await _client.PostAsJsonAsync("/notes", new
        {
            title = "  Release checklist  ",
            content = "  Verify CI and CD  "
        });

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var created = await response.Content.ReadFromJsonAsync<NoteDetails>();

        Assert.NotNull(created);
        Assert.True(created.Id > 0);
        Assert.Equal("Release checklist", created.Title);
        Assert.Equal("Verify CI and CD", created.Content);
        Assert.NotEqual(default, created.CreatedAt);
    }

    [Fact]
    public async Task PostNotesUsesDefaultTitleWhenTitleIsBlank()
    {
        var response = await _client.PostAsJsonAsync("/notes", new
        {
            title = "   ",
            content = "content"
        });

        var created = await response.Content.ReadFromJsonAsync<NoteDetails>();

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.NotNull(created);
        Assert.Equal("Untitled note", created.Title);
    }

    [Fact]
    public async Task CreatedNoteCanBeReadById()
    {
        var createResponse = await _client.PostAsJsonAsync("/notes", new
        {
            title = "Read by id",
            content = "details"
        });
        var created = await createResponse.Content.ReadFromJsonAsync<NoteDetails>();

        var readResponse = await _client.GetAsync($"/notes/{created!.Id}");
        var found = await readResponse.Content.ReadFromJsonAsync<NoteDetails>();

        Assert.Equal(HttpStatusCode.OK, readResponse.StatusCode);
        Assert.NotNull(found);
        Assert.Equal(created.Id, found.Id);
        Assert.Equal("Read by id", found.Title);
        Assert.Equal("details", found.Content);
    }

    [Fact]
    public async Task MissingNoteReturnsNotFound()
    {
        var response = await _client.GetAsync("/notes/999999");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    [Fact]
    public async Task HtmlNotesListEscapesStoredTitles()
    {
        await _client.PostAsJsonAsync("/notes", new
        {
            title = "<script>alert(1)</script>",
            content = "unsafe"
        });

        using var request = new HttpRequestMessage(HttpMethod.Get, "/notes");
        request.Headers.Accept.ParseAdd("text/html");

        var response = await _client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("text/html", response.Content.Headers.ContentType?.MediaType);
        Assert.Contains("&lt;script&gt;alert(1)&lt;/script&gt;", body, StringComparison.Ordinal);
        Assert.DoesNotContain("<td><script>", body, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public async Task FormPostCreatesHtmlResponseWhenHtmlIsPreferred()
    {
        using var content = new FormUrlEncodedContent(new Dictionary<string, string>
        {
            ["title"] = "Form note",
            ["content"] = "Form content"
        });
        using var request = new HttpRequestMessage(HttpMethod.Post, "/notes") { Content = content };
        request.Headers.Accept.ParseAdd("text/html");

        var response = await _client.SendAsync(request);
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        Assert.Equal("text/html", response.Content.Headers.ContentType?.MediaType);
        Assert.Contains("Form note", body, StringComparison.OrdinalIgnoreCase);
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
    }

    private sealed record NoteSummary(long Id, string Title);

    private sealed record NoteDetails(
        long Id,
        string Title,
        string Content,
        [property: JsonPropertyName("created_at")] DateTime CreatedAt);
}
